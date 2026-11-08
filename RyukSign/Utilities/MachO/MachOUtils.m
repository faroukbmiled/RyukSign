//
//  MachOUtils.m
//  Feather
//
//  Created by samara on 12.06.2025.
//

#import "MachOUtils.h"

#define SDK_VERSION_26_0_0 0x1A0000
#define SDK_VERSION_27_1_0 0x1B0100

/// https://github.com/LiveContainer/LiveContainer/commit/3a029b6bb36c11cc05784a8840d41c7e46af1540
/// this is licensed under Apache-2.0, bundled when compiled.
NSString *LCPatchMachOFixupARM64eSlice(const char *path) {
	int fd = open(path, O_RDWR, 0600);
	if(fd < 0) {
		return [NSString stringWithFormat:@"Failed to open %s: %s", path, strerror(errno)];
	}
	struct stat s = {0};
	fstat(fd, &s);
	void *map = mmap(NULL, s.st_size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
	if(map == MAP_FAILED) {
		close(fd);
		return [NSString stringWithFormat:@"Failed to map %s: %s", path, strerror(errno)];
	}
	
	uint32_t magic = *(uint32_t *)map;
	if(magic == FAT_CIGAM) {
		// Find arm64e slice without CPU_SUBTYPE_LIB64
		struct fat_header *header = (struct fat_header *)map;
		struct fat_arch *arch = (struct fat_arch *)(map + sizeof(struct fat_header));
		for(int i = 0; i < OSSwapInt32(header->nfat_arch); i++) {
			if(OSSwapInt32(arch->cputype) == CPU_TYPE_ARM64 && OSSwapInt32(arch->cpusubtype) == CPU_SUBTYPE_ARM64E) {
				struct mach_header_64 *header = (struct mach_header_64 *)(map + OSSwapInt32(arch->offset));
				header->cpusubtype |= CPU_SUBTYPE_LIB64;
				arch->cpusubtype = htonl(header->cpusubtype);
				break;
			}
			arch = (struct fat_arch *)((void *)arch + sizeof(struct fat_arch));
		}
	}
	
	msync(map, s.st_size, MS_SYNC);
	munmap(map, s.st_size);
	close(fd);
	return nil;
}

/// `raiseOnly` leaves a slice already built against `sdk` or newer untouched.
static NSString *PatchMachOAtOffset(void *mapped, size_t fileSize, off_t offset, uint32_t index, uint32_t sdk, BOOL raiseOnly) {
	uint8_t *base = (uint8_t *)mapped + offset;
	
	if ((size_t)(offset + sizeof(struct mach_header_64)) > fileSize) {
		return [NSString stringWithFormat:@"Slice %u: Invalid offset or truncated header", index];
	}
	
	struct mach_header_64 *header = (struct mach_header_64 *)base;
	if (header->magic != MH_MAGIC_64) {
		return [NSString stringWithFormat:@"Slice %u: Unsupported or non-64-bit Mach-O", index];
	}
	
	struct load_command *cmd = (struct load_command *)(base + sizeof(struct mach_header_64));
	
	for (uint32_t i = 0; i < header->ncmds; i++) {
		uint8_t *cmdEnd = (uint8_t *)cmd + sizeof(struct load_command);
		if ((size_t)(cmdEnd - (uint8_t *)mapped) > fileSize) {
			return [NSString stringWithFormat:@"Slice %u: Load command exceeds file size", index];
		}
		
		if (cmd->cmd == LC_BUILD_VERSION) {
			struct build_version_command *bvc = (struct build_version_command *)cmd;
			if (raiseOnly && bvc->sdk >= sdk) {
				return [NSString stringWithFormat:@"Slice %u: LC_BUILD_VERSION already at SDK %u.%u", index, bvc->sdk >> 16, (bvc->sdk >> 8) & 0xFF];
			}
			bvc->sdk = sdk;
			return [NSString stringWithFormat:@"Slice %u: Patched LC_BUILD_VERSION to SDK %u.%u", index, sdk >> 16, (sdk >> 8) & 0xFF];
		}
		
		cmd = (struct load_command *)((uint8_t *)cmd + cmd->cmdsize);
	}
	
	return [NSString stringWithFormat:@"Slice %u: LC_BUILD_VERSION not found", index];
}

static NSString *PatchMachOSDK(const char *path, uint32_t sdk, BOOL raiseOnly) {
	int fd = open(path, O_RDWR, 0600);
	if(fd < 0) {
		return [NSString stringWithFormat:@"Failed to open %s: %s", path, strerror(errno)];
	}
	struct stat s = {0};
	fstat(fd, &s);
	void *map = mmap(NULL, s.st_size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
	if(map == MAP_FAILED) {
		close(fd);
		return [NSString stringWithFormat:@"Failed to map %s: %s", path, strerror(errno)];
	}
	
	NSMutableString *result = [NSMutableString string];
	uint32_t magic = *(uint32_t *)map;
	
	if (magic == FAT_MAGIC || magic == FAT_CIGAM) {
		struct fat_header *fat = (struct fat_header *)map;
		uint32_t nfat = OSSwapBigToHostInt32(fat->nfat_arch);
		struct fat_arch *archs = (struct fat_arch *)((uint8_t *)map + sizeof(struct fat_header));
		
		for (uint32_t i = 0; i < nfat; i++) {
			uint32_t offset = OSSwapBigToHostInt32(archs[i].offset);
			NSString *sliceResult = PatchMachOAtOffset(map, s.st_size, offset, i, sdk, raiseOnly);
			[result appendFormat:@"%@\n", sliceResult];
		}
	} else if (magic == MH_MAGIC_64) {
		NSString *mainResult = PatchMachOAtOffset(map, s.st_size, 0, 0, sdk, raiseOnly);
		[result appendFormat:@"%@\n", mainResult];
	} else {
		munmap(map, s.st_size);
		close(fd);
		return [NSString stringWithFormat:@"Unsupported binary format %s: %s", path, strerror(errno)];
	}
	
	munmap(map, s.st_size);
	close(fd);
	return result;
}

NSString *LCPatchMachOForSDK26(const char *path) {
	return PatchMachOSDK(path, SDK_VERSION_26_0_0, NO);
}

/// The iPhone Duo letterboxes apps built against an SDK older than 27.1.
NSString *LCPatchMachOForIPhoneDuo(const char *path) {
	return PatchMachOSDK(path, SDK_VERSION_27_1_0, YES);
}
