#!/usr/bin/env python3
"""
OintOS unattended install driver (Phase 6).

Reads an install plan (YAML or JSON, subiquity-shaped so the Windows/Libertix
side can produce it) and drives a HEADLESS Calamares install:

  1. Parse the plan (disk, partitioning, filesystem, user, features/late-commands).
  2. Pre-seed /etc/calamares/*.conf from the plan (partition, users).
  3. Write an exec-only settings.conf.
  4. Invoke `calamares -c <conf>` with that config.

This is the thin unattended layer the master prompt needs for the Windows-side
handoff (Phase 7) — Calamares itself has no native autoinstall, so we generate
its configs from a plan.

Accepts TWO plan shapes (auto-detected by top-level keys):
  1. Libertix schema-v3 installation-plan.json (authoritative for the
     Windows handoff): account/locale/disk/firmware/distribution/runtime.
  2. Legacy OintOS shorthand (identity/storage/late_commands) for manual
     headless installs.

Libertix mapping (verified against ekimiateam/libertix main):
  - account.username -> users.conf presets.loginName (+ fullname fallback)
  - account.computerName -> machineid hostname (late command)
  - account.passwordHashWindowsPath -> Windows path (e.g. C:\\dir\\file)
    resolved against a mounted Windows root (--windows-root); contents must
    be `$6$...` SHA-512 crypt (same check as libertix-install-main.sh);
    applied chrooted via `chpasswd -e` (same as configure-target-main.sh).
    The path may carry a `recoveryRunId` transaction suffix — stripped.
  - locale.systemLanguage/keyboardLayout/keyboardModel/keyboardVariant/
    timezone -> locale.conf/keyboard.conf/hostname+timezone late commands
    (same files configure-target-main.sh writes: /etc/default/locale,
    /etc/default/keyboard, /etc/localtime).
  - disk.installer.finalSizeBytes -> informational only (Calamares owns
    partitioning; plan does NOT resize). disk.partitionStyle must agree
    with firmware (GPT/uefi, MBR/bios) or build() raises.
  - distribution.osReleaseId must be ubuntu (target identity check, same
    as assert_target_distribution_identity).
  - runtime.secureBootEnabled=true -> refused (no signed shim yet, same
    limitation as decision 007).
  - Staging discovery: --staging scans LABEL=OINTOSSTG (vfat) then
    /cdrom + /run/live/medium for installation-plan.json (same pattern
    as libertix-live-context.sh, OintOS label).

Example shorthand:
    identity:
        username: ervin
        hostname: ointos
    storage:
        disk: /dev/sda
        layout: gpt
        efi: true
        filesystem: ext4
    late_commands:
        - "install-ointos-apps.sh"
"""

import argparse
import json
import os
import shlex
import subprocess
import sys

try:
    import yaml
except ImportError:
    yaml = None


def load_plan(path):
    with open(path) as fh:
        text = fh.read()
    if path.endswith(".json"):
        return json.loads(text)
    if yaml:
        return yaml.safe_load(text)
    # Fallback naive JSON
    return json.loads(text)


def write_conf(dst, data):
    """Write a dict as a Calamares-style YAML-ish conf. Calamares reads YAML,
    so if PyYAML is present use that; else emit simple key: value lines."""
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    if yaml:
        with open(dst, "w") as fh:
            yaml.safe_dump(data, fh, sort_keys=False, default_flow_style=False)
    else:
        with open(dst, "w") as fh:
            for k, v in data.items():
                fh.write(f"{k}: {json.dumps(v)}\n")


STAGING_LABEL = "OINTOSSTG"
STAGING_CANDIDATES = ["/run/live/medium/installation-plan.json",
                      "/lib/live/mount/medium/installation-plan.json",
                      "/cdrom/installation-plan.json"]


def _is_libertix_plan(plan):
    return "schemaVersion" in plan and "account" in plan


