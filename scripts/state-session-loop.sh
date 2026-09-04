#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECKPOINT_SECONDS="${DEVBOX_CHECKPOINT_SECONDS:-900}"
SESSION_SECONDS="${DEVBOX_SESSION_SECONDS:-19200}"
final_attempted=0

[[ "$CHECKPOINT_SECONDS" =~ ^[0-9]+$ ]] && (( CHECKPOINT_SECONDS > 0 )) || {
  echo 'DEVBOX_CHECKPOINT_SECONDS must be a positive integer.' >&2
  exit 1
}
[[ "$SESSION_SECONDS" =~ ^[0-9]+$ ]] && (( SESSION_SECONDS > 0 )) || {
  echo 'DEVBOX_SESSION_SECONDS must be a positive integer.' >&2
  exit 1
}

save_checkpoint() {
  local label="$1"
  echo "Saving persistent state checkpoint: $label"
  if bash "$SCRIPT_DIR/save-git-state.sh"; then
    echo "Persistent state checkpoint completed: $label"
    return 0
  fi
  echo "::warning::Persistent state checkpoint failed: $label. The previous valid remote state was not intentionally replaced."
  return 1
}

final_save() {
  if (( final_attempted == 1 )); then
    return 0
  fi
  final_attempted=1
  save_checkpoint 'final'
}

on_signal() {
  echo 'Session loop received a termination signal; attempting one final state save.'
  final_save || true
  exit 130
}
trap on_signal INT TERM

started_at="$(date +%s)"
deadline=$(( started_at + SESSION_SECONDS ))
next_checkpoint=$(( started_at + CHECKPOINT_SECONDS ))

echo "Actions Server session is active with ${CHECKPOINT_SECONDS}s state checkpoints."
echo "Session loop will stop after approximately ${SESSION_SECONDS}s so the workflow has time to save before timeout."

while true; do
  now="$(date +%s)"
  if (( now >= deadline )); then
    break
  fi

  sleep_for=$(( next_checkpoint - now ))
  remaining=$(( deadline - now ))
  if (( sleep_for <= 0 )); then
    save_checkpoint 'periodic' || true
    next_checkpoint=$(( $(date +%s) + CHECKPOINT_SECONDS ))
    continue
  fi
  if (( sleep_for > remaining )); then
    sleep_for=$remaining
  fi

  sleep "$sleep_for" &
  wait $!

done

final_save
