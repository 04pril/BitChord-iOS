// Experimental launch association repair for sideloaded YouTube Music.
// No networking, URL scheme interception, entitlement rewriting, or launch loops.
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#ifndef YTMU_NP_TEST
#import <UIKit/UIKit.h>
#import <MediaPlayer/MediaPlayer.h>
#endif


static NSString *NPText(NSString *key, NSString *fallback) {
#ifdef YTMU_NP_TEST
    return fallback;
#else
    Class cls = NSBundle.class;
    SEL sel = NSSelectorFromString(@"ytmu_defaultBundle");
    NSBundle *bundle = [cls respondsToSelector:sel] ? [cls performSelector:sel] : NSBundle.mainBundle;
    return [bundle localizedStringForKey:key value:fallback table:nil];
#endif
}

static NSString *const NPPreference = @"BitChord.NowPlayingLaunchFix.enabled";
static NSDictionary *NPInfo;
static NSObject *NPLock;
static void *(*NPGetOrigin)(void);
static void (*NPSetParent)(void *, CFStringRef);
static NSUInteger NPPublishCount, NPBindCount;
static BOOL NPBound, NPInstalled;
static BOOL NPSPIFailed;

static BOOL NPEnabled(void) {
    id value = [NSUserDefaults.standardUserDefaults objectForKey:NPPreference];
    return value == nil || [value boolValue];
}

static NSString *NPBundleID(void) { return NPInfo[@"CFBundleIdentifier"]; }

static void NPBind(void) {
    if (!NPEnabled() || !NPBundleID().length || !NPGetOrigin || !NPSetParent || NPSPIFailed) return;
    // WebKit's MediaRemoteSoftLink.h declares this exact two-argument ABI.
    // The void return means "request sent", never "iOS accepted".
    @try {
        void *origin = NPGetOrigin();
        if (!origin) return;
        NPSetParent(origin, (__bridge CFStringRef)NPBundleID());
        @synchronized (NPLock) { NPBindCount++; NPBound = YES; }
    } @catch (NSException *exception) {
        @synchronized (NPLock) { NPSPIFailed = YES; }
    }
}

static void NPSetEnabled(BOOL enabled) {
    [NSUserDefaults.standardUserDefaults setBool:enabled forKey:NPPreference];
    if (enabled) { NPBind(); return; }
    @synchronized (NPLock) {
        if (NPBound && NPGetOrigin && NPSetParent && !NPSPIFailed) {
            @try {
                void *origin = NPGetOrigin();
                if (origin) NPSetParent(origin, NULL);
            } @catch (NSException *exception) { NPSPIFailed = YES; }
        }
        NPBound = NO;
    }
}

static NSString *NPSignedAppID(void) {
    // Dynamically resolve: these Security functions are not public iOS SDK API.
    CFTypeRef (*create)(CFAllocatorRef) = dlsym(RTLD_DEFAULT, "SecTaskCreateFromSelf");
    CFTypeRef (*copy)(CFTypeRef, CFStringRef, CFErrorRef *) =
        dlsym(RTLD_DEFAULT, "SecTaskCopyValueForEntitlement");
    if (!create || !copy) return nil;
    CFTypeRef task = create(kCFAllocatorDefault);
    if (!task) return nil;
    CFTypeRef value = copy(task, CFSTR("application-identifier"), NULL);
    CFRelease(task);
    if (!value) return nil;
    NSString *result = CFGetTypeID(value) == CFStringGetTypeID() ? [(__bridge NSString *)value copy] : nil;
    CFRelease(value);
    return result;
}

static NSString *NPSigningAssessment(NSString *bundle, NSString *signedID) {
    if (!signedID.length) return NPText(@"NP_UNKNOWN", @"Signed App ID unavailable: match unverified");
    if ([signedID hasSuffix:[@"." stringByAppendingString:bundle ?: @""]])
        return NPText(@"NP_MATCH", @"Signed App ID matches the bundle ID");
    return NPText(@"NP_MISMATCH", @"Signed App ID mismatch: check the signer/profile. This patch cannot change signing permissions.");
}

static NSString *NPReport(void) {
    NSString *signedID = NPSignedAppID();
    NSUInteger published, bound;
    @synchronized (NPLock) { published = NPPublishCount; bound = NPBindCount; }
    return [NSString stringWithFormat:
        NPText(@"NP_REPORT_FORMAT", @"BitChord Now Playing patch (verify on your device)\nPatch: %@\nApp version: %@\nInstalled bundle ID: %@\nSigned App ID: %@\n%@\nMetadata published: %lu\nMediaRemote API: %@\nAssociation requests: %lu\n\nRequest counts do not confirm iOS approval or successful app opening.\nPlay a track and test the Lock Screen and Dynamic Island."),
        NPEnabled() ? NPText(@"NP_ENABLED", @"On") : NPText(@"NP_DISABLED", @"Off"), NPInfo[@"CFBundleShortVersionString"] ?: @"?",
        NPBundleID() ?: @"?", signedID ?: NPText(@"NP_UNREADABLE", @"Unavailable"), NPSigningAssessment(NPBundleID(), signedID),
        (unsigned long)published, NPSPIFailed ? NPText(@"NP_FAILED", @"Exception: disabled for this launch") :
            (NPGetOrigin && NPSetParent ? NPText(@"NP_AVAILABLE", @"Available") : NPText(@"NP_UNAVAILABLE", @"Unavailable (not applied)")),
        (unsigned long)bound];
}

