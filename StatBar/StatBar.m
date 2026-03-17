// StatusBarInfoActivator.m — CPU temp + RAM info in the status bar
// Standalone dylib for Coruna — no substrate/Theos
// Inspired by Orion tweak

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <mach/mach.h>
#import <mach/mach_host.h>
#import <sys/sysctl.h>
#import <dlfcn.h>

#pragma mark - Device temperature via IOKit (battery temperature)

#include <IOKit/IOKitLib.h>

static double getDeviceTemperature(void) {
    // AppleSmartBattery exposes Temperature in centidegrees Celsius (e.g. 2950 = 29.5°C)
    io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault,
        IOServiceMatching("AppleSmartBattery"));
    if (!service) return -1;

    double temp = -1;
    CFTypeRef prop = IORegistryEntryCreateCFProperty(service, CFSTR("Temperature"), kCFAllocatorDefault, 0);
    if (prop) {
        if (CFGetTypeID(prop) == CFNumberGetTypeID()) {
            int64_t raw = 0;
            CFNumberGetValue(prop, kCFNumberSInt64Type, &raw);
            temp = (double)raw / 100.0; // centidegrees → degrees
        }
        CFRelease(prop);
    }
    IOObjectRelease(service);
    return temp;
}

#pragma mark - RAM info

typedef struct {
    double usedMB;
    double freeMB;
    double totalMB;
} RAMInfo;

static RAMInfo getRAMInfo(void) {
    RAMInfo info = {0, 0, 0};

    mach_port_t host = mach_host_self();
    vm_statistics64_data_t vmstat;
    mach_msg_type_number_t count = HOST_VM_INFO64_COUNT;

    if (host_statistics64(host, HOST_VM_INFO64, (host_info64_t)&vmstat, &count) != KERN_SUCCESS) {
        return info;
    }

    double pageSize = (double)vm_kernel_page_size;
    double totalPages = vmstat.free_count + vmstat.active_count +
                        vmstat.inactive_count + vmstat.wire_count +
                        vmstat.compressor_page_count;

    info.totalMB = (totalPages * pageSize) / (1024.0 * 1024.0);
    info.freeMB = ((double)(vmstat.free_count + vmstat.inactive_count) * pageSize) / (1024.0 * 1024.0);
    info.usedMB = info.totalMB - info.freeMB;

    // Use physical memory for total if available
    uint64_t physMem = [NSProcessInfo processInfo].physicalMemory;
    if (physMem > 0) {
        info.totalMB = (double)physMem / (1024.0 * 1024.0);
        info.freeMB = info.totalMB - info.usedMB;
    }

    return info;
}

#pragma mark - Status bar label

static UILabel *g_infoLabel = nil;
static NSTimer *g_updateTimer = nil;
static BOOL g_useFahrenheit = NO;

static void updateInfoLabel(void) {
    if (!g_infoLabel) return;

    double temp = getDeviceTemperature();
    RAMInfo ram = getRAMInfo();

    NSMutableString *text = [NSMutableString string];
    if (temp > 0) {
        if (g_useFahrenheit) {
            [text appendFormat:@"%.1f°F  ", temp * 9.0 / 5.0 + 32.0];
        } else {
            [text appendFormat:@"%.1f°C  ", temp];
        }
    }
    if (ram.usedMB > 0) {
        [text appendFormat:@"U: %.0fMB  F: %.0fMB", ram.usedMB, ram.freeMB];
    }

    g_infoLabel.text = text;
}

static BOOL g_created = NO;

