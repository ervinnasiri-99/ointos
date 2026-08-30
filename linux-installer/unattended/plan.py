#!/usr/bin/env python3
"""
OintOS unattended install driver (Phase 6).

Reads an install plan (YAML or JSON, subiquity-shaped so the Windows/Libertix
side can produce it) and drives a HEADLESS Calamares install:

  1. Parse the plan (disk, partitioning, filesystem, user, features/late-commands).
  2. Pre-seed /etc/calamares/*.conf from the plan (partition, users, btrfs
     subvolumes for Phase 5).
  3. Write an exec-only settings.conf.
  4. Invoke `calamares --is-installer` with that config.

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

    # --- partition.conf ---------------------------------------------------
    partition = {
        "defaultPartitioningTableType": storage.get("layout", "gpt"),
        "defaultPartitioningImplementation": storage.get("layout", "gpt"),
        "alwaysShowPartitionLabels": True,
        "defaultFilesystemType": storage.get("filesystem", "btrfs"),
        "allowManualPartitioning": False,        # unattended
        "allowEmptyPartitions": False,
        "allowResize": False,
        "userSupportedPartitioningModes": [],
        "initialPartitioningChoice": "alongside",
        # os-prober for dual-boot
    }
    write_conf(os.path.join(cal_conf, "partition.conf"), partition)

    # --- mount.conf (btrfs subvolumes => Phase 5 / Timeshift) -------------
    sv = storage.get("subvolumes", ["@", "@home", "@cache", "@log"])
    # Timeshift / Calamares expect the Ubuntu-type layout:
    #   "@"  -> mountpoint "/"      (root subvolume)
    #   "@home" -> mountpoint "/home"
    #   "@cache" -> mountpoint "/var/cache" (configurable per distro)
    def _subvol(s):
        name = s.lstrip("@")
        if name == "":
            return {"mountpoint": "/", "subvolume": "/@"}
        if name == "cache":
            return {"mountpoint": "/var/cache", "subvolume": "/@cache"}
        if name == "log":
            return {"mountpoint": "/var/log", "subvolume": "/@log"}
        return {"mountpoint": "/" + name, "subvolume": "/" + s}

    btrfs = [_subvol(s) for s in sv]
    mount = {
        "mountOptions": ["default"],
        "btrfsSubvolumes": btrfs,
        "efiMountOptions": ["utf8"],
        "cryptoPassphrase": "",
    }
    write_conf(os.path.join(cal_conf, "mount.conf"), mount)

    # --- users.conf -------------------------------------------------------
    users = {
        "setRootPassword": False,
        "autologinUser": "",
        "sudoersGroup": "sudo",
    }
    if ident.get("username"):
        users["doAutologin"] = False
        users["autologinUser"] = ident["username"]
    write_conf(os.path.join(cal_conf, "users.conf"), users)

    # --- bootloader.conf --------------------------------------------------
    bootloader = {
        "efiBootLoader": "grub",
        "grubInstallTarget": "/boot",
        "osproberEnabled": True,
        "efiFallback": True,
    }
    write_conf(os.path.join(cal_conf, "bootloader.conf"), bootloader)

    # --- shellprocess.conf (late commands) --------------------------------
    late = [
        {"name": "update-grub", "command": "chroot ${ROOT} update-grub || true"}
    ]
    for cmd in plan.get("late_commands", []):
        late.append({"name": "late-" + str(len(late)), "command": cmd})
    write_conf(os.path.join(cal_conf, "shellprocess.conf"), {"scripts": late})

    # --- settings.conf: exec-only (unattended) -----------------------------
    settings = {
        "modules-search": ["local", "/usr/lib/calamares/modules"],
        "instances": [
            {"id": "partition", "module": "partition", "config": "partition.conf"},
            {"id": "mount", "module": "mount", "config": "mount.conf"},
            {"id": "unpackfs", "module": "unpackfs", "config": "unpackfs.conf"},
            {"id": "users", "module": "users", "config": "users.conf"},
            {"id": "displaymanager", "module": "displaymanager", "config": "displaymanager.conf"},
            {"id": "bootloader", "module": "bootloader", "config": "bootloader.conf"},
            {"id": "shellprocess", "module": "shellprocess", "config": "shellprocess.conf"},
            {"id": "finished", "module": "finished"},
        ],
        "sequence": {
            "exec": [
                "partition", "mount", "unpackfs", "users", "displaymanager",
                "bootloader", "shellprocess", "finished",
            ]
        },
        "branding": "ointos",
        "prompt-install": False,
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

    if os.geteuid() != 0 and not args.no_sudo:
        cmd = ["sudo", "calamares", "--is-installer", "-c", args.cal_conf]
    else:
        cmd = ["calamares", "--is-installer", "-c", args.cal_conf]
    print("Running:", shlex.join(cmd))
    return subprocess.call(cmd)


if __name__ == "__main__":
    sys.exit(main())