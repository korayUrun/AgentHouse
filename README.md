# AgentHouse

A tiny, always-on-top macOS overlay that shows every running [Claude Code](https://claude.com/claude-code) session as a little animated house — so you always know which agent is working, which one is waiting for you, and which one just finished.

**Observe-only. Fully local. Nothing ever leaves your machine.**

<!-- demo GIF: docs/demo.gif -->

## What it does

- One card per Claude Code session, named after the project folder.
- A single mascot reflects the session state:
  - **idle** — resting
  - **working** — busy (chimney smoking)
  - **attention** — Claude is waiting for your permission or input
  - **done** — the task finished (with a banner if it ran long)
  - **limit** — a rate limit was detected, with an estimated reset time
- Click a card to jump to the terminal that owns the session.
- Menu bar popover with a session summary and local token/cost estimates.
- English and Turkish localization; follows the system language.

## Requirements

- macOS 14.0 (Sonoma) or newer
- [Claude Code](https://claude.com/claude-code) CLI

## Install

1. Download the latest `.dmg` from Releases, drag AgentHouse to Applications, and launch it.
2. On first launch, onboarding offers to install the Claude Code hooks (see below — it's one small, reversible change).
3. Start a **new** Claude Code session. A card appears in the overlay.

Sessions that were already running before the hooks were installed won't report events; start a fresh session.

## How it works — full transparency

AgentHouse never talks to Claude Code. It only **listens**:

1. **Hooks.** Claude Code supports [hooks](https://docs.claude.com/en/docs/claude-code/hooks): shell commands that run when session events happen. AgentHouse adds one command to seven events (`SessionStart`, `UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `Notification`, `Stop`, `SessionEnd`) in `~/.claude/settings.json`:

   ```
   curl -s --max-time 1 -X POST http://127.0.0.1:48756/event \
     -H 'Content-Type: application/json' -d @- || true
   ```

   - `--max-time 1` and `|| true` guarantee that Claude Code is **never blocked or affected**, even when AgentHouse isn't running.
   - The hook is observe-only: it returns nothing, so it can never approve, deny, or modify anything Claude does.

2. **Safe settings editing.** When installing hooks, AgentHouse parses your existing `settings.json`, merges its entries in, and writes back — your own hooks and settings are never overwritten. A backup is saved first at `~/.claude/settings.json.agenthouse-backup`.

3. **Local event server.** AgentHouse listens on `127.0.0.1:48756` (configurable in Settings). The listener is bound to the loopback interface, so connections from outside your machine are impossible at the socket level.

4. **Usage estimates.** Token counts and cost estimates are computed by reading the session transcript files under `~/.claude/projects/` — opened strictly **read-only**, parsed incrementally.

### Privacy guarantees (verifiable in the source)

- **No network beyond localhost.** The only networking code in the app is the `127.0.0.1` listener. No analytics, no telemetry, no crash reporting, no update checks.
- **No data written to disk.** The app is stateless; only UI preferences (panel position, port, thresholds) are stored in `UserDefaults`.
- **`~/.claude` is read-only** — except for the single, backed-up, reversible hook installation described above.

## Uninstall

1. Open **Settings → Remove hooks**. This removes *only* the entries AgentHouse added to `~/.claude/settings.json`; everything else is left untouched. (Your pre-install backup remains at `settings.json.agenthouse-backup`.)
2. Quit AgentHouse and delete it from Applications.

If you deleted the app without removing the hooks first: the hooks are harmless no-ops (they time out after 1 second and always succeed), but you can remove them manually by deleting the entries containing `127.0.0.1:48756/event` from `~/.claude/settings.json`.

## Performance

Measured on Apple Silicon, Release build: ~20 MB memory footprint, ~0% CPU with no active sessions, ~2% CPU while one mascot animates. App size under 3 MB. Animations pause automatically when the panel is hidden or covered.

## Building from source

```bash
git clone <repo-url>
cd AgentHouse
xcodebuild -project AgentHouse.xcodeproj -scheme AgentHouse -configuration Release build
```

Tests: `xcodebuild -project AgentHouse.xcodeproj -scheme AgentHouse test`

The app icon is generated from `Tools/makeicon.swift` (`swift Tools/makeicon.swift <output-dir>`).

## FAQ

**Does this send my prompts or code anywhere?** No. Hook payloads travel from Claude Code to AgentHouse over loopback only, live in memory only, and are never persisted or transmitted.

**Claude Code isn't installed — will the app break?** No. The overlay simply waits for sessions. Installing hooks just creates `~/.claude/settings.json` for when Claude Code arrives.

**What if the port is taken?** AgentHouse retries once, then warns you; pick another port in Settings and the installed hooks are updated automatically.
