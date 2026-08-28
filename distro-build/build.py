#!/usr/bin/env python3
"""
OintOS ISO Builder — Python version with verbose logging.

Builds a custom Ubuntu 26.04 LTS + KDE Plasma ISO using live-build.

Run inside WSL2 Ubuntu (or any native Ubuntu):
    sudo python3 build.py

Logging: writes a timestamped full-text log to output/build-<date>.log
and mirrors everything with ANSI-colored output to the console.

Supports:
    --version <ver>     (default: 1.0)
    --no-prereqs        skip prerequisite installation (assume already installed)
    --arch <arch>       (default: amd64)
    --output <dir>      (default: <repo>/output)
    --keep-logs <n>     keep last N log files (default: 10)
"""

import argparse
import os
import shutil
import subprocess
import sys
import threading
import time
from datetime import datetime

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
DISTRO = "resolute"          # Ubuntu 26.04 LTS codename
DEFAULT_ARCH = "amd64"
DEFAULT_VERSION = "1.0"

# Host packages required to run live-build
PREREQS = [
    "live-build",
    "debootstrap",
    "squashfs-tools",
    "xorriso",
    "genisoimage",
    "grub-efi-amd64-bin",
    "grub-pc-bin",
    "mtools",
    "dosfstools",
    "git",
]

MIN_DISK_GB = 25          # peak disk space needed for the build
RECOMMENDED_RAM_MB = 8192
MIN_RAM_MB = 4096

COLOR_RED = "\033[91m"
COLOR_YELLOW = "\033[93m"
COLOR_GREEN = "\033[92m"
COLOR_CYAN = "\033[96m"
COLOR_BOLD = "\033[1m"
COLOR_DIM = "\033[2m"
COLOR_RESET = "\033[0m"


# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------

class Logger:
    """Writes to both a log file and the console (with ANSI colors)."""

    def __init__(self, log_path: str):
        self.log_path = log_path
        self.console_enabled = True
        # Open log file immediately and keep it
        self.fh = open(log_path, "w", encoding="utf-8")

    def _ts(self) -> str:
        return datetime.now().strftime("%H:%M:%S")

    def _emit(self, color: str, prefix: str, msg: str) -> None:
        line = f"{self._ts()} [{prefix}] {msg}"
        self.fh.write(line + "\n")
        self.fh.flush()
        if self.console_enabled:
            print(f"{color}{line}{COLOR_RESET}", flush=True)

    def info(self, msg: str) -> None:
        self._emit(COLOR_CYAN, "INFO ", msg)

    def step(self, msg: str) -> None:
        self._emit(COLOR_BOLD + COLOR_GREEN, "STEP ", msg)

    def ok(self, msg: str) -> None:
        self._emit(COLOR_GREEN, " OK  ", msg)

    def warn(self, msg: str) -> None:
        self._emit(COLOR_YELLOW, "WARN ", msg)

    def error(self, msg: str) -> None:
        self._emit(COLOR_RED, "ERROR", msg)

    def flush(self) -> None:
        """Force any buffered log output to disk immediately."""
        if self.fh:
            self.fh.flush()
            os.fsync(self.fh.fileno())

    def close(self) -> None:
        if self.fh:
            self.fh.close()
            self.fh = None


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def run(cmd: list, logger: Logger, cwd: str = None,
        check: bool = True, env: dict = None) -> subprocess.CompletedProcess:
    """Run a command, STREAMING output live to console + log line-by-line.

    Unlike subprocess.run with PIPE (which buffers all output until the
    process exits — hiding progress and losing logs on a crash), this reads
    each line as it's produced and forwards it immediately through the
    logger. The log file is therefore always up to date even if the build
    is interrupted.
    """
    display = " ".join(cmd)
    logger.info(f"$ {display}")

    # Buffered atomic log flush: stash the current console state so this file
    # stays the single source of truth. (Belt-and-braces; see Logger.flush.)
    logger.flush()

    # Launch with pipes; stderr merged into stdout so we catch everything.
    try:
        proc = subprocess.Popen(
            cmd,
            cwd=cwd,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1,          # line-buffered
            env=env,
        )
    except FileNotFoundError as exc:
        logger.error(f"command not found: {cmd[0]}")
        if check:
            raise SystemExit(f"Failed to execute: {display}") from exc
        return None

    def _reader(stream):
        # Read lines as they arrive and log them immediately.
        try:
            for raw in stream:
                line = raw.rstrip("\n")
                if line:
                    logger.info(f"    {line}")
        finally:
            try:
                stream.close()
            except OSError:
                pass

    reader = threading.Thread(target=_reader, args=(proc.stdout,), daemon=True)
    reader.start()

    # Wait for the process to finish.
    try:
        proc.wait()
    except KeyboardInterrupt:
        logger.warn("interrupted — terminating build subprocess")
        proc.terminate()
        try:
            proc.wait(timeout=10)
        except subprocess.TimeoutExpired:
            proc.kill()
        raise

    # Wait for the reader to drain any remaining buffered lines.
    reader.join(timeout=5)

    if proc.returncode != 0:
        logger.error(f"command exited with code {proc.returncode}: {display}")
        if check:
            raise SystemExit(f"Failed: {display}")
    else:
        logger.ok(f"command succeeded: {display}")

    return proc


