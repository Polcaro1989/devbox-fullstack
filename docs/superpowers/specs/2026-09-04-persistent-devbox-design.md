# Persistent Devbox Design

## Goal

Make each manually started `Actions Server` session feel like the same development machine even though GitHub-hosted `ubuntu-latest` runners are ephemeral.

The persistent state must restore the user's working environment, including uncommitted Git changes, staged files, local Git metadata, user configuration, permissions, symlinks, scripts, and selected tool/application state.

## Chosen Architecture

Use Restic with Cloudflare R2-compatible object storage for encrypted, incremental snapshots.

The GitHub Actions runner remains disposable. On startup, the workflow reconstructs the base toolchain, restores the latest persistent snapshot, reapplies selected system-level state, starts Tailscale, and exposes SSH.

The repository remains public. All storage credentials and backup encryption secrets stay in GitHub Actions repository secrets and are never committed.

## Persistent Scope

### Primary snapshot

Persist the complete `/home/runner` tree so that the following return on the next session:

- project directories;
- `.git` directories and local repository metadata;
- tracked files with uncommitted modifications;
- staged Git index state;
- untracked files;
- local branches and commits that have not been pushed;
- `.config` and other user-level application configuration;
- `.gitconfig`;
- scripts and user files;
- Unix ownership/mode information that Restic can preserve;
- symlinks and timestamps.

### System reconstruction

Do not blindly restore the complete `/etc` tree or the whole root filesystem because a new GitHub runner may use a different base image.

Instead, capture/reapply selected reproducible system state, such as:

- apt package manifest where useful;
- globally installed CLI/tool manifests where useful;
- selected safe configuration files;
- Docker-related persistent data only when explicitly included and safe to restore.

The existing toolchain bootstrap remains the source of truth for .NET, Node/NVM, Python, PHP, Docker, and other base development tooling.

## Startup Flow

1. GitHub creates a fresh `ubuntu-latest` runner.
2. Validate all required secrets.
3. Reclaim disk space and install/verify the base development toolchain.
4. Install Restic if required.
5. Configure R2 endpoint credentials in environment variables.
6. If the backup repository does not exist, initialize it.
7. If a valid snapshot exists, restore the latest snapshot into `/home/runner`.
8. Reapply any selected system-level state that is safe and reproducible.
9. Ensure restored files have the expected `runner` ownership where needed.
10. Connect the runner to Tailscale.
11. Start the private SSH server.
12. Keep the manually started development session alive for the normal workflow duration.

## Save Flow

Saving must be safe against interruption and must always leave at least one valid snapshot.

1. Create a new Restic snapshot of the configured persistent scope.
2. Verify that the new snapshot exists and the backup repository is readable.
3. Only after successful verification, remove all older snapshots.
4. Prune unused Restic data so storage does not accumulate indefinitely.
5. Leave exactly the newest verified snapshot as the retained persistent state.

This ordering is mandatory. Never delete the previous known-good snapshot before the new snapshot has been created and verified.

## Retention Policy

The storage behaves like a replaceable persistent disk rather than a historical backup archive.

Retention rule:

- keep exactly 1 verified snapshot;
- newest valid snapshot wins;
- after a successful new backup, run Restic retention equivalent to `forget --keep-last 1 --prune`;
- if the new snapshot fails, keep the previous snapshot untouched;
- if verification fails, do not prune older data.

This satisfies the requirement to clear previous stored state and retain only the newest successful state while protecting against an interrupted save.

## Save Timing

Because a GitHub-hosted job can be forcefully terminated and a final cleanup step is not guaranteed to run after every possible failure, persistence must not depend solely on end-of-job cleanup.

The design will support:

- an initial restore on startup;
- periodic snapshot refreshes during the active SSH session at a conservative interval;
- a final snapshot attempt when the workflow exits normally or is deliberately stopped in a way that still permits cleanup;
- a manual save command available inside the server for important checkpoints.

Only one backup operation may run at a time to avoid repository lock conflicts.

## Security

Required secrets will be stored in GitHub Actions repository secrets, for example:

- `R2_ACCESS_KEY_ID`;
- `R2_SECRET_ACCESS_KEY`;
- `R2_ACCOUNT_ID` or an explicit R2 endpoint value;
- `RESTIC_PASSWORD`;
- existing `TAILSCALE_AUTHKEY`;
- existing `DESKTOP_PASSWORD` until SSH-key authentication replaces it.

The Restic repository is encrypted client-side with `RESTIC_PASSWORD`.

Secrets must never be printed, committed, written into workflow summaries, or persisted inside the backed-up workspace in plaintext.

## Exclusions

Exclude files that are useless, volatile, or risky to snapshot, such as:

- large temporary/cache directories that are cheaper to rebuild;
- sockets, runtime files, and transient process state;
- obvious package/build outputs when appropriate;
- storage credentials and generated secret files;
- Restic's own local temporary/cache data if it causes pointless churn.

The exact exclusion list will be defined in a dedicated file/script so it is testable and reviewable.

## Failure Handling

### No previous snapshot

Treat the session as first boot and continue with an empty persistent home after initializing the repository.

### Restore fails

Fail the persistence stage visibly rather than silently overwriting the remote backup with a potentially empty home directory.

### New backup fails

Keep the previous remote snapshot and skip retention/pruning.

### Verification fails

Do not delete any older snapshot.

### Retention/prune fails after a successful backup

Keep the new snapshot and report the cleanup failure. Extra historical storage is preferable to losing the current state.

### Concurrent backup attempt

Use locking so a second backup waits or exits cleanly instead of corrupting the repository.

## Repository Changes Expected During Implementation

Likely changes:

- `.github/workflows/actions-desktop.yml` — add persistence secrets, restore step, periodic/final save orchestration;
- `scripts/setup-persistence.sh` — install/configure Restic and initialize/check storage;
- `scripts/restore-persistence.sh` — restore the latest snapshot safely;
- `scripts/save-persistence.sh` — create, verify, retain only latest, and prune;
- `scripts/persistence-excludes.txt` — explicit exclusions;
- tests under `tests/` — validate workflow wiring, secret handling, retention ordering, and failure behavior.

Existing Tailscale and SSH behavior should remain unchanged except for restoring user state before SSH becomes available.

## Testing Strategy

Tests should verify at minimum:

1. workflow references required persistence secrets without leaking values;
2. restore occurs before SSH startup;
3. save happens before retention cleanup;
4. old snapshots are deleted only after a successful new snapshot and verification;
5. failed backup never triggers `forget --keep-last 1 --prune`;
6. exclusions cover volatile/secret-prone paths;
7. scripts use strict shell error handling;
8. existing toolchain and SSH/Tailscale tests continue to pass.

A smoke test with a temporary Restic repository should verify preservation of:

- file contents;
- executable permission bits;
- symlinks;
- a Git repository containing staged, unstaged, and untracked changes.

## Success Criteria

After one session saves state and a later manually started Actions Server restores it, the user should be able to SSH in and see the prior working state, including Git changes that were never committed or pushed.

After each successful save, remote storage should contain only the newest verified Restic snapshot plus the repository data required by that snapshot.

If a save fails, the previously valid snapshot must remain recoverable.
