#!/usr/bin/env bash
# Keeps the Codex (ChatGPT) 5-hour window rolling, the same way ping.sh does for Claude.
#   decide -> is a ping due in this run?   ping -> send it and store the next ping time.
# State: codex-state/next-ping (epoch seconds).
set -euo pipefail

: "${MARGIN_SECONDS:=60}"   # ping this long after a reset, never before it
: "${LEAD_SECONDS:=900}"    # start waiting when a ping is less than 15 min away
: "${TIMEZONE:=America/New_York}"
BLIND_SECONDS=18300         # ponytail: 5h05 blind cadence when Codex reports no usable
                            # reset time; parse app-server account/rateLimits/read if
                            # the drift ever matters

now=${NOW:-$(date +%s)}
show() { TZ=$TIMEZONE date -d "@$1" '+%a %b %-d, %-I:%M %p'; }
say() {
  echo "$1"
  if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then echo "$1" >> "$GITHUB_STEP_SUMMARY"; fi
}
out() {
  if [ -n "${GITHUB_OUTPUT:-}" ]; then echo "$1" >> "$GITHUB_OUTPUT"; fi
}
is_num() { case "$1" in ''|*[!0-9]*) return 1 ;; *) return 0 ;; esac; }

case "${1:-}" in
decide)
  if [ -z "${CODEX_AUTH_JSON:-}" ]; then
    out "due=false"
    echo "::notice::CODEX_AUTH_JSON is not set, skipping the Codex ping. Run 'codex login' locally and paste ~/.codex/auth.json into that secret."
    exit 0
  fi
  next=$(cat codex-state/next-ping 2>/dev/null || echo 0)
  is_num "$next" || next=0
  wait=$((next - now))
  if [ "$wait" -gt "$LEAD_SECONDS" ]; then
    out "due=false"
    say "Codex: not due. Next ping $(show "$next")."
    exit 0
  fi
  if [ "$wait" -lt 0 ]; then wait=0; fi
  at=$((now + wait))
  out "due=true"
  out "wait=$wait"
  out "at=$at"   # absolute target: the sleep step recomputes the remainder after npm install
  say "Codex: pinging $(show "$at") (sent by this run)."
  ;;

ping)
  if [ -z "${CODEX_AUTH_JSON:-}" ]; then
    echo "::notice::CODEX_AUTH_JSON is not set, skipping the Codex ping. Run 'codex login' locally and paste ~/.codex/auth.json into that secret."
    exit 0
  fi
  mkdir -p "$HOME/.codex"
  printf '%s' "$CODEX_AUTH_JSON" > "$HOME/.codex/auth.json"
  chmod 600 "$HOME/.codex/auth.json"
  before=$(sha256sum "$HOME/.codex/auth.json" | cut -d' ' -f1)

  # No --ephemeral: the rollout file it would delete is where the reset time lives.
  if ! reply=$(codex exec --skip-git-repo-check -s read-only "Reply with the single word: ok" 2>&1); then
    echo "$reply" | tail -n 15
    echo "::error::Codex ping failed. The stored auth.json may be expired, re-run 'codex login' and update CODEX_AUTH_JSON."
    exit 1
  fi
  echo "Codex replied: $(echo "$reply" | tail -n 1)"

  after=$(sha256sum "$HOME/.codex/auth.json" | cut -d' ' -f1)
  if [ "$before" != "$after" ]; then
    echo "::warning::Codex refreshed auth.json during this run. The copy in CODEX_AUTH_JSON is now older and will stop working eventually, re-paste it when runs start failing."
  fi

  # Rate limits are not in `codex exec` stdout; they ride along in token_count events
  # in the rollout file. The 5-hour window is the one with window_minutes == 300.
  resets=""
  roll=$(find "$HOME/.codex/sessions" -name 'rollout-*.jsonl' -printf '%T@ %p
' 2>/dev/null | sort -nr | head -n 1 | cut -d' ' -f2- || true)
  if [ -n "$roll" ]; then
    for c in python3 python; do
      if command -v "$c" >/dev/null 2>&1 && "$c" -c '' >/dev/null 2>&1; then PY_BIN=$c; break; fi
    done
    if [ -n "${PY_BIN:-}" ]; then
      resets=$("$PY_BIN" "$(dirname "$0")/read_reset.py" "$roll" 2>/dev/null || true)
    fi
  fi

  now2=${NOW:-$(date +%s)}   # re-read after the sleep; NOW only overrides it in tests
  # The reset must still be ahead of us: one that just passed means the new window
  # already started, so a "+ margin" target would fire another prompt inside it.
  if is_num "$resets" && [ "$resets" -gt "$now2" ] && [ "$resets" -lt $((now2 + 5184000)) ]; then
    next=$((resets + MARGIN_SECONDS))
    why="Codex reported this window's reset"
  else
    next=$((now2 + BLIND_SECONDS))
    why="blind 5h05 cadence, Codex reported no usable reset time"
  fi

  mkdir -p codex-state
  echo "$next" > codex-state/next-ping
  out "pinged=true"
  say "### Codex next ping: $(show "$next") ($why)"
  ;;

*)
  echo "usage: $0 decide|ping" >&2
  exit 2
  ;;
esac
