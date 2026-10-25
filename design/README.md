# Podium brand kit

Direction: **The Raised Platform**, three glass tiers with the top one lit. Colours: night `#2B2E5A → #0A0B1B`, stage light `#FFC26B → #FF6A3D`. Wordmark font: Inter (SIL Open Font License). The tagline "Stage your work." is a placeholder.

| Asset | File | Size |
|---|---|---|
| App icon (static, glass baked in) | `kit/app-icon/AppIcon.icns`, `AppIcon-1024.png` | 16–1024 px; 824 px tile inside a 1024 px canvas |
| App icon, editable glass preview | `kit/app-icon/AppIcon-glass-preview.svg` | 1024 × 1024 |
| Flat layers for Apple's Icon Composer | `kit/flat-layers/*.svg` (background + 3 tiers) | 1024 × 1024, no filters |
| Menu-bar icon (template) | `kit/menu-bar/PodiumMenuTemplate.png`, `@2x`, `@3x`, `menubar-template.svg` | 18 / 36 / 54 px, black on transparent |
| README banner | `kit/github/readme-banner.png` | 1600 × 400 |
| Social preview | `kit/github/social-preview.png` | 1280 × 640 (upload under Settings → General) |
| Installer background | `kit/installer/background.tiff` (1× + 2×), plus the two PNGs | 660 × 400 pt; icons go at (165, 200) and (495, 200), 128 pt |

`Resources/AppIcon.icns` is the copy the app build uses (`scripts/build-app.sh`).

## Regenerate

Sources are in `kit/src/`. `python3 kit/src/flat.py kit/flat-layers kit/menu-bar` rewrites the four flat layers and `menubar-template.svg` (checked: output is identical). The menu-bar PNGs are that SVG rendered at 18, 36 and 54 px, and the banner, social preview and installer images are the `kit/src/*.html` files rendered with the logo-design skill's `render_png.py` (Chrome); only the social preview was re-rendered to check it matches. The icon master comes from `shapes.py` (`tiers()`), and the `.icns` is `iconutil` run on its rendered sizes.

## Not verified

- The glass look is a static stand-in. The dynamic Liquid Glass icon needs Xcode's Icon Composer (not installed here).
- How macOS 27 frames a plain `.icns` in Finder.
- The installer background has only been simulated, not built into a real disk image.

`concepts/` and `icon-directions/` are earlier explorations, kept for reference.
