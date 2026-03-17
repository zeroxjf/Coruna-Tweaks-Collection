// CylinderActivator.m — Standalone Cylinder Remade port for Coruna
// No substrate, no Theos, no Swift — pure ObjC runtime hooking
// Ported from Cylinder Remade by Ryan Nair (ryannair05)

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <math.h>

#pragma mark - CALayer+Cylinder (save/restore position)

@interface CALayer (Cylinder)
- (void)cyl_savePosition;
- (void)cyl_restorePosition;
@end

@implementation CALayer (Cylinder)
- (void)setCyl_savedValue:(NSValue *)value {
    objc_setAssociatedObject(self, @selector(cyl_savedValue), value, OBJC_ASSOCIATION_RETAIN);
}
- (NSValue *)cyl_savedValue {
    return objc_getAssociatedObject(self, @selector(cyl_savedValue));
}
- (void)cyl_savePosition {
    if (!self.cyl_savedValue)
        self.cyl_savedValue = [NSValue valueWithCGPoint:self.position];
}
- (void)cyl_restorePosition {
    NSValue *v = self.cyl_savedValue;
    if (!v) return;
    self.position = v.CGPointValue;
    self.cyl_savedValue = nil;
}
@end

#pragma mark - Forward declarations

@interface SBIconScrollView : UIScrollView
@end

@interface SBIconView : UIView
@end

@interface SBIconListView : UIView
@property (readonly, nonatomic) NSUInteger iconColumnsForCurrentOrientation;
- (void)setAlphaForAllIcons:(CGFloat)alpha;
- (void)enumerateIconViewsUsingBlock:(void (^)(SBIconView *icon, NSUInteger idx, BOOL *stop))block;
@end

@interface SBFolderView : UIView
@property (nonatomic, copy, readonly) NSArray *iconListViews;
- (void)enumerateIconListViewsUsingBlock:(void (^)(SBIconListView *))block;
@end

#pragma mark - Animation effects

typedef NS_ENUM(NSInteger, CylinderEffect) {
    CylinderEffectCubeInside = 0,
    CylinderEffectCubeOutside,
    CylinderEffectPageFade,
    CylinderEffectPageFlip,
    CylinderEffectPageTwist,
    CylinderEffectShrink,
    CylinderEffectSpin,
    CylinderEffectHinge,
    CylinderEffectBackwards,
    CylinderEffectVerticalScrolling,
    CylinderEffectCardHorizontal,
    CylinderEffectCardVertical,
    CylinderEffectIconCollection,
    CylinderEffectVortex,
    CylinderEffectWave,
    CylinderEffectWheel,
    CylinderEffectSuck,
    CylinderEffectScatter,
    CylinderEffectLeftStairs,
    CylinderEffectRightStairs,
    CylinderEffectDoubleDoor,
    CylinderEffectHorizontalAntLines,
    CylinderEffectVerticalAntLines,
    CylinderEffectHyperspace,
    CylinderEffectCount
};

static CylinderEffect g_currentEffect = CylinderEffectCubeInside;
static BOOL g_enabled = YES;
static uint32_t g_randSeed = 0;

static CGFloat screenWidth(void) { return UIScreen.mainScreen.bounds.size.width; }
static CGFloat screenHeight(void) { return UIScreen.mainScreen.bounds.size.height; }
static CGFloat perspDist(void) { return (screenWidth() + screenHeight()) / 2.0; }

// Helper: view width accounting for transform
static CGFloat viewWidth(UIView *v) {
    return v.frame.size.width / v.layer.transform.m11;
}
static CGFloat viewHeight(UIView *v) {
    return v.frame.size.height / v.layer.transform.m22;
}

// Transform helpers (matching CylinderAnimator.swift)
static void cyl_rotate2D(UIView *v, CGFloat angle) {
    v.layer.transform = CATransform3DRotate(v.layer.transform, angle, 0, 0, 1);
}

