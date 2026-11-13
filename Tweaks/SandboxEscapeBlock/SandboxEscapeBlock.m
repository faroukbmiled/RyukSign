//
//  SandboxEscapeBlock.m
//  RyukSign
//
//  Created by Ryuk
//
//  refuse App Group symlinks and container query domains that lead out of the container
//

#include <errno.h>
#include <fcntl.h>
#include <fts.h>
#include <limits.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <os/log.h>
#include <sys/clonefile.h>
#include <sys/stat.h>

#define DYLD_INTERPOSE(_replacement, _replacee) \
	__attribute__((used)) static struct { const void *replacement; const void *replacee; } \
	_interpose_##_replacee __attribute__((section("__DATA,__interpose"))) = \
	{ (const void *)(unsigned long)&_replacement, (const void *)(unsigned long)&_replacee };

static const char kGroupMarker[] = "/Containers/Shared/AppGroup/";

static size_t RSBGroupRootLength(const char *path) {
	const char *marker = strstr(path, kGroupMarker);
	if (!marker) return 0;

	const char *end = strchr(marker + sizeof(kGroupMarker) - 1, '/');
	return end ? (size_t)(end - path) : 0;
}

static const char *RSBSkipPrivate(const char *path) {
	return strncmp(path, "/private/var/", 13) == 0 ? path + 8 : path;
}

static void RSBNormalize(char *path) {
	char copy[PATH_MAX * 3];
	strlcpy(copy, path, sizeof(copy));

	size_t length = 0;
	char *cursor = copy;
	for (char *part; (part = strsep(&cursor, "/")); ) {
		if (!*part || strcmp(part, ".") == 0) continue;
		if (strcmp(part, "..") == 0) {
			while (length > 0 && path[--length] != '/');
			continue;
		}
		size_t partLength = strlen(part);
		path[length++] = '/';
		memcpy(path + length, part, partLength);
		length += partLength;
	}
	if (length == 0) path[length++] = '/';
	path[length] = '\0';
}

// Follows links through the part that exists, so nested links can't hide where a path really lands.
static void RSBResolve(const char *path, char *out, size_t size) {
	char head[PATH_MAX * 2], real[PATH_MAX];
	strlcpy(head, path, sizeof(head));

	size_t cut = strlen(head);
	while (!realpath(cut ? head : "/", real)) {
		while (cut > 0 && head[--cut] != '/');
		head[cut] = '\0';
	}
	snprintf(out, size, "%s/%s", real, path + cut);
	RSBNormalize(out);
}

static bool RSBAbsolute(int fd, const char *path, char *out, size_t size) {
	if (path[0] == '/') return strlcpy(out, path, size) < size;

	char base[PATH_MAX];
	if (fd == AT_FDCWD ? !getcwd(base, sizeof(base)) : fcntl(fd, F_GETPATH, base) != 0) return false;
	return (size_t)snprintf(out, size, "%s/%s", base, path) < size;
}

/// Where a new directory entry at `path` will really live: parent resolved, last component kept as is.
static bool RSBEntryLocation(int fd, const char *path, char *out, size_t size) {
	char absolute[PATH_MAX * 2];
	if (!RSBAbsolute(fd, path, absolute, sizeof(absolute))) return false;

	size_t length = strlen(absolute);
	while (length > 1 && absolute[length - 1] == '/') absolute[--length] = '\0';

	char *name = strrchr(absolute, '/');
	if (!name || !name[1]) return false;
	*name++ = '\0';

	char parent[PATH_MAX];
	if (!realpath(absolute[0] ? absolute : "/", parent)) return false;
	return (size_t)snprintf(out, size, "%s/%s", parent, name) < size;
}

static bool RSBLinkEscapes(const char *link, const char *target) {
	size_t rootLength = RSBGroupRootLength(link);
	if (!rootLength) return false;

	char joined[PATH_MAX * 2], destination[PATH_MAX * 3];
	if (target[0] == '/') {
		strlcpy(joined, target, sizeof(joined));
	} else {
		snprintf(joined, sizeof(joined), "%.*s/%s", (int)(strrchr(link, '/') - link), link, target);
	}
	RSBResolve(joined, destination, sizeof(destination));

	const char *root = RSBSkipPrivate(link);
	const char *landing = RSBSkipPrivate(destination);
	rootLength -= (size_t)(root - link);

	if (strncmp(landing, root, rootLength) == 0 && (landing[rootLength] == '/' || landing[rootLength] == '\0')) {
		return false;
	}

	os_log_error(OS_LOG_DEFAULT, "[SandboxEscapeBlock] refused link %{public}s -> %{public}s", link, destination);
	return true;
}

