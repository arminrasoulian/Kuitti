# Kuitti — brand assets (icon & launch)

Everything visual about the Kuitti brand is generated from code here, so the app
icon and launch logo are reproducible and tweakable. No design app required.

## Concept

A clean white **receipt** on a spruce-green gradient, whose lower half is an
**upward price-history trend line** that rises across the receipt and **breaks
past the top edge into an arrow**. It says, in one mark, what the app does: turn
a paper receipt into a rising story of what things cost. Spruce green is the
brand color (`#157F5F` / `#1FA57B`), matching the in-app accent.

This concept was chosen from a 6-direction exploration (runner-ups: a "K"
monogram built from a receipt + trend arm, and a receipt whose line-items grow
into a bar chart).

## Files

| File | What |
|------|------|
| `icon.py` | Generates the SVGs (all geometry is computed here). |
| `render.py` | Rasterizes an SVG → PNG via macOS `sips`, and **strips the alpha channel** (App Store marketing icons must be opaque RGB). |
| `sources/icon_master.svg` | Full-bleed 1024 app icon (opaque gradient bg). |
| `sources/mark_launch.svg` | Receipt **without** the trend, transparent, cropped square — the static launch image. |
| `sources/mark_full.svg` | Receipt **with** the trend — reference; equals the splash's final frame and the icon foreground. |

## Regenerate

```bash
cd Design
python3 icon.py                                   # rewrite sources/*.svg

ASSETS=../Kuitti/Resources/Assets.xcassets
# App icon (1024, NO alpha — required by the App Store)
python3 render.py svg2png sources/icon_master.svg "$ASSETS/AppIcon.appiconset/AppIcon.png" 1024
# Launch logo (transparent) at 1x/2x/3x for a ~240pt centered mark
python3 render.py svg2png sources/mark_launch.svg "$ASSETS/LaunchLogo.imageset/launch@1x.png" 240 --keep-alpha
python3 render.py svg2png sources/mark_launch.svg "$ASSETS/LaunchLogo.imageset/launch@2x.png" 480 --keep-alpha
python3 render.py svg2png sources/mark_launch.svg "$ASSETS/LaunchLogo.imageset/launch@3x.png" 720 --keep-alpha
```

No third-party tools needed — only the system `python3` and `sips`.

## How it ties into the app

- **App icon**: single 1024 universal icon (`AppIcon.appiconset`); Xcode renders
  every device size from it at build time.
- **Launch screen**: configured in `project.yml` (`UILaunchScreen` →
  `UIColorName: LaunchBG`, `UIImageName: LaunchLogo`), **not** the generated
  `Info.plist`. Background color lives in `Assets.xcassets/LaunchBG.colorset`.
- **Animated splash**: `Kuitti/Features/Splash/SplashView.swift` redraws the
  trend as native SwiftUI shapes over the static launch mark and animates it on.
  Its `Mark` geometry mirrors the constants in `icon.py` — **keep them in sync**
  if you change the trend shape.
```