static void cyl_rotate3D(UIView *v, CGFloat angle, CGFloat pitch, CGFloat yaw, CGFloat roll) {
    CATransform3D t = v.layer.transform;
    if (pitch != 0 || yaw != 0)
        t.m34 = -1.0 / perspDist();
    v.layer.transform = CATransform3DRotate(t, angle, pitch, yaw, roll);
}

static void cyl_scale(UIView *v, CGFloat pct) {
    CATransform3D t = v.layer.transform;
    CGFloat old34 = t.m34;
    t.m34 = -1.0 / perspDist();
    t = CATransform3DScale(t, pct, pct, 1);
    t.m34 = old34;
    v.layer.transform = t;
}

static void cyl_translate2D(UIView *v, CGFloat x, CGFloat y) {
    v.layer.transform = CATransform3DTranslate(v.layer.transform, x, y, 0);
}

static void cyl_translate3D(UIView *v, CGFloat x, CGFloat y, CGFloat z) {
    CATransform3D t = v.layer.transform;
    CGFloat old34 = t.m34;
    t.m34 = -1.0 / perspDist();
    t = CATransform3DTranslate(t, x, y, z);
    t.m34 = old34;
    v.layer.transform = t;
}

#pragma mark - Effect implementations

static void effect_cubeInside(UIView *page, CGFloat offset) {
    CGFloat w = viewWidth(page);
    CGFloat pct = offset / w;
    [page.layer cyl_savePosition];
    CGPoint pos = page.layer.position;
    pos.x += offset;
    page.layer.position = pos;

    CGFloat angle = pct * M_PI / 2.0;
    CGFloat h = w / 2.0;
    CGFloat xv = h * cos(fabs(angle)) - h;
    CGFloat z = h * sin(fabs(angle));
    if (pct > 0) xv = -xv;
    xv -= offset;

    cyl_translate3D(page, xv, 0, z);
    cyl_rotate3D(page, angle, 0, 1, 0);
}

static void effect_cubeOutside(UIView *page, CGFloat offset) {
    CGFloat w = viewWidth(page);
    CGFloat pct = offset / w;
    [page.layer cyl_savePosition];
    CGPoint pos = page.layer.position;
    pos.x += offset;
    page.layer.position = pos;

    CGFloat angle = -pct * M_PI / 2.0;
    CGFloat h = w / 2.0;
    CGFloat xv = h * cos(fabs(angle)) - h;
    CGFloat z = -h * sin(fabs(angle));
    if (pct > 0) xv = -xv;
    xv -= offset;

    cyl_translate3D(page, xv, 0, z);
    cyl_rotate3D(page, angle, 0, 1, 0);

    CGFloat threshold = fabs(atan((perspDist() - z) / xv));
    CGFloat absAngle = fabs(angle);
    if (absAngle > threshold)
        page.alpha = 1.0 - (absAngle - threshold) / (M_PI / 2.0 - threshold);
    else
        page.alpha = 1.0;
}

static void effect_pageFade(UIView *page, CGFloat offset) {
    CGFloat pct = 1.0 - fabs(offset / page.layer.bounds.size.width);
    page.alpha = pct;
    for (UIView *icon in page.subviews)
        icon.alpha = pct;
}

static void effect_pageFlip(UIView *page, CGFloat offset) {
    CGFloat w = viewWidth(page);
    CGFloat pct = offset / w;
    page.alpha = 1.0 - fabs(pct);
    cyl_rotate3D(page, pct * M_PI, 0, 1, 0);
}

static void effect_pageTwist(UIView *page, CGFloat offset) {
    CGFloat w = viewWidth(page);
    CGFloat pct = offset / w;
    page.alpha = 1.0 - fabs(pct);
    cyl_rotate3D(page, -2.0/3.0 * pct * M_PI, 1, 0, 0);
}

static void effect_shrink(UIView *page, CGFloat offset) {
    CGFloat pct = 1.0 - fabs(offset / page.layer.bounds.size.width);
    for (UIView *icon in page.subviews)
        cyl_scale(icon, pct);
}

