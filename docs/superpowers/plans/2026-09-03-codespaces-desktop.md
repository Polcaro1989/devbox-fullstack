# Codespaces Desktop Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a GitHub Codespaces mode with a lightweight browser-accessible Linux desktop while preserving the existing Docker/SSH devbox behavior.

**Architecture:** Refactor the root Dockerfile into a reusable `toolchain` stage and a final `ssh-runtime` stage. Docker Compose explicitly builds `ssh-runtime`, while `.devcontainer/devcontainer.json` builds `toolchain` and adds the official `desktop-lite` feature with private noVNC port 6080.

**Tech Stack:** Docker, Docker Compose, Ubuntu 24.04, GitHub Codespaces, Dev Containers, Fluxbox, TigerVNC, noVNC, PHP, Python, NVM/Node.js LTS, .NET SDK 8/9/10, Bash, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-09-03-codespaces-desktop-design.md`

## Global Constraints

- Existing local/server Docker + password SSH behavior must remain intact.
- Docker Compose must build the `ssh-runtime` target and retain `restart: unless-stopped`.
- Codespaces must build only the `toolchain` target and must not require `DEVBOX_SSH_PASSWORD`.
- Codespaces must use `ghcr.io/devcontainers/features/desktop-lite:1`.
- noVNC must use port 6080, labeled `Desktop (noVNC)`, with private port visibility.
- Codespaces remote user must be `dev`.
- GUI shared memory must be at least 1 GB.
- Toolchain remains PHP/Composer, Python/pip, NVM/Node.js LTS, and .NET SDK 8/9/10 only.
- No real passwords or desktop secrets may be committed.

---

### Task 1: Extend the configuration contract first

**Files:**
- Modify: `tests/test-config.sh`
- Test: `tests/test-config.sh`

**Interfaces:**
- Consumes: planned Docker stages and Dev Container configuration.
- Produces: static assertions that reject regressions in Docker/SSH and missing Codespaces desktop configuration.

- [ ] **Step 1: Add failing assertions for the new architecture**

Add these requirements to `tests/test-config.sh` before implementation exists:

```bash
require_file '.devcontainer/devcontainer.json'
require_literal Dockerfile 'AS toolchain'
require_literal Dockerfile 'AS ssh-runtime'
require_literal docker-compose.yml 'target: ssh-runtime'
require_literal .devcontainer/devcontainer.json '"target": "toolchain"'
require_literal .devcontainer/devcontainer.json 'ghcr.io/devcontainers/features/desktop-lite:1'
require_literal .devcontainer/devcontainer.json '"forwardPorts": [6080]'
require_literal .devcontainer/devcontainer.json '"label": "Desktop (noVNC)"'
require_literal .devcontainer/devcontainer.json '"visibility": "private"'
require_literal .devcontainer/devcontainer.json '"remoteUser": "dev"'
require_literal .devcontainer/devcontainer.json '"--shm-size=1g"'
```

Also fail if `.devcontainer/devcontainer.json` contains `DEVBOX_SSH_PASSWORD`.

- [ ] **Step 2: Verify RED**

Run in CI/local checkout:

```bash
bash tests/test-config.sh
```

Expected: non-zero exit because `.devcontainer/devcontainer.json` and the multi-stage target markers do not yet exist.

### Task 2: Split the Docker image without changing the normal runtime

**Files:**
- Modify: `Dockerfile`
- Modify: `docker-compose.yml`
- Test: `tests/test-config.sh`

**Interfaces:**
- Produces Docker target `toolchain` with all development runtimes and default user `dev`.
- Produces Docker target `ssh-runtime` with OpenSSH and the existing `/usr/local/bin/devbox-entrypoint`.
- Compose service `devbox` explicitly consumes target `ssh-runtime`.

- [ ] **Step 1: Create the reusable toolchain stage**

The beginning of the Dockerfile becomes:

```dockerfile
FROM ubuntu:24.04 AS toolchain
```

Keep PHP/Composer, Python/pip, NVM/Node.js LTS and .NET 8/9/10 in this stage. Keep `/usr/local/bin/verify-toolchain` in this stage so both execution modes can validate it. End the stage with:

```dockerfile
USER dev
WORKDIR /workspace
```

- [ ] **Step 2: Move SSH-only setup into the final runtime stage**

Append:

```dockerfile
FROM toolchain AS ssh-runtime
USER root
RUN apt-get update && apt-get install -y --no-install-recommends openssh-server \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /run/sshd /var/lib/devbox-ssh \
    && printf '%s\n' 'PasswordAuthentication yes' 'PermitRootLogin no' 'PubkeyAuthentication yes' 'AllowUsers dev' 'UsePAM yes' > /etc/ssh/sshd_config.d/99-devbox.conf
