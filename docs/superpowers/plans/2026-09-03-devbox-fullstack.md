# Devbox Fullstack Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build an always-on Docker devbox with PHP, Composer, Python, pip, NVM/Node, .NET SDKs 8/9/10 and password-based SSH for the non-root `dev` user.

**Architecture:** Ubuntu 24.04 provides the base OS and common packages. .NET SDKs are installed side by side with Microsoft's `dotnet-install.sh`; NVM installs the current Node.js LTS for `dev`. Docker Compose injects the SSH password from an ignored `.env`, exposes SSH, mounts a configurable workspace, persists SSH host keys and uses `restart: unless-stopped` for 24/7 recovery.

**Tech Stack:** Docker, Docker Compose, Ubuntu 24.04, OpenSSH, PHP, Composer, Python 3, pip, NVM, Node.js LTS, .NET SDK 8/9/10, Bash, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-09-03-devbox-fullstack-design.md`

## Global Constraints

- Never commit the SSH password or password hash.
- SSH root login must be disabled and only `dev` may log in.
- Password authentication is required.
- Default host SSH port is 2222, configurable with `SSH_PORT`.
- Compose must use `restart: unless-stopped`.
- Docker must be enabled on Linux systemd hosts by the install script.
- .NET SDK major versions 8, 9 and 10 must all be present; .NET 7 must not be installed.
- Node.js must be installed through NVM for the `dev` user.

---

### Task 1: Configuration contract and static test

**Files:** `tests/test-config.sh`, `.gitignore`, `.dockerignore`, `.env.example`

- [x] Add a static contract test that requires always-on restart, SSH password injection, port/workspace mappings, OpenSSH restrictions, .NET 8/9/10, NVM and host Docker boot enablement.
- [x] Add secret-safe environment example and ignore rules.
- [x] Verify the static contract against the implementation files.

### Task 2: Runtime image and Compose service

**Files:** `Dockerfile`, `docker-compose.yml`, `entrypoint.sh`, `scripts/verify-toolchain.sh`, `scripts/install-host.sh`

- [x] Install PHP/Composer, Python/pip/venv, Git/build tools, NVM + Node LTS, OpenSSH and .NET 8/9/10.
- [x] Configure SSH password auth for `dev`, disable root SSH and persist host keys.
- [x] Configure Compose with `restart: unless-stopped`, SSH port mapping and workspace mount.
- [x] Add host installer that enables Docker on systemd and starts the Compose project.

### Task 3: Documentation and CI

**Files:** `.github/workflows/ci.yml`, `README.md`

- [x] Document setup, SSH, workspace and always-on behavior.
- [x] Add CI that runs the static contract test, validates Compose, builds the image and runs the toolchain verifier.
- [ ] Confirm the GitHub Actions image build and runtime verification succeed before merging to `main`.