static void effect_spin(UIView *page, CGFloat offset) {
    CGFloat w = viewWidth(page);
    CGFloat pct = offset / w;
    CGFloat angle = pct * M_PI * 2.0;
    for (UIView *icon in page.subviews)
        cyl_rotate2D(icon, angle);
}

static void effect_hinge(UIView *page, CGFloat offset) {
    CGFloat w = viewWidth(page);
    CGFloat pct = offset / w;
    [page.layer cyl_savePosition];
    CGPoint pos = page.layer.position;
    pos.x += offset;
    page.layer.position = pos;

    CGFloat angle = pct * M_PI;
    CGFloat x = w / 2.0;
    if (pct > 0) x = -x;

    cyl_translate2D(page, x, 0);
    cyl_rotate3D(page, angle, 0, 1, 0);
    cyl_translate2D(page, -x, 0);
}

static void effect_backwards(UIView *page, CGFloat offset) {
    cyl_translate2D(page, 2.0 * offset, 0);
}

static void effect_verticalScrolling(UIView *page, CGFloat offset) {
    CGFloat w = viewWidth(page);
    CGFloat h = viewHeight(page);
    CGFloat pct = offset / w;
    cyl_translate2D(page, offset, pct * h);
    page.alpha = 1.0 - fabs(pct);
}

static void effect_cardHorizontal(UIView *page, CGFloat offset) {
    CGFloat w = viewWidth(page);
    [page.layer cyl_savePosition];
    CGPoint pos = page.layer.position;
    pos.x += offset;
    page.layer.position = pos;

    CGFloat pct = offset / w;
    if (fabs(pct) >= 0.5) page.alpha = 0;
    cyl_rotate3D(page, -M_PI * pct, 0, 1, 0);
}

static void effect_cardVertical(UIView *page, CGFloat offset) {
    CGFloat w = viewWidth(page);
    [page.layer cyl_savePosition];
    CGPoint pos = page.layer.position;
    pos.x += offset;
    page.layer.position = pos;

    CGFloat pct = offset / w;
    if (fabs(pct) >= 0.5) page.alpha = 0;
    cyl_rotate3D(page, M_PI * pct, 1, 0, 0);
}

static void effect_iconCollection(SBIconListView *page, CGFloat offset) {
    CGFloat w = viewWidth(page);
    CGFloat h = viewHeight(page);
    CGFloat pct = fabs(offset / w);
    CGFloat cx = w / 2.0;
    CGFloat cy = h / 2.0;

    [(id)page enumerateIconViewsUsingBlock:^(SBIconView *icon, NSUInteger idx, BOOL *stop) {
        CGFloat x = icon.frame.origin.x + icon.frame.size.width / 2.0;
        CGFloat y = icon.frame.origin.y + icon.frame.size.height / 2.0;
        CGFloat hyp = pct * hypot(x - cx, y - cy);
        CGFloat angle = atan((cx - x) / (cy - y));
        if (y > cy) hyp = -hyp;
        cyl_translate2D(icon, hyp * sin(angle), hyp * cos(angle));
    }];
}

static void effect_vortex(UIView *page, CGFloat offset) {
    CGFloat w = viewWidth(page);
    CGFloat h = viewHeight(page);
    CGFloat pct = fabs(offset / w);
    CGFloat cx = w / 2.0;
    CGFloat cy = h / 2.0 + 7.0;
    CGFloat radius = 0.60 * cx;
    if (radius > h) radius = 0.60 * h / 2.0;

    NSUInteger count = page.subviews.count;
    CGFloat theta = (2.0 * M_PI) / (CGFloat)count;
    CGFloat s1 = fmin(pct * 3.0, 1.0);
    CGFloat s2 = fmax(fmin(pct * 3.0 - 1.0, 1.0), 0);
    CGFloat s3 = s2 * (M_PI / 3.0);

    NSUInteger i = 0;
    for (UIView *icon in page.subviews) {
        CGFloat iAngle = theta * (CGFloat)i - M_PI / 6.0 + s3;
        CGFloat bx = icon.frame.origin.x + icon.frame.size.width / 2.0;
        CGFloat by = icon.frame.origin.y + icon.frame.size.height / 2.0;
        CGFloat ex = cx + radius * cos(iAngle);
        CGFloat ey = cy - radius * sin(iAngle);
        cyl_translate2D(icon, (ex - bx) * s1, (ey - by) * s1);
        cyl_rotate2D(icon, -s1 * (M_PI / 2.0 + iAngle));
        i++;
    }
    page.alpha = 1.0 - s2;
    cyl_translate2D(page, offset, 0);
}

