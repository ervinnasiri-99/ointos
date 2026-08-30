# Phase 4 — Distro Build System & Package Curation (roadmap)

**Status:** Kicked off 2026-08-30
**Goal (master prompt Phase 4):** distro build system — ISO build automation, curated package set, reproducible builds.

---

## Phase 4 objectives
1. **Curate the default package set** — replace the current grab-bag with a deliberate, justified list (master: "exact list TBD during Phase 4 defaults work").
2. **Make the build reproducible/versioned** — pin inputs, tag ISOs, lock commit references.
3. **Finish build-system polish** — CI-able, headless, documented.
4. **Close the lingering Phase-3 bugs** rolled forward (below).

---

## PENDING ITEMS rolled forward from Phase 3 (must finish in Phase 4)

### A. Network applet — wired still shows "unknown/Ø"
- **Status:** wifi works + appears in applet; **wired (en\*) still doesn't show** in the KDE applet even though internet works.
- **Latest fix (942a909):** NM profile now matches `interface-name=en*` explicitly; NM.conf overwritten with `[ifupdown] managed=true` + `[main] plugins=keyfile,ifupdown`.
- **Still to verify:** on next build, confirm `en*` appears in applet. If still missing → the KDE applet may need `plasma-nm`'s interface list to see the device (check NM `nmcli device` shows it as `connected`/`>= 40` state, and that `plasma-nm` is running/recognizes the backend).

### B. Wallpaper — not default & missing from picker
- **Cause:** wallpaper was dropped in `/usr/share/wallpapers` without a Plasma 6 metadata.json, so the KDE picker never saw it.
- **Latest fix (942a909):** proper wallpaper PACKAGE (metadata.json w/ `X-Plasma-Image`) + default via `/etc/skel` `plasma-org.kde.plasma.desktop-appletsrc` `[Containments]` path.
- **Still to verify:** on next build, wallpaper picker lists "OintOS" and desktop shows it first login.

### C. Logo/icon system-wide
- **Latest fix (942a909):** hicolor icon theme at 16–256px + `/usr/share/pixmaps` + `distributor-logo` + icon cache refresh.
- **Still to verify:** shows in taskbar launcher icon, start menu, about/system settings branding.

### D. casper Bug 2055021 overlay false-panic
- **Fixed (5b30275):** sed-patch casper initramfs `/scripts/casper` before `update-initramfs` (overlayfs built-in → no false panic).

### E. App defaults (browser/office/terminal/media)-open items
- Browser = Brave (done in build). Office = install-time selectable (Phase 4 default set work).
- Terminal/Konsole default scheme, media player, PDF/image viewer defaults → decide these as part of package curation.

---

## Phase 4 work items

1. **Package curation table** — enumerate every package in `isobuild.sh`, justify or drop, add missing defaults (media player, image/pdf viewer, notes, etc.) per the theming/defaults doc.
2. **Brave defaults** — home page, search engine, new-tab (branding-sensible).
3. **Reproducibility** — pin debootstrap mirror/archive areas, record package versions at build time (manifest), tag ISO with date+commit.
4. **Build polish** — keep Docker isolation; add `--version`/checksum to output name; CI hook (lint `isobuild.sh`, shellcheck).
5. **Docs** — update README with the curated set + how to add packages.

---

## Definition of done for Phase 4
- A single, justified package list committed.
- Build reproduces a bootable ISO from a clean checkout in Docker.
- Lingering Phase-3 bugs (A/B/C above) verified fixed in the produced ISO.
- Brave + default apps ship by default; no snaps.