#!/usr/bin/env bash
# Decides when the next ping goes out and whether this run should send it.
# Reads state/ (last known reset) and plan/ (planned start); writes step outputs.
set -euo pipefail

now=${NOW:-$(date +%s)}
show() { TZ=$TIMEZONE date -d "@$1" '+%a %b %-d, %-I:%M %p'; }
say() { echo "$1"; echo "$1" >> "$GITHUB_STEP_SUMMARY"; }

reset=$(cat state/next-reset 2>/dev/null || echo 0)
consumed=$(cat state/consumed-plan 2>/dev/null || echo none)
plan_id=$(cat plan/id 2>/dev/null || echo none)
plan_start=$(cat plan/start 2>/dev/null || echo 0)
plan_after=$(cat plan/reset-after 2>/dev/null || echo 60)

# Auto: ping right after the current window resets, or now if none is running.
if [ "$reset" -gt "$now" ]; then target=$((reset + MARGIN_SECONDS)); else target=$now; fi
consume=""

if [ "${FORCE:-false}" = "true" ]; then
  say "Pinging now (requested)."
  target=$now
elif [ "$plan_start" -gt 0 ] && [ "$plan_id" != "$consumed" ]; then
  goal=$((plan_start + plan_after * 60))               # when the window should reset
  anchor=$((goal - WINDOW_SECONDS + MARGIN_SECONDS))   # ping that makes it reset then
  say "Mode: plan. You start $(show "$plan_start"), window should reset $(show "$goal")."
  if [ $((target + WINDOW_SECONDS)) -le "$anchor" ]; then
    say "Normal pings continue for now. The plan's ping is at $(show "$anchor")."
  elif [ "$target" -le "$anchor" ]; then
    target=$anchor
    consume=$plan_id
    say "Holding pings until $(show "$anchor") so the window resets on time."
  else
    consume=$plan_id
    if [ "$reset" -gt "$now" ]; then
      say "A window is already running until $(show "$reset"), so the reset can't land at $(show "$goal"). Pinging right after it instead."
    else
      say "Too late for a reset at $(show "$goal"). Pinging now so a new window starts as early as possible."
    fi
  fi
else
  say "Mode: auto. Pinging right after every reset."
fi

wait=$((target - now))
if [ "$wait" -le "$LEAD_SECONDS" ]; then
  if [ "$wait" -lt 0 ]; then wait=0; fi
  echo "due=true" >> "$GITHUB_OUTPUT"
  echo "wait=$wait" >> "$GITHUB_OUTPUT"
  echo "consume=$consume" >> "$GITHUB_OUTPUT"
  say "Next ping: $(show "$target") (sent by this run)."
else
  echo "due=false" >> "$GITHUB_OUTPUT"
  say "Next ping: $(show "$target")."
fi
