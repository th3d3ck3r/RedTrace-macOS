# RedTrace integration for interactive zsh sessions.
# Mirrors prompts, commands, stdout, and stderr to a local log file.

[[ -o interactive ]] || return
[[ -n "${REDTRACE_ATTACHED:-}" ]] && return
[[ -n "${COMMANDGLASS_ATTACHED:-}" ]] && return
export REDTRACE_ATTACHED=1
export COMMANDGLASS_ATTACHED=1

COMMANDGLASS_DIR="$HOME/.redtrace"
COMMANDGLASS_LOG="$COMMANDGLASS_DIR/stream.log"
COMMANDGLASS_SESSIONS="$COMMANDGLASS_DIR/sessions"
COMMANDGLASS_SESSION_NAME="${TERM_PROGRAM:-Terminal}_$$_$(date +%s)"
COMMANDGLASS_SESSION_NAME="${COMMANDGLASS_SESSION_NAME//[^A-Za-z0-9._-]/_}"
COMMANDGLASS_SESSION_LOG="$COMMANDGLASS_SESSIONS/$COMMANDGLASS_SESSION_NAME.log"
COMMANDGLASS_SESSION_ACTIVE="$COMMANDGLASS_SESSIONS/$COMMANDGLASS_SESSION_NAME.active"
mkdir -p "$COMMANDGLASS_SESSIONS"
touch "$COMMANDGLASS_LOG" "$COMMANDGLASS_SESSION_LOG"
print -r -- "$$" > "$COMMANDGLASS_SESSION_ACTIVE"
chmod 700 "$COMMANDGLASS_DIR"
chmod 700 "$COMMANDGLASS_SESSIONS"
chmod 600 "$COMMANDGLASS_LOG" "$COMMANDGLASS_SESSION_LOG" "$COMMANDGLASS_SESSION_ACTIVE"

function _redtrace_remove_active_marker {
  rm -f "$COMMANDGLASS_SESSION_ACTIVE"
}
trap _redtrace_remove_active_marker EXIT

# Retain at most about 10 MB when a fresh shell starts.
if (( $(wc -c < "$COMMANDGLASS_LOG") > 10485760 )); then
  tail -c 5242880 "$COMMANDGLASS_LOG" > "$COMMANDGLASS_LOG.tmp"
  mv "$COMMANDGLASS_LOG.tmp" "$COMMANDGLASS_LOG"
fi

print -r -- "" "— session started: $(date '+%Y-%m-%d %H:%M:%S') · ${TERM_PROGRAM:-terminal} —" >> "$COMMANDGLASS_LOG"
print -r -- "" "— session started: $(date '+%Y-%m-%d %H:%M:%S') · ${TERM_PROGRAM:-terminal} · pid $$ —" >> "$COMMANDGLASS_SESSION_LOG"

# Run the visible shell behind a pseudo-terminal. Commands inside the child
# continue to see real TTY stdin/stdout/stderr, while script's output is copied
# to the terminal and both RedTrace logs. This keeps interactive installers,
# sudo, progress UIs, and programs that call isatty() working normally.
/usr/bin/script -q /dev/null /bin/zsh -il \
  > >(tee -a "$COMMANDGLASS_LOG" "$COMMANDGLASS_SESSION_LOG") 2>&1
REDTRACE_STATUS=$?

print -r -- "" "— session ended: $(date '+%Y-%m-%d %H:%M:%S') —" >> "$COMMANDGLASS_LOG"
print -r -- "" "— session ended: $(date '+%Y-%m-%d %H:%M:%S') —" >> "$COMMANDGLASS_SESSION_LOG"
rm -f "$COMMANDGLASS_SESSION_ACTIVE"
exit "$REDTRACE_STATUS"
