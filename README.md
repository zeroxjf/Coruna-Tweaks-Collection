# Coruna Tweaks Collection

Standalone tweak dylibs for the [Coruna](https://github.com/khanhduytran0/coruna) exploit chain (iOS 13.0 - 17.2.1). No substrate, no ellekit — pure ObjC runtime hooking.

## Tweaks

### FloatingDockXVI
iPad-style floating dock on iPhone with 6-icon support.

- **Original tweak:** [FloatingDockXVI](https://github.com/nahtedetihw/FloatingDockXVI) by [@EthanWhited](https://x.com/EthanWhited)
- **Source:** [`FloatingDock/FloatingDockActivator.m`](FloatingDock/FloatingDockActivator.m)

### Cylinder Remade
24 page-swipe animations for the home screen (cube, vortex, wave, spin, etc.).

- **Original tweak:** [Cylinder Remade](https://github.com/ryannair05/Cylinder-Remade) by ryannair05
- **Source:** [`Cylinder/CylinderActivator.m`](Cylinder/CylinderActivator.m)

## Usage

1. Run the Coruna exploit chain from `index.html`
2. Long-press the status bar or tap **Options Menu**
3. Select **Floating Dock** or **Cylinder** from the popup

These are session-only — reload after respring/reboot.

## Building

```bash
# FloatingDockActivator
xcrun --sdk iphoneos clang -target arm64e-apple-ios14.0 -fobjc-arc -dynamiclib \
  -o FloatingDockActivator.dylib FloatingDock/FloatingDockActivator.m \
  -framework Foundation -framework UIKit -lobjc \
  -Wl,-dead_strip -Os -undefined dynamic_lookup && \
codesign -s - FloatingDockActivator.dylib

# CylinderActivator
xcrun --sdk iphoneos clang -target arm64e-apple-ios14.0 -fobjc-arc -dynamiclib \
  -o CylinderActivator.dylib Cylinder/CylinderActivator.m \
  -framework Foundation -framework UIKit -framework QuartzCore -lobjc \
  -Wl,-dead_strip -Os -undefined dynamic_lookup && \
codesign -s - CylinderActivator.dylib
```

## Pre-built

Pre-built ad-hoc signed dylibs are in [`dylibs/`](dylibs/).

## Credits

- [FloatingDockXVI](https://github.com/nahtedetihw/FloatingDockXVI) by [@EthanWhited](https://x.com/EthanWhited) — original floating dock tweak
- [Cylinder Remade](https://github.com/ryannair05/Cylinder-Remade) by ryannair05 — original page animation tweak
- [Coruna](https://github.com/khanhduytran0/coruna) by 34306, Duy Tran, Nick Chan — exploit chain