static void effect_wave(UIView *page, CGFloat offset) {
    CGFloat w = viewWidth(page);
    CGFloat pct = fabs(offset / w);
    NSInteger numIcons = (NSInteger)page.subviews.count;

    NSInteger i = 0;
    for (UIView *icon in page.subviews) {
        CGFloat dir = (offset < 0) ? 1.0 : -1.0;
        CGFloat iconIdx = (CGFloat)((offset < 0) ? numIcons - i : i - 1);
        CGFloat cur = pct - ((0.525 / (CGFloat)numIcons) * iconIdx);
        if (cur > 0) {
            CGFloat dx = dir * (cur * pow(3.5, 2)) * w;
            cyl_translate2D(icon, dx, 0);
        }
        i++;
    }
    cyl_translate2D(page, offset, 0);
}

static void effect_wheel(UIView *page, CGFloat offset) {
    CGFloat w = viewWidth(page);
    [page.layer cyl_savePosition];
    CGPoint pos = page.layer.position;
    pos.x += offset;
    page.layer.position = pos;

    CGFloat pct = offset / w;
    for (UIView *icon in page.subviews) {
        CGFloat icx = icon.frame.origin.x + icon.frame.size.width / 2.0;
        CGFloat icy = icon.frame.origin.y + icon.frame.size.height / 2.0;
        CGFloat icxOff = w / 2.0 - icx;
        CGFloat iconRad = screenHeight() - icy;
        CGFloat pct2 = ((offset < 0) ? icx : w - icx) / w;
        CGFloat angle = -pct * (1.0 + pct2 * 2.0) * M_PI / 2.0;
        cyl_translate2D(icon, icxOff, iconRad);
        cyl_rotate2D(icon, angle);
        cyl_translate2D(icon, -icxOff, -iconRad);
    }
}

static void effect_suck(UIView *page, CGFloat offset) {
    CGFloat w = viewWidth(page);
    CGFloat h = viewHeight(page);
    CGFloat pct = offset / w;
    CGFloat fixed = fabs(pct);
    CGFloat side = (pct > 0) ? 1.0 : 0.0;

    for (UIView *icon in page.subviews) {
        CGFloat icx = icon.frame.origin.x + icon.frame.size.width / 2.0;
        CGFloat icy = icon.frame.origin.y + icon.frame.size.height / 2.0;
        CGFloat absX = icx + side * (screenWidth() - 2.0 * icx);
        CGFloat pathX = w * side;
        CGFloat pathY = h + 7.0 + icon.frame.size.height / (2.0 * (icon.layer.transform.m22 ?: 1.0));
        CGFloat iAngle = atan(icy / absX);
        cyl_translate2D(icon, (pathX - icx) * fixed, (pathY - icy) * fixed);
        cyl_rotate2D(icon, pct * iAngle);
        cyl_scale(icon, sqrt(-fixed + 1.0));
    }
}

static void effect_scatter(SBIconListView *page, CGFloat offset) {
    CGFloat w = viewWidth(page);
    CGFloat h = viewHeight(page);
    CGFloat pct = fabs(offset / w);

    [(id)page enumerateIconViewsUsingBlock:^(SBIconView *icon, NSUInteger idx, BOOL *stop) {
        if (idx % 2 == 1)
            cyl_translate2D(icon, 0, pct * h / 2.0);
        else
            cyl_translate2D(icon, 0, -pct * h / 2.0);
    }];
}

