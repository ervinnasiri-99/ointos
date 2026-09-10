#!/usr/bin/env python3
"""Producer/consumer contract: PS1 policy values == plan.py enforcement.

stdlib only. Run: python3 test_producer_contract.py
"""
import json
import re
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent  # ointos/
REPO = ROOT.parent.parent  # OintOS/
PLAN = REPO / "linux-installer" / "unattended" / "plan.py"
POLICY = json.loads((ROOT / "config" / "ointos-policy.json").read_text())
PS1 = (ROOT / "scripts" / "New-OIntOSStaging.ps1").read_text()
FIX = HERE / "fixtures"

fails = []


def check(name, cond, detail=""):
    print(("PASS " if cond else "FAIL ") + name + (f" — {detail}" if detail and not cond else ""))
    if not cond:
        fails.append(name)


def dry_run(plan_path, extra=()):
    with tempfile.TemporaryDirectory() as cal:
        p = subprocess.run([sys.executable, str(PLAN), str(plan_path),
                            "--dry-run", "--cal-conf", cal, *extra],
                           capture_output=True, text=True)
        return p


# 1. policy <-> PS1 value agreement
check("label OINTOSSTG in PS1+policy",
      "OINTOSSTG" in PS1 and POLICY["volumeLabels"]["staging"] == "OINTOSSTG")
check("uefi-only in PS1+policy",
      POLICY["guardrails"]["firmware"] == "uefi" and "UEFI-only" in PS1)
check("secureboot gate in PS1", "SecureBoot" in PS1 and "secureBootEnabled" in PS1)
check("bitlocker gate in PS1", "FullyDecrypted" in PS1)
check("sha256 gate in PS1", "Get-FileHash" in PS1 and "SHA256" in PS1)
check("planId equality in PS1", PS1.count("planId") >= 3)
check("default dry-run", "-DryRun" in PS1 and "nothing written" in PS1)
check("reserved oinstaller in policy", "oinstaller" in POLICY["account"]["reservedUsernames"])

# 2. consumer accepts the minimal producer plan
r = dry_run(FIX / "plan-minimal.json",
            extra=["--windows-root", str(FIX), "--staging", str(FIX)])
# note: minimal plan has no hash path on disk -> dry-run still writes configs;
# hash read happens only when passwordHashWindowsPath set... it IS set.
# Provide the hash file so accept-path is exercised:
(FIX / "password-hash.txt").write_text("$6$rounds=5000$salt$abcdefghijklmnopqrstuv0123456789ABCDEFabcdefghijklmnopqrstu")
r = dry_run(FIX / "plan-minimal.json", extra=["--windows-root", str(FIX)])
check("minimal plan dry-run rc==0", r.returncode == 0, r.stderr[-500:])

# 3. refuse matrix
r = dry_run(FIX / "plan-secureboot.json")
check("secureboot refused rc==2", r.returncode == 2, r.stderr[-300:])
r = dry_run(FIX / "plan-gpt-bios.json")
check("gpt/bios mismatch refused rc==2", r.returncode == 2, r.stderr[-300:])

# 4. PS1 structural sanity (no pwsh on Pi/WSL here)
for a, b in [("{", "}"), ("(", ")"), ("[", "]")]:
    check(f"balanced {a}{b}", PS1.count(a) == PS1.count(b))
check("requires PS7", "#requires -Version 7.0" in PS1)

print(f"\n{len(fails)} failures: {fails}" if fails else "\nall green")
sys.exit(1 if fails else 0)
