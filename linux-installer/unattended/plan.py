#!/usr/bin/env python3
"""
OintOS unattended install driver (Phase 6).

Reads an install plan (YAML or JSON, subiquity-shaped so the Windows/Libertix
side can produce it) and drives a HEADLESS Calamares install:

  1. Parse the plan (disk, partitioning, filesystem, user, features/late-commands).
  2. Pre-seed /etc/calamares/*.conf from the plan (partition, users, btrfs
     subvolumes for Phase 5).
  3. Write an exec-only settings.conf.
  4. Invoke `calamares -c <conf>` with that config.

This is the thin unattended layer the master prompt needs for the Windows-side
handoff (Phase 7) — Calamares itself has no native autoinstall, so we generate
its configs from a plan.

Plan schema (subiquity-flavored for Libertix), e.g.:
    identity:
        username: oinstaller
        hostname: ointos
    storage:
        disk: /dev/sda
        layout: gpt
        efi: true
        filesystem: btrfs
        subvolumes: [@, @home, @cache, @log]
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


def build(plan, cal_conf="/etc/calamares"):
    """Write all Calamares configs from the plan."""
    ident = plan.get("identity", {})
    storage = plan.get("storage", {})

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
        "defaultFileSystemType": storage.get("filesystem", "btrfs"),
        "availableFileSystemTypes": ["ext4", "btrfs", "xfs"],
    }
    write_conf(os.path.join(moddir, "partition.conf"), partition)

    # --- mount.conf (btrfs subvolumes => Phase 5 / Timeshift) -------------
    # mount.schema.yaml has additionalProperties:false: ONLY extraMounts,
    # btrfsSubvolumes, btrfsSwapSubvol, mountOptions are valid. Entry keys
    # are `mountPoint` (capital P). mountOptions entries are
    # {filesystem, options[], ssdOptions[], hddOptions[]}.
    sv = storage.get("subvolumes", ["@", "@home", "@cache", "@log"])
    # Timeshift / Calamares expect the Ubuntu-type layout:
    #   "@"  -> mountpoint "/"      (root subvolume)
    #   "@home" -> mountpoint "/home"
    #   "@cache" -> mountpoint "/var/cache" (configurable per distro)
    def _subvol(s):
        name = s.lstrip("@")
        if name == "":
            return {"mountPoint": "/", "subvolume": "/@"}
        if name == "cache":
            return {"mountPoint": "/var/cache", "subvolume": "/@cache"}
        if name == "log":
            return {"mountPoint": "/var/log", "subvolume": "/@log"}
        return {"mountPoint": "/" + name, "subvolume": "/" + s}

    btrfs = [_subvol(s) for s in sv]
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
        "btrfsSubvolumes": btrfs,
        "btrfsSwapSubvol": "/@swap",
        "mountOptions": [
            {"filesystem": "default", "options": ["defaults"]},
            {"filesystem": "efi", "options": ["defaults", "umask=0077"]},
            {"filesystem": "btrfs",
             "options": ["defaults", "compress=zstd:1"]},
            {"filesystem": "btrfs_swap",
             "options": ["defaults", "noatime"]},
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
                          {"name": "sambashare", "must_exist": False,
                           "system": True}, "sudo"],
        "passwordRequirements": {"minLength": 1, "maxLength": -1},
        "user": {"shell": "/bin/bash", "forbidden_names": ["root"]},
    }
    if ident.get("username"):
        users["autologinUser"] = ident["username"]
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

    # --- shellprocess.conf (late commands) --------------------------------
    # Key is `script:` (list) NOT `scripts:` — with `scripts:` the module
    # loads but runs nothing. Leading "-" on a command ignores its failure.
    late = [
        {"command": "-chroot ${ROOT} update-grub", "timeout": 300}
    ]
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
            {"id": "unpackfs", "module": "unpackfs", "config": "unpackfs.conf"},
            {"id": "users", "module": "users", "config": "users.conf"},
            {"id": "displaymanager", "module": "displaymanager", "config": "displaymanager.conf"},
            {"id": "bootloader", "module": "bootloader", "config": "bootloader.conf"},
            {"id": "shellprocess", "module": "shellprocess", "config": "shellprocess.conf"},
        ],
        "sequence": [
            {"exec": [
                "partition", "mount", "unpackfs", "machineid", "fstab",
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


def main():
    ap = argparse.ArgumentParser(description="OintOS unattended install driver")
    ap.add_argument("plan", help="path to YAML/JSON install plan")
    ap.add_argument("--cal-conf", default="/etc/calamares",
                    help="Calamares config dir (default /etc/calamares)")
    ap.add_argument("--dry-run", action="store_true",
                    help="write configs but do not run calamares")
    ap.add_argument("--no-sudo", action="store_true",
                    help="run calamares without sudo (for testing)")
    args = ap.parse_args()

    plan = load_plan(args.plan)
    build(plan, args.cal_conf)
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