static void effect_leftStairs(UIView *page, CGFloat offset) {
    CGFloat w = viewWidth(page);
    CGFloat pct = offset / w;
    cyl_translate3D(page, pct * -20.0, 0, pct * -100.0);
}

static void effect_rightStairs(UIView *page, CGFloat offset) {
    CGFloat w = viewWidth(page);
    CGFloat pct = offset / w;
    cyl_translate3D(page, pct * -20.0, 0, pct * 100.0);
}

static void effect_doubleDoor(UIView *page, CGFloat offset) {
    CGFloat w = viewWidth(page);
    cyl_translate2D(page, offset, 0);
    CGFloat pct = fabs(offset / w);
    for (UIView *icon in page.subviews) {
        if (icon.frame.origin.x + icon.frame.size.width / 2.0 > w / 2.0)
            cyl_translate2D(icon, pct * w, 0);
        else
            cyl_translate2D(icon, -pct * w, 0);
    }
}

static void effect_horizontalAntLines(UIView *page, CGFloat offset) {
    CGFloat w = viewWidth(page);
    CGFloat pct = offset / w;
    cyl_translate2D(page, offset, 0);
    page.alpha = 1.0 - fabs(pct);
    CGFloat dir = 1.0;
    CGFloat lastY = 0;
    for (UIView *icon in page.subviews) {
        if (icon.frame.origin.y > lastY) {
            dir = -dir;
            lastY = icon.frame.origin.y;
        }
        cyl_translate2D(icon, dir * offset, 0);
    }
}

static void effect_verticalAntLines(UIView *page, CGFloat offset) {
    CGFloat w = viewWidth(page);
    CGFloat h = viewHeight(page);
    CGFloat pct = offset / w;
    cyl_translate2D(page, offset, 0);
    page.alpha = 1.0 - fabs(pct);
    CGFloat dir = 1.0;
    CGFloat lastX = w;
    for (UIView *icon in page.subviews) {
        if (lastX > icon.frame.origin.x)
            dir = -1.0;
        else
            dir = -dir;
        lastX = icon.frame.origin.x;
        cyl_translate2D(icon, 0, dir * pct * h);
    }
}

static void effect_hyperspace(SBIconListView *page, CGFloat offset) {
    CGFloat w = viewWidth(page);
    CGFloat h = viewHeight(page);
    CGFloat pct = fabs(offset / w);
    CGFloat rollup = fmin(pct * 5.0, 1.0);
    CGFloat front = (offset > 0) ? 1.0 : -1.0;
    CGFloat runaway = fmax(fmin((pct - 0.2) / 0.7, 1.0), 0);
    CGFloat midX = w / 2.0;
    CGFloat midY = h / 2.0 + 7.0;

    [(id)page enumerateIconViewsUsingBlock:^(SBIconView *icon, NSUInteger idx, BOOL *stop) {
        CGFloat icx = icon.frame.origin.x + icon.frame.size.width / 2.0;
        CGFloat icy = icon.frame.origin.y + icon.frame.size.height / 2.0;
        CGFloat angle = atan((midY - icy) / (midX - icx));
        CGFloat side = (midX < icx) ? -1.0 : 1.0;
        CGFloat pitch = M_PI / 2.4;

        if (fabs(angle) == M_PI / 2.0) {
            CGFloat side2 = (midX - icy > 0) ? -1.0 : 1.0;
            cyl_rotate3D(icon, rollup * pitch * side2, 1, 0, 0);
            cyl_translate2D(icon, -500.0 * runaway * side2 * front, 0);
        } else {
            cyl_rotate2D(icon, rollup * angle);
        }
        cyl_rotate3D(icon, rollup * pitch * side, 0, 1, 0);
        cyl_translate2D(icon, 500.0 * runaway * side * front, 0);
        icon.alpha = 1.0 - runaway;
    }];

    cyl_translate2D(page, offset, 0);
}

typedef void (*EffectFunc)(id page, CGFloat offset);

