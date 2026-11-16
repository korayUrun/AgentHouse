# AgentHouse

A tiny, always-on-top macOS overlay that shows every running [Claude Code](https://claude.com/claude-code) session as a little animated mascot — so you always know which agent is working, which one is waiting for you, and which one just finished.

**Observe-only. Fully local. Nothing ever leaves your machine.**

AgentHouse is **open source** (MIT) and open to contributions — see [Contributing](#contributing).

<!-- demo GIF: docs/demo.gif -->

## What it does

- One card per Claude Code session, named after the project folder.
- A mascot on each card reflects the session state:
  - **idle** — resting
  - **working** — busy
  - **attention** — Claude is waiting for your permission or input
  - **question** — Claude asked you a question (`AskUserQuestion`)
  - **done** — the task finished (with a banner if it ran long)
  - **limit** — a rate limit was detected
- Pick a different mascot per project (house, lighthouse, rocket, race car, robot, and more) from the card's right-click menu; the choice is remembered for that project.
- Split cards into their own panels and drag panels onto each other to merge them again. "Gather all cards" in the menu bar brings everything back together.
- Click a card to jump to the terminal / editor that owns the session.
- Menu bar popover with a session summary and local token/cost estimates.
- English and Turkish localization; follows the system language.

## Requirements

- macOS 14.0 (Sonoma) or newer
- [Claude Code](https://claude.com/claude-code) CLI
- Xcode 15.3+ (Swift 5.10) to build from source

## Installation

There are no prebuilt releases yet, so you build the app yourself. It takes about a minute and has **no third-party dependencies**.

### Option A — Xcode

1. Clone the repo:
   ```bash
   git clone https://github.com/<your-username>/AgentHouse.git
   ```
2. Open `AgentHouse.xcodeproj` in Xcode.
3. Select the **AgentHouse** target → **Signing & Capabilities** → choose your own **Team** (a free Apple ID works for local use).
4. Press **⌘R** to run. To keep it installed, use **Product → Archive** or copy the built app into `/Applications`.

### Option B — Command line

Builds an ad-hoc signed app without needing an Apple developer account:

```bash
xcodebuild -project AgentHouse.xcodeproj -scheme AgentHouse -configuration Release \
  -derivedDataPath build CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= build
```

```bash
cp -R build/Build/Products/Release/AgentHouse.app /Applications/
```

```bash
open /Applications/AgentHouse.app
```

## Usage

1. **Launch AgentHouse.** It lives in the menu bar (no Dock icon).
2. **Install the hooks.** On first launch, onboarding offers to install the Claude Code hooks. You can also do it later from **Settings → Install Hooks**. (What exactly this changes is explained [below](#how-it-works--full-transparency).)
3. **Start a new Claude Code session** in any terminal. A card appears on the overlay.
   Sessions that were already running before the hooks were installed won't report events — start a fresh one.
4. **Work as usual.** Glance at the overlay to see which session needs you.
   - **Click** a card to focus the terminal that runs it.
   - **Right-click** a card to change its mascot or move it to its own panel.
   - **Drag** panels anywhere on screen; drop one panel onto another to merge them.
5. **Menu bar icon** → session summary, token/cost estimates, "Gather all cards", Settings, Quit.

**Settings** include: launch at login, a system notification when a task finishes, the local port, install/remove hooks, and an event log for debugging.

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

4. **Usage estimates.** Token counts and cost estimates are computed by reading the session transcript files under `~/.claude/projects/` — opened strictly **read-only**, parsed incrementally. Costs are approximate.

### Privacy guarantees (verifiable in the source)

- **No network beyond localhost.** The only networking code in the app is the `127.0.0.1` listener. No analytics, no telemetry, no crash reporting, no update checks.
- **No user data written to disk.** Only UI preferences (panel positions, port, mascot choice per project) are stored in `UserDefaults`.
- **`~/.claude` is read-only** — except for the single, backed-up, reversible hook installation described above.

## Uninstall

1. Open **Settings → Remove Hooks**. This removes *only* the entries AgentHouse added to `~/.claude/settings.json`; everything else is left untouched. (Your pre-install backup remains at `settings.json.agenthouse-backup`.)
2. Quit AgentHouse and delete it from Applications.

If you deleted the app without removing the hooks first: the hooks are harmless no-ops (they time out after 1 second and always succeed), but you can remove them manually by deleting the entries containing `127.0.0.1:48756/event` from `~/.claude/settings.json`.

## Contributing

Contributions are welcome — bug reports, ideas, new mascots, translations, and pull requests.

1. Fork the repo and create a branch.
2. Make your change and run the tests:
   ```bash
   xcodebuild -project AgentHouse.xcodeproj -scheme AgentHouse -destination 'platform=macOS' \
     CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= test
   ```
3. Open a pull request describing what and why.

Please keep these project principles in mind (details in [`CLAUDE.md`](CLAUDE.md) and [`DECISIONS.md`](DECISIONS.md)):

- **Observe-only:** the app never sends anything to Claude Code and never answers a hook.
- **Local-only:** no network requests outside `127.0.0.1` — no analytics, telemetry or update checks.
- **Safe hooks:** never overwrite a user's `settings.json`; hook commands must never block Claude Code.
- **Architecture:** one-way data flow `EventServer → SessionManager → SessionStateMachine → UI`. State transitions live only in `SessionStateMachine`. Core does not import UI.
- **New mascots** only add drawing code; the shared animation logic (`MascotPose`) stays character-independent.
- **Strings** visible to the user go through `AgentHouse/App/Localizable.xcstrings` (English base + Turkish).

Project layout:

```
AgentHouse/
├── App/        app entry point, localization, assets
├── Core/       events, state machine, usage parsing, hook installer, terminal focus
├── UI/         overlay panels, cards, mascots, menu bar, settings, onboarding
└── Tests/      unit tests for the Core layer
Tools/          app icon generator (swift Tools/makeicon.swift <output-dir>)
docs/           landing page
```

Planning docs (`PLAN.md`, `PHASES.md`, `DECISIONS.md`) are written in Turkish.

## FAQ

**Does this send my prompts or code anywhere?** No. Hook payloads travel from Claude Code to AgentHouse over loopback only, live in memory only, and are never persisted or transmitted.

**Claude Code isn't installed — will the app break?** No. The overlay simply waits for sessions.

**What if the port is taken?** AgentHouse retries once, then warns you; pick another port in Settings and the installed hooks are updated automatically.

**Is this an official Anthropic product?** No. AgentHouse is an independent, community project and is not affiliated with Anthropic.

## License

[MIT](LICENSE)