static id (*NPOriginalDefaultCenter)(id, SEL);
static void (*NPOriginalSetInfo)(id, SEL, NSDictionary *);

static id NPDefaultCenter(id self, SEL cmd) {
    id center = NPOriginalDefaultCenter(self, cmd);
    if (center) NPBind();
    return center;
}

static void NPSetInfo(id self, SEL cmd, NSDictionary *info) {
    NPOriginalSetInfo(self, cmd, info);
    if (info.count) {
        @synchronized (NPLock) { NPPublishCount++; }
        NPBind();
    }
}

static BOOL NPHook(Class cls, SEL selector, IMP replacement, IMP *original) {
    Method method = class_getInstanceMethod(cls, selector);
    if (!method) return NO;
    *original = method_getImplementation(method);
    class_replaceMethod(cls, selector, replacement, method_getTypeEncoding(method));
    return YES;
}

#ifndef YTMU_NP_TEST
@interface YTMUNPDiagnosticAction : NSObject
@property (nonatomic, weak) UIViewController *controller;
- (void)show;
@end
@implementation YTMUNPDiagnosticAction
- (void)show {
    UIViewController *controller = self.controller;
    if (!controller || controller.presentedViewController) return;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:NPText(@"NP_TITLE", @"Now Playing \u2192 Open app")
        message:NPReport() preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:NPText(@"NP_COPY", @"Copy diagnostics") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        UIPasteboard.generalPasteboard.string = NPReport();
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:NPEnabled() ? NPText(@"NP_OFF", @"Turn patch off") : NPText(@"NP_ON", @"Turn patch on")
        style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { NPSetEnabled(!NPEnabled()); }]];
    [alert addAction:[UIAlertAction actionWithTitle:NPText(@"NP_CLOSE", @"Close") style:UIAlertActionStyleCancel handler:nil]];
    [controller presentViewController:alert animated:YES completion:nil];
}
@end

static const char NPActionKey;
static void (*NPOriginalSettingsLoad)(id, SEL);
static void NPSettingsLoad(UIViewController *self, SEL cmd) {
    NPOriginalSettingsLoad(self, cmd);
    YTMUNPDiagnosticAction *action = [YTMUNPDiagnosticAction new];
    action.controller = self;
    objc_setAssociatedObject(self, &NPActionKey, action, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    NSMutableArray *items = [self.navigationItem.rightBarButtonItems mutableCopy] ?: [NSMutableArray new];
    [items addObject:[[UIBarButtonItem alloc] initWithTitle:NPText(@"NP_DIAGNOSTICS", @"App-opening diagnostics")
        style:UIBarButtonItemStylePlain target:action action:@selector(show)]];
    self.navigationItem.rightBarButtonItems = items;
}
#endif

static void NPInstall(void) {
    if (NPInstalled) return;
    NPInstalled = YES;
    NPLock = [NSObject new];
    Class center = NSClassFromString(@"MPNowPlayingInfoCenter");
    NPHook(object_getClass(center), NSSelectorFromString(@"defaultCenter"),
        (IMP)NPDefaultCenter, (IMP *)&NPOriginalDefaultCenter);
    NPHook(center, NSSelectorFromString(@"setNowPlayingInfo:"),
        (IMP)NPSetInfo, (IMP *)&NPOriginalSetInfo);
#ifndef YTMU_NP_TEST
    // dlopen handle intentionally lives for the process lifetime.
    void *framework = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY | RTLD_LOCAL);
    if (framework) {
        NPGetOrigin = dlsym(framework, "MRMediaRemoteGetLocalOrigin");
        NPSetParent = dlsym(framework, "MRMediaRemoteSetParentApplication");
    }
    Class settings = NSClassFromString(@"YTMUWGSettingsController");
    NPHook(settings, @selector(viewDidLoad), (IMP)NPSettingsLoad, (IMP *)&NPOriginalSettingsLoad);
    [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidBecomeActiveNotification
        object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) { NPBind(); }];
#endif
}

#ifndef YTMU_NP_TEST
__attribute__((constructor)) static void NPStart(void) {
    @autoreleasepool {
        // Read the actual on-disk plist, bypassing YTMU's NSBundle identity hooks.
        NSString *file = [NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:@"Info.plist"];
        NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:file];
        if (![info[@"CFBundleExecutable"] isEqualToString:@"BitChord"]) return;
        NPInfo = [info copy];
        dispatch_async(dispatch_get_main_queue(), ^{ NPInstall(); });
    }
}
#endif
