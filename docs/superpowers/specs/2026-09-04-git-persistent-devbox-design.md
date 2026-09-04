# Git-backed Persistent Devbox Design

## Goal

Make each manually started `Actions Server` session restore the previous useful user state even though GitHub-hosted runners are disposable.

The persistent state must preserve project trees, nested `.git` directories, staged/unstaged/untracked changes, user configuration, permissions, timestamps, and symlinks. The base operating system and development toolchain remain reproducible and are rebuilt by the existing workflow.

## Storage

Use the private repository `Polcaro1989/Repository-` as the state store. The runtime state is kept on a dedicated `devbox-state` branch.

The public `devbox-fullstack` repository never stores state data or credentials. Access to the private state repository uses a fine-grained GitHub token stored only as the `DEVBOX_STATE_TOKEN` Actions secret. Snapshot encryption uses `DEVBOX_STATE_PASSWORD`, also stored only as an Actions secret.

## Snapshot format

A save creates a GNU tar archive from `/home/runner`, preserving Unix modes, timestamps, symlinks, nested `.git` directories, and user files. Rebuildable or unsafe runner internals are excluded, especially `/home/runner/work`, package caches, installed SDK copies, and build caches.

The archive is compressed with zstd, encrypted symmetrically with GnuPG AES-256, checksummed, and split into chunks below GitHub's 100 MB per-object limit. Production chunks default to 90 MiB.

The encrypted archive is validated before publication by checking its SHA-256 checksum, decrypting it to a temporary file, and listing the tar contents successfully.

## Single-state retention

The state branch behaves like a replaceable disk, not backup history.

Every successful save creates a new orphan commit containing only the latest encrypted chunks and metadata, then force-pushes that orphan commit to `refs/heads/devbox-state`. Because the new commit has no parent, the reachable branch history contains exactly one state commit.

Old Git objects can remain physically on GitHub until GitHub garbage collection removes unreachable objects; the workflow cannot force GitHub's server-side garbage collection. Logically and through normal Git history, only the latest state remains reachable.

A failed archive, encryption, verification, or push never replaces the previous branch state.

## Authentication

Production Git operations use a temporary `GIT_ASKPASS` helper in `/tmp`; the token is never embedded in a repository remote URL or committed file. The helper reads `DEVBOX_STATE_TOKEN` from the environment. The temporary helper and state working directories are deleted on exit.

Required production environment:

- `DEVBOX_STATE_REPO=Polcaro1989/Repository-`
- `DEVBOX_STATE_TOKEN` from GitHub Actions secret
- `DEVBOX_STATE_PASSWORD` from GitHub Actions secret
- `DEVBOX_STATE_BRANCH=devbox-state`

Tests may override `DEVBOX_STATE_REMOTE_URL` with a local bare Git repository and do not require a token.

## Restore flow

1. Rebuild and verify the base development toolchain.
2. Install/verify `zstd`, `gnupg`, and Git support required for state handling.
3. Probe the private state repository for `devbox-state`.
4. If the branch does not exist, continue as a first boot.
5. Fetch only the latest state commit.
6. Reassemble encrypted chunks.
7. Verify SHA-256.
8. Decrypt with `DEVBOX_STATE_PASSWORD`.
9. Validate tar paths and archive readability.
10. Extract into `/home/runner`, preserving file metadata.
11. Connect Tailscale and start SSH.

Restore failures on an existing state are fatal; the workflow must not silently continue with an empty home and later overwrite the good remote state.

## Save flow

1. Acquire a local `flock` so checkpoint/final saves cannot overlap.
2. Archive the configured persistent root with exclusions.
3. Compress and encrypt the archive.
4. Verify checksum and decrypt/list round trip.
5. Enforce a maximum encrypted snapshot size before Git publication.
6. Split into chunks below 100 MB.
7. Create a fresh local Git repository with an orphan `devbox-state` commit containing only the new chunks, checksum, and non-sensitive metadata.
8. Force-push the orphan commit to the private state repository.
9. Report success only after the push succeeds.

The previous remote state remains reachable until step 8 succeeds.

## Checkpoint timing

The workflow does not wait for the GitHub-hosted runner timeout. The SSH session's long-running step performs checkpoints every 15 minutes and runs for approximately 5 hours 20 minutes, leaving margin for setup and a final save within the existing 355-minute job timeout.

A final save is attempted when the session loop exits normally and again from a final `if: always()` workflow step. A TERM/INT trap also attempts a last save when the process receives a catchable shutdown signal. None of these are treated as a guarantee after a hard runner termination; periodic checkpoints cap ordinary data loss to roughly one checkpoint interval.

The workflow remains manual-only. It does not schedule, self-dispatch, chain, or automatically replace expired runners.

## Persistent scope and exclusions

Persist `/home/runner` by default, including user projects, `.git`, `.ssh`, `.config`, `.gitconfig`, shell dotfiles, scripts, and ordinary user files.

Exclude rebuildable/runtime-heavy data:

- `work/` (GitHub Actions checkout and transient credentials/runtime internals)
- `.cache/`
- `.npm/`
- `.nuget/packages/`
- `.nvm/`
- `.dotnet-actions/`
- `.local/share/Trash/`
- project `node_modules/`
- common generated `.NET` `bin/` and `obj/`
- Python virtual environments
- common generated frontend/build output

The exclusions intentionally do not exclude `.git` directories.

## Size guard

Regular GitHub Git storage is not an object-storage replacement. The encrypted snapshot therefore has a default hard limit of 1.5 GB before splitting/pushing. If that limit is exceeded, the save fails and the previous remote state remains untouched. The workflow should print the persistent-root disk usage so the user can remove rebuildable files rather than corrupt or partially replace state.

## Testing

A local behavior test uses a temporary bare Git repository and a fake home tree. It verifies:

- staged, unstaged, and untracked Git changes survive;
- symlinks and executable permissions survive;
- files deleted before the newest save do not return;
- a second save leaves the state branch with exactly one reachable orphan commit;
- restore succeeds without network access;
- wrong encryption password fails restore;
- the state repository never contains plaintext snapshot contents.

Static tests verify workflow ordering, required secrets, exclusions, manual-only triggering, and the absence of R2/B2 dependencies.
