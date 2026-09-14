#!/usr/bin/env bash
# Saves (or clears) a planned start time from the "Run workflow" form into plan/.
set -euo pipefail

now=${NOW:-$(date +%s)}
show() { TZ=$TIMEZONE date -d "@$1" '+%a %b %-d, %-I:%M %p %Z'; }
say() { echo "$1"; echo "$1" >> "$GITHUB_STEP_SUMMARY"; }
fail() { echo "::error::$1"; exit 1; }

mkdir -p plan
echo "$PLAN_ID" > plan/id

if [ "$MODE" = "auto" ]; then
  echo 0 > plan/start
  say "### Mode: auto"
  say "Any planned start was cleared. Pings go out right after every reset."
  exit 0
fi

[ -n "$START" ] || fail "Enter when you'll start in the 'start' field, e.g. 9am or tomorrow 18:30."
[[ "$RESET_AFTER" =~ ^[0-9]+$ ]] && [ "$RESET_AFTER" -le 240 ] \
  || fail "'reset_after' must be a number of minutes from 0 to 240."

start=$(TZ=$TIMEZONE date -d "$START" +%s 2>/dev/null) \
  || fail "Couldn't understand the start time '$START'. Try 9am, 18:30, tomorrow 9am or 2026-09-20 14:00."
if [ "$start" -le "$now" ]; then
  # A time without a date that already passed today means tomorrow.
  shopt -s nocasematch
  if [[ "$START" =~ ^[0-9]{1,2}(:[0-9]{2})?\ *([ap]m)?$ ]]; then
    start=$(TZ=$TIMEZONE date -d "tomorrow $START" +%s)
  else
    fail "The start time $(show "$start") is in the past."
  fi
fi

goal=$((start + RESET_AFTER * 60))
anchor=$((goal - WINDOW_SECONDS))
echo "$start" > plan/start
echo "$RESET_AFTER" > plan/reset-after

say "### Planned start: $(show "$start")"
say "- Window resets: about $(show "$goal") ($RESET_AFTER min after you start)"
if [ "$anchor" -gt "$now" ]; then
  say "- Planning ping: about $(show "$anchor"). Pings that would still be running then are skipped."
else
  say "- Too soon for that exact reset, so a new window starts as early as possible instead."
fi
say "- After that ping it goes back to auto."
