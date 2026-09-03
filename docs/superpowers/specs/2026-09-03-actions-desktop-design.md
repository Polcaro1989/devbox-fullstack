# Actions Desktop Design

## Goal
Provide one cloud-interactive development mode for this repository: a manually started GitHub Actions desktop session on the standard Ubuntu hosted runner, using the existing PHP/Python/Node/.NET toolchain and a lightweight browser desktop.

## Operating model
The workflow is named `Actions Desktop` and is started only with `workflow_dispatch`. It runs on `ubuntu-latest`, has a hard timeout below the GitHub-hosted job limit, and never schedules, relaunches, or chains itself.

The runner provides the development machine for the lifetime of one job. The session is temporary. Source work that must persist should be committed/pushed to Git before the job ends.

## Toolchain
The session provides and verifies PHP/Composer, Python/pip, NVM with Node.js LTS/npm, and .NET SDK 8, 9, and 10 side by side. .NET 7 remains excluded.

The Actions setup installs the toolchain directly on the runner rather than building the full Docker image for the interactive session, reducing disk pressure on the 14 GB hosted runner. The existing Docker files remain as a local/server path and CI reference, but they are not a second cloud desktop mode.

## Desktop
The graphical stack is intentionally light:
- Xvfb virtual X display.
- Fluxbox window manager.
- x11vnc bound to localhost.
- noVNC/websockify bound to localhost.
- ttyd browser terminal bound to localhost.
- nginx as a single local authenticated reverse proxy.
- Cloudflare Quick Tunnel as an outbound-only temporary HTTPS ingress to nginx.

The root URL opens noVNC. `/terminal/` opens ttyd.

## Authentication
Because the repository and Actions logs are public, no generated password is printed to logs or job summaries. A repository Actions secret named `DESKTOP_PASSWORD` is required. nginx protects both noVNC and ttyd with HTTP Basic Authentication using username `devbox` and that secret.

No fixed password, token, private key, or tunnel credential is committed. x11vnc/noVNC and ttyd listen only on loopback and are reachable externally only through the authenticated nginx proxy.

Cloudflare Quick Tunnel does not require a committed tunnel token; it supplies a temporary random `trycloudflare.com` URL for the lifetime of the job. The URL may appear in public Actions logs, so password authentication is mandatory.

## Disk budget
Target the standard GitHub-hosted Ubuntu runner and its 14 GB SSD. Install only lightweight GUI packages, remove apt caches, avoid heavyweight desktop environments, and install the requested language runtimes directly on the host runner.

## Repository shape
There is no `.devcontainer`/Codespaces configuration in the final result. The earlier Codespaces experiment is not merged.

Files added for this mode:
- `.github/workflows/actions-desktop.yml`
- `scripts/setup-actions-toolchain.sh`
- `scripts/start-actions-desktop.sh`

`tests/test-config.sh` statically enforces the workflow trigger, timeout, GUI/access components, secret reference, loopback binding, and absence of Codespaces configuration.

## Validation
Acceptance requires:
- `Actions Desktop` uses only `workflow_dispatch` and `ubuntu-latest`.
- timeout is at most 355 minutes.
- no schedule, self-dispatch, or automatic relaunch exists.
- `DESKTOP_PASSWORD` is read from GitHub Secrets and never printed.
- Xvfb, Fluxbox, x11vnc, noVNC/websockify, ttyd, nginx, and cloudflared are configured.
- local services bind to `127.0.0.1`.
- toolchain verification requires PHP, Composer, Python, pip, NVM, Node, npm, and .NET 8/9/10; .NET 7 is absent.
- `.devcontainer/devcontainer.json` is absent.
- normal repository CI stays green.

## Out of scope
- Automatic restart to create an effectively endless runner session.
- Evading GitHub Actions limits or acceptable-use restrictions.
- Persistent disk across GitHub-hosted runner jobs.
- Windows desktop support.
