#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

// Core: floating dock supported
static BOOL (*orig_isFloatingDockSupported)(id self, SEL _cmd);
static BOOL hook_isFloatingDockSupported(id self, SEL _cmd) { return YES; }
static BOOL (*orig_isDockExternal)(id self, SEL _cmd);
static BOOL hook_isDockExternal(id self, SEL _cmd) { return YES; }
static BOOL (*orig_fdockCtrl_isSupported)(id self, SEL _cmd);
static BOOL hook_fdockCtrl_isSupported(id self, SEL _cmd) { return YES; }
static BOOL (*orig_isFloatingDockSupportedForIconManager)(id self, SEL _cmd, id mgr);
static BOOL hook_isFloatingDockSupportedForIconManager(id self, SEL _cmd, id mgr) { return YES; }

// SBFloatingDockDefaults: recents YES, app library NO
static BOOL (*orig_recentsEnabled)(id self, SEL _cmd);
static BOOL hook_recentsEnabled(id self, SEL _cmd) { return YES; }
static void (*orig_setRecentsEnabled)(id self, SEL _cmd, BOOL v);
static void hook_setRecentsEnabled(id self, SEL _cmd, BOOL v) { orig_setRecentsEnabled(self, _cmd, YES); }
static BOOL (*orig_appLibraryEnabled)(id self, SEL _cmd);
static BOOL hook_appLibraryEnabled(id self, SEL _cmd) { return NO; }
static void (*orig_setAppLibraryEnabled)(id self, SEL _cmd, BOOL v);
static void hook_setAppLibraryEnabled(id self, SEL _cmd, BOOL v) { orig_setAppLibraryEnabled(self, _cmd, NO); }

// SBFloatingDockSuggestionsModel: max 3 recents
static unsigned long long (*orig_maxSuggestions)(id self, SEL _cmd);
static unsigned long long hook_maxSuggestions(id self, SEL _cmd) { return 3; }

// SBIconListGridLayoutConfiguration: allow more dock icons
static unsigned long long (*orig_numberOfPortraitColumns)(id self, SEL _cmd);
static unsigned long long hook_numberOfPortraitColumns(id self, SEL _cmd) {
    unsigned long long o = orig_numberOfPortraitColumns(self, _cmd);
    if (((unsigned long long (*)(id, SEL))objc_msgSend)(self, sel_registerName("numberOfPortraitRows")) == 1 && o == 4)
        return 6;
    return o;
}

// SBIconListView: max dock icons
static unsigned long long (*orig_maximumIconCount)(id self, SEL _cmd);
static unsigned long long hook_maximumIconCount(id self, SEL _cmd) {
    id iconLocation = ((id (*)(id, SEL))objc_msgSend)(self, sel_registerName("iconLocation"));
    if (iconLocation && ([iconLocation isEqual:@"SBIconLocationDock"] ||
                         [iconLocation isEqual:@"SBIconLocationFloatingDock"]))
        return 6;
    return orig_maximumIconCount(self, _cmd);
}

// SBFloatingDockController: no-op folder assertion
static void (*orig_configureBehaviorForFolder)(id self, SEL _cmd, id arg1, NSUInteger arg2);
static void hook_configureBehaviorForFolder(id self, SEL _cmd, id arg1, NSUInteger arg2) { }

// SBFluidSwitcherViewController: dock visibility in switcher
static BOOL (*orig_isFloatingDockGesturePossible)(id self, SEL _cmd);
static BOOL hook_isFloatingDockGesturePossible(id self, SEL _cmd) { return NO; }
static BOOL (*orig_switcher_isFloatingDockSupported)(id self, SEL _cmd);
static BOOL hook_switcher_isFloatingDockSupported(id self, SEL _cmd) {
    Class coordCls = objc_getClass("SBMainSwitcherControllerCoordinator");
    if (coordCls) {
        id inst = ((id (*)(id, SEL))objc_msgSend)((id)coordCls, sel_registerName("sharedInstance"));
        if (inst && ((BOOL (*)(id, SEL))objc_msgSend)(inst, sel_registerName("isAnySwitcherVisible")))
            return YES;
    }
    return NO;
}

#define HOOK(cls, sel, hook, orig) do { \
    Method _m = class_getInstanceMethod(cls, sel); \
    if (_m) { orig = (void *)method_getImplementation(_m); method_setImplementation(_m, (IMP)hook); } \
} while(0)

static id g_fdockCtrl = nil;

