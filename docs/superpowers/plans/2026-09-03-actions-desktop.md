# Actions Desktop Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add one manually started GitHub Actions Linux desktop session with browser GUI and terminal while preserving the requested development toolchain.

**Architecture:** Install the language toolchain and lightweight desktop directly on `ubuntu-latest` to conserve disk. Expose localhost-only noVNC and ttyd through an nginx Basic Auth proxy, then publish that proxy through a temporary Cloudflare Quick Tunnel. Authentication comes only from the repository secret `DESKTOP_PASSWORD`.

**Tech Stack:** GitHub Actions, Ubuntu, Bash, PHP/Composer, Python/pip, NVM/Node.js, .NET 8/9/10, Xvfb, Fluxbox, x11vnc, noVNC/websockify, ttyd, nginx, cloudflared.

**Spec:** `docs/superpowers/specs/2026-09-03-actions-desktop-design.md`

## Global Constraints

- Only one cloud-interactive mode: Actions Desktop.
- No `.devcontainer` in the final branch.
- Workflow trigger is manual `workflow_dispatch` only.
- Runner is `ubuntu-latest`; timeout is 355 minutes or less.
- No schedule, self-dispatch, chaining, or automatic relaunch.
- `DESKTOP_PASSWORD` comes from GitHub Secrets and is never printed.
- Local GUI/terminal services bind to loopback.
- Toolchain is PHP/Composer, Python/pip, NVM/Node LTS/npm, .NET 8/9/10; no .NET 7.
- Keep the GUI lightweight for the standard 14 GB runner disk.

---

### Task 1: Define the final configuration contract

**Files:**
- Modify: `tests/test-config.sh`

- [ ] Replace the old Docker-only contract with assertions for the Actions Desktop workflow and scripts while retaining critical Docker security/toolchain assertions.
- [ ] Assert `.devcontainer/devcontainer.json` is absent.
- [ ] Assert workflow is manual, uses `ubuntu-latest`, timeout <= 355, and references `secrets.DESKTOP_PASSWORD`.
- [ ] Assert no schedule/self-dispatch pattern exists.
- [ ] Commit the failing contract before implementation.

### Task 2: Install and verify the runner toolchain

**Files:**
- Create: `scripts/setup-actions-toolchain.sh`
- Modify: `scripts/verify-toolchain.sh`

- [ ] Install only missing PHP/Composer/Python prerequisites.
- [ ] Install NVM + current Node LTS for the runner user.
- [ ] Install .NET SDK channels 8.0, 9.0 and 10.0 side-by-side under the runner home.
- [ ] Export paths using `GITHUB_PATH` when running in Actions.
- [ ] Generalize the verification script so NVM uses the current user's home instead of hard-coded `/home/dev`.
- [ ] Validate Bash syntax and toolchain contract.

### Task 3: Build the authenticated graphical session

**Files:**
- Create: `scripts/start-actions-desktop.sh`

- [ ] Fail early when `DESKTOP_PASSWORD` is missing.
- [ ] Install Xvfb, Fluxbox, x11vnc, noVNC/websockify, nginx and minimal GUI apps.
- [ ] Install pinned ttyd and cloudflared binaries.
- [ ] Start Xvfb + Fluxbox, x11vnc on loopback, websockify/noVNC on loopback, ttyd on loopback.
- [ ] Create nginx Basic Auth with username `devbox` and the secret password; proxy `/` to noVNC and `/terminal/` to ttyd with websocket headers.
- [ ] Start one Cloudflare Quick Tunnel to the local nginx endpoint and print only the temporary URL and username, never the password.
- [ ] Add process/liveness checks before declaring the session ready.

### Task 4: Add the manual workflow

**Files:**
- Create: `.github/workflows/actions-desktop.yml`
- Modify: `.github/workflows/ci.yml`

- [ ] Define `workflow_dispatch`, read-only contents permission, `ubuntu-latest`, and `timeout-minutes: 355`.
- [ ] Checkout, validate the secret, setup toolchain, verify toolchain, start desktop, and keep the job alive for less than six hours.
- [ ] Upgrade CI checkout action and keep normal Docker build/toolchain verification.
- [ ] Run the static contract via PR CI.

### Task 5: Integrate only after green CI

**Files:** no additional production files.

- [ ] Open a PR from `feature/actions-desktop` to `main`.
- [ ] Verify PR CI is green.
- [ ] Review changed files for accidental credentials.
- [ ] Merge the PR.
- [ ] Verify `main` CI is green and the `Actions Desktop` workflow appears in the Actions tab.
- [ ] Tell the user how to create `DESKTOP_PASSWORD` and manually start/access the session.
