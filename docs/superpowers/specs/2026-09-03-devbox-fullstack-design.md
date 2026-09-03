# Devbox Fullstack Design

## Goal
Create a reusable Docker-based development environment with PHP, Python, Node.js managed by NVM, and .NET SDKs 7, 8, 9 and 10 available side by side, plus SSH access and an automatic daily runtime window.

## Architecture
Use one Ubuntu 24.04 based image built by a `Dockerfile` and started through `docker-compose.yml`. The repository is mounted at `/workspace`, so projects can be edited on the host while tools execute inside the container.

The .NET SDKs are installed side by side under `/usr/share/dotnet` so `dotnet --list-sdks` exposes 7.x, 8.x, 9.x and 10.x. Individual projects can select an SDK with `global.json`.

NVM is installed for a non-root `dev` user, with the current Node.js LTS installed by default. PHP, Composer, Python, pip, Git and common build tools are included.

OpenSSH Server runs inside the container. SSH login is enabled for the non-root `dev` user on host port `2222`, mapped to container port `22`. Root SSH login is disabled. Password authentication is enabled, but the password is injected at runtime through `DEVBOX_PASSWORD` from a local `.env` file that is ignored by Git; no password or password hash is committed to the repository.

## Files
- `Dockerfile` — builds the development image and installs runtimes, SSH and tooling.
- `docker-compose.yml` — starts the devbox, mounts the repository into `/workspace`, exposes SSH on port 2222 and reads the runtime password from `.env`.
- `entrypoint.sh` — validates `DEVBOX_PASSWORD`, sets the `dev` password, prepares SSH host keys and starts `sshd` in the foreground.
- `scripts/verify-toolchain.sh` — verifies PHP, Composer, Python, pip, NVM, Node, npm and all four .NET SDK major versions.
- `scripts/devbox-window.sh` — starts the Compose service when the host local time is from 00:00 up to 12:59 and stops it from 13:00 onward.
- `scripts/install-systemd.sh` — installs and enables the systemd service/timer using the repository's actual path.
- `systemd/devbox-window.service.template` — one-shot service template used by the installer.
- `systemd/devbox-window.timer` — triggers at boot and at 00:00 and 13:00 every day so reboots are corrected to the proper state.
- `.env.example` — documents the required `DEVBOX_PASSWORD` without containing a real secret.
- `.gitignore` — excludes `.env` and local workspace artifacts.
- `.dockerignore` — keeps unnecessary files out of the image build context.
- `tests/test-config.sh` — static validation for required security, runtime and schedule configuration.
- `README.md` — build, start, SSH, schedule and version-selection instructions.

## Runtime behavior
The intended daily window is exactly 13 hours in the Linux host's local timezone: start at 00:00 and stop at 13:00.

A systemd timer invokes `scripts/devbox-window.sh` at boot, 00:00 and 13:00. The script checks the current local hour before deciding what to do. This means a reboot at 08:00 starts the container, while a reboot at 18:00 keeps it stopped. The container uses a restart policy for unexpected failures, but the 13:00 window check remains authoritative.

The container uses `/workspace` as its working directory. It does not run Docker-in-Docker and does not include project-specific databases or services.

## Security and maintenance
No tokens, SSH keys, API keys or user secrets are committed. The generated SSH password lives only in the host's `.env` file. SSH root login is disabled. The `dev` account is the only intended SSH account.

.NET 7 is end-of-support but remains available because it was explicitly requested. The image should be rebuilt periodically to refresh OS packages, Node.js LTS and SDK patch releases.

## Validation
A successful image must satisfy all of the following inside the container:
- `php --version` succeeds.
- `composer --version` succeeds.
- `python3 --version` and `pip3 --version` succeed.
- `nvm --version`, `node --version` and `npm --version` succeed.
- `dotnet --list-sdks` contains at least one 7.x, 8.x, 9.x and 10.x SDK.
- `sshd` is installed and configured with `PasswordAuthentication yes` and `PermitRootLogin no`.
- Compose exposes `2222:22` and requires `DEVBOX_PASSWORD`.
- `.env` is ignored by Git.

The scheduling configuration must show the 00:00 and 13:00 transitions and a boot-time correction path.

`tests/test-config.sh` must fail with a non-zero exit code if any required configuration is missing.