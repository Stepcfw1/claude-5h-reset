# Claude 5-hour window keep-alive

A GitHub Actions workflow that sends Claude one tiny message right after your 5-hour
usage window resets, so the next window starts immediately. It runs on GitHub's
servers, so your PC can be off.

Claude Pro/Max usage limits are shared between claude.ai and Claude Code, so a ping
from the Claude Code CLI starts the same window you see in the chat app
("Current session · Resets at …").

> This does not give you more usage, and weekly limits still apply. It only controls
> when your windows start and reset.

## Modes

Switch modes on GitHub: **Actions → Claude 5h ping → Run workflow**, pick a mode,
then click **Run workflow**. This works from your phone's browser too.

| Mode | What it does |
|---|---|
| `auto` | Pings right after every reset, so a window is always running. This is the normal behavior. Choosing it clears any plan. |
| `plan` | Enter when you'll start. It times one ping so your window resets `reset_after` minutes (default 60) after you start. Auto pings that would still be running at that moment are skipped. After that ping it goes back to `auto` on its own. |
| `ping-now` | Sends one ping right away. A plan stays in place. |

**Plan example:** start `tomorrow 9am`, reset_after `60`. It pings at about 5:00 AM,
so the window resets at about 10:00 AM. You use the rest of that window from 9 to 10,
then get a fresh 5 hours.

- `start` is Pacific time. Examples: `9am`, `18:30`, `tomorrow 9am`, `sat 10am`, `2026-09-20 14:00`.
- A time without a date that has already passed today means tomorrow.
- If you start in less than about 4 hours, that exact reset is no longer possible.
  A new window starts as early as possible instead.
- Only one plan at a time. A new plan replaces the old one.

Each run's summary shows the current mode and when the next ping goes out.

From a terminal with GitHub CLI:

```bash
gh workflow run claude-5h-ping.yml -R Stepcfw1/claude-5h-reset -f mode=plan -f start="tomorrow 9am" -f reset_after=60
```

## How it works

1. Every 10 minutes a quick check runs. It sends **no message** unless a ping is
   less than 25 minutes away.
2. When one is close, the job waits until the ping time (1 minute after the reset,
   or the plan's ping time) and sends one short Haiku message.
3. Claude Code reports the new reset time with the reply. The workflow saves that
   time (in the Actions cache) for the next check.
4. If you start a window yourself in chat, the next ping picks up that window's real
   reset time and follows it.

The scripts in `scripts/` hold the logic: `plan.sh` saves a plan, `decide.sh` picks
the next ping time, and `ping.sh` sends the ping.

GitHub can delay scheduled runs. Because the job starts waiting up to 25 minutes
ahead, pings usually land within about a minute of their time anyway.

A weekly `keepalive` job stops GitHub from disabling the schedule after 60 days of
repo inactivity (a public-repo rule).

## Setup

1. **Get a subscription token** (on any computer with Node.js):

   ```bash
   npx @anthropic-ai/claude-code setup-token
   ```

   Sign in in the browser, then copy the token it prints. It's valid for **1 year**.

2. **Add the secret**: repo → Settings → Secrets and variables → Actions →
   New repository secret
   - Name: `CLAUDE_CODE_OAUTH_TOKEN`
   - Value: the token from step 1

3. **Test it**: Run workflow with mode `ping-now`. The run summary shows
   **Next reset: …**, which should match
   [claude.ai/settings/usage](https://claude.ai/settings/usage).

## Is my token safe?

- It's stored as an encrypted GitHub Actions secret. Nobody can view it, not even
  you, after saving. You can only replace or delete it.
- GitHub hides it as `***` if it ever appears in a log.
- Forks and pull requests from other people don't get access to secrets.
- Only people with write access to this repo could change the workflow, and that's
  just you. Don't add collaborators, and keep 2FA on your GitHub account.
- This is a public repo, so anyone can read the run logs. They only show Claude's
  `ok` reply, your reset times and your planned start times.

## Maintenance

- **Token renewal:** the token expires 1 year after you create it. When runs start
  failing (GitHub emails you about failed workflows), repeat setup step 1 and update the
  secret.
- **Pause:** Actions tab → *Claude 5h ping* → `...` → Disable workflow.

## Cost

- **Claude usage:** about 5 very short Haiku messages a day.
- **GitHub minutes:** ~144 short checks a day, free on public repos.