def _normalize(plan):
    """Map a Libertix schema-v3 plan onto the shorthand shape. Raises
    ValueError on anything the unattended path cannot honor (fail closed,
    never silently ignore a destructive decision)."""
    if not _is_libertix_plan(plan):
        return plan
    if plan.get("schemaVersion") != 3:
        raise ValueError(f"unsupported schemaVersion "
                         f"{plan.get('schemaVersion')!r} (need 3)")
    account = plan.get("account", {})
    locale = plan.get("locale", {})
    disk = plan.get("disk", {})
    firmware = plan.get("firmware")
    distribution = plan.get("distribution", {})
    runtime = plan.get("runtime", {})

    os_id = distribution.get("osReleaseId", "")
    # Accept our own ID too: live image writes ID=ointos (+ID_LIKE ubuntu
    # debian) — rejecting it would refuse our own ISO (Libertix
    # assert_target_distribution_identity allows ID + ID_LIKE family).
    if os_id and os_id not in ("ubuntu", "ointos"):
        raise ValueError(f"distribution.osReleaseId {os_id!r} is not ubuntu")
    if runtime.get("secureBootEnabled"):
        raise ValueError("secureBootEnabled=true refused: no signed shim "
                         "(decision 007 limitation)")
    style = disk.get("partitionStyle")
    if style == "GPT" and firmware != "uefi":
        raise ValueError("GPT disk with bios firmware")
    if style == "MBR" and firmware != "bios":
        raise ValueError("MBR disk with uefi firmware")
    bl_state = runtime.get("windowsBitLockerState")
    if bl_state not in (None, "FullyDecrypted", "NotEncryptable"):
        raise ValueError(f"refusing install with BitLocker state "
                         f"{bl_state!r}: decrypt/suspend first")

    username = account.get("username", "")
    if username in ("root", "oinstaller"):
        raise ValueError(f"refusing reserved username {username!r}")
    return {
        "identity": {
            "username": username,
            "fullname": username,
            "hostname": account.get("computerName", "ointos"),
            "passwordHashWindowsPath": account.get(
                "passwordHashWindowsPath", ""),
            "recoveryRunId": (runtime.get("recoveryRunId") or ""),
        },
        "locale": {
            "systemLanguage": locale.get("systemLanguage", "en_US.UTF-8"),
            "languageCode": locale.get("languageCode", "en"),
            "keyboardLayout": locale.get("keyboardLayout", "us"),
            "keyboardVariant": locale.get("keyboardVariant", ""),
            "keyboardModel": locale.get("keyboardModel", "pc105"),
            "timezone": locale.get("timezone", "America/New_York"),
        },
        "storage": {
            "layout": ("gpt" if disk.get("partitionStyle") == "GPT"
                       else "mbr"),
            "efi": firmware == "uefi",
            "filesystem": "ext4",
        },
        "late_commands": [],
    }


def _resolve_windows_path(win_path, windows_root):
    """Turn r'C:\\dir\\file' into <windows_root>/dir/file. Returns None
    when unresolvable (caller fails closed)."""
    if not win_path or not windows_root:
        return None
    rel = win_path.replace("/", "\\").split("\\")
    if not rel or len(rel[0]) != 2 or rel[0][1] != ":":
        return None
    return os.path.join(windows_root, *rel[1:])


def _read_password_hash(ident, windows_root):
    """Read + validate the $6$ crypt hash (same rules as
    libertix-install-main.sh: must start with $6$, no CR/LF/TAB)."""
    src = _resolve_windows_path(ident.get("passwordHashWindowsPath", ""),
                                windows_root)
    if not src or not os.path.isfile(src):
        raise ValueError("password hash file missing: mount Windows at "
                         "--windows-root (e.g. /mnt/windows) so "
                         f"{ident.get('passwordHashWindowsPath', '')!r} "
                         "resolves")
    with open(src) as fh:
        h = fh.read().strip()
    if not h.startswith("$6$") or any(c in h for c in "\r\n\t"):
        raise ValueError("password hash is not a valid SHA-512 crypt hash")
    return h