static EffectFunc effectForType(CylinderEffect type) {
    switch (type) {
        case CylinderEffectCubeInside: return (EffectFunc)effect_cubeInside;
        case CylinderEffectCubeOutside: return (EffectFunc)effect_cubeOutside;
        case CylinderEffectPageFade: return (EffectFunc)effect_pageFade;
        case CylinderEffectPageFlip: return (EffectFunc)effect_pageFlip;
        case CylinderEffectPageTwist: return (EffectFunc)effect_pageTwist;
        case CylinderEffectShrink: return (EffectFunc)effect_shrink;
        case CylinderEffectSpin: return (EffectFunc)effect_spin;
        case CylinderEffectHinge: return (EffectFunc)effect_hinge;
        case CylinderEffectBackwards: return (EffectFunc)effect_backwards;
        case CylinderEffectVerticalScrolling: return (EffectFunc)effect_verticalScrolling;
        case CylinderEffectCardHorizontal: return (EffectFunc)effect_cardHorizontal;
        case CylinderEffectCardVertical: return (EffectFunc)effect_cardVertical;
        case CylinderEffectIconCollection: return (EffectFunc)effect_iconCollection;
        case CylinderEffectVortex: return (EffectFunc)effect_vortex;
        case CylinderEffectWave: return (EffectFunc)effect_wave;
        case CylinderEffectWheel: return (EffectFunc)effect_wheel;
        case CylinderEffectSuck: return (EffectFunc)effect_suck;
        case CylinderEffectScatter: return (EffectFunc)effect_scatter;
        case CylinderEffectLeftStairs: return (EffectFunc)effect_leftStairs;
        case CylinderEffectRightStairs: return (EffectFunc)effect_rightStairs;
        case CylinderEffectDoubleDoor: return (EffectFunc)effect_doubleDoor;
        case CylinderEffectHorizontalAntLines: return (EffectFunc)effect_horizontalAntLines;
        case CylinderEffectVerticalAntLines: return (EffectFunc)effect_verticalAntLines;
        case CylinderEffectHyperspace: return (EffectFunc)effect_hyperspace;
        default: return (EffectFunc)effect_cubeInside;
    }
}

#pragma mark - Icon layout reset

static void reset_icon_layout(SBIconListView *page) {
    ((UIView *)page).layer.transform = CATransform3DIdentity;
    [((UIView *)page).layer cyl_restorePosition];
    ((UIView *)page).alpha = 1.0;
    [(id)page enumerateIconViewsUsingBlock:^(SBIconView *v, NSUInteger idx, BOOL *stop) {
        v.layer.transform = CATransform3DIdentity;
        v.alpha = 1.0;
    }];
}

