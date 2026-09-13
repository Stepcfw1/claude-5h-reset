# Claude 5-hour window keep-alive

A GitHub Actions workflow that sends Claude a one-word message every 30 minutes, so a
5-hour usage window is always running, even when your PC is off.

Claude Pro/Max usage limits are shared between claude.ai and Claude Code, so a ping
from the Claude Code CLI starts the same 5-hour window you see in the chat app.

> This does not give you more usage, and weekly limits still apply. It only makes sure
> a window is already running (and resetting) whenever you sit down to work.

## How it works

- `.github/workflows/claude-5h-ping.yml` runs at **:13 and :43 past every hour (UTC)**.
- Each run installs the Claude Code CLI and sends one tiny Haiku message using your
  subscription token.
- If a window is already open, the ping uses a negligible amount of usage.
  If the window just reset, the ping opens a new one within ~30 minutes.
- Pings are frequent on purpose: GitHub cron runs are often 5–30 minutes late, so a
  ping every 5 hours would regularly miss the reset and leave hours with no window.
- A weekly `keepalive` job stops GitHub from disabling the schedule after 60 days of
  repo inactivity (a public-repo rule).

## Setup

1. **Get a subscription token** (on any computer with Node.js):

   ```bash
   npx @anthropic-ai/claude-code setup-token
   ```

   Sign in in the browser, then copy the token it prints. It's valid for **1 year**.

2. **Create a GitHub repo** and add this repo's files to it.
   Public repos get unlimited Actions minutes. Private repos work too, see *Cost* below.

3. **Add the secret**: repo → Settings → Secrets and variables → Actions →
   New repository secret
   - Name: `CLAUDE_CODE_OAUTH_TOKEN`
   - Value: the token from step 1

   Never commit the token to the repo itself.

4. **Test it**: Actions tab → *Claude 5h ping* → **Run workflow**.
   The run should go green, with `ok` in the log. Then check
   [claude.ai/settings/usage](https://claude.ai/settings/usage): you should see a current
   session with a reset time about 5 hours away.

## Maintenance

- **Token renewal:** the token expires 1 year after you create it. When runs start
  failing (GitHub emails you about failed workflows), repeat setup step 1 and update the
  secret.
- **Pause:** Actions tab → *Claude 5h ping* → `...` → Disable workflow.

## Cost

- **Claude usage:** each ping is one very short Haiku message.
- **GitHub minutes:** ~48 runs/day × ~1 min ≈ 1,440 min/month. That's free on public
  repos. On a private repo it's most of the 2,000 free minutes/month, so if you use Actions
  for anything else, switch to hourly by changing the cron to `'13 * * * *'`.

## Optional: align resets to your day

With no anchor, reset times drift around the clock. If you later settle into a routine,
you can anchor the windows instead. Replace the ping cron with fixed times at least
5h15m apart, plus a backup ping 30 minutes after each one in case GitHub runs late.
Leave a gap overnight so no window is still open when the morning anchor ping fires.

Cron times are **UTC**. Pacific time is UTC-7 in summer (PDT) and UTC-8 in winter (PST).

Example: start work ~9 AM Pacific on weekdays and ~11 AM on weekends (PDT). Anchor pings
run 2 hours before you start, so your first reset lands mid-session:

```yaml
schedule:
  # Weekdays: 7:00 AM, 12:15 PM, 5:30 PM, 10:45 PM PDT, each with a +30 min backup
  - cron: '0,30 14 * * 1-5'
  - cron: '15,45 19 * * 1-5'
  - cron: '30 0 * * 2-6'
  - cron: '0 1 * * 2-6'
  - cron: '45 5 * * 2-6'
  - cron: '15 6 * * 2-6'
  # Weekends: 9:00 AM, 2:15 PM, 7:30 PM PDT, each with a +30 min backup
  - cron: '0,30 16 * * 0,6'
  - cron: '15,45 21 * * 0,6'
  - cron: '30 2 * * 0,1'
  - cron: '0 3 * * 0,1'
```

In the evenings (Pacific), the UTC date has already rolled over to the next day,
which is why those lines use the following weekday numbers.
