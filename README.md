# Claude 5-hour window keep-alive

A GitHub Actions workflow that sends Claude one tiny message right after your 5-hour
usage window resets, so the next window starts immediately. It runs on GitHub's
servers, so your PC can be off.

Claude Pro/Max usage limits are shared between claude.ai and Claude Code, so a ping
from the Claude Code CLI starts the same window you see in the chat app
("Current session · Resets at …").

> This does not give you more usage, and weekly limits still apply. It only makes sure
> a new window starts the moment the old one ends.

## How it works

1. Every 10 minutes a quick check runs. It sends **no message** unless a reset is
   less than 25 minutes away.
2. When a reset is close, the job waits until **1 minute after the reset**, then sends
   one short Haiku message.
3. Claude Code reports the new reset time with the reply. The workflow saves that
   time (in the Actions cache) for the next check.
4. The very first run pings immediately to learn your current reset time.
5. If you start a window yourself in chat, the next ping just picks up that window's
   real reset time and follows it.

GitHub can delay scheduled runs. Because the job starts waiting up to 25 minutes
ahead of the reset, pings usually land within about a minute of it anyway.

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

3. **Test it**: Actions tab → *Claude 5h ping* → **Run workflow** (tick *Ping now*).
   The run summary shows **Next reset: …**, which should match
   [claude.ai/settings/usage](https://claude.ai/settings/usage).

## Is my token safe?

- It's stored as an encrypted GitHub Actions secret. Nobody can view it, not even
  you, after saving. You can only replace or delete it.
- GitHub hides it as `***` if it ever appears in a log.
- Forks and pull requests from other people don't get access to secrets.
- Only people with write access to this repo could change the workflow, and that's
  just you. Don't add collaborators, and keep 2FA on your GitHub account.
- This is a public repo, so anyone can read the run logs. The logs only show
  Claude's `ok` reply and your reset times.

## Maintenance

- **Token renewal:** the token expires 1 year after you create it. When runs start
  failing (GitHub emails you about failed workflows), repeat setup step 1 and update the
  secret.
- **Pause:** Actions tab → *Claude 5h ping* → `...` → Disable workflow.

## Cost

- **Claude usage:** about 5 very short Haiku messages a day.
- **GitHub minutes:** ~144 short checks a day, free on public repos.
