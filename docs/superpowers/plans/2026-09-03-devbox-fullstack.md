# Devbox Fullstack Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build an always-on Docker devbox with PHP, Composer, Python, pip, NVM/Node, .NET SDKs 7/8/9/10 and password-based SSH for the non-root `dev` user.

**Architecture:** Ubuntu 24.04 provides the base OS and common packages. .NET SDKs are installed side by side with Microsoft's `dotnet-install.sh`; NVM installs the current Node.js LTS for `dev`. Docker Compose injects the SSH password from an ignored `.env`, exposes SSH, mounts a configurable workspace, persists SSH host keys and uses `restart: unless-stopped` for 24/7 recovery.

**Tech Stack:** Docker, Docker Compose, Ubuntu 24.04, OpenSSH, PHP, Composer, Python 3, pip, NVM, Node.js LTS, .NET SDK 7/8/9/10, Bash, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-09-03-devbox-fullstack-design.md`

## Global Constraints

- Never commit the SSH password or password hash.
- SSH root login must be disabled and only `dev` may log in.
- Password authentication is required.
- Default host SSH port is 2222, configurable with `SSH_PORT`.
- Compose must use `restart: unless-stopped`.
- Docker must be enabled on Linux systemd hosts by the install script.
- .NET SDK major versions 7, 8, 9 and 10 must all be present.
- Node.js must be installed through NVM for the `dev` user.

---

### Task 1: Configuration contract and static test

**Files:**
- Create: `tests/test-config.sh`
- Create: `.gitignore`
- Create: `.dockerignore`
- Create: `.env.example`

**Interfaces:**
- Consumes: repository configuration files created by later tasks.
- Produces: `tests/test-config.sh`, a static contract checker used locally and in CI.

- [ ] **Step 1: Create the failing static configuration test**

The test must assert the presence of `restart: unless-stopped`, `${DEVBOX_SSH_PASSWORD:?`, `${SSH_PORT:-2222}:22`, `.env` ignore rules, OpenSSH installation/configuration, all four .NET channels, NVM installation and Docker boot enablement.

- [ ] **Step 2: Run the static test and confirm it fails because implementation files are absent**

Run: `bash tests/test-config.sh`
Expected: non-zero exit status identifying missing `Dockerfile`, `docker-compose.yml`, `entrypoint.sh` or `scripts/install-host.sh`.

- [ ] **Step 3: Add secret-safe ignore/example files**

`.env.example` contains only variable names and safe sample values; `.gitignore` excludes `.env`; `.dockerignore` excludes `.git`, `.env` and workspace contents.

### Task 2: Build the runtime image and Compose service

**Files:**
- Create: `Dockerfile`
- Create: `docker-compose.yml`
- Create: `entrypoint.sh`
- Create: `scripts/verify-toolchain.sh`
- Create: `scripts/install-host.sh`

**Interfaces:**
- Consumes: `DEVBOX_SSH_PASSWORD`, optional `SSH_PORT`, optional `WORKSPACE_PATH`.
- Produces: Compose service `devbox`, SSH endpoint on host port 2222 by default, and verification command `/usr/local/bin/verify-toolchain`.

- [ ] **Step 1: Implement the Ubuntu 24.04 image**

Install OpenSSH, PHP/Composer, Python/pip/venv, Git/build tools, NVM + current Node.js LTS for user `dev`, then install .NET channels 7.0, 8.0, 9.0 and 10.0 into `/usr/share/dotnet`.

- [ ] **Step 2: Implement secure runtime SSH startup**

`entrypoint.sh` exits if `DEVBOX_SSH_PASSWORD` is absent, applies the password with `chpasswd`, creates persistent ED25519/RSA host keys if missing, and executes `sshd -D -e`. SSH config requires password auth, forbids root and allows only `dev`.

- [ ] **Step 3: Implement always-on Compose behavior**

Use `restart: unless-stopped`, map `${SSH_PORT:-2222}:22`, mount `${WORKSPACE_PATH:-./workspace}:/workspace`, mount a named volume at `/var/lib/devbox-ssh`, and require `DEVBOX_SSH_PASSWORD`.

- [ ] **Step 4: Implement host boot installation**

`scripts/install-host.sh` verifies `.env`, enables/starts Docker through systemd when available, then executes `docker compose up -d --build`.

- [ ] **Step 5: Make the static test pass**

Run: `bash tests/test-config.sh`
Expected: `PASS: devbox configuration contract satisfied`.

### Task 3: Build verification, documentation and CI

**Files:**
- Create: `.github/workflows/ci.yml`
- Create: `README.md`

**Interfaces:**
- Consumes: the image and scripts from Task 2.
- Produces: repeatable GitHub Actions proof that the image builds and all requested toolchains are installed.

- [ ] **Step 1: Add image-level toolchain verification**

`scripts/verify-toolchain.sh` must print installed versions and fail unless `dotnet --list-sdks` contains majors 7, 8, 9 and 10 and PHP, Composer, Python, pip, NVM, Node and npm all execute successfully.

- [ ] **Step 2: Add GitHub Actions CI**

CI runs `bash tests/test-config.sh`, validates Compose with a dummy non-secret password, builds the image, then runs the image with `--entrypoint /usr/local/bin/verify-toolchain`.

- [ ] **Step 3: Document first-run and SSH commands**

README documents copying `.env.example` to `.env`, setting a unique `DEVBOX_SSH_PASSWORD`, running `./scripts/install-host.sh`, connecting with `ssh dev@HOST -p 2222`, changing `SSH_PORT`/`WORKSPACE_PATH`, selecting .NET with `global.json`, and stopping/restarting with Docker Compose.

- [ ] **Step 4: Verify CI before integration**

Expected: GitHub Actions workflow succeeds on `feature/devbox-runtime` before merge to `main`.
