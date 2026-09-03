# Devbox Fullstack Design

## Goal
Create a reusable Docker-based development environment with PHP, Python, Node.js managed by NVM, and .NET SDKs 7, 8, 9 and 10 available side by side, plus password-based SSH access and 24/7 operation.

## Architecture
Use one Ubuntu 24.04 based image built by a `Dockerfile` and started through `docker-compose.yml`. A configurable host workspace path is mounted at `/workspace`, so projects can be edited on the host while tools execute inside the container.

The .NET SDKs are installed side by side under `/usr/share/dotnet` so `dotnet --list-sdks` exposes 7.x, 8.x, 9.x and 10.x. Individual projects can select an SDK with `global.json`.

NVM is installed for a non-root `dev` user, with the current Node.js LTS installed by default. PHP, Composer, Python, pip, Git and common build tools are included.

OpenSSH Server runs inside the container. SSH login is enabled for the non-root `dev` user on host port `2222` by default, mapped to container port `22`. Root SSH login is disabled. Password authentication is enabled, but the password is injected at runtime through `DEVBOX_SSH_PASSWORD` from a local `.env` file that is ignored by Git; no password or password hash is committed to the repository.

## Files
- `Dockerfile` — builds the development image and installs runtimes, SSH and tooling.
- `docker-compose.yml` — starts the devbox, mounts a configurable workspace into `/workspace`, exposes SSH, requires `DEVBOX_SSH_PASSWORD`, and uses `restart: unless-stopped`.
- `entrypoint.sh` — validates `DEVBOX_SSH_PASSWORD`, sets the `dev` password, creates persistent SSH host keys when necessary and starts `sshd` in the foreground.
- `scripts/verify-toolchain.sh` — verifies PHP, Composer, Python, pip, NVM, Node, npm and all four .NET SDK major versions.
- `scripts/install-host.sh` — validates the local `.env`, enables and starts the Docker service with systemd when available, then builds and starts the Compose service.
- `.env.example` — documents required runtime variables without containing a real secret.
- `.gitignore` — excludes `.env` and local workspace artifacts.
- `.dockerignore` — keeps unnecessary files out of the image build context.
- `tests/test-config.sh` — static validation for required security, runtime and always-on configuration.
- `.github/workflows/ci.yml` — validates Compose configuration, builds the image and runs the toolchain verification script.
- `README.md` — build, start, SSH, autostart and version-selection instructions.

## Runtime behavior
The container is intended to remain running continuously, 24 hours per day. Compose uses `restart: unless-stopped`, so an existing container is restarted automatically after a Docker daemon or host restart unless it was explicitly stopped by an administrator.

On Linux hosts that use systemd, the one-time host installation script runs `systemctl enable --now docker` when possible, ensuring the Docker daemon itself starts on boot. It then runs `docker compose up -d --build` so the devbox exists and is eligible for automatic restart thereafter.

The container uses `/workspace` as its working directory. It does not run Docker-in-Docker and does not include project-specific databases or services.

## SSH security
Password-based SSH is enabled because it was explicitly requested. Root login remains disabled and only the `dev` account is allowed through SSH. The password is never baked into the image and never committed; the host's ignored `.env` provides it at container start.

Persistent SSH host keys are stored in a named Docker volume so recreating or restarting the container does not unexpectedly change the host fingerprint.

## Security and maintenance
No tokens, API keys, SSH private keys or user passwords are committed. `.env` is ignored by Git. The SSH password should be long, random and unique to this devbox.

.NET 7 is end-of-support but remains available because it was explicitly requested. The image should be rebuilt periodically to refresh OS packages, Node.js LTS and SDK patch releases.

## Validation
A successful image must satisfy all of the following inside the container:
- `php --version` succeeds.
- `composer --version` succeeds.
- `python3 --version` and `pip3 --version` succeed.
- `nvm --version`, `node --version` and `npm --version` succeed.
- `dotnet --list-sdks` contains at least one 7.x, 8.x, 9.x and 10.x SDK.
- `sshd` is installed and configured with `PasswordAuthentication yes`, `PermitRootLogin no` and `AllowUsers dev`.
- Compose exposes SSH on `${SSH_PORT:-2222}:22`, requires `DEVBOX_SSH_PASSWORD`, and uses `restart: unless-stopped`.
- `.env` is ignored by Git.
- The host installation script enables Docker on boot when systemd is available and starts the Compose project.

`tests/test-config.sh` must fail with a non-zero exit code if any required configuration is missing. GitHub Actions must build the image and execute `scripts/verify-toolchain.sh` successfully before the implementation is considered complete.
