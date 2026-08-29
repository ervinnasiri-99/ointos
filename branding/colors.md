# OintOS Brand Color Palette (official)

Source: company brand palette provided 2026-08-29. All values verified.

| Name | Hex | RGB | CMYK | HSB | HSL | LAB |
|------|-----|-----|------|-----|-----|-----|
| Orchid Mist | `#c35ec5` | 195,94,197 | 1,52,0,23 | 299,52,77 | 299,47,57 | 56,55,-36 |
| Bright Peony | `#f676f5` | 246,118,245 | 0,52,0,4 | 300,52,96 | 300,88,71 | 69,65,-42 |
| Purple | `#791f7d` | 121,31,125 | 3,75,0,51 | 297,75,49 | 297,60,31 | 31,50,-33 |
| Pink Orchid | `#facbfc` | 250,203,252 | 1,19,0,1 | 298,19,99 | 298,89,89 | 87,25,-18 |
| Vivid Orchid | `#bb42bc` | 187,66,188 | 1,65,0,26 | 300,65,74 | 300,48,50 | 50,63,-41 |

## Roles (proposed, to confirm at theming stage)
- **Primary / brand:** `#bb42bc` Vivid Orchid (strong, saturated — good for accent/action)
- **Deep / dark sections:** `#791f7d` Purple (good for deep gradients/titlebars in dark mode)
- **Soft / light sections:** `#facbfc` Pink Orchid (good for light-mode backgrounds/highlight)
- **Support / highlights:** `#c35ec5` Orchid Mist, `#f676f5` Bright Peony
- **Neutral text/base:** keep near-black / near-white (not in palette), with orchid accents.

## Contrast sanity (for accessible text on these)
- `#facbfc` on `#791f7d`: high contrast — good for light-on-dark.
- White text on `#bb42bc` / `#c35ec5`: **borderline** — may fail for small text; prefer `#791f7d`-dark or larger/bold white text a11y.
- Dark text on `#facbfc`: high contrast — good.

These roles are suggestions; the theming pass (`branding/README-theming.md`) will confirm exact usage per surface.