static void activateDock(void) {
    @try {
        NSLog(@"[FDock] Activating...");

        id iconCtrl = ((id (*)(id, SEL))objc_msgSend)(
            (id)objc_getClass("SBIconController"), sel_registerName("sharedInstance"));
        id iconManager = ((id (*)(id, SEL))objc_msgSend)(iconCtrl, sel_registerName("iconManager"));

        // Step 1: Create floating dock via official path (gets icons + suggestions)
        if (!g_fdockCtrl) {
            id homeScreenVC = ((id (*)(id, SEL))objc_msgSend)(iconCtrl, sel_registerName("homeScreenViewController"));
            UIWindowScene *windowScene = nil;
            if (homeScreenVC) {
                UIView *hsView = ((UIView *(*)(id, SEL))objc_msgSend)(homeScreenVC, @selector(view));
                windowScene = hsView.window.windowScene;
            }
            if (!windowScene) {
                for (UIScene *s in UIApplication.sharedApplication.connectedScenes)
                    if ([s isKindOfClass:[UIWindowScene class]]) { windowScene = (UIWindowScene *)s; break; }
            }
            if (!windowScene) { NSLog(@"[FDock] no scene"); return; }

            g_fdockCtrl = ((id (*)(id, SEL, id))objc_msgSend)(iconCtrl,
                sel_registerName("createFloatingDockControllerForWindowScene:"), windowScene);
            NSLog(@"[FDock] Created controller: %s", g_fdockCtrl ? "YES" : "NO");
        }
        if (!g_fdockCtrl) return;

        // Step 2: Get the floating dock VC and its dock view (which has icons)
        id fdockVC = ((id (*)(id, SEL))objc_msgSend)(g_fdockCtrl, sel_registerName("floatingDockViewController"));
        if (!fdockVC) { NSLog(@"[FDock] no fdockVC"); return; }

        // Step 3: Get dock view - set its frame so viewDidLayoutSubviews works
        UIView *fdockVCView = ((UIView *(*)(id, SEL))objc_msgSend)(fdockVC, sel_registerName("view"));
        fdockVCView.frame = CGRectMake(0, 0, 430, 932);
        ((void (*)(id, SEL))objc_msgSend)(fdockVC, @selector(viewDidLayoutSubviews));

        id dockViewObj = ((id (*)(id, SEL))objc_msgSend)(fdockVC, sel_registerName("dockView"));
        UIView *dockView = (UIView *)dockViewObj;
        NSLog(@"[FDock] dockView: %s frame: %@", class_getName(object_getClass(dockView)), NSStringFromCGRect(dockView.frame));

        // Step 4: Hide the floating dock window (we'll use the root folder view instead)
        UIWindow *dockWindow = ((UIWindow *(*)(id, SEL))objc_msgSend)(g_fdockCtrl, sel_registerName("floatingDockWindow"));
        if (dockWindow) dockWindow.hidden = YES;

        // Step 5: Move the floating dock VC to root folder controller
        id rfc = ((id (*)(id, SEL))objc_msgSend)(iconManager, sel_registerName("rootFolderController"));
        UIViewController *rfcVC = (UIViewController *)rfc;
        UIView *rfcView = rfcVC.view;
        UIViewController *fdockVCasVC = (UIViewController *)fdockVC;

        // Remove from current parent (SBFloatingDockRootViewController)
        [fdockVCasVC willMoveToParentViewController:nil];
        [fdockVCView removeFromSuperview];
        [fdockVCasVC removeFromParentViewController];

        // Add to root folder controller
        [rfcVC addChildViewController:fdockVCasVC];

        CGFloat screenW = rfcView.bounds.size.width;
        CGFloat screenH = rfcView.bounds.size.height;
        CGFloat dockH = dockView.bounds.size.height > 0 ? dockView.bounds.size.height : 96;

        fdockVCView.frame = CGRectMake(0, screenH - dockH, screenW, dockH);
        fdockVCView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;
        [rfcView addSubview:fdockVCView];
        [fdockVCasVC didMoveToParentViewController:rfcVC];

        // Re-trigger layout now that the view has a proper frame
        ((void (*)(id, SEL))objc_msgSend)(fdockVC, @selector(viewDidLayoutSubviews));

        NSLog(@"[FDock] Added dockView to rfcView at %@", NSStringFromCGRect(dockView.frame));
        NSLog(@"[FDock] dockView subviews: %lu", (unsigned long)dockView.subviews.count);
        for (UIView *sub in dockView.subviews) {
            NSLog(@"[FDock]   %s frame: %@ hidden: %d subs: %lu",
                class_getName(object_getClass(sub)), NSStringFromCGRect(sub.frame),
                sub.hidden, (unsigned long)sub.subviews.count);
        }

        // Step 6: Hide stock dock
        if ([rfc respondsToSelector:sel_registerName("dockListView")]) {
            UIView *dlv = ((UIView *(*)(id, SEL))objc_msgSend)(rfc, sel_registerName("dockListView"));
            if (dlv) {
                dlv.hidden = YES;
                // Also hide the stock dock background
                UIView *dockBG = dlv.superview;
                if (dockBG && [NSStringFromClass(object_getClass(dockBG)) containsString:@"DockView"]) {
                    dockBG.hidden = YES;
                }
            }
        }

        NSLog(@"[FDock] Done!");
    } @catch (NSException *e) {
        NSLog(@"[FDock] EXCEPTION: %@", e);
    }
}

