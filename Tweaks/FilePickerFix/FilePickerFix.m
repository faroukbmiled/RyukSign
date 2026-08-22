//
//  FilePickerFix.m
//  RyukSign
//
//  Created by Ryuk
//
//  force the picker into copy mode and relocate anything that still lands outside
//  the sandbox before the app sees it
//

#import <UIKit/UIKit.h>
#import <objc/runtime.h>

static const void *kOriginalPickURLs = &kOriginalPickURLs;
static const void *kOriginalPickURL = &kOriginalPickURL;

static NSURL *RSFRelocate(NSURL *url) {
	if (!url.isFileURL || [url.path hasPrefix:NSHomeDirectory()]) return url;

	BOOL scoped = [url startAccessingSecurityScopedResource];

	NSString *directory = [NSTemporaryDirectory() stringByAppendingPathComponent:
		[@"FilePickerFix" stringByAppendingPathComponent:NSUUID.UUID.UUIDString]];
	NSURL *destination = [NSURL fileURLWithPath:[directory stringByAppendingPathComponent:url.lastPathComponent]];

	NSFileManager *manager = NSFileManager.defaultManager;
	NSError *error = nil;
	BOOL copied = [manager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:&error]
		&& [manager copyItemAtURL:url toURL:destination error:&error];

	if (scoped) [url stopAccessingSecurityScopedResource];

	if (!copied) {
		NSLog(@"[FilePickerFix] could not copy %@: %@", url.lastPathComponent, error.localizedDescription);
		return url;
	}
	return destination;
}

static IMP RSFOriginal(id delegate, const void *key) {
	for (Class cls = object_getClass(delegate); cls; cls = class_getSuperclass(cls)) {
		NSValue *stored = objc_getAssociatedObject(cls, key);
		if (stored) return stored.pointerValue;
	}
	return NULL;
}

static void RSFPickedURLs(id self, SEL _cmd, id picker, NSArray<NSURL *> *urls) {
	IMP original = RSFOriginal(self, kOriginalPickURLs);
	if (!original) return;

	NSMutableArray<NSURL *> *relocated = [NSMutableArray arrayWithCapacity:urls.count];
	for (NSURL *url in urls) [relocated addObject:RSFRelocate(url)];

	((void (*)(id, SEL, id, id))original)(self, _cmd, picker, relocated);
}

static void RSFPickedURL(id self, SEL _cmd, id picker, NSURL *url) {
	IMP original = RSFOriginal(self, kOriginalPickURL);
	if (!original) return;

	((void (*)(id, SEL, id, id))original)(self, _cmd, picker, RSFRelocate(url));
}

/// Overrides the callback on the delegate's own class so sibling classes that merely
/// inherit the same implementation don't lose track of which original to call through to.
static void RSFPatchDelegate(Class cls, SEL selector, IMP replacement, const void *key) {
	Method existing = class_getInstanceMethod(cls, selector);
	if (!existing || method_getImplementation(existing) == replacement) return;

	IMP previous = class_replaceMethod(cls, selector, replacement, method_getTypeEncoding(existing));
	if (!previous) previous = method_getImplementation(existing);

	objc_setAssociatedObject(cls, key, [NSValue valueWithPointer:previous], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void (*RSFOriginalSetDelegate)(id, SEL, id);

static void RSFSetDelegate(id self, SEL _cmd, id delegate) {
	if (delegate) {
		Class cls = object_getClass(delegate);
		RSFPatchDelegate(cls, @selector(documentPicker:didPickDocumentsAtURLs:), (IMP)RSFPickedURLs, kOriginalPickURLs);
		RSFPatchDelegate(cls, @selector(documentPicker:didPickDocumentAtURL:), (IMP)RSFPickedURL, kOriginalPickURL);
	}
	RSFOriginalSetDelegate(self, _cmd, delegate);
}

static id (*RSFOriginalInitWithTypes)(id, SEL, NSArray *, NSInteger);

static id RSFInitWithTypes(id self, SEL _cmd, NSArray *types, NSInteger mode) {
	if (mode == UIDocumentPickerModeOpen) mode = UIDocumentPickerModeImport;
	return RSFOriginalInitWithTypes(self, _cmd, types, mode);
}

static id (*RSFOriginalInitForOpening)(id, SEL, NSArray *, BOOL);

static id RSFInitForOpening(id self, SEL _cmd, NSArray *types, BOOL asCopy) {
	return RSFOriginalInitForOpening(self, _cmd, types, YES);
}

static void RSFSwizzle(Class cls, SEL selector, IMP replacement, IMP *original) {
	Method method = class_getInstanceMethod(cls, selector);
	if (!method) return;
	*original = method_setImplementation(method, replacement);
}

__attribute__((constructor))
static void RSFInstall(void) {
	Class picker = UIDocumentPickerViewController.class;
	RSFSwizzle(picker, @selector(initWithDocumentTypes:inMode:), (IMP)RSFInitWithTypes, (IMP *)&RSFOriginalInitWithTypes);
	RSFSwizzle(picker, @selector(initForOpeningContentTypes:asCopy:), (IMP)RSFInitForOpening, (IMP *)&RSFOriginalInitForOpening);
	RSFSwizzle(picker, @selector(setDelegate:), (IMP)RSFSetDelegate, (IMP *)&RSFOriginalSetDelegate);
}