def human_bytes(n: int) -> str:
    for unit in ["B", "KB", "MB", "GB", "TB"]:
        if n < 1024:
            return f"{n:.1f} {unit}"
        n /= 1024
    return f"{n:.1f} TB"


def check_disk_space(logger: Logger) -> None:
    """Warn/error if there isn't enough disk space for the build."""
    st = shutil.disk_usage(SCRIPT_DIR)
    free_gb = st.free / (1024 ** 3)
    logger.info(f"disk: {human_bytes(st.total)} total, "
                f"{human_bytes(st.free)} free")
    if free_gb < MIN_DISK_GB:
        logger.warn(
            f"Only {free_gb:.1f} GB free; build needs ~{MIN_DISK_GB} GB peak. "
            f"This may fail. Consider freeing space or running on a "
            f"machine with more room."
        )
    else:
        logger.ok(f"{free_gb:.1f} GB free — sufficient (need ~{MIN_DISK_GB} GB)")


def check_ram(logger: Logger) -> None:
    """Warn if RAM is low for the build."""
    try:
        with open("/proc/meminfo") as fh:
            for line in fh:
                if line.startswith("MemTotal:"):
                    total_kb = int(line.split()[1])
                    total_mb = total_kb // 1024
                    break
    except Exception:
        logger.warn("could not read /proc/meminfo to check RAM")
        return

    logger.info(f"RAM: {total_mb} MB total")
    if total_mb < MIN_RAM_MB:
        logger.error(
            f"Only {total_mb} MB RAM; build recommends ~{RECOMMENDED_RAM_MB} MB "
            f"and needs at least {MIN_RAM_MB} MB."
        )
        raise SystemExit(
            "Not enough RAM. If using WSL2, add a .wslconfig with:\n"
            "  [wsl2]\n  memory=8GB\n"
        )
    if total_mb < RECOMMENDED_RAM_MB:
        logger.warn(
            f"{total_mb} MB RAM is below the recommended "
            f"{RECOMMENDED_RAM_MB} MB; build may be slow but should proceed."
        )


def check_root(logger: Logger) -> None:
    if os.geteuid() != 0:
        logger.error(
            "This script must run as root (the build chroot needs root). "
            "Re-run with: sudo python3 build.py"
        )
        raise SystemExit(1)


# ---------------------------------------------------------------------------
# Main build
# ---------------------------------------------------------------------------

def install_prereqs(logger: Logger) -> None:
    logger.step("Installing build prerequisites")
    run(["apt-get", "update"], logger)
    missing = []
    for pkg in PREREQS:
        if shutil.which(pkg) is None and pkg not in ("live-build", "debootstrap"):
            missing.append(pkg)
    install = PREREQS  # just install all of them, apt is idempotent
    run(["apt-get", "install", "-y"] + install, logger)


def build(args, logger: Logger) -> str:
    build_dir = os.path.join(SCRIPT_DIR, "build")
    output_dir = args.output
    os.makedirs(output_dir, exist_ok=True)

    # Clean previous build directory
    logger.step("Cleaning previous build directory")
    if os.path.isdir(build_dir):
        logger.info(f"removing {build_dir}")
        shutil.rmtree(build_dir)
    os.makedirs(build_dir)

    # Copy config -> build dir
    logger.step("Copying live-build configuration")
    src_config = os.path.join(SCRIPT_DIR, "config")
    dst_config = os.path.join(build_dir, "config")
    if os.path.isdir(src_config):
        shutil.copytree(src_config, dst_config)
        logger.ok(f"copied config to {dst_config}")
    else:
        logger.warn(f"no config directory at {src_config}; using defaults")

    # lb config
    # NOTE: option names follow Ubuntu's live-build 3.0~a57 (verified via
    # `lb config --help`). Notably: --bootloader (singular, grub|syslinux|
    # yaboot) — there is no --bootloaders/grub-efi split; and --security/
    # --updates/--backports are NOT flags in this version — those repos are
    # configured via the mirror options (--parent-mirror-chroot-*), which
    # live-build default include for Ubuntu.
    logger.step("Configuring live-build (lb config)")
    lb_config = [
        "lb", "config",
        "--distribution", DISTRO,
        "--architectures", args.arch,
        "--archive-areas", "main restricted universe multiverse",
        "--bootloader", "grub",
        "--binary-images", "iso-hybrid",
        "--debian-installer", "live",
        "--iso-application", "OintOS",
        "--iso-publisher", "OintOS Project",
        "--iso-volume", f"OintOS {args.version}",
        "--apt-indices", "false",
        "--apt-recommends", "false",
    ]
    run(lb_config, logger, cwd=build_dir)

    # lb build
    logger.step("Building ISO (lb build) — this takes 30-90 minutes")
    logger.warn("Streaming full live-build output to console and log; "
                "large output expected.")
    run(["lb", "build"], logger, cwd=build_dir)

    # Locate the produced ISO
    logger.step("Locating produced ISO")
    candidates = []
    for fn in os.listdir(build_dir):
        if fn.endswith((".iso", ".hybrid.iso")):
            candidates.append(os.path.join(build_dir, fn))
    if not candidates:
        logger.error("no ISO produced — check the build log for errors")
        raise SystemExit("Build finished but no ISO was produced.")
    # Prefer the hybrid one
    iso_src = None
    for c in candidates:
        if "hybrid" in c:
            iso_src = c
            break
    if iso_src is None:
        iso_src = candidates[0]

    ts = datetime.now().strftime("%Y%m%d")
    iso_name = f"OintOS-{args.version}-{args.arch}-{ts}.iso"
    iso_dst = os.path.join(output_dir, iso_name)
    logger.step(f"Moving ISO to {output_dir}")
    shutil.move(iso_src, iso_dst)
    logger.ok(f"ISO: {iso_dst} ({human_bytes(os.path.getsize(iso_dst))})")

    # SHA-256 checksum
    logger.step("Generating SHA-256 checksum")
    import hashlib
    h = hashlib.sha256()
    with open(iso_dst, "rb") as fh:
        while chunk := fh.read(1024 * 1024):
            h.update(chunk)
    digest = h.hexdigest()
    sha_path = iso_dst + ".sha256"
    with open(sha_path, "w") as fh:
        fh.write(f"{digest}  {iso_name}\n")
    logger.ok(f"SHA256: {digest}")
    logger.ok(f"Written to {sha_path}")

    return iso_dst