def find_staging_plan(staging_dir=None):
    """Locate installation-plan.json: explicit dir, LABEL=OINTOSSTG (vfat),
    then live-medium fallbacks. Same pattern as libertix-live-context.sh."""
    if staging_dir:
        cand = os.path.join(staging_dir, "installation-plan.json")
        if os.path.isfile(cand):
            return cand
        raise ValueError(f"no installation-plan.json in {staging_dir}")
    try:
        import subprocess as _sp
        out = _sp.run(["blkid", "-o", "device"], capture_output=True,
                      text=True, timeout=30).stdout.split()
        for dev in out:
            lab = _sp.run(["blkid", "-s", "LABEL", "-o", "value", dev],
                          capture_output=True, text=True,
                          timeout=30).stdout.strip()
            if lab != STAGING_LABEL:
                continue
            mnt = _sp.run(["mktemp", "-d"], capture_output=True, text=True,
                          timeout=30).stdout.strip()
            try:
                r = _sp.run(["mount", "-t", "vfat", "-o", "ro", dev, mnt],
                            timeout=30)
                if r.returncode == 0:
                    cand = os.path.join(mnt, "installation-plan.json")
                    if os.path.isfile(cand):
                        import shutil as _sh
                        dst = "/tmp/installation-plan.json"
                        _sh.copy(cand, dst)
                        return dst
            finally:
                _sp.run(["umount", mnt], timeout=30)
                _sp.run(["rmdir", mnt], timeout=30)
    except (OSError, ValueError):
        pass
    for cand in STAGING_CANDIDATES:
        if os.path.isfile(cand):
            return cand
    raise ValueError("no installation-plan.json found (staging "
                     f"LABEL={STAGING_LABEL}, /cdrom, /run/live/medium)")


