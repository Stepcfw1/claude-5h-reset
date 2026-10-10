#!/usr/bin/env bash
# Self-check for scripts/codex-ping.sh. Uses a fake `codex` on PATH, never calls the real one.
#   bash scripts/test-codex-ping.sh
set -euo pipefail

SCRIPT=$(cd "$(dirname "$0")" && pwd)/codex-ping.sh
NOW=1800000000
export MARGIN_SECONDS=60 LEAD_SECONDS=900 TIMEZONE=UTC
fails=0

# Builds a sandbox: fake HOME, fake codex that drops $1 as a rollout file, empty workdir.
setup() { # setup <rollout-json-or-empty>
  work=$(mktemp -d)
  home=$(mktemp -d)
  bin=$(mktemp -d)
  mkdir -p "$home/.codex/sessions/2026/10/10"
  if [ -n "$1" ]; then printf '%s\n' "$1" > "$home/.codex/sessions/2026/10/10/rollout-test.jsonl"; fi
  cat > "$bin/codex" <<'FAKE'
#!/usr/bin/env bash
echo "ok"
FAKE
  chmod +x "$bin/codex"
}

run() { # run <subcommand> ; echoes outputs file contents
  ( cd "$work" && HOME="$home" PATH="$bin:$PATH" NOW=$NOW GITHUB_OUTPUT="$work/out" \
      GITHUB_STEP_SUMMARY="$work/sum" bash "$SCRIPT" "$1" >"$work/log" 2>&1 )
}

check() { # check <name> <expected> <actual>
  if [ "$2" = "$3" ]; then echo "ok   - $1"; else echo "FAIL - $1: expected '$2', got '$3'"; fails=$((fails+1)); fi
}

limits() { # limits <window_minutes> <resets_at>
  printf '{"type":"token_count","rate_limits":{"primary":{"used_percent":12,"window_minutes":%s,"resets_at":%s},"secondary":null}}' "$1" "$2"
}

# (a) not due: a ping further away than LEAD_SECONDS sends nothing
setup ""; mkdir -p "$work/codex-state"; echo $((NOW + 7200)) > "$work/codex-state/next-ping"
CODEX_AUTH_JSON='{"tokens":{"x":1}}' run decide
check "a: not due -> due=false" "due=false" "$(cat "$work/out")"
check "a: not due -> state untouched" "$((NOW + 7200))" "$(cat "$work/codex-state/next-ping")"

# (a2) no state at all: due immediately, no wait
setup ""; CODEX_AUTH_JSON='{"tokens":{"x":1}}' run decide
check "a2: no state -> due now" "due=true wait=0 at=$NOW" "$(tr '\n' ' ' < "$work/out" | sed 's/ $//')"

# (a3) ping inside the lead window: wait the remainder
setup ""; mkdir -p "$work/codex-state"; echo $((NOW + 600)) > "$work/codex-state/next-ping"
CODEX_AUTH_JSON='{"tokens":{"x":1}}' run decide
check "a3: within lead -> wait=600 + absolute target" "due=true wait=600 at=$((NOW + 600))" "$(tr '\n' ' ' < "$work/out" | sed 's/ $//')"

# (g) decide with no secret: no ping, no install, no sleep
setup ""
( cd "$work" && HOME="$home" PATH="$bin:$PATH" NOW=$NOW GITHUB_OUTPUT="$work/out"     GITHUB_STEP_SUMMARY="$work/sum" bash "$SCRIPT" decide >"$work/log" 2>&1 )
check "g: decide without secret -> due=false" "due=false" "$(cat "$work/out")"
check "g: decide without secret -> notice" "yes" "$(grep -q '::notice::' "$work/log" && echo yes || echo no)"

# (b) due + a usable 5h reset -> reset + margin
setup "$(limits 300 $((NOW + 17000)))"; CODEX_AUTH_JSON='{"tokens":{"x":1}}' run ping
check "b: 5h window -> resets_at+60" "$((NOW + 17060))" "$(cat "$work/codex-state/next-ping")"
check "b: reports pinged" "pinged=true" "$(cat "$work/out")"

# (c) no rate limits in the rollout -> blind cadence
setup '{"type":"token_count","rate_limits":null}'; CODEX_AUTH_JSON='{"tokens":{"x":1}}' run ping
check "c: no rate limits -> now+18300" "$((NOW + 18300))" "$(cat "$work/codex-state/next-ping")"

# (d) reset already in the past -> blind cadence, never an already-due target
setup "$(limits 300 $((NOW - 600)))"; CODEX_AUTH_JSON='{"tokens":{"x":1}}' run ping
check "d: stale reset -> now+18300" "$((NOW + 18300))" "$(cat "$work/codex-state/next-ping")"

# (e) weekly-only window -> ignored, blind cadence
setup "$(limits 10080 $((NOW + 400000)))"; CODEX_AUTH_JSON='{"tokens":{"x":1}}' run ping
check "e: weekly window ignored -> now+18300" "$((NOW + 18300))" "$(cat "$work/codex-state/next-ping")"

# (h) reset 30 s in the past -> blind cadence, not a target 30 s away
setup "$(limits 300 $((NOW - 30)))"; CODEX_AUTH_JSON='{"tokens":{"x":1}}' run ping
check "h: reset just passed -> now+18300" "$((NOW + 18300))" "$(cat "$work/codex-state/next-ping")"

# (i) a decoy object with the same shape must not override the real token_count event
setup "$(limits 300 $((NOW + 17000)))
{\"type\":\"other\",\"stuff\":{\"window_minutes\":300,\"resets_at\":1804000000}}"
CODEX_AUTH_JSON='{"tokens":{"x":1}}' run ping
check "i: decoy ignored -> real resets_at+60" "$((NOW + 17060))" "$(cat "$work/codex-state/next-ping")"

# (f) no secret -> exits 0, writes no state
setup "$(limits 300 $((NOW + 17000)))"
if ( cd "$work" && HOME="$home" PATH="$bin:$PATH" NOW=$NOW GITHUB_OUTPUT="$work/out" \
     GITHUB_STEP_SUMMARY="$work/sum" bash "$SCRIPT" ping >"$work/log" 2>&1 ); then rc=0; else rc=$?; fi
check "f: no secret -> exit 0" "0" "$rc"
check "f: no secret -> no state" "absent" "$([ -f "$work/codex-state/next-ping" ] && echo present || echo absent)"

[ "$fails" -eq 0 ] && echo "all passed" || { echo "$fails failed"; exit 1; }
