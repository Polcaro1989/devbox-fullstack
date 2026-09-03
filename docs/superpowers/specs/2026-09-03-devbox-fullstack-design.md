# Devbox Fullstack Design

## Goal
Create a reusable Docker-based development environment that starts with PHP, Python, Node.js managed by NVM, and .NET SDKs 7, 8, 9 and 10 already available in the same container.

## Architecture
Use one Ubuntu 24.04 based image built by a `Dockerfile` and started through `docker-compose.yml`. The repository itself is mounted at `/workspace`, so projects can be edited on the host while tools execute inside the container.

The .NET SDKs will be installed side by side under the standard `dotnet` location so `dotnet --list-sdks` exposes 7.x, 8.x, 9.x and 10.x. Individual projects can select an SDK with `global.json`.

NVM will be installed for a non-root development user, with the current Node.js LTS installed by default. PHP and Python will come from Ubuntu packages, together with Composer, pip and common build tools.

## Files
- `Dockerfile` — builds the development image and installs all runtimes and tooling.
- `docker-compose.yml` — starts the devbox and mounts the repository into `/workspace`.
- `scripts/verify-toolchain.sh` — verifies PHP, Composer, Python, pip, NVM, Node, npm and all four .NET SDK major versions.
- `scripts/start-devbox.sh` — starts the Compose service.
- `scripts/stop-devbox.sh` — stops the Compose service.
- `systemd/devbox-start.service` and `systemd/devbox-start.timer` — start the devbox every day at 00:00 local host time.
- `systemd/devbox-stop.service` and `systemd/devbox-stop.timer` — stop the devbox every day at 13:00 local host time.
- `.dockerignore` — keeps unnecessary files out of the image build context.
- `README.md` — build, start, shell, schedule and version-selection instructions.

## Runtime behavior
The container is scheduled to run every day for a 13-hour window, from 00:00 through 13:00 in the Linux host's local timezone. `systemd` timers on the host trigger `docker compose up -d` at 00:00 and `docker compose stop` at 13:00.

The container uses `/workspace` as its working directory. It will not run Docker-in-Docker and will not contain project-specific databases or services; those can be added later as separate Compose services when needed.

The Compose service will use a restart policy suitable for recovering from an unexpected container failure while inside the daily runtime window. The stop timer remains authoritative at 13:00.

## Security and maintenance
No tokens, SSH keys, API keys or user secrets will be committed. Versions that have reached end of support, such as older .NET SDK lines, remain available only because they were explicitly requested. The image should be rebuilt periodically to refresh OS packages and the current Node.js LTS patch release.

## Validation
A successful build must satisfy all of the following inside the container:
- `php --version` succeeds.
- `composer --version` succeeds.
- `python3 --version` and `pip3 --version` succeed.
- `nvm --version`, `node --version` and `npm --version` succeed.
- `dotnet --list-sdks` contains at least one 7.x, 8.x, 9.x and 10.x SDK.

The scheduling setup must also be verifiable with `systemctl list-timers` and show a start timer for 00:00 and a stop timer for 13:00.

The verification script must fail with a non-zero exit code if any required runtime is missing.