COPY entrypoint.sh /usr/local/bin/devbox-entrypoint
RUN chmod +x /usr/local/bin/devbox-entrypoint
EXPOSE 22
ENTRYPOINT ["/usr/local/bin/devbox-entrypoint"]
```

- [ ] **Step 3: Pin Compose to the SSH runtime**

Under `services.devbox.build`, add:

```yaml
target: ssh-runtime
```

- [ ] **Step 4: Verify the static contract moves toward GREEN**

Run:

```bash
bash tests/test-config.sh
```

Expected: it should now fail only on the missing Dev Container requirements.

### Task 3: Add the Codespaces graphical desktop

**Files:**
- Create: `.devcontainer/devcontainer.json`
- Test: `tests/test-config.sh`

**Interfaces:**
- Consumes Docker target `toolchain`.
- Produces a Codespace using user `dev`, private noVNC port 6080, and the official `desktop-lite` feature.

- [ ] **Step 1: Create the Dev Container configuration**

Create exactly this shape:

```json
{
  "name": "Devbox Fullstack Desktop",
  "build": {
    "dockerfile": "../Dockerfile",
    "context": "..",
    "target": "toolchain"
  },
  "remoteUser": "dev",
  "features": {
    "ghcr.io/devcontainers/features/desktop-lite:1": {
      "password": "noPassword",
      "webPort": "6080"
    }
  },
  "forwardPorts": [6080],
  "portsAttributes": {
    "6080": {
      "label": "Desktop (noVNC)",
      "onAutoForward": "notify",
      "visibility": "private"
    }
  },
  "runArgs": ["--shm-size=1g"],
  "postCreateCommand": "/usr/local/bin/verify-toolchain"
}
```

`noPassword` is safe here only because the Codespaces forwarded port remains private and GitHub access control gates the port; no fixed VNC secret is stored in the repository.

- [ ] **Step 2: Verify GREEN for the static contract**

Run:

```bash
bash tests/test-config.sh
```

Expected: `PASS: devbox configuration contract satisfied`.

### Task 4: CI and documentation

**Files:**
- Modify: `.github/workflows/ci.yml`
- Modify: `README.md`
- Test: GitHub Actions workflow `devbox-ci`

**Interfaces:**
- CI verifies the normal SSH image remains buildable and that the reusable toolchain target builds independently.
- README provides one-click Codespaces usage and noVNC instructions without changing existing Docker instructions.

- [ ] **Step 1: Extend CI**

Keep the existing Compose and normal-image build checks, then add:

```yaml
- name: Build Codespaces toolchain target
  run: docker build --target toolchain -t devbox-fullstack:toolchain-test .

- name: Verify Codespaces toolchain
  run: docker run --rm --entrypoint /usr/local/bin/verify-toolchain devbox-fullstack:toolchain-test
```

Ensure the workflow runs for pull requests into `main`.

- [ ] **Step 2: Document Codespaces desktop usage**

README must explain:

```text
GitHub -> Code -> Codespaces -> Create codespace on main
```

Then open the `Ports` panel and choose `Desktop (noVNC)` on port 6080. State that the forwarded desktop port is private by default and that Codespaces usage is subject to GitHub quota/idle lifecycle.

- [ ] **Step 3: Verify the full PR build**

Expected GitHub Actions steps:

```text
Static configuration contract: success
Validate Compose: success
Build image: success
Verify toolchain: success
Build Codespaces toolchain target: success
Verify Codespaces toolchain: success
```

Only merge after the PR CI is green.
