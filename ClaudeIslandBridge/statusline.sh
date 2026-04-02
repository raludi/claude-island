#!/bin/bash
# Claude Island status line bridge
# Reads context window data from Claude Code and sends to the app via socket
SOCKET="/tmp/claude-island.sock"
input=$(cat)
# Extract remaining percentage
REMAINING=$(echo "$input" | /usr/bin/python3 -c "import sys,json; d=json.load(sys.stdin); print(int(d.get('context_window',{}).get('remaining_percentage',0)))" 2>/dev/null)
SESSION_ID=$(echo "$input" | /usr/bin/python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('session_id',''))" 2>/dev/null)
[ -z "$REMAINING" ] && REMAINING=0
[ -z "$SESSION_ID" ] && exit 0
# Send to socket as a status update event
MSG="{\"session_id\":\"${SESSION_ID}\",\"event\":\"StatusLine\",\"status\":\"status_update\",\"cwd\":\"\",\"remaining_percentage\":${REMAINING}}"
echo "$MSG" | /usr/bin/nc -U -w1 "$SOCKET" 2>/dev/null
# Output for Claude Code's status bar (shown in terminal)
echo "${REMAINING}% ctx"
