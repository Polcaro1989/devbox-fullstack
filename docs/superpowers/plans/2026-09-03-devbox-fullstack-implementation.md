# Devbox Fullstack Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Docker development container with PHP, Python, NVM/Node, .NET SDKs 7/8/9/10, password-based SSH, and an automatic 00:00–13:00 daily runtime window on a Linux host.

**Architecture:** One Ubuntu 24.04 image runs `sshd` as PID 1 through an entrypoint. Toolchains live in the image; the repository is mounted at `/workspace`. A host-side systemd timer calls a window script at boot, 00:00 and 13:00 so the container state always matches the intended daily window.

**Tech Stack:** Docker, Docker Compose, Ubuntu 24.04, Bash, OpenSSH, PHP/Composer, Python/pip, NVM/Node.js LTS, .NET install script, systemd.

**Spec:** `docs/superpowers/specs/2026-09-03-devbox-fullstack-design.md`

## Global Constraints

- SSH password must never be committed to Git.
- SSH root login must be disabled.
- SSH password authentication must be enabled for user `dev`.
- Host SSH port is `2222`; container SSH port is `22`.
- Required .NET SDK major versions: 7, 8, 9 and 10.
- Daily runtime window uses the host local timezone: start at 00:00, stop at 13:00.
- A reboot inside the window must restore the container; a reboot outside the window must keep it stopped.
- No Docker-in-Docker.

---

### Task 1: Configuration contract tests

**Files:**
- Create: `tests/test-config.sh`

**Interfaces:**
- Consumes: repository files that later tasks will create.
- Produces: a single Bash test command, `bash tests/test-config.sh`, that fails until all required config is present.

- [ ] **Step 1: Write the failing test**