def build(plan, cal_conf="/etc/calamares", windows_root=None):
    """Write all Calamares configs from the plan."""
    plan = _normalize(plan)
    ident = plan.get("identity", {})
    storage = plan.get("storage", {})
    loc = plan.get("locale", {})

    # Module .conf files live in <cal_conf>/modules/ (NOT directly in
    # <cal_conf>/ — Calamares only searches /etc/calamares/modules and
    # /usr/share/calamares/modules for them).
    moddir = os.path.join(cal_conf, "modules")

    # --- partition.conf ---------------------------------------------------
    # Key names per upstream PartitionViewStep.cpp: userSwapChoices is
    # REQUIRED; plural availableFileSystemTypes (singular is ignored).
    partition = {
        "efiSystemPartition": "/boot/efi",
        "enableLuksAutomatedPartitioning": True,
        "luksGeneration": "luks2",
        "userSwapChoices": ["none", "file"],
        "initialSwapChoice": "file",
        "drawNestedPartitions": True,
        "alwaysShowPartitionLabels": True,
        "allowManualPartitioning": False,        # unattended
        "defaultFileSystemType": "ext4",
        "availableFileSystemTypes": ["ext4"],
        # Explicit root layout (build19: implicit default emitted ESP-only).
        "partitionLayout": [{"name": "rootfs", "filesystem": "unknown",
                             "mountPoint": "/", "size": "100%"}],
    }
    write_conf(os.path.join(moddir, "partition.conf"), partition)

    # --- mount.conf (ext4 target, decision 008: no btrfs) -----------------
    mount = {
        "extraMounts": [
            {"device": "proc", "fs": "proc", "mountPoint": "/proc"},
            {"device": "sys", "fs": "sysfs", "mountPoint": "/sys"},
            {"device": "/dev", "mountPoint": "/dev",
             "options": ["bind"]},
            {"device": "tmpfs", "fs": "tmpfs", "mountPoint": "/run"},
            {"device": "/run/udev", "mountPoint": "/run/udev",
             "options": ["bind"]},
            {"device": "efivarfs", "fs": "efivarfs",
             "mountPoint": "/sys/firmware/efi/efivars", "efi": True},
        ],
        "mountOptions": [
            {"filesystem": "default", "options": ["defaults"]},
            {"filesystem": "efi", "options": ["defaults", "umask=0077"]},
        ],
    }
    write_conf(os.path.join(moddir, "mount.conf"), mount)

    # --- users.conf -------------------------------------------------------
    # Upstream schema requires defaultGroups, autologinGroup, sudoersGroup.
    users = {
        "doAutologin": False,
        "setRootPassword": False,
        "doReusePassword": True,
        "allowRootPassword": True,
        "sudoersGroup": "sudo",
        "autologinGroup": "autologin",
        "defaultGroups": ["adm", "cdrom", "dip", "lpadmin", "plugdev",
                          "sambashare", "sudo"],
        "passwordRequirements": {"minLength": 1, "maxLength": -1},
        "user": {"shell": "/bin/bash",
                 "forbidden_names": ["root", "oinstaller"]},
        # Upstream users module reads the login ONLY from presets
        # (Config.cpp updateGSAutoLogin(loginName); top-level autologinUser
        # does not exist). Empty/missing preset -> createJobs() returns [],
        # SetupGroupsJob/CreateUserJob never run, live user kept.
        "presets": {
            "fullname": {"value": ident.get("fullname",
                                            ident.get("username", ""))},
            "loginName": {"value": ident.get("username", "")},
        },
    }
    write_conf(os.path.join(moddir, "users.conf"), users)

    # --- bootloader.conf --------------------------------------------------
    # bootloader.schema.yaml: additionalProperties:false, ONLY these keys.
    bootloader = {
        "efiBootLoader": "grub",
        "grubInstall": "grub-install",
        "grubMkconfig": "grub-mkconfig",
        "grubCfg": "/boot/grub/grub.cfg",
        "grubProbe": "grub-probe",
        "efiBootMgr": "efibootmgr",
        "installEFIFallback": True,
        "installHybridGRUB": False,
    }
    write_conf(os.path.join(moddir, "bootloader.conf"), bootloader)

    # --- locale.conf / keyboard.conf (Libertix configure_locale/keyboard) --
    # locale.schema.yaml: ONLY region/zone (+geoip/useSystemTimezone...).
    # Extra keys (locale/language) are REJECTED (additionalProperties:false).
    # Keyboard layout itself comes from the keyboard PAGE/globalstorage —
    # keyboard.conf only tunes WHERE it is written (xorg path, localed,
    # kwin/gnome flags). So: preseed region/zone + mirror interactive
    # keyboard.conf verbatim, real layout via late-command files below.
    _tz = loc.get("timezone", "America/New_York")
    _region, _, _zone = _tz.partition("/")
    write_conf(os.path.join(moddir, "locale.conf"),
               {"region": _region or "America",
                "zone": _zone or "New_York"})
    write_conf(os.path.join(moddir, "keyboard.conf"),
               {"xOrgConfFileName": "/etc/X11/xorg.conf.d/00-keyboard.conf",
                "convertedKeymapPath": "/lib/kbd/keymaps/xkb",
                "configure": {"kwin": False, "gnome": False}})

    # --- shellprocess.conf (late commands) --------------------------------
    # Key is `script:` (list) NOT `scripts:` — with `scripts:` the module
    # loads but runs nothing. Leading "-" on a command ignores its failure.
    # Mirror the interactive shellprocess.conf fixes (015): strip casper so
    # the target initramfs stops probing /dev/sr0, drop live-user leftovers.
    # Runs chrooted (dontChroot False), same as interactive.
    #
    # Libertix parity (configure-target-main.sh, chrooted equivalents):
    # hostname, password hash via chpasswd -e, /etc/default/locale,
    # /etc/default/keyboard, /etc/localtime — the users/locale/keyboard
    # modules cover the interactive path; late commands cover unattended.
    late = [
        {"command": "-apt-get purge -y casper", "timeout": 300},
        {"command": "rm -f /etc/initramfs-tools/conf.d/casperize.conf /etc/casper.conf; update-initramfs -u",
         "timeout": 300},
        {"command": "if [ \"$(ls /home 2>/dev/null | grep -v lost+found | wc -l)\" -gt 1 ]; then userdel -r oinstaller 2>/dev/null || rm -rf /home/oinstaller; fi",
         "timeout": 60},
        {"command": "-update-grub", "timeout": 300},
        {"command": f"echo {shlex.quote(ident.get('hostname', 'ointos'))} > /etc/hostname",
         "timeout": 60},
        {"command": f"printf 'LANG={loc.get('systemLanguage', 'en_US.UTF-8')}\\nLC_ALL={loc.get('systemLanguage', 'en_US.UTF-8')}\\nLANGUAGE={loc.get('languageCode', 'en')}\\n' > /etc/default/locale",
         "timeout": 60},
        {"command": f"printf 'XKBMODEL=\"{loc.get('keyboardModel', 'pc105')}\"\\nXKBLAYOUT=\"{loc.get('keyboardLayout', 'us')}\"\\nXKBVARIANT=\"{loc.get('keyboardVariant', '')}\"\\nXKBOPTIONS=\"\"\\nBACKSPACE=\"guess\"\\n' > /etc/default/keyboard",
         "timeout": 60},
        {"command": f"ln -sf /usr/share/zoneinfo/{loc.get('timezone', 'America/New_York')} /etc/localtime && echo {shlex.quote(loc.get('timezone', 'America/New_York'))} > /etc/timezone",
         "timeout": 60},
        {"command": "touch /etc/ointos-installed",
         "timeout": 60},
        {"command": "rm -f /etc/sddm.conf.d/autologin.conf /usr/bin/ointos-installer-prompt /usr/share/applications/ointos-installer.desktop /usr/share/applications/calamares.desktop /usr/share/applications/*kubuntu*.desktop /etc/xdg/autostart/ointos-installer.desktop /etc/xdg/autostart/*calamares*.desktop /etc/xdg/autostart/*kubuntu*.desktop /etc/sudoers.d/ointos-installer",
         "timeout": 60},
        {"command": "rm -rf /usr/share/calamares /etc/calamares /home/oinstaller/Desktop/Install*.desktop /root/Desktop/Install*.desktop /home/*/Desktop/Install*.desktop /etc/skel/Desktop/Install*.desktop",
         "timeout": 60},
        {"command": "-apt-get purge -y calamares calamares-settings-kubuntu calamares-settings-ubuntu-common calamares-data; apt-get autoremove --purge -y",
         "timeout": 300},
    ]
    # Password hash: read NOW (live side, Windows root mounted) and bake
    # into a chrooted chpasswd -e late command (same as Libertix
    # configure_user: printf user:hash | chpasswd -e). Fail closed.
    if ident.get("passwordHashWindowsPath"):
        pw_hash = _read_password_hash(ident, windows_root)
        late.append({
            "command": f"printf '%s:%s\\n' {shlex.quote(ident['username'])} "
                       f"{shlex.quote(pw_hash)} | chpasswd -e",
            "timeout": 60})
    for cmd in plan.get("late_commands", []):
        late.append({"command": cmd, "timeout": 300})
    write_conf(os.path.join(moddir, "shellprocess.conf"),
               {"dontChroot": False, "timeout": 300, "verbose": True,
                "script": late})

    # --- settings.conf: exec-only (unattended) -----------------------------
    # modules-search MUST be [ local ]: `local` = $LIBDIR/calamares/modules.
    # Extra absolute paths only produce "module-search entry non-existent"
    # noise; never list /usr/lib/calamares/modules.
    # Exec chain mirrors the interactive one (Kubuntu-trimmed): every entry
    # ships in Ubuntu's `calamares` package.
    settings = {
        "modules-search": ["local"],
        "instances": [
            {"id": "partition", "module": "partition", "config": "partition.conf"},
            {"id": "mount", "module": "mount", "config": "mount.conf"},
            {"id": "locale", "module": "locale", "config": "locale.conf"},
            {"id": "keyboard", "module": "keyboard", "config": "keyboard.conf"},
            {"id": "unpackfs", "module": "unpackfs", "config": "unpackfs.conf"},
            {"id": "users", "module": "users", "config": "users.conf"},
            {"id": "displaymanager", "module": "displaymanager", "config": "displaymanager.conf"},
            {"id": "bootloader", "module": "bootloader", "config": "bootloader.conf"},
            {"id": "shellprocess", "module": "shellprocess", "config": "shellprocess.conf"},
            # rootcheck guard lives in the ISO image (shellprocess_rootcheck.conf,
            # not overwritten here) — fail fast if / never mounted (build17).
            {"id": "rootcheck", "module": "shellprocess", "config": "shellprocess_rootcheck.conf"},
        ],
        "sequence": [
            {"exec": [
                "partition", "mount", "shellprocess@rootcheck", "unpackfs", "machineid", "fstab",
                "locale", "keyboard", "localecfg", "users",
                "displaymanager", "networkcfg", "hwclock", "grubcfg",
                "bootloader", "shellprocess", "umount",
            ]},
            {"show": ["finished"]},
        ],
        "branding": "ointos",
        "prompt-install": False,
        "dont-chroot": False,
        "oem-setup": False,
        "disable-cancel": False,
        "disable-cancel-during-exec": False,
        "hide-back-and-next-during-exec": False,
        "quit-at-end": False,
    }
    write_conf(os.path.join(cal_conf, "settings.conf"), settings)