/// Checks every link in `from` as if it already sat at `to`, since a move or clone can smuggle one in.
static bool RSBTreeEscapes(int fromfd, const char *from, int tofd, const char *to, bool followRoot) {
	char destination[PATH_MAX], source[PATH_MAX * 2];
	if (!RSBEntryLocation(tofd, to, destination, sizeof(destination)) || !RSBGroupRootLength(destination)) return false;
	if (!RSBAbsolute(fromfd, from, source, sizeof(source))) return false;

	char *roots[] = { source, NULL };
	FTS *tree = fts_open(roots, FTS_PHYSICAL | FTS_NOCHDIR | (followRoot ? FTS_COMFOLLOW : 0), NULL);
	if (!tree) return false;

	bool escapes = false;
	size_t sourceLength = strlen(source);
	for (FTSENT *entry; !escapes && (entry = fts_read(tree)); ) {
		if (entry->fts_info != FTS_SL && entry->fts_info != FTS_SLNONE) continue;

		char target[PATH_MAX], moved[PATH_MAX * 2];
		ssize_t length = readlink(entry->fts_accpath, target, sizeof(target) - 1);
		if (length < 0) continue;
		target[length] = '\0';

		snprintf(moved, sizeof(moved), "%s%s", destination, entry->fts_path + sourceLength);
		escapes = RSBLinkEscapes(moved, target);
	}
	fts_close(tree);
	return escapes;
}

static int RSBRefuse(void) {
	errno = EPERM;
	return -1;
}

static int RSBSymlinkAt(const char *target, int fd, const char *path) {
	char link[PATH_MAX];
	if (RSBEntryLocation(fd, path, link, sizeof(link)) && RSBLinkEscapes(link, target)) return RSBRefuse();
	return symlinkat(target, fd, path);
}

static int RSBSymlink(const char *target, const char *path) {
	return RSBSymlinkAt(target, AT_FDCWD, path);
}

static int RSBRenameAtX(int fromfd, const char *from, int tofd, const char *to, unsigned int flags) {
	if (RSBTreeEscapes(fromfd, from, tofd, to, false)) return RSBRefuse();
	if ((flags & RENAME_SWAP) && RSBTreeEscapes(tofd, to, fromfd, from, false)) return RSBRefuse();
	return renameatx_np(fromfd, from, tofd, to, flags);
}

static int RSBRenameX(const char *from, const char *to, unsigned int flags) {
	return RSBRenameAtX(AT_FDCWD, from, AT_FDCWD, to, flags);
}

static int RSBRenameAt(int fromfd, const char *from, int tofd, const char *to) {
	return RSBRenameAtX(fromfd, from, tofd, to, 0);
}

static int RSBRename(const char *from, const char *to) {
	return RSBRenameAtX(AT_FDCWD, from, AT_FDCWD, to, 0);
}

static int RSBCloneFileAt(int fromfd, const char *from, int tofd, const char *to, uint32_t flags) {
	if (RSBTreeEscapes(fromfd, from, tofd, to, !(flags & CLONE_NOFOLLOW))) return RSBRefuse();
	return clonefileat(fromfd, from, tofd, to, flags);
}

static int RSBCloneFile(const char *from, const char *to, uint32_t flags) {
	return RSBCloneFileAt(AT_FDCWD, from, AT_FDCWD, to, flags);
}

extern void container_query_operation_set_part_domain(void *query, const char *domain);

static bool RSBDomainClimbs(const char *domain) {
	if (domain[0] == '/') return true;
	for (const char *dots = domain; (dots = strstr(dots, "..")); dots += 2) {
		bool starts = dots == domain || dots[-1] == '/';
		bool ends = dots[2] == '/' || dots[2] == '\0';
		if (starts && ends) return true;
	}
	return false;
}

static void RSBSetPartDomain(void *query, const char *domain) {
	if (domain && RSBDomainClimbs(domain)) {
		os_log_error(OS_LOG_DEFAULT, "[SandboxEscapeBlock] dropped part domain %{public}s", domain);
		return;
	}
	container_query_operation_set_part_domain(query, domain);
}

DYLD_INTERPOSE(RSBSetPartDomain, container_query_operation_set_part_domain)
DYLD_INTERPOSE(RSBSymlink, symlink)
DYLD_INTERPOSE(RSBSymlinkAt, symlinkat)
DYLD_INTERPOSE(RSBRename, rename)
DYLD_INTERPOSE(RSBRenameAt, renameat)
DYLD_INTERPOSE(RSBRenameX, renamex_np)
DYLD_INTERPOSE(RSBRenameAtX, renameatx_np)
DYLD_INTERPOSE(RSBCloneFile, clonefile)
DYLD_INTERPOSE(RSBCloneFileAt, clonefileat)
