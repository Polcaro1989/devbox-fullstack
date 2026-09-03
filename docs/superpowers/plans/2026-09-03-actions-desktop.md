# Actions Desktop Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the in-progress Codespaces mode with one manually started GitHub Actions desktop session using the standard Ubuntu runner, a lightweight browser desktop, and a browser terminal.

**Architecture:** A manual `workflow_dispatch` job installs a lightweight GUI/session layer directly on the GitHub-hosted Ubuntu runner to conserve the 14 GB disk budget. Xvfb + Fluxbox create the desktop, x11vnc + noVNC expose it locally, nginx adds strong HTTP Basic authentication, `ttyd` provides an authenticated terminal, and two temporary Cloudflare Quick Tunnels publish the HTTP endpoints for the lifetime of the job. The normal Docker image remains only as the canonical/local toolchain path, not as a second cloud desktop mode.

**Tech Stack:** GitHub Actions, Ubuntu, Bash, Xvfb, Fluxbox, x11vnc, noVNC, websockify, nginx, ttyd, cloudflared, PHP/Composer, Python/pip, NVM/Node LTS, .NET 8/9/10.

**Spec:** `docs/superpowers/specs/2026-09-03-actions-desktop-design.md`

## Global Constraints

- The cloud-interactive mode is Actions Desktop only; `.devcontainer` must be absent.
- Workflow trigger is manual `workflow_dispatch` only.
- Job timeout is less than or equal to 360 minutes and it must not self-restart, schedule itself, or chain replacement jobs.
- A repository secret named `DESKTOP_PASSWORD` supplies the browser password; no fixed password is committed or printed.
- noVNC is reachable only through an authenticated nginx reverse proxy; x11vnc and noVNC bind to localhost.
- `ttyd` binds to localhost and uses the same strong browser credential.
- Quick Tunnels are temporary development ingress only and their random URLs may be printed; passwords/tokens may not be printed.
- Toolchain must verify PHP/Composer, Python/pip, NVM/Node/npm, and .NET SDK 8/9/10. .NET 7 remains excluded.
- Extra packages and apt caches are minimized for the 14 GB runner.

---

### Task 1: Replace the static contract

**Files:**
- Modify: `tests/test-config.sh`

- [ ] Add assertions for `.github/workflows/actions-desktop.yml` and `scripts/start-actions-desktop.sh`.
- [ ] Assert `workflow_dispatch`, `timeout-minutes: 350`, `DESKTOP_PASSWORD`, Xvfb, Fluxbox, x11vnc, noVNC/websockify, nginx auth, ttyd, cloudflared, and localhost bindings.
- [ ] Fail if `.devcontainer/devcontainer.json` exists.
- [ ] Run CI and confirm RED before implementation.

### Task 2: Implement the desktop session

**Files:**
- Create: `scripts/start-actions-desktop.sh`
- Create: `.github/workflows/actions-desktop.yml`

- [ ] Require `DESKTOP_PASSWORD` without echoing it.
- [ ] Install only the required GUI/web packages and remove apt caches.
- [ ] Ensure PHP/Composer, Python/pip/venv, NVM/Node LTS and .NET SDK 8/9/10 are available directly on the runner.
- [ ] Start Xvfb and Fluxbox on display `:99`.
- [ ] Start localhost-only x11vnc without external VNC authentication because it is unreachable except through localhost noVNC.
- [ ] Start localhost-only noVNC/websockify on 6080.
- [ ] Put nginx on localhost:8080 with bcrypt-backed Basic Auth using `DESKTOP_PASSWORD`, proxying noVNC including WebSocket upgrade.
- [ ] Start localhost-only ttyd on 7681 with Basic Auth.
- [ ] Start two Cloudflare Quick Tunnels for nginx and ttyd, extract only the random URLs, and write them to the GitHub step summary.
- [ ] Keep the session alive until cancellation/job timeout; no relaunch logic.

### Task 3: Remove Codespaces and update CI

**Files:**
- Delete: `.devcontainer/devcontainer.json`
- Modify: `.github/workflows/ci.yml`

- [ ] Remove Dev Container/Codespaces validation/build steps.
- [ ] Keep normal Docker/toolchain verification.
- [ ] Add Bash syntax checks for the Actions Desktop script and YAML/static contract checks.

### Task 4: Verify and integrate

- [ ] Confirm the PR CI passes after the implementation.
- [ ] Review the PR diff for accidental secrets and Codespaces remnants.
- [ ] Update PR title/body to Actions Desktop.
- [ ] Merge only after green CI.
- [ ] After merge, user adds `DESKTOP_PASSWORD` under repository Actions secrets and starts `Actions Desktop` from the Actions tab.