def main(argv=None):
    ap = argparse.ArgumentParser(description="OintOS unattended install driver")
    ap.add_argument("plan", nargs="?",
                    help="path to YAML/JSON install plan "
                         "(default: staging discovery)")
    ap.add_argument("--cal-conf", default="/etc/calamares",
                    help="Calamares config dir (default /etc/calamares)")
    ap.add_argument("--dry-run", action="store_true",
                    help="write configs but do not run calamares")
    ap.add_argument("--no-sudo", action="store_true",
                    help="run calamares without sudo (for testing)")
    ap.add_argument("--staging", default=None,
                    help="staging dir with installation-plan.json "
                         "(default: discover LABEL=OINTOSSTG / /cdrom)")
    ap.add_argument("--windows-root", default=None,
                    help="mounted Windows root for passwordHashWindowsPath "
                         "resolution (e.g. /mnt/windows)")
    args = ap.parse_args(argv)

    try:
        if not args.plan or args.staging:
            # Windows handoff: discover the staging plan (no file given).
            args.plan = find_staging_plan(args.staging)
            print(f"Using staging plan: {args.plan}")
        plan = load_plan(args.plan)
    except (ValueError, OSError) as e:
        print(f"FATAL: {e}", file=sys.stderr)
        return 2
    # planId match: plan/state pair must agree (same as live-context.sh).
    sib = os.path.join(os.path.dirname(args.plan),
                       os.path.basename(args.plan).replace(
                           ".plan.json", ".state.json").replace(
                           "installation-plan.json",
                           "installation-state.json"))
    if os.path.basename(args.plan) in ("installation-plan.json",) or \
            args.plan.endswith(".plan.json"):
        if os.path.isfile(sib):
            try:
                state = load_plan(sib)
                for k in ("planId", "plan_id", "planID"):
                    if k in plan and k in state and \
                            plan[k] != state[k]:
                        print(f"FATAL: plan/state {k} mismatch", file=sys.stderr)
                        return 2
            except ValueError:
                pass
    try:
        build(plan, args.cal_conf, windows_root=args.windows_root)
    except ValueError as e:
        print(f"FATAL: {e}", file=sys.stderr)
        return 2
    print(f"Wrote Calamares configs to {args.cal_conf}")

    if args.dry_run:
        print("Dry run: not running calamares.")
        return 0

    # Calamares 3.3.x has no --is-installer flag; mode is set via settings.conf
    # (the sequence with exec modules determines installer vs welcome).
    if os.geteuid() != 0 and not args.no_sudo:
        cmd = ["sudo", "calamares", "-c", args.cal_conf]
    else:
        cmd = ["calamares", "-c", args.cal_conf]
    print("Running:", shlex.join(cmd))
    return subprocess.call(cmd)


if __name__ == "__main__":
    sys.exit(main())