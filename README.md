# Claude Buddy

A tiny always-on-top macOS widget: a pixel-art character that shows what Claude Code is doing.
It reads, types, runs commands, raises a hand when Claude is waiting for you, and spawns smaller
clones for every subagent — each clone animates its own work and waves goodbye when it finishes.

No hacks: Claude Code's built-in **HTTP hooks** POST every lifecycle event to `http://127.0.0.1:4789/event`.
The app is a ~500-line Swift package with a minimal HTTP listener and a SwiftUI sprite renderer.

## Install

```bash
tools/install.sh          # build, assemble ~/Applications/ClaudeBuddy.app, register hooks, launch
tools/install.sh --login  # same, plus a LaunchAgent so it starts at login
```

The installer backs up `~/.claude/settings.json` before merging the `hooks` block from
`hooks/settings.hooks.json`. Hooks are `async`, so Claude Code never waits on the widget, and when
the app isn't running the POSTs simply fail silently.

## Develop

```bash
python3 tools/gen_sprites.py   # regenerate placeholder sprite sheets
swift build && .build/debug/ClaudeBuddy &
tools/replay.sh                # send a scripted fake session (no Claude needed)
tools/replay.sh --snapshot /tmp/buddy.png   # also render the panel to a PNG mid-replay
```

Menu bar icon → Show/Hide, Reset position, Play demo, Quit. Drag the character anywhere; the
position is remembered.

## How events map to poses

| Hook event | Pose |
|---|---|
| `SessionStart` | sparkles, "hej!" |
| `UserPromptSubmit` | idle with "…" |
| `PreToolUse` Read / Grep / Glob / WebFetch | reading a book |
| `PreToolUse` Edit / Write | typing on a laptop |
| `PreToolUse` Bash | terminal window |
| `PreToolUse` Agent, `SubagentStart` | sparkles; a smaller tinted clone appears labelled with the agent type |
| `SubagentStop` | clone waves, fades out |
| `PostToolUseFailure` | startled, sweat drop |
| `PermissionRequest`, `Notification` permission_prompt | hand raised, "may I?" |
| `Stop`, `Notification` idle_prompt | idle loop with blink |
| context grew since last check | eating a cookie, "nom nom · +12k" |
| 60 s without events | sleeping |
| `SessionEnd` | waves, disappears |

Events carry `agent_id`, so tool calls made *inside* a subagent animate that clone, not the main character.

**Context size = body size.** Every event names the session's transcript; the app reads the tail of that
`.jsonl` (or the subagent's file under `<session>/subagents/`) and takes the latest assistant turn's
input + cache tokens as the context in use. The sheet has four body widths; the character steps up one
size for every 25 % of the window used, and the label shows the count, e.g. `shack-products · 115k`.
The window size (200k or 1M) is a toggle in the menu bar.
Multiple concurrent Claude sessions each get their own character (labelled with the project folder).

## Replace the art

Sprite sheets live in `Sources/ClaudeBuddy/Resources/buddy.png` (main) and `buddy_1..4.png` (clone tints).
Grid: 32×32 px frames, 4 columns, one animation per row in this order:
`idle(4) read(2) type(2) run(2) wait(2) sleep(2) oops(2) wave(2) spawn(2) eat(3)`,
repeated as one block per fat level (normal → fattest; the app derives the level count from the sheet height).
Drop in your own PNGs with the same grid and rebuild. Frame counts / fps per row are in `Pose` in `Model.swift`.
