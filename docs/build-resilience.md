# Build Resilience Notes

## Rule 1: Build must survive SSH disconnection
- The ISO build runs on the WSL2 machine via Docker.
- `dockerbuild.sh` is started with `nohup ... &` so it continues even if the SSH session drops.
- The build log is written to `/tmp/phase6-build.log` (separate from stdout).
- If the Pi SSH connection dies, the build keeps running on WSL.

## Rule 2: Monitor every 20 minutes
- Check build progress by: `ssh -o ConnectTimeout=15 -p 2222 ervin@192.168.1.113 "tail -5 /tmp/phase6-build.log"`
- Use `ScheduleWakeup` to poll every 20 min.
- On BUILD COMPLETE: `otest2.sh` (Phase 4) + `otest4.sh` (Phase 6 installer).

## Rule 3: Never SSH-run the build directly
- Build is launched once with `nohup` and runs to completion.
- Never send interactive commands to a running build.
- Monitor passively via log tail only.

## Build location
- WSL2 machine: `~/ointos/distro-build`
- Build log: `/tmp/phase6-build.log`
- Output ISO: `~/ointos/distro-build/output/OintOS-1.0-amd64.iso`