// Associated object for wasModifiedByCylinder
static BOOL getWasModified(id self) {
    return [objc_getAssociatedObject(self, @selector(wasModifiedByCylinder)) boolValue];
}
static void setWasModified(id self, BOOL val) {
    objc_setAssociatedObject(self, @selector(wasModifiedByCylinder), @(val), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

#pragma mark - Hook: scrollViewDidScroll:

static void (*orig_scrollViewDidScroll)(id self, SEL _cmd, id scrollView);
static void hook_scrollViewDidScroll(id self, SEL _cmd, id scrollView) {
    orig_scrollViewDidScroll(self, _cmd, scrollView);
    if (!g_enabled) return;

    UIScrollView *sv = (UIScrollView *)scrollView;
    CGRect eye = (CGRect){ sv.contentOffset, sv.frame.size };
    EffectFunc doEffect = effectForType(g_currentEffect);

    for (SBIconListView *view in [(SBFolderView *)self iconListViews]) {
        if (((UIView *)view).subviews.count < 1) continue;
        if (getWasModified(view)) reset_icon_layout(view);
        if (CGRectIntersectsRect(eye, ((UIView *)view).frame)) {
            CGFloat offset = sv.contentOffset.x - ((UIView *)view).frame.origin.x;
            doEffect(view, offset);
            setWasModified(view, YES);
        }
    }
}

#pragma mark - Hook: scrollViewDidEndDecelerating:

static void (*orig_scrollViewDidEndDecelerating)(id self, SEL _cmd, id scrollView);
static void hook_scrollViewDidEndDecelerating(id self, SEL _cmd, id scrollView) {
    orig_scrollViewDidEndDecelerating(self, _cmd, scrollView);
    if (!g_enabled) return;

    [(SBFolderView *)self enumerateIconListViewsUsingBlock:^(SBIconListView *view) {
        reset_icon_layout(view);
        [(id)view setAlphaForAllIcons:1.0];
        setWasModified(view, NO);
    }];
    g_randSeed = arc4random();
}

#pragma mark - Hook: updateVisibleColumnRange (iOS 15+ — prevent icon recycling)

static void (*orig_updateVisible)(id self, SEL _cmd, NSUInteger totalLists, NSInteger handling);
static void hook_updateVisible(id self, SEL _cmd, NSUInteger totalLists, NSInteger handling) {
    orig_updateVisible(self, _cmd, totalLists, 0);
}

#pragma mark - Effect switching via notification

static void setEffectFromNotification(CFNotificationCenterRef center, void *observer,
    CFNotificationName name, const void *object, CFDictionaryRef userInfo) {
    // Cycle to next effect
    g_currentEffect = (g_currentEffect + 1) % CylinderEffectCount;
    NSLog(@"[Cylinder] Switched to effect %ld", (long)g_currentEffect);
}

#pragma mark - Helper: swizzle instance method

static void hookMethod(Class cls, SEL sel, void *replacement, void **original) {
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) return;
    *original = (void *)method_getImplementation(m);
    method_setImplementation(m, (IMP)replacement);
}

#pragma mark - Constructor

__attribute__((constructor))
static void CylinderActivatorInit(void) {
    NSLog(@"[Cylinder] CylinderActivator loading...");

    // Hook SBFolderView scrollViewDidScroll: / scrollViewDidEndDecelerating:
    Class folderViewCls = objc_getClass("SBFolderView");
    if (folderViewCls) {
        hookMethod(folderViewCls, @selector(scrollViewDidScroll:),
                   (void *)hook_scrollViewDidScroll, (void **)&orig_scrollViewDidScroll);
        hookMethod(folderViewCls, @selector(scrollViewDidEndDecelerating:),
                   (void *)hook_scrollViewDidEndDecelerating, (void **)&orig_scrollViewDidEndDecelerating);
        NSLog(@"[Cylinder] Hooked SBFolderView scroll methods");
    }

    // Hook SBRootFolderView updateVisibleColumnRangeWithTotalLists:iconVisibilityHandling: (iOS 15+)
    Class rootFolderCls = objc_getClass("SBRootFolderView");
    if (rootFolderCls) {
        SEL updateSel = NSSelectorFromString(@"updateVisibleColumnRangeWithTotalLists:iconVisibilityHandling:");
        Method m = class_getInstanceMethod(rootFolderCls, updateSel);
        if (m) {
            hookMethod(rootFolderCls, updateSel,
                       (void *)hook_updateVisible, (void **)&orig_updateVisible);
            NSLog(@"[Cylinder] Hooked updateVisibleColumnRange (iOS 15+)");
        }
    }

    // Add wasModifiedByCylinder property to SBIconListView
    Class iconListCls = objc_getClass("SBIconListView");
    if (iconListCls) {
        class_addMethod(iconListCls, @selector(wasModifiedByCylinder),
                        imp_implementationWithBlock(^BOOL(id self){ return getWasModified(self); }), "B@:");
        class_addMethod(iconListCls, @selector(setWasModifiedByCylinder:),
                        imp_implementationWithBlock(^(id self, BOOL v){ setWasModified(self, v); }), "v@:B");
    }

    // Listen for effect-switch notification (can be triggered from command server)
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL,
        setEffectFromNotification, CFSTR("com.coruna.cylinder.nextEffect"), NULL,
        CFNotificationSuspensionBehaviorCoalesce);

    g_randSeed = arc4random();

    NSLog(@"[Cylinder] Active — effect: Cube (inside)");
}
