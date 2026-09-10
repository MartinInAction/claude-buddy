#!/usr/bin/env bash
# Sends a scripted sequence of fake Claude Code hook events to a running Claude Buddy.
# Usage: tools/replay.sh [--snapshot /path/out.png]
set -u
URL=http://127.0.0.1:4789/event
SID="replay-$$"
SNAP=""
[[ "${1:-}" == "--snapshot" ]] && SNAP="${2:-}"

post() { curl -s -m 2 -X POST "$URL" -H 'Content-Type: application/json' -d "$1" >/dev/null || echo "buddy not running?"; }
ev()   { post "{\"hook_event_name\":\"$1\",\"session_id\":\"$SID\",\"cwd\":\"$PWD\"${2:+,$2}}"; }

ev SessionStart;                                                                     sleep 1.5
ev UserPromptSubmit '"prompt":"fix the bug"';                                        sleep 1
ev PreToolUse '"tool_name":"Read","tool_input":{"file_path":"src/App.tsx"}';         sleep 2
ev PostToolUse '"tool_name":"Read"';                                                 sleep 0.5
ev PreToolUse '"tool_name":"Agent","tool_input":{"description":"Explore codebase"}'; sleep 1
ev SubagentStart '"agent_id":"'$SID'-sub1","agent_type":"Explore"';                  sleep 1
ev PreToolUse '"agent_id":"'$SID'-sub1","agent_type":"Explore","tool_name":"Grep","tool_input":{"pattern":"useQuery"}'; sleep 1
ev PreToolUse '"tool_name":"Edit","tool_input":{"file_path":"src/theme.ts"}';        sleep 2
ev PreToolUse '"tool_name":"Bash","tool_input":{"command":"npm run typecheck"}';     sleep 2
[[ -n "$SNAP" ]] && curl -s -m 2 -X POST http://127.0.0.1:4789/snapshot -d "{\"path\":\"$SNAP\"}" >/dev/null
ev SubagentStop '"agent_id":"'$SID'-sub1","agent_type":"Explore"';                   sleep 2
ev PostToolUseFailure '"tool_name":"Bash","tool_input":{"command":"npm run typecheck"}'; sleep 2.5
ev PermissionRequest '"tool_name":"Bash","tool_input":{"command":"git push"}';       sleep 3
ev PostToolUse '"tool_name":"Bash"';                                                 sleep 1
ev Notification '"notification_type":"agent_needs_input","message":"Which library should we use for dates?"'; sleep 3
ev Stop;                                                                             sleep 3
ev SessionEnd
echo "replay done"
