// Quick test to validate that the CoreGraphics display detection
// (same approach Moonlight uses in StreamUtils::getNativeDesktopMode)
// correctly identifies native resolutions and refresh rates on this machine.

#import <CoreGraphics/CoreGraphics.h>
#import <Foundation/Foundation.h>

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        // Enumerate displays (same as Moonlight's getNativeDesktopMode on macOS)
        CGDirectDisplayID displayIds[16];
        uint32_t displayCount = 0;
        CGGetActiveDisplayList(16, displayIds, &displayCount);

        printf("=== Display Detection Test (CoreGraphics - same as Moonlight) ===\n\n");
        printf("Found %u active display(s)\n\n", displayCount);

        for (uint32_t i = 0; i < displayCount; i++) {
            CGDirectDisplayID displayId = displayIds[i];
            printf("--- Display %u (ID: %u) ---\n", i, displayId);
            printf("  Built-in: %s\n", CGDisplayIsBuiltin(displayId) ? "YES" : "NO");

            // Get current display mode
            CGDisplayModeRef currentMode = CGDisplayCopyDisplayMode(displayId);
            if (currentMode) {
                size_t curW = CGDisplayModeGetWidth(currentMode);
                size_t curH = CGDisplayModeGetHeight(currentMode);
                double curRefresh = CGDisplayModeGetRefreshRate(currentMode);
                uint32_t ioFlags = CGDisplayModeGetIOFlags(currentMode);
                printf("  Current mode: %zux%zu @ %.1f Hz (native flag: %s)\n",
                       curW, curH, curRefresh,
                       (ioFlags & kDisplayModeNativeFlag) ? "YES" : "NO");
                CGDisplayModeRelease(currentMode);
            }

            // Enumerate all modes and find native (same algorithm as Moonlight)
            CFArrayRef modeList = CGDisplayCopyAllDisplayModes(displayId, NULL);
            CFIndex count = CFArrayGetCount(modeList);

            printf("  Total modes available: %ld\n", (long)count);

            // Find native mode (Moonlight's approach: look for kDisplayModeNativeFlag)
            int nativeW = 0, nativeH = 0;
            double nativeRefresh = 0;
            for (CFIndex j = 0; j < count; j++) {
                CGDisplayModeRef cgMode = (CGDisplayModeRef)CFArrayGetValueAtIndex(modeList, j);
                uint32_t flags = CGDisplayModeGetIOFlags(cgMode);
                if (flags & kDisplayModeNativeFlag) {
                    nativeW = (int)CGDisplayModeGetWidth(cgMode);
                    nativeH = (int)CGDisplayModeGetHeight(cgMode);
                    nativeRefresh = CGDisplayModeGetRefreshRate(cgMode);
                    printf("  >> NATIVE mode found: %dx%d @ %.1f Hz\n", nativeW, nativeH, nativeRefresh);
                    break;
                }
            }

            if (nativeW == 0) {
                printf("  >> WARNING: No native mode flag found!\n");
            }

            // Also check for notch safe area (Moonlight's approach for ARM64 Macs)
            #if TARGET_CPU_ARM64
            if (CGDisplayIsBuiltin(displayId) && nativeW > 0) {
                for (CFIndex j = 0; j < count; j++) {
                    CGDisplayModeRef cgMode = (CGDisplayModeRef)CFArrayGetValueAtIndex(modeList, j);
                    int modeW = (int)CGDisplayModeGetWidth(cgMode);
                    int modeH = (int)CGDisplayModeGetHeight(cgMode);
                    if (nativeW == modeW && nativeH != modeH && nativeH <= modeH + 100) {
                        printf("  >> Safe area (notch) mode: %dx%d\n", modeW, modeH);
                    }
                }
            }
            #endif

            // Find highest refresh rate at native resolution
            double maxRefresh = 0;
            for (CFIndex j = 0; j < count; j++) {
                CGDisplayModeRef cgMode = (CGDisplayModeRef)CFArrayGetValueAtIndex(modeList, j);
                int modeW = (int)CGDisplayModeGetWidth(cgMode);
                int modeH = (int)CGDisplayModeGetHeight(cgMode);
                double refresh = CGDisplayModeGetRefreshRate(cgMode);
                if (modeW == nativeW && modeH == nativeH && refresh > maxRefresh) {
                    maxRefresh = refresh;
                }
            }
            if (maxRefresh > 0) {
                printf("  Max refresh at native res: %.1f Hz\n", maxRefresh);
            }

            CFRelease(modeList);
            printf("\n");
        }

        printf("=== Conclusion ===\n");
        printf("If native resolutions above match your actual display specs,\n");
        printf("the existing Moonlight detection (StreamUtils::getNativeDesktopMode)\n");
        printf("will work correctly for the 'Match current display' feature.\n");
    }
    return 0;
}
