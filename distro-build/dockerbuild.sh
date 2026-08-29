#!/bin/bash
# ============================================================================
# OintOS Docker ISO build — runs isobuild.sh inside an isolated container.
#
# WHY: isobuild.sh does debootstrap + mounts (bind /proc,/sys,/dev, overlay).
# Running it directly in WSL2 can leave stale mounts behind that corrupt the
# WSL host's systemd/devfs on the next `wsl --shutdown` (we lost a WSL distro
# to that). A Docker container has its own mount namespace — even if the build
# fails violently, the WSL host is untouched. This is the SAFE build path.
#
# Requirements: Docker with a working daemon (Docker Desktop WSL2 backend, or
# docker-ce inside WSL2). Must be able to run privileged containers
# (debootstrap + mount require it).
#
# Usage (from the repo root):
#   bash distro-build/dockerbuild.sh
#
# Output ISO in distro-build/output/ (mirrored out of the container).
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ISO_NAME="OintOS-${OINTOS_VERSION:-1.0}-amd64"

# Check Docker
if ! command -v docker >/dev/null 2>&1; then
    echo "ERROR: docker not found. Install Docker Desktop (WSL2 backend) or docker-ce."
    exit 1
fi
if ! docker info >/dev/null 2>&1; then
    echo "ERROR: docker daemon not reachable. Is Docker Desktop running?"
    exit 1
fi

# Pull the base image explicitly so failures surface early.
echo ">>> Pulling ubuntu:26.04..."
docker pull ubuntu:26.04

# Run the build inside an isolated, privileged container.
#   --privileged            : debootstrap + mounts need real capabilities
#   -v "$REPO_ROOT":/workspace : mount the repo so the script + output live there
#   -w /workspace           : workdir = repo (script uses relative paths/output)
#   --rm                    : auto-remove the container when done
#   OINTOS_WORK_DIR=/workspace/buildroot : keep scratch inside the mounted repo
#                                          so it's easy to inspect/clean, and
#                                          output lands in output/ on the host.
echo ">>> Starting OintOS build inside isolated container..."
mkdir -p "$REPO_ROOT/distro-build/output"
if ! docker run --rm --privileged \
    -v "$REPO_ROOT":/workspace \
    -w /workspace \
    -e DEBIAN_FRONTEND=noninteractive \
    -e OINTOS_VERSION="${OINTOS_VERSION:-1.0}" \
    -e OINTOS_WORK_DIR=/workspace/buildroot \
    --platform linux/amd64 \
    ubuntu:26.04 \
    bash -c "bash /workspace/distro-build/isobuild.sh"; then
    echo ""
    echo ">>> BUILD FAILED. Container cleaned up automatically (--rm)."
    echo "    Stale mounts inside the container vanish with it — WSL host is safe."
    exit 1
fi

echo ""
echo ">>> Copying ISO out of buildroot to distro-build/output/ ..."
cp -f "$REPO_ROOT/buildroot/output/"*.iso* "$REPO_ROOT/distro-build/output/" 2>/dev/null || true
rm -rf "$REPO_ROOT/buildroot" 2>/dev/null || true   # drop the container scratch

echo ""
echo ">>> Build finished. Output:"
ls -lh "$REPO_ROOT/distro-build/output/" 2>/dev/null || echo "  (no output found)"