Create `tests/test-config.sh` to assert that `Dockerfile`, `docker-compose.yml`, `entrypoint.sh`, `scripts/verify-toolchain.sh`, `scripts/devbox-window.sh`, `scripts/install-systemd.sh`, `systemd/devbox-window.service.template`, `systemd/devbox-window.timer`, `.env.example`, `.gitignore`, `.dockerignore`, and `README.md` exist. Assert required strings: `PasswordAuthentication yes`, `PermitRootLogin no`, `2222:22`, `DEVBOX_PASSWORD`, `.env`, .NET channels `7.0`, `8.0`, `9.0`, `10.0`, and timer transitions `00:00:00` and `13:00:00`.

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test-config.sh`

Expected: non-zero exit because production/config files are missing.

- [ ] **Step 3: Commit the failing test**

Commit message: `test: define devbox configuration contract`

### Task 2: Docker image and SSH runtime

**Files:**
- Create: `Dockerfile`
- Create: `entrypoint.sh`
- Create: `docker-compose.yml`
- Create: `.env.example`
- Create: `.gitignore`
- Create: `.dockerignore`

**Interfaces:**
- Consumes: `DEVBOX_PASSWORD` from host `.env`.
- Produces: Compose service `devbox`, host SSH endpoint `localhost:2222`, Linux user `dev`, `/workspace` working directory.

- [ ] **Step 1: Implement minimal image/runtime configuration**

Use Ubuntu 24.04. Install `openssh-server`, PHP CLI and common extensions, Composer, Python 3, pip/venv, curl, git, unzip, zip, build-essential and certificates. Create non-root user `dev`. Install .NET SDK channels 7.0, 8.0, 9.0 and 10.0 into `/usr/share/dotnet`. Install NVM under `/home/dev/.nvm` and Node.js LTS. Configure SSH with password auth enabled and root login disabled.

`entrypoint.sh` must exit if `DEVBOX_PASSWORD` is empty, run `echo "dev:${DEVBOX_PASSWORD}" | chpasswd`, generate missing SSH host keys and exec `/usr/sbin/sshd -D -e`.

Compose must build the image, map `2222:22`, mount `.:/workspace`, pass `${DEVBOX_PASSWORD:?DEVBOX_PASSWORD must be set}`, and use `restart: unless-stopped`.

- [ ] **Step 2: Run static test**

Run: `bash tests/test-config.sh`

Expected: may still fail only for scheduling/README files not created yet; Docker/SSH assertions pass.

- [ ] **Step 3: Validate Bash syntax**

Run: `bash -n entrypoint.sh`

Expected: exit 0.

- [ ] **Step 4: Commit**

Commit message: `feat: add fullstack docker image with ssh`

### Task 3: Toolchain verification

**Files:**
- Create: `scripts/verify-toolchain.sh`

**Interfaces:**
- Consumes: installed commands inside the container.
- Produces: non-zero exit if any required runtime is missing.

- [ ] **Step 1: Implement verification script**

Check `php`, `composer`, `python3`, `pip3`, NVM, `node`, `npm`, `dotnet`, and `sshd`. Capture `dotnet --list-sdks` and require lines beginning with 7., 8., 9. and 10. Print detected versions.

- [ ] **Step 2: Validate Bash syntax**

Run: `bash -n scripts/verify-toolchain.sh`

Expected: exit 0.

- [ ] **Step 3: Commit**

Commit message: `test: add runtime toolchain verification`

### Task 4: Daily 00:00–13:00 systemd scheduling

**Files:**
- Create: `scripts/devbox-window.sh`
- Create: `scripts/install-systemd.sh`
- Create: `systemd/devbox-window.service.template`
- Create: `systemd/devbox-window.timer`

**Interfaces:**
- Consumes: repository path and local host clock.
- Produces: systemd timer `devbox-window.timer`; service `devbox-window.service`; desired-state function: hours 00–12 => `docker compose up -d`, hours 13–23 => `docker compose stop`.

- [ ] **Step 1: Implement window script**

Resolve repository root from script path. Read hour using `date +%H`. Convert safely to base-10. If hour is less than 13 run `docker compose up -d`; otherwise run `docker compose stop`.

- [ ] **Step 2: Implement systemd templates and installer**

Timer contains `OnBootSec=1min`, `OnCalendar=*-*-* 00:00:00`, `OnCalendar=*-*-* 13:00:00`, `Persistent=true`. Installer substitutes the actual repo path into the service template, copies units to `/etc/systemd/system`, runs `systemctl daemon-reload`, enables/starts the timer, and immediately runs the service once to reconcile the current window.

- [ ] **Step 3: Validate Bash syntax and config test**

Run: `bash -n scripts/devbox-window.sh scripts/install-systemd.sh && bash tests/test-config.sh`

Expected: static test may fail only for README if not created yet.

- [ ] **Step 4: Commit**

Commit message: `feat: add automatic daily runtime window`

### Task 5: Documentation and final static verification

**Files:**
- Create: `README.md`

**Interfaces:**
- Consumes: all commands/files from previous tasks.
- Produces: exact setup instructions for host deployment.

- [ ] **Step 1: Document setup**

Document: clone repo; copy `.env.example` to `.env`; set `DEVBOX_PASSWORD`; `docker compose build`; `docker compose up -d`; verify with `docker compose exec devbox bash -lc './scripts/verify-toolchain.sh'`; SSH with `ssh dev@HOST -p 2222`; install scheduling with `sudo ./scripts/install-systemd.sh`; inspect with `systemctl list-timers devbox-window.timer` and `systemctl status devbox-window.timer`.

- [ ] **Step 2: Run complete static verification**

Run: `bash tests/test-config.sh && bash -n entrypoint.sh scripts/verify-toolchain.sh scripts/devbox-window.sh scripts/install-systemd.sh`

Expected: all commands exit 0.

- [ ] **Step 3: Note Docker verification limitation**

If Docker is unavailable in the execution environment, record that image build/runtime verification must occur on a Docker-capable host before merge; do not claim a successful Docker build without evidence.

- [ ] **Step 4: Commit**

Commit message: `docs: add devbox setup and operations guide`
