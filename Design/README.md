# Design

Artwork and screenshots for people working on Lodge. The public README and the website do not link here.

## Folders

| Path | What it is |
| --- | --- |
| `lodge-cabin-night/` | The night Lodge Cabin icon set the app uses now: one PNG per slot, `Contents.json`, `icon_1024.png`, and the masters `lodge-cabin.svg` and `lodge-cabin-small.svg`. |
| `lodge-cabin-sunset/` | The previous sunset Lodge Cabin set, including the 2400-pixel header masters `lodge-header-dark.png` and `lodge-header-light.png`. |
| `lodge-cabin-night/menubar/` | `MenuBarIcon.svg`, the master for the menu bar icon (`MenuBarIcon` PNGs in the asset catalog, drawn as a template image). |
| `onboarding/` | First-launch setup: `SPEC.md`, the screen mockups and the scene, glyph and wordmark masters behind `OnboardingSplashScene`, `OnboardingDoneScene`, `LodgeGlyph` and `LodgeWordmark`. |
| `support-graphic/` | Art for the Support Lodge card (`SupportHeader` in the asset catalog). |
| `icon-1024.png` | Master app icon, 1024×1024. |
| `screenshots/` | Screenshots taken in demo mode. The copies used on the site and in the README live in `docs/assets/screenshots/`. |
| `dusk-cabin-v3/` | The previous Dusk Cabin (v3) icon set, kept for reference. |
| `comet-a-v3/` | The previous Comet A (v3) icon set, kept for reference. |
| `comet-a-v1/`, `comet-a-v2/` | Earlier Comet A drafts. |
| `icon-legacy-blue.png`, `icon-legacy-blue.svg` | The previous blue icon. |

The icon on the website is a separate copy, `docs/assets/app-icon/`. The icon the built app uses is `Lodge/Assets.xcassets/AppIcon.appiconset`. Replacing one does not replace the other. The banners on the site are the 1600-pixel files in `docs/assets/`.

## Updating the icon

The in-app icon is the night Lodge Cabin: a snow-roofed cabin under a starry sky. The set in `lodge-cabin-night/` is the source. The sunset set is archived in `lodge-cabin-sunset/`.

Each size is drawn for that size. The 16×16, 16×16@2x, and 32×32 versions come from a simplified small master so they stay readable in the menu bar and in Finder lists. Generate a real set. Scaling one PNG with `sips` softens those small sizes.

1. Put the new set in `lodge-cabin-night/` with these names: `icon_16x16.png`, `icon_16x16@2x.png`, `icon_32x32.png`, `icon_32x32@2x.png`, `icon_128x128.png`, `icon_128x128@2x.png`, `icon_256x256.png`, `icon_256x256@2x.png`, `icon_512x512.png`, `icon_512x512@2x.png`, plus `icon_1024.png`.
2. Copy them into the asset catalog and refresh the master:

```sh
cp Design/lodge-cabin-night/icon_*x*.png Lodge/Assets.xcassets/AppIcon.appiconset/
cp Design/lodge-cabin-night/icon_1024.png Design/icon-1024.png
```

`Contents.json` already points each slot at the file with the same name. Copy the same sizes into `docs/assets/app-icon/` when the public icon should change too.
