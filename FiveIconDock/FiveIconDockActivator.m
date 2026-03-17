// FiveIconDockActivator.m — Standalone FiveIconDock port for Coruna
// No substrate, no Theos — pure ObjC runtime
// Original tweak by lunaynx: https://github.com/lunaynx/fiveicondock

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

#define DOCK_ICONS 5

// SBIconListGridLayoutConfiguration: 5 columns when row==1 (dock)
static unsigned long long (*orig_numberOfPortraitColumns)(id self, SEL _cmd);
static unsigned long long hook_numberOfPortraitColumns(id self, SEL _cmd) {
    unsigned long long rows = ((unsigned long long (*)(id, SEL))objc_msgSend)(self, sel_registerName("numberOfPortraitRows"));
    if (rows == 1)
        return DOCK_ICONS;
    return orig_numberOfPortraitColumns(self, _cmd);
}

// SBIconListView: max icon count for dock locations
static unsigned long long (*orig_maximumIconCount)(id self, SEL _cmd);
static unsigned long long hook_maximumIconCount(id self, SEL _cmd) {
    id loc = ((id (*)(id, SEL))objc_msgSend)(self, sel_registerName("iconLocation"));
    if (loc && ([loc isEqual:@"SBIconLocationDock"] || [loc isEqual:@"SBIconLocationFloatingDock"]))
        return DOCK_ICONS;
    return orig_maximumIconCount(self, _cmd);
}

// SBIconListModel: max number of icons the model accepts
static unsigned long long (*orig_maxNumberOfIcons)(id self, SEL _cmd);
static unsigned long long hook_maxNumberOfIcons(id self, SEL _cmd) {
    unsigned long long orig = orig_maxNumberOfIcons(self, _cmd);
    // Dock models have max 4 by default — bump to 5
    if (orig == 4)
        return DOCK_ICONS;
    return orig;
}

// SBDockIconListView: override icons in dock column count
static unsigned long long (*orig_iconsInRowForSpacingCalculation)(id self, SEL _cmd);
static unsigned long long hook_iconsInRowForSpacingCalculation(id self, SEL _cmd) {
    return DOCK_ICONS;
}

// SBIconListModel: never report full for dock-sized models
static BOOL (*orig_isFull)(id self, SEL _cmd);
static BOOL hook_isFull(id self, SEL _cmd) {
    unsigned long long max = ((unsigned long long (*)(id, SEL))objc_msgSend)(self, sel_registerName("maxNumberOfIcons"));
    if (max == DOCK_ICONS) {
        unsigned long long count = ((unsigned long long (*)(id, SEL))objc_msgSend)(self, sel_registerName("numberOfIcons"));
        return count >= DOCK_ICONS;
    }
    return orig_isFull(self, _cmd);
}

// SBIconListModel: report correct free slots
static unsigned long long (*orig_numberOfFreeSlots)(id self, SEL _cmd);
static unsigned long long hook_numberOfFreeSlots(id self, SEL _cmd) {
    unsigned long long max = ((unsigned long long (*)(id, SEL))objc_msgSend)(self, sel_registerName("maxNumberOfIcons"));
    if (max == DOCK_ICONS) {
        unsigned long long count = ((unsigned long long (*)(id, SEL))objc_msgSend)(self, sel_registerName("numberOfIcons"));
        return DOCK_ICONS > count ? DOCK_ICONS - count : 0;
    }
    return orig_numberOfFreeSlots(self, _cmd);
}

static void hookMethod(Class cls, SEL sel, void *replacement, void **original) {
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) return;
    *original = (void *)method_getImplementation(m);
    method_setImplementation(m, (IMP)replacement);
}

__attribute__((constructor))
static void FiveIconDockInit(void) {
    NSLog(@"[FiveIconDock] Loading...");

    Class gridCfg = objc_getClass("SBIconListGridLayoutConfiguration");
    if (gridCfg) {
        hookMethod(gridCfg, sel_registerName("numberOfPortraitColumns"),
                   (void *)hook_numberOfPortraitColumns, (void **)&orig_numberOfPortraitColumns);
    }

    Class iconListView = objc_getClass("SBIconListView");
    if (iconListView) {
        hookMethod(iconListView, sel_registerName("maximumIconCount"),
                   (void *)hook_maximumIconCount, (void **)&orig_maximumIconCount);
    }

    Class iconListModel = objc_getClass("SBIconListModel");
    if (iconListModel) {
        hookMethod(iconListModel, sel_registerName("maxNumberOfIcons"),
                   (void *)hook_maxNumberOfIcons, (void **)&orig_maxNumberOfIcons);
        hookMethod(iconListModel, sel_registerName("isFull"),
                   (void *)hook_isFull, (void **)&orig_isFull);
        hookMethod(iconListModel, sel_registerName("numberOfFreeSlots"),
                   (void *)hook_numberOfFreeSlots, (void **)&orig_numberOfFreeSlots);
    }

    Class dockListView = objc_getClass("SBDockIconListView");
    if (dockListView) {
        hookMethod(dockListView, sel_registerName("iconsInRowForSpacingCalculation"),
                   (void *)hook_iconsInRowForSpacingCalculation, (void **)&orig_iconsInRowForSpacingCalculation);
    }

    // Patch the dock's icon list model _gridSize ivar to allow 5 columns
    // _gridSize is a packed {columns(u16), rows(u16)} = SBHIconGridSize
    // Default dock: columns=4, rows=1 → packed as 0x00010004
    // We want: columns=5, rows=1 → packed as 0x00010005
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        id iconCtrl = ((id (*)(Class, SEL))objc_msgSend)(objc_getClass("SBIconController"), sel_registerName("sharedInstance"));
        if (!iconCtrl) return;

        // Get the dock icon list view via iconManager (iOS 17)
        id iconMgr = ((id (*)(id, SEL))objc_msgSend)(iconCtrl, sel_registerName("iconManager"));
        if (!iconMgr) { NSLog(@"[FiveIconDock] No icon manager found"); return; }
        id dockListView = ((id (*)(id, SEL))objc_msgSend)(iconMgr, sel_registerName("dockListView"));
        if (!dockListView) { NSLog(@"[FiveIconDock] No dock list view found"); return; }

        // Get the model from the dock list view
        id model = ((id (*)(id, SEL))objc_msgSend)(dockListView, sel_registerName("model"));
        if (!model) { NSLog(@"[FiveIconDock] No dock model found"); return; }

        // Patch _gridSize ivar: {columns=5, rows=1}
        Ivar gridSizeIvar = class_getInstanceVariable(object_getClass(model), "_gridSize");
        if (gridSizeIvar) {
            ptrdiff_t offset = ivar_getOffset(gridSizeIvar);
            uint32_t *gridPtr = (uint32_t *)((uint8_t *)(__bridge void *)model + offset);
            uint32_t oldVal = *gridPtr;
            // Pack as {columns(low16)=5, rows(high16)=1}
            *gridPtr = (1 << 16) | DOCK_ICONS;
            NSLog(@"[FiveIconDock] Patched _gridSize: 0x%08x → 0x%08x", oldVal, *gridPtr);
        }

        // Force relayout
        ((void (*)(id, SEL))objc_msgSend)(dockListView, sel_registerName("layoutIconsNow"));

        NSLog(@"[FiveIconDock] Dock model patched for %d icons", DOCK_ICONS);
    });

    NSLog(@"[FiveIconDock] Active — %d dock icons", DOCK_ICONS);
}
