# Codespaces Desktop Design

## Goal
Add a GitHub Codespaces mode to `devbox-fullstack` that provides the existing PHP, Composer, Python, pip, NVM/Node.js LTS, and .NET SDK 8/9/10 toolchain together with a lightweight Linux graphical desktop accessible from the browser.

## Architecture
Keep the existing local/server Docker workflow and SSH behavior intact. Refactor the root `Dockerfile` into a multi-stage image with a reusable `toolchain` stage containing the development runtimes and a final `ssh-runtime` stage containing the password-based SSH entrypoint used by the existing Docker Compose service.

The existing `docker-compose.yml` will explicitly build the `ssh-runtime` target so its current 24/7 behavior remains unchanged. GitHub Codespaces will build only the `toolchain` target through `.devcontainer/devcontainer.json`, avoiding the SSH entrypoint and avoiding any need for `DEVBOX_SSH_PASSWORD` inside Codespaces.

The Codespaces configuration will add the official `ghcr.io/devcontainers/features/desktop-lite:1` feature. This feature provides a lightweight Fluxbox desktop, TigerVNC, and a noVNC web client. Port `6080` will be forwarded automatically and labeled `Desktop (noVNC)` so the graphical environment can be opened from the Codespaces Ports panel in a browser.

## Components
- `Dockerfile` — split into `toolchain` and `ssh-runtime` stages.
- `docker-compose.yml` — build the `ssh-runtime` stage explicitly, preserving the existing server/local deployment.
- `.devcontainer/devcontainer.json` — build the `toolchain` stage, use `dev` as the remote user, add `desktop-lite`, forward port 6080, and increase shared memory for GUI applications.
- `tests/test-config.sh` — retain the existing Docker/SSH contract and add assertions for the multi-stage build and Codespaces configuration.
- `README.md` — document both modes: local/server Docker and GitHub Codespaces graphical desktop.
- `.github/workflows/ci.yml` — continue validating the normal Docker image and add a static validation of the Codespaces configuration.

## Desktop behavior
The Codespace opens normally in VS Code Web. The graphical Linux desktop is a second interface inside the same Codespace, exposed by noVNC on port 6080. GUI applications launched from the Codespaces terminal inherit the desktop display and appear inside Fluxbox.

The desktop uses the official Dev Containers `desktop-lite` feature rather than installing and maintaining a separate XFCE or Cinnamon stack. This keeps memory and CPU usage lower while still providing a file manager, terminal, editor utilities, and support for launching additional Linux GUI applications.

The noVNC port remains private to the Codespace by default. The repository will not intentionally make the desktop port public.

## Compatibility
The existing Docker Compose flow must continue to provide:
- PHP and Composer.
- Python and pip.
- NVM with Node.js LTS and npm.
- .NET SDK 8, 9, and 10 side by side.
- Password-based SSH for `dev` on host port 2222 by default.
- `restart: unless-stopped` for always-on server/local deployments.

The Codespaces flow must provide the same toolchain but does not need to run the SSH server because Codespaces already provides its own remote access path.

## Validation
A change is acceptable only if:
- `docker compose config` still succeeds with a dummy SSH password.
- the normal Docker image still builds successfully.
- `scripts/verify-toolchain.sh` still succeeds inside the normal Docker image.
- `tests/test-config.sh` verifies that Compose targets `ssh-runtime` and that `.devcontainer/devcontainer.json` targets `toolchain`.
- `.devcontainer/devcontainer.json` contains `desktop-lite`, forwards port 6080, labels the port, uses remote user `dev`, and configures at least 1 GB of shared memory for GUI applications.
- the Codespaces configuration does not require or commit a real SSH password.

## Security
No new secrets are committed. The existing `.env` SSH password flow remains limited to the normal Docker Compose deployment. Codespaces relies on GitHub's own access control and port-forwarding model; no fixed desktop credential or public VNC endpoint will be added to the repository.

## Out of scope
- Windows desktop support; that will be handled as a separate project after this Linux Codespaces mode is complete.
- Keeping a Codespace alive 24/7 beyond GitHub's normal lifecycle and quota rules.
- Installing heavyweight desktop environments such as Cinnamon, KDE, or GNOME by default.