def prune_logs(output_dir: str, keep: int, logger: Logger) -> None:
    logs = sorted(
        f for f in os.listdir(output_dir)
        if f.startswith("build-") and f.endswith(".log")
    )
    while len(logs) > keep:
        old = logs.pop(0)
        path = os.path.join(output_dir, old)
        try:
            os.remove(path)
            logger.info(f"pruned old log: {old}")
        except OSError:
            pass


def main() -> None:
    parser = argparse.ArgumentParser(description="Build the OintOS ISO.")
    parser.add_argument("--version", default=DEFAULT_VERSION,
                        help=f"ISO version (default: {DEFAULT_VERSION})")
    parser.add_argument("--arch", default=DEFAULT_ARCH,
                        help=f"architecture (default: {DEFAULT_ARCH})")
    parser.add_argument("--output", default=os.path.join(SCRIPT_DIR, "output"),
                        help="output directory for the ISO")
    parser.add_argument("--no-prereqs", action="store_true",
                        help="skip prerequisite installation")
    parser.add_argument("--keep-logs", type=int, default=10,
                        help="keep last N log files (default: 10)")
    args = parser.parse_args()

    # Prepare log file + logger
    os.makedirs(args.output, exist_ok=True)
    ts = datetime.now().strftime("%Y%m%d-%H%M%S")
    log_path = os.path.join(args.output, f"build-{ts}.log")
    logger = Logger(log_path)

    start = time.time()
    try:
        logger.info("=" * 60)
        logger.info("OintOS ISO Builder")
        logger.info(f"Distribution: Ubuntu {DISTRO} ({args.arch})")
        logger.info(f"Version: {args.version}")
        logger.info(f"Build dir: {os.path.join(SCRIPT_DIR, 'build')}")
        logger.info(f"Output dir: {args.output}")
        logger.info(f"Log file: {log_path}")
        logger.info("=" * 60)

        check_root(logger)
        check_disk_space(logger)
        check_ram(logger)

        if not args.no_prereqs:
            install_prereqs(logger)
        else:
            logger.warn("Skipping prerequisite installation (--no-prereqs)")

        iso = build(args, logger)

        # Prune old logs
        prune_logs(args.output, args.keep_logs, logger)

        elapsed = time.time() - start
        logger.step("Build complete")
        logger.ok(f"ISO:  {iso}")
        logger.ok(f"SHA:  {iso}.sha256")
        logger.ok(f"Log:  {log_path}")
        logger.info(f"Elapsed: {int(elapsed // 60)}m {int(elapsed % 60)}s")
        logger.info("Test with:")
        logger.info("  qemu-system-x86_64 -cdrom <iso> -m 4096 -enable-kvm -smp 2")

    except SystemExit as exc:
        logger.error(str(exc) if str(exc) else "build stopped")
        elapsed = time.time() - start
        logger.info(f"Elapsed before failure: {int(elapsed // 60)}m "
                    f"{int(elapsed % 60)}s")
        logger.info(f"Full log: {log_path}")
        raise
    except Exception as exc:  # noqa: BLE001
        logger.error(f"unexpected error: {exc!r}")
        elapsed = time.time() - start
        logger.info(f"Elapsed before failure: {int(elapsed // 60)}m "
                    f"{int(elapsed % 60)}s")
        logger.info(f"Full log: {log_path}")
        raise
    finally:
        logger.close()


if __name__ == "__main__":
    main()
