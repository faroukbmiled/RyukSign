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

static NSString *PatchMachOAtOffset(uint8_t *mapped, size_t fileSize, size_t offset, uint32_t index, uint32_t sdk, BOOL raiseOnly) {
	if (offset > fileSize || fileSize - offset < sizeof(struct mach_header_64)) {
		return [NSString stringWithFormat:@"Slice %u: Invalid offset or truncated header", index];
	}
	
	struct mach_header_64 *header = (struct mach_header_64 *)(mapped + offset);
	if (header->magic != MH_MAGIC_64) {
		return [NSString stringWithFormat:@"Slice %u: Unsupported or non-64-bit Mach-O", index];
	}
	
	size_t cursor = offset + sizeof(struct mach_header_64);
	
	for (uint32_t i = 0; i < header->ncmds; i++) {
		if (fileSize - cursor < sizeof(struct load_command)) {
			return [NSString stringWithFormat:@"Slice %u: Load command exceeds file size", index];
		}
		
		struct load_command *cmd = (struct load_command *)(mapped + cursor);
		if (cmd->cmdsize < sizeof(struct load_command) || fileSize - cursor < cmd->cmdsize) {
			return [NSString stringWithFormat:@"Slice %u: Malformed load command", index];
		}
		
		uint32_t *field = NULL;
		if (cmd->cmd == LC_BUILD_VERSION && cmd->cmdsize >= sizeof(struct build_version_command)) {
			field = &((struct build_version_command *)cmd)->sdk;
		} else if (cmd->cmd == LC_VERSION_MIN_IPHONEOS && cmd->cmdsize >= sizeof(struct version_min_command)) {
			field = &((struct version_min_command *)cmd)->sdk;
		}
		
		if (field) {
			if (raiseOnly && *field >= sdk) {
				return [NSString stringWithFormat:@"Slice %u: SDK already %u.%u", index, *field >> 16, (*field >> 8) & 0xFF];
			}
			*field = sdk;
			return [NSString stringWithFormat:@"Slice %u: Patched SDK to %u.%u", index, sdk >> 16, (sdk >> 8) & 0xFF];
		}
		
		cursor += cmd->cmdsize;
	}
	
	return [NSString stringWithFormat:@"Slice %u: No SDK version load command found", index];
}

static NSString *PatchMachOSDK(const char *path, uint32_t sdk, BOOL raiseOnly) {
	int fd = open(path, O_RDWR, 0600);
	if(fd < 0) {
		return [NSString stringWithFormat:@"Failed to open %s: %s", path, strerror(errno)];
	}
	struct stat s = {0};
	fstat(fd, &s);
	size_t size = (size_t)s.st_size;
	if (size < sizeof(uint32_t)) {
		close(fd);
		return [NSString stringWithFormat:@"Unsupported binary format %s", path];
	}
	uint8_t *map = mmap(NULL, size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
	if(map == MAP_FAILED) {
		close(fd);
		return [NSString stringWithFormat:@"Failed to map %s: %s", path, strerror(errno)];
	}
	
	NSMutableString *result = [NSMutableString string];
	uint32_t magic = *(uint32_t *)map;
	
	if (magic == FAT_CIGAM && size >= sizeof(struct fat_header)) {
		uint32_t nfat = OSSwapBigToHostInt32(((struct fat_header *)map)->nfat_arch);
		size_t available = (size - sizeof(struct fat_header)) / sizeof(struct fat_arch);
		struct fat_arch *archs = (struct fat_arch *)(map + sizeof(struct fat_header));
		
		for (uint32_t i = 0; i < MIN(nfat, available); i++) {
			size_t offset = OSSwapBigToHostInt32(archs[i].offset);
			[result appendFormat:@"%@\n", PatchMachOAtOffset(map, size, offset, i, sdk, raiseOnly)];
		}
	} else if (magic == MH_MAGIC_64) {
		[result appendFormat:@"%@\n", PatchMachOAtOffset(map, size, 0, 0, sdk, raiseOnly)];
	} else {
		munmap(map, size);
		close(fd);
		return [NSString stringWithFormat:@"Unsupported binary format %s", path];
	}
	
	msync(map, size, MS_SYNC);
	munmap(map, size);
	close(fd);
	return result;
}

NSString *LCPatchMachOForSDK26(const char *path) {
	return PatchMachOSDK(path, SDK_VERSION_26_0_0, NO);
}

NSString *LCPatchMachOForIPhoneDuo(const char *path) {
	return PatchMachOSDK(path, SDK_VERSION_27_1_0, YES);
}