static void createStatusBarInfo(void) {
    if (g_created) return;
    g_created = YES;

    dispatch_async(dispatch_get_main_queue(), ^{
        // Find the status bar
        UIWindow *statusBarWindow = nil;
        UIView *statusBar = nil;

        for (UIWindowScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if (![scene isKindOfClass:[UIWindowScene class]]) continue;
            id sbWindow = ((id (*)(id, SEL))objc_msgSend)(scene, sel_registerName("statusBarManager"));
            if (!sbWindow) continue;

            for (UIWindow *w in scene.windows) {
                // Look for the status bar window
                if (w.windowLevel > 1000) {
                    statusBarWindow = w;
                    break;
                }
            }
            if (statusBarWindow) break;
        }

        // Create an overlay window for the info label
        UIWindowScene *scene = nil;
        for (UIScene *s in [UIApplication sharedApplication].connectedScenes) {
            if ([s isKindOfClass:[UIWindowScene class]]) {
                scene = (UIWindowScene *)s;
                break;
            }
        }
        if (!scene) return;

        CGFloat screenW = [UIScreen mainScreen].bounds.size.width;

        // Dynamic Island devices: place info just below the island
        CGFloat labelY = 59;
        CGFloat labelH = 14;
        CGFloat windowH = labelY + labelH + 2;

        UIWindow *overlay = [[UIWindow alloc] initWithWindowScene:scene];
        overlay.frame = CGRectMake(0, 0, screenW, windowH);
        overlay.windowLevel = 100001;
        overlay.userInteractionEnabled = NO;
        overlay.backgroundColor = [UIColor clearColor];
        overlay.opaque = NO;

        UIViewController *vc = [[UIViewController alloc] init];
        vc.view.backgroundColor = [UIColor clearColor];
        vc.view.userInteractionEnabled = NO;
        overlay.rootViewController = vc;

        // Semi-transparent background strip
        UIView *strip = [[UIView alloc] initWithFrame:CGRectMake(0, labelY, screenW, labelH + 2)];
        strip.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.35];
        [vc.view addSubview:strip];

        g_infoLabel = [[UILabel alloc] initWithFrame:CGRectMake(8, labelY, screenW - 16, labelH)];
        g_infoLabel.font = [UIFont monospacedSystemFontOfSize:10 weight:UIFontWeightMedium];
        g_infoLabel.textColor = [UIColor whiteColor];
        g_infoLabel.textAlignment = NSTextAlignmentCenter;
        g_infoLabel.backgroundColor = [UIColor clearColor];
        g_infoLabel.adjustsFontSizeToFitWidth = YES;
        g_infoLabel.minimumScaleFactor = 0.7;
        [vc.view addSubview:g_infoLabel];

        overlay.hidden = NO;

        // Keep reference so it doesn't get deallocated
        objc_setAssociatedObject([UIApplication sharedApplication], "statusBarInfoWindow", overlay, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

        // Update immediately then every 3 seconds
        updateInfoLabel();
        g_updateTimer = [NSTimer scheduledTimerWithTimeInterval:3.0 repeats:YES block:^(NSTimer *t) {
            updateInfoLabel();
        }];

        NSLog(@"[StatusBarInfo] Active");
    });
}

#pragma mark - Constructor

static void showSettingsPicker(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIAlertController *picker = [UIAlertController alertControllerWithTitle:@"Status Bar Info"
            message:@"Choose temperature unit."
            preferredStyle:UIAlertControllerStyleAlert];

        [picker addAction:[UIAlertAction actionWithTitle:g_useFahrenheit ? @"Celsius" : @"Celsius ✓"
            style:UIAlertActionStyleDefault
            handler:^(__unused UIAlertAction *a) {
                g_useFahrenheit = NO;
                updateInfoLabel();
            }]];

        [picker addAction:[UIAlertAction actionWithTitle:g_useFahrenheit ? @"Fahrenheit ✓" : @"Fahrenheit"
            style:UIAlertActionStyleDefault
            handler:^(__unused UIAlertAction *a) {
                g_useFahrenheit = YES;
                updateInfoLabel();
            }]];

        [picker addAction:[UIAlertAction actionWithTitle:@"Cancel"
            style:UIAlertActionStyleCancel handler:nil]];

        UIViewController *root = nil;
        for (UIWindowScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if (![scene isKindOfClass:[UIWindowScene class]]) continue;
            for (UIWindow *w in scene.windows) {
                if (w.isKeyWindow) { root = w.rootViewController; break; }
            }
            if (root) break;
        }
        if (!root) root = [[UIApplication sharedApplication].keyWindow rootViewController];
        while (root.presentedViewController) root = root.presentedViewController;
        [root presentViewController:picker animated:YES completion:nil];
    });
}

__attribute__((constructor))
static void StatusBarInfoInit(void) {
    NSLog(@"[StatusBarInfo] Loading...");

    // Delete staged file so re-loading via file picker re-runs constructor
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_global_queue(0, 0), ^{
        [[NSFileManager defaultManager] removeItemAtPath:@"/tmp/TweakInject/StatusBarInfoActivator.dylib" error:nil];
    });

    static BOOL created = NO;
    if (created) {
        // Re-loaded — just show settings
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            showSettingsPicker();
        });
        return;
    }
    created = YES;

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        createStatusBarInfo();
    });

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        showSettingsPicker();
    });
}
