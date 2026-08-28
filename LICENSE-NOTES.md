# Licensing Notes — OintOS

## Libertix Fork (GPL-3.0)

OintOS's Windows-side installer is a direct fork of [Libertix](https://github.com/ekimiateam/libertix/), which is licensed under the **GNU General Public License v3.0 (GPL-3.0)**.

### Obligations

Forking Libertix under GPL-3.0 obligates the OintOS Windows installer code to:

1. Remain GPL-3.0 compatible (or a compatible copyleft license)
2. Be publicly available as source code
3. Include the full GPL-3.0 license text
4. Preserve original copyright notices
5. Mark any modifications made to upstream code

### Current Status

**⚠️ PENDING LEGAL REVIEW** — The assumption that GPL-3.0 fork obligations are compatible with the OintOS project goals has not been formally reviewed by legal counsel. This document flags that risk clearly.

### Code Separation Strategy

To preserve optionality and simplify future upstream syncing:

- `windows-installer/upstream/` — Minimally-modified Libertix core code
- `windows-installer/ointos/` — OintOS-specific adaptations, branding, and configuration

This separation ensures that:
- Upstream Libertix changes can be synced more easily
- The boundary between generic and distro-specific code is clear
- Any future legal review can assess each layer independently

### What Must Be GPL-3.0

All code in `windows-installer/` that derives from Libertix source must remain GPL-3.0 compatible. This includes:
- Forked C#/WPF application code
- Forked PowerShell scripts
- Forked Python live installer scripts
- Forked shell scripts and GRUB configuration
- Any modifications to JSON schemas from Libertix

### What Can Be Separate

OintOS-specific code that does NOT derive from Libertix source may use a different license (to be decided). This includes:
- Distro build configuration (package lists, ISO build scripts)
- First-boot OOBE wizard (if written from scratch)
- Branding assets (logo, theme, wallpapers)
- Documentation

### Third-Party Components

- **WinBoat**: Verify licensing compatibility for bundling/pre-integration
- **Proton/Wine**: Standard open-source licenses (LGPL/GPL), compatible with GPL-3.0
- **Brave Browser**: Chromium-based, Apache 2.0 / BSD-style, compatible
- **Fonts/icons/wallpapers**: Ensure any placeholder assets are properly licensed for redistribution

### Action Items

- [ ] Obtain formal legal review of GPL-3.0 fork obligations
- [ ] Verify licensing compatibility of WinBoat integration
- [ ] Ensure all placeholder branding assets are properly licensed
- [ ] Add copyright headers to all forked files marking modifications
