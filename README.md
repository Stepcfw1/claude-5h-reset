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
| `check` | What the outside timer runs every 5 minutes. It pings only if one is due and never changes a plan. You don't need to pick it. |

**Plan example:** start `tomorrow 9am`, reset_after `60`. It pings at about 5:00 AM,
so the window resets at about 10:00 AM. You use the rest of that window from 9 to 10,
then get a fresh 5 hours.

- `start` is Eastern (DC) time. Examples: `9am`, `18:30`, `tomorrow 9am`, `sat 10am`, `2026-09-20 14:00`.
- A time without a date that has already passed today means tomorrow.
- After midnight Eastern, `tomorrow` means the day after. Use a day name like `mon 10am` to avoid mix-ups.
- If you start in less than about 4 hours, that exact reset is no longer possible.
  A new window starts as early as possible instead.
- Only one plan at a time. A new plan replaces the old one.

Each run's summary shows the current mode and when the next ping goes out.

From a terminal with GitHub CLI:

```bash
gh workflow run claude-5h-ping.yml -R Stepcfw1/claude-5h-reset -f mode=plan -f start="mon 10am" -f reset_after=60
```

## How it works

1. Every 5 minutes, [cron-job.org](https://cron-job.org) asks GitHub to run a quick
   `check`. It sends **no message** unless a ping is less than 15 minutes away.
   GitHub's own schedule is only an hourly backup, because GitHub skips many
   scheduled runs when it's busy.
2. When a ping is close, the job waits until the ping time (1 minute after the reset,
   or the plan's ping time) and sends one short Haiku message.
3. Claude Code reports the new reset time with the reply. The workflow saves that
   time (in the Actions cache) for the next check.
4. If you start a window yourself in chat, the next ping picks up that window's real
   reset time and follows it.

The scripts in `scripts/` hold the logic: `plan.sh` saves a plan, `decide.sh` picks
the next ping time, and `ping.sh` sends the ping. `codex-ping.sh` (with
`read_reset.py`) does both jobs for Codex; `test-codex-ping.sh` is its self-check,
run it with `bash scripts/test-codex-ping.sh`.

A weekly `keepalive` job stops GitHub from disabling the schedule after 60 days of
repo inactivity (a public-repo rule).

## Codex too

The `codex` job does the same for a Codex (ChatGPT) 5-hour window, which is a separate
limit from Claude's. It runs on the same timer, in its own job, with its own cache
(`codex-next-*`), so neither side can break the other. Without the `CODEX_AUTH_JSON`
secret the job just prints a notice and exits.

Two differences from the Claude side:

- **Reset time:** `codex exec` doesn't print it. The job reads it from the rollout file
  Codex writes under `~/.codex/sessions` (the window with `window_minutes: 300`). When
  that isn't there, or the value is stale, the job falls back to pinging every
  **5 h 05 m** and says so in the log. Expect ~1 minute of idle per window with a
  reset time, a few minutes without one.
- **Login:** Codex has no `setup-token`. The only way to use your ChatGPT plan quota in
  CI is a copy of your `~/.codex/auth.json` (an API key would bill separately and
  wouldn't touch the plan quota). OpenAI recommends API keys for CI, so this is a
  deliberate trade-off. Codex refreshes that file as it runs and the refreshed copy is
  thrown away with the runner, so the stored secret can go stale; the job prints a
  warning when it sees a refresh, and fails loudly once it stops working.

There's no `plan` mode for Codex, just the always-on behavior.

## Setup

### 1. Claude token

1. On any computer with Node.js, run:

   ```bash
   npx @anthropic-ai/claude-code setup-token
   ```

   Sign in in the browser, then copy the token it prints. It's valid for **1 year**.
2. Repo → Settings → Secrets and variables → Actions → New repository secret.
   Name it `CLAUDE_CODE_OAUTH_TOKEN` and paste the token as the value.

### 2. GitHub token for the outside timer

1. Open <https://github.com/settings/personal-access-tokens/new> (fine-grained token).
2. **Token name:** `cron-job.org claude ping`. **Expiration:** 1 year, or whatever you prefer.
3. **Repository access:** *Only select repositories* → `Stepcfw1/claude-5h-reset`.
4. **Permissions → Repository permissions → Actions:** *Read and write*. Leave
   everything else as it is.
5. Click **Generate token** and copy it. You won't be able to see it again.

### 3. Codex login (optional, skip if you only use Claude)

1. Install Codex and run `codex login` on this PC.
2. Open `%USERPROFILE%\.codex\auth.json` and copy everything in it.
3. Repo → Settings → Secrets and variables → Actions → New repository secret.
   Name it `CODEX_AUTH_JSON` and paste the file contents as the value.

Treat that file like a password. If runs start failing with an auth error, run
`codex login` again and re-paste it.

### 4. cron-job.org

1. Create a free account at <https://cron-job.org>, then click **Create cronjob**.
2. **Title:** `Claude 5h check`
3. **URL:** `https://api.github.com/repos/Stepcfw1/claude-5h-reset/actions/workflows/claude-5h-ping.yml/dispatches`
4. **Execution schedule:** every 5 minutes.
5. In the **Advanced** section:
   - **Request method:** `POST`
   - **Headers:**
     - `Accept` = `application/vnd.github+json`
     - `Authorization` = `Bearer ` followed by the GitHub token from step 2
     - `X-GitHub-Api-Version` = `2022-11-28`
     - `Content-Type` = `application/json`
   - **Request body:** `{"ref":"main","inputs":{"mode":"check"}}`
6. Save. Each call should get a **200** (or **204**) response, and new `check` runs
   appear in the Actions tab.

### 5. Test

Run workflow with mode `ping-now`. The run summary shows **Next reset: …**, which should
match [claude.ai/settings/usage](https://claude.ai/settings/usage).

## Are my tokens safe?

- **Claude token:** stored as an encrypted GitHub Actions secret. Nobody can view it,
  not even you, after saving. You can only replace or delete it. GitHub hides it as
  `***` if it ever appears in a log. Forks and pull requests from other people don't
  get access to secrets.
- **Codex `auth.json`:** stored as an encrypted secret like the Claude token, and never
  printed. It is still a login file, so if you'd rather not keep one in GitHub, skip
  the Codex job entirely.
- **GitHub token in cron-job.org:** it can only start and manage workflow runs in this
  one repo. It can't read your secrets, change code, or touch your other repos. If it
  ever leaks, delete it at <https://github.com/settings/personal-access-tokens>.
- Only people with write access to this repo could change the workflow, and that's
  just you. Don't add collaborators, and keep 2FA on your GitHub account.
- This is a public repo, so anyone can read the run logs. They only show Claude's
  `ok` reply, your reset times and your planned start times.

## Maintenance

- **Token renewal:** both tokens expire (the Claude token after 1 year, the GitHub token
  when you chose). When runs fail or cron-job.org reports errors, make a new token and
  replace the old one.
- **Pause:** disable the cron job on cron-job.org, and in GitHub go to Actions tab →
  *Claude 5h ping* → `...` → Disable workflow.

## Cost

- **Claude usage:** about 5 very short Haiku messages a day.
- **Codex usage:** about 5 very short prompts a day, only if you set `CODEX_AUTH_JSON`.
- **GitHub minutes:** ~290 short checks a day, free on public repos.