__attribute__((constructor))
static void init(void) {
    Class iconMgr = objc_getClass("SBHIconManager");
    if (iconMgr) HOOK(iconMgr, @selector(isFloatingDockSupported), hook_isFloatingDockSupported, orig_isFloatingDockSupported);

    Class rfcClass = objc_getClass("SBRootFolderController");
    if (rfcClass) HOOK(rfcClass, @selector(isDockExternal), hook_isDockExternal, orig_isDockExternal);

    Class fdockCtrl = objc_getClass("SBFloatingDockController");
    if (fdockCtrl) HOOK(object_getClass(fdockCtrl), @selector(isFloatingDockSupported), hook_fdockCtrl_isSupported, orig_fdockCtrl_isSupported);

    Class iconCtrlClass = objc_getClass("SBIconController");
    if (iconCtrlClass) HOOK(iconCtrlClass, sel_registerName("isFloatingDockSupportedForIconManager:"), hook_isFloatingDockSupportedForIconManager, orig_isFloatingDockSupportedForIconManager);

    // SBFloatingDockDefaults
    Class fdDefaults = objc_getClass("SBFloatingDockDefaults");
    if (fdDefaults) {
        HOOK(fdDefaults, @selector(recentsEnabled), hook_recentsEnabled, orig_recentsEnabled);
        HOOK(fdDefaults, sel_registerName("setRecentsEnabled:"), hook_setRecentsEnabled, orig_setRecentsEnabled);
        HOOK(fdDefaults, @selector(appLibraryEnabled), hook_appLibraryEnabled, orig_appLibraryEnabled);
        HOOK(fdDefaults, sel_registerName("setAppLibraryEnabled:"), hook_setAppLibraryEnabled, orig_setAppLibraryEnabled);
    }

    // SBFloatingDockSuggestionsModel
    Class suggModel = objc_getClass("SBFloatingDockSuggestionsModel");
    if (suggModel) HOOK(suggModel, sel_registerName("maxSuggestions"), hook_maxSuggestions, orig_maxSuggestions);

    // SBIconListGridLayoutConfiguration
    Class gridConfig = objc_getClass("SBIconListGridLayoutConfiguration");
    if (gridConfig) HOOK(gridConfig, sel_registerName("numberOfPortraitColumns"), hook_numberOfPortraitColumns, orig_numberOfPortraitColumns);

    // SBIconListView
    Class iconListView = objc_getClass("SBIconListView");
    if (iconListView) HOOK(iconListView, sel_registerName("maximumIconCount"), hook_maximumIconCount, orig_maximumIconCount);

    // SBFloatingDockController folder behavior
    Class fdockCtrlInst = objc_getClass("SBFloatingDockController");
    if (fdockCtrlInst) HOOK(fdockCtrlInst, sel_registerName("_configureFloatingDockBehaviorAssertionForOpenFolder:atLevel:"), hook_configureBehaviorForFolder, orig_configureBehaviorForFolder);

    // SBFluidSwitcherViewController
    Class fluidSwitcher = objc_getClass("SBFluidSwitcherViewController");
    if (fluidSwitcher) {
        HOOK(fluidSwitcher, sel_registerName("isFloatingDockGesturePossible"), hook_isFloatingDockGesturePossible, orig_isFloatingDockGesturePossible);
        HOOK(fluidSwitcher, sel_registerName("isFloatingDockSupported"), hook_switcher_isFloatingDockSupported, orig_switcher_isFloatingDockSupported);
    }

    NSLog(@"[FDock] All hooks installed");
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        activateDock();
    });
}
