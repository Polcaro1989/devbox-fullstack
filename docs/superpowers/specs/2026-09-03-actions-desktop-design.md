# Actions Desktop Design

## Goal
Replace the in-progress Codespaces desktop mode with a single GitHub Actions desktop mode for `devbox-fullstack`, using the standard Ubuntu GitHub-hosted runner with its 14 GB SSD allocation. The environment must expose a lightweight graphical Linux desktop and a web terminal while preserving the existing development toolchain: PHP/Composer, Python/pip, NVM/Node.js LTS, and .NET SDK 8/9/10.

## Final operating model
There will be one cloud-interactive mode in the repository: **Actions Desktop**. GitHub Codespaces support will not remain in the final implementation.

A user starts the desktop manually with `workflow_dispatch`. A standard `ubuntu-latest` runner prepares the environment, launches Fluxbox, Xvfb, a VNC server, noVNC/websockify, and `ttyd`, then keeps the job alive until the GitHub-hosted runner time limit is reached or the user cancels it. The workflow must not automatically restart itself, chain new jobs, schedule itself to evade limits, or otherwise attempt to bypass GitHub Actions lifecycle restrictions.

## Architecture
The existing root Docker image remains the canonical definition of the development toolchain. The Actions workflow may either build the existing Docker target and run the graphical/session services around it, or install the GUI/session layer directly on the runner while using the repository's verification script to prove the same toolchain is present. The implementation should prefer the approach that minimizes disk usage and startup time on the 14 GB runner while preserving the toolchain contract.

The graphical stack is intentionally lightweight:
- Xvfb provides the virtual X display.
- Fluxbox provides the window manager.
- TigerVNC/x11vnc provides VNC access to the display.
- noVNC + websockify provides browser access to the desktop.
- `ttyd` provides a browser terminal in the same session.

No GNOME, KDE, Cinnamon, or other heavyweight desktop environment is installed by default.

## Access model
The workflow must be manually started from the Actions tab. During the run, it must print the connection information needed to reach the noVNC desktop and the `ttyd` terminal.

The repository must not commit a fixed desktop password, SSH password, tunnel token, or other credential. Any session credential must be generated at runtime or supplied through GitHub Secrets. If an external tunnel is required to reach browser services from the hosted runner, its credentials must come from GitHub Secrets and must never be echoed in logs.

The design does not assume a specific tunnel provider until implementation verifies what can be used securely and reliably from GitHub Actions. The implementation must not create a publicly reachable unauthenticated VNC/noVNC endpoint.

## Toolchain
The Actions Desktop session must provide and verify:
- PHP CLI and Composer.
- Python 3, pip, and venv.
- NVM with Node.js LTS and npm.
- .NET SDK 8.x, 9.x, and 10.x side by side.
- Git and common build tools.

.NET 7 must remain excluded.

## Disk budget
The design targets the standard GitHub-hosted Ubuntu runner with 14 GB SSD. The workflow must minimize extra packages and remove package-manager caches and temporary build artifacts where practical. The GUI layer must stay lightweight so the development toolchain and a normal project workspace can coexist within the runner disk budget.

## Repository visibility
The implementation itself must work in both private and public repositories. Repository visibility is a separate account-level decision and is not changed by the code implementation. The repository must not be made public without explicit user approval.

For the user's goal of avoiding the private-repository monthly Actions minute quota, the repository would need to be public when using standard GitHub-hosted runners. That visibility change is outside the code implementation and requires explicit approval after a secrets/history review.

## Existing Docker mode
The existing Docker/SSH files remain available as the toolchain source and local/server execution path unless removing them is strictly required for the Actions implementation. The user specifically requested that there be only one cloud-interactive mode; therefore Codespaces configuration must be removed before merge, but the normal Docker build may remain because it is not a competing cloud desktop mode and is useful for CI/toolchain reproducibility.

## Validation
A change is acceptable only if:
- the Codespaces `.devcontainer` configuration introduced on the feature branch is removed before merge;
- the Actions Desktop workflow is manual (`workflow_dispatch`);
- the workflow has a timeout no greater than GitHub-hosted runner limits and no self-restart or scheduled chaining;
- the workflow installs/starts Fluxbox, a virtual display, VNC/noVNC, and `ttyd`;
- no fixed secret is committed;
- the existing toolchain verification passes for PHP, Composer, Python, pip, NVM/Node.js, npm, and .NET 8/9/10;
- .NET 7 is absent;
- static tests assert the workflow's manual trigger, GUI components, terminal component, timeout, and absence of Codespaces configuration;
- CI for ordinary commits remains green after the change.

## Security
No long-lived credential is stored in Git. If browser exposure requires a tunnel, only a provider configured through repository secrets may be used. Logs must not reveal tunnel credentials or generated passwords. Root SSH access remains disabled in the existing Docker mode.

## Out of scope
- Automatic relaunching to create an effectively endless GitHub Actions session.
- Circumventing GitHub Actions time, quota, or acceptable-use limits.
- Heavyweight desktop environments.
- Windows desktop support; that is a separate future task.
- Changing repository visibility without explicit user approval.
