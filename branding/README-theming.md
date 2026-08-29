# OintOS Theming Stage — Roadmap & Full Question List

**Status:** Prepared 2026-08-29 · **Applies to:** the dedicated theming/branding pass (master-prompt Phase 14, and the pre-branding polish in Phase 4 defaults).

This document banks **every** branding/theming question so that when we reach the theming stage we settle them in one focused pass — down to the last detail — instead of guessing.

---

## Roadmap: when & how theming will happen

1. **Phase 3/4 (now-ish):** placeholders. Current ISO already ships:
   - OintOS logo (`/usr/share/icons/ointos-logo*.png`)
   - OintOS wallpaper (`/usr/share/wallpapers/OintOS/OintOSWallpaper.png`) + `/etc/skel` Plasma config so the live desktop uses it
   - `os-release`, hostname, username set to OintOS
2. **Theming stage (dedicated pass):** settle ALL questions below, then implement across: GRUB theme, Plymouth/splash, SDDM login, KDE Plasma Look-and-Feel, icons, cursors, fonts, colors, GTK apps, default apps.

---

## 1. NAME / IDENTITY
- Confirm display strings: "OintOS" everywhere (boot, login, about, menus)? Any official short form / tagline?
- Version string format shown to users (`OintOS 1.0`, or `1.0` only)?
- Logo: is the current "O" mark **final**, or a placeholder to be replaced? Is there a horizontal lockup (logo + wordmark) for login/installer use?
- Any mascot / secondary symbol?

## 2. COLOR PALETTE
- **Primary brand color(s)?** (current logo is orange-red — hex values?)
- **Secondary / accent** colors?
- **Semantic colors** (success/warning/error) — stick to defaults or custom?
- **Dark vs light variants:** which palette per mode? Any per-mode differences beyond inversion?
- **Text colors** (primary/secondary/muted) and **selection** color?
- **Link color** (both modes)?

## 3. LIGHT/DARK MODE
- Default mode at first boot: **light, dark, or system/auto**?
- Do we **support both** (user toggle), or ship only one for v1?
- If both: what's the **auto-switch rule** (time-based, sunset/sunrise, manual)?
- Any apps that should **always be dark** even in light mode (e.g. terminal)?
- Wallpaper per mode, or same?

## 4. LOGIN / GREETER (SDDM)
- **Background:** same wallpaper as desktop, or a special login backdrop (logo on solid/duotone)?
- **Logo placement** on login screen?
- Username/password field style, button style, avatar show/hide?
- Clock/date shown on login? Locale/format?
- **Power menu** (sleep/restart/shutdown) — show all?
- Virtual keyboard option enabled?
- Autologin in live session (we set `oinstaller`) — confirm keep for live, and what the **installed** system should do (Phases 6-10)?

## 5. BOOT / SPLASH
- **GRUB menu theme:** custom background + styled menu, or minimal/text?
- Default GRUB **timeout** and default entry (Try OintOS / first OS)?
- **Plymouth/boot splash:** branded logo + spinner? Or text-only boot?
- Boot messages shown or hidden (`quiet splash` vs verbose)?
- Any boot **animation** (logo + progress)?

## 6. DESKTOP — KDE PLASMA LOOK & FEEL
- **Plasma global theme:** build a custom "OintOS" theme or fork Breeze? (This is the big one.)
- **Window decorations** (titlebar style/roundedness): default Breeze, or custom?
- **Icons:** Breeze? Breeze-Dark? Papirus? Custom? Size preference?
- **Cursors:** Breeze, or a custom OintOS cursor? Pointer size for HiDPI?
- **Widgets/panel:** panel position (bottom default?), panel style (floating/classic), task manager style (icons-only vs text)?
- **Desktop:** desktop icons show/hide? Folder view vs widget-only?
- **Default virtual desktops / activities:** 1? Grid?
- **Workspace behavior:** single-click or double-click to open? Focus-follows-mouse or click-to-focus?
- **Window behavior:** minimize/maximize on...; present-open-windows effect; window border size.

## 7. FONTS
- **UI font** (system sans)? Default is Noto Sans — keep or use a specific family?
- **Monospace font** (terminal/code)? Default is Noto Sans Mono — keep or use JetBrains Mono/Fira Code/etc.?
- **Font rendering**: hinting/antialiasing settings? Subpixel on?
- **Default font sizes** (UI, menus, titlebars)? Should we install extra font packages (e.g. Inter, Cantarell)?

