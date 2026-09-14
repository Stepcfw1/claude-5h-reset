#!/usr/bin/env bash
# Sends one tiny message to Claude and saves the next reset time it reports to state/.
set -euo pipefail

say() { echo "$1"; echo "$1" >> "$GITHUB_STEP_SUMMARY"; }

if [ -z "${CLAUDE_CODE_OAUTH_TOKEN:-}" ]; then
  echo "::error::Secret CLAUDE_CODE_OAUTH_TOKEN is not set. Run 'claude setup-token' and add it under Settings > Secrets and variables > Actions."
  exit 1
fi
mkdir -p state
for attempt in 1 2 3; do
  # No --bare: bare mode ignores CLAUDE_CODE_OAUTH_TOKEN.
  # --tools "" must be followed by another option, not the prompt.
  out=$(claude --model haiku \
    --tools "" \
    --system-prompt "Reply with the single word: ok" \
    --no-session-persistence \
    --output-format stream-json --verbose \
    -p "ping" || true)
  now=$(date +%s)
  json=$(jq -cR 'fromjson?' <<<"$out")
  reply=$(jq -r 'select(.type=="result") | .result // empty' <<<"$json")
  is_error=$(jq -r 'select(.type=="result") | .is_error' <<<"$json")
  limits=$(jq -c 'select(.type=="rate_limit_event") | .rate_limit_info' <<<"$json")
  echo "Claude replied: ${reply:-<nothing>}"
  jq -c '{status, rateLimitType, resetsAt}' <<<"$limits"

  # Prefer a limit that is currently blocking, otherwise the 5-hour window.
  reset=$(jq -rs 'map(select(.resetsAt != null))
    | (map(select(.status == "rejected")) + map(select(.rateLimitType == "five_hour" or .rateLimitType == null)))
    | .[0].resetsAt // empty' <<<"$limits")
  reset=${reset%.*}
  if [ -n "$reset" ] && [ "$reset" -gt 100000000000 ]; then
    reset=$((reset / 1000)) # milliseconds -> seconds
  fi

  if [ -z "$reset" ]; then
    if [ "$is_error" != "false" ]; then
      echo "::error::Ping failed. The token may be expired or invalid."
      exit 1
    fi
    echo "::warning::Claude replied but sent no reset time. Checking again in 30 minutes."
    reset=$((now + 1800))
  elif [ $((reset - now)) -lt 300 ] && [ "$attempt" -lt 3 ]; then
    # Landed just before the old window ended: wait for the reset and ping again.
    sleep $(( reset - now + MARGIN_SECONDS > 0 ? reset - now + MARGIN_SECONDS : 0 ))
    continue
  fi
  break
done

echo "$reset" > state/next-reset
if [ -n "${CONSUME:-}" ]; then
  echo "$CONSUME" > state/consumed-plan
  say "Plan done, back to auto."
fi
say "### Next reset: $(TZ=$TIMEZONE date -d "@$reset" '+%a %-I:%M %p %Z')"