## 8. ICON/BRANDING PLACEMENTS (beyond desktop)
- **File manager** icon/theme for OintOS folders (home/Downloads/etc.)?
- **Default wallpaper** in `systemsettings` + per-user accounts?
- **Plymouth/GRUB/SDDM** each get OintOS logo?
- **About dialog** (hostname, os-release PRETTY_NAME): confirm wording.
- **Firefox/Brave** (our browser) default theme — system or light?
- **Terminal** default profile colors/scheme (Konsole): custom palette?

## 9. GTK APPS
- Ubuntu ships some GTK apps — do we **theme GTK** to match (via KDE GTK settings / Breeze-GTK)?
- **LibreOffice/Office** look and feel — match Plasma (LibreOffice-dark)?
- **Firefox/Brave** window: follow system (Qt/GTK) or browser-default?

## 10. DEFAULT APPS & BEHAVIOR
- **Browser:** Brave (confirmed). Homepage? New-tab default? Search engine (DuckDuckGo/Bing/Google)? Do we set a branded homepage or leave default?
- **File manager:** Dolphin (confirmed KDE). Default view (icons/list)? Split view?
- **Terminal:** Konsole (confirmed). Default shell?! (bash default? zsh preinstalled?)
- **Editor:** Kate (KDE). Or VS Code/Cursor in v1?
- **PDF:** Okular. **Images:** Gwenview. **Video/audio:** VLC or Elisa or mpv? (Confirm — master list open.)
- **Office:** user-selectable at install (LibreOffice...). Any defaults pre-installed?
- **Archive:** Ark. **Notes:** no default? **Email/calendar:** KMail or none?
- **System monitor:** KDE System Monitor, or htop/bashtop? **Settings:** System Settings.
- **Calculator:** kcalc. **Screenshot:** KDE Spectacle (we have `kde-spectacle`). Confirm.

## 11. NETWORK / PRIVACY / UX DETAILS
- **Notifications:** OSD style (top? bottom-left)? Duration?
- **Night light** (warm colors): default on at sunset, or off?
- **Screensaver/lock:** timeout? Lock screen wallpaper = login wallpaper?
- **Power settings:** suspend/lid behavior defaults?
- **Audio:** default sink, volume steps, output device preference?
- **Privacy (KDE):** which apps get camera/mic; location services off by default?
- **Privacy (Ubuntu):** we already removed telemetry — confirm KDE's own usage telemetry is off too (some KDE components collect).

## 12. FIRST-BOOT / OOBE (Phase 10 tie-in)
- Theme selection in OOBE: **light/dark** toggle (we planned this) — any "auto"?
- Accent/color choice shown in OOBE (if we offer more than one)?
- Wallpaper picker in OOBE, or default only?
- Anything the user should NOT be able to change (locked placeholders)?

## 13. TECH-CONSTRAINT CHECKS (need research before deciding)
- **HiDPI / fractional scaling** default (Plasma 6 supports it well on 26.04)?
- **Multi-GPU/quirks:** on VirtualBox/QEMU we saw vmwgfx — real-world NVIDIA/AMD/Intel theming same via Breeze, but confirm non-GTK assets on proprietary drivers.
- **Brave default theme** when system is dark — does it follow GTK/Qt, and should we force `prefers-color-scheme` via a flag?

---

## What I recommend as sensible initial defaults (to confirm or override)

| Item | Proposed default |
|---|---|
| Mode | Light + dark both, **auto** default, toggle in OOBE |
| Primary color | Follow your orange-red logo (get exact hex) |
| Plasma theme | Custom "OintOS" Look-and-Feel **based on Breeze** |
| Icons / Cursor | Breeze + Breeze cursor (optionally custom cursor later) |
| Fonts | Noto Sans / Noto Sans Mono (Ubuntu stock), tuned sizes |
| Panel | Bottom, default Breeze layout, icons-only taskbar |
| Terminal | Konsole, bash, transparent-off, dark scheme |
| Browser | Brave, DuckDuckGo default, follows system theme |
| Office | LibreOffice at install-time option (Phase 4) |
| Splash/GRUB/SDDM | Branded with your logo + wallpaper |

---

When we hit the theming stage, open this doc and we'll go question-by-question. I will ask **all** of these (and any that arise) before writing theme files.