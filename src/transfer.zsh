#!/bin/zsh

set -u
unsetopt BG_NICE

DEST_ROOT=""
VERIFY_ONLY=0
SOURCES=()

while (( $# > 0 )); do
  case "$1" in
    --destination)
      [[ $# -ge 2 ]] || { print -u2 -- "--destination requires a path"; exit 2; }
      DEST_ROOT="$2"
      shift 2
      ;;
    --source)
      [[ $# -ge 2 ]] || { print -u2 -- "--source requires a path"; exit 2; }
      SOURCES+=("$2")
      shift 2
      ;;
    --verify-only)
      VERIFY_ONLY=1
      shift
      ;;
    *)
      print -u2 -- "Unknown argument: $1"
      exit 2
      ;;
  esac
done

[[ -n "$DEST_ROOT" && ${#SOURCES[@]} -gt 0 ]] || { print -u2 -- "A destination and at least one source are required"; exit 2; }
DEST_ROOT="${DEST_ROOT:A}"
STATE_ROOT="$DEST_ROOT/.cygentig-transfer"
LOG_FILE="$STATE_ROOT/transfer.log"
STATUS_FILE="$STATE_ROOT/status.txt"
STATUS_CODE_FILE="$STATE_ROOT/status-code.txt"
STATUS_ARGUMENTS_FILE="$STATE_ROOT/status-arguments.txt"
PID_FILE="$STATE_ROOT/worker.pid"
CHILD_PID_FILE="$STATE_ROOT/rsync.pid"
LOCK_DIR="$STATE_ROOT/lock"
PROGRESS_FILE="$STATE_ROOT/progress.txt"

if [[ -x /opt/homebrew/bin/rsync ]]; then
  RSYNC_BIN=/opt/homebrew/bin/rsync
  RSYNC3=1
elif [[ -x /usr/local/bin/rsync ]]; then
  RSYNC_BIN=/usr/local/bin/rsync
  RSYNC3=1
else
  RSYNC_BIN=/usr/bin/rsync
  RSYNC3=0
fi

mkdir -p "$STATE_ROOT"
timestamp() { /bin/date '+%Y-%m-%d %H:%M:%S'; }
log() { print -r -- "[$(timestamp)] $*" >> "$LOG_FILE"; }
set_status() {
  local code="$1" message="$2"
  shift 2
  print -r -- "$code" >| "$STATUS_CODE_FILE"
  : >| "$STATUS_ARGUMENTS_FILE"
  local argument
  for argument in "$@"; do print -r -- "$argument" >> "$STATUS_ARGUMENTS_FILE"; done
  print -r -- "$message" >| "$STATUS_FILE"
  log "$message"
}

if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  if [[ -f "$PID_FILE" ]] && /bin/kill -0 "$(<"$PID_FILE")" 2>/dev/null; then
    log "A transfer task is already running; duplicate launch ignored."
    exit 0
  fi
  rmdir "$LOCK_DIR" 2>/dev/null || true
  mkdir "$LOCK_DIR" 2>/dev/null || { set_status lock_failed "Unable to acquire the transfer lock; see the log."; exit 1; }
fi

print -r -- "$$" >| "$PID_FILE"
cleanup() {
  rm -f "$PID_FILE" "$CHILD_PID_FILE" "$STATE_ROOT/progress.fifo"
  rmdir "$LOCK_DIR" 2>/dev/null || true
}
stop_worker() {
  set_status paused "Paused. Incomplete files were preserved and can be resumed."
  if [[ -f "$CHILD_PID_FILE" ]]; then
    /bin/kill -TERM "$(<"$CHILD_PID_FILE")" 2>/dev/null || true
    /bin/sleep 1
  fi
  exit 130
}
trap cleanup EXIT
trap stop_worker INT TERM HUP

[[ -d "$DEST_ROOT" ]] || { set_status destination_unavailable "Destination unavailable: $DEST_ROOT" "$DEST_ROOT"; exit 2; }

typeset -A SEEN_NAMES
NORMALIZED_SOURCES=()
for raw_source in "${SOURCES[@]}"; do
  source_path="${raw_source:A}"
  [[ -d "$source_path" ]] || { set_status source_unavailable "Source unavailable: $source_path" "$source_path"; exit 2; }
  name="${source_path:t}"
  key="${name:l}"
  [[ -z "${SEEN_NAMES[$key]:-}" ]] || { set_status duplicate_source "Duplicate source folder name: $name" "$name"; exit 2; }
  SEEN_NAMES[$key]=1
  target="$DEST_ROOT/$name"
  if [[ "$target" == "$source_path" || "$target" == "$source_path"/* ]]; then
    set_status recursive_target "Destination would be inside source: $source_path" "$source_path"
    exit 2
  fi
  NORMALIZED_SOURCES+=("$source_path")
done

verify_job() {
  local src="$1" index="$2" total="$3"
  local name="${src:t}" dst="$DEST_ROOT/${src:t}/"
  local source_key="$(print -rn -- "$src" | /usr/bin/shasum -a 256 | /usr/bin/awk '{print substr($1,1,16)}')"
  local audit="$STATE_ROOT/${name}.${source_key}.checksum-audit.txt"
  set_status verifying "Verifying [$index/$total]: $name" "$index" "$total" "$name"
  log "Starting content verification $src/ -> $dst"
  if (( RSYNC3 )); then
    "$RSYNC_BIN" -anc --exclude='.cygentig-rsync-partial/' "$src/" "$dst" >| "$audit" 2>> "$LOG_FILE" &
  else
    "$RSYNC_BIN" -aEnc --exclude='.cygentig-rsync-partial/' "$src/" "$dst" >| "$audit" 2>> "$LOG_FILE" &
  fi
  local child=$!
  print -r -- "$child" >| "$CHILD_PID_FILE"
  wait "$child"
  local code=$?
  rm -f "$CHILD_PID_FILE"
  (( code == 0 )) || { set_status verify_failed "Verification failed [$index/$total]: $name (see log)" "$index" "$total" "$name"; return "$code"; }
  [[ ! -s "$audit" ]] || { set_status verify_difference "Verification found differences [$index/$total]: $name" "$index" "$total" "$name"; log "Differences: $audit"; return 3; }
  log "Verification passed: $name"
}

copy_job() {
  local src="$1" index="$2" total="$3"
  local name="${src:t}" dst="$DEST_ROOT/${src:t}/"
  local source_key="$(print -rn -- "$src" | /usr/bin/shasum -a 256 | /usr/bin/awk '{print substr($1,1,16)}')"
  local done_marker="$STATE_ROOT/${name}.${source_key}.copy-complete"
  if [[ -f "$done_marker" ]]; then
    set_status completed_skip "Already complete, skipped [$index/$total]: $name" "$index" "$total" "$name"
    return 0
  fi
  mkdir -p "$dst"
  rm -f "$PROGRESS_FILE"
  set_status copying "Copying [$index/$total]: $name" "$index" "$total" "$name"
  log "Starting/resuming $src/ -> $dst (rsync: $RSYNC_BIN)"
  if (( RSYNC3 )); then
    local progress_pipe="$STATE_ROOT/progress.fifo"
    rm -f "$progress_pipe"
    /usr/bin/mkfifo "$progress_pipe"
    (
      /usr/bin/tr '\r' '\n' < "$progress_pipe" | while IFS= read -r line; do
        if [[ "$line" == *"%"* ]]; then
          if [[ "$line" != *"(xfr#"* || ! -s "$PROGRESS_FILE" ]]; then
            print -r -- "$line" >| "$PROGRESS_FILE"
          fi
        elif [[ -n "${line//[[:space:]]/}" ]]; then
          print -r -- "$line" >> "$LOG_FILE"
        fi
      done
    ) &
    local parser=$!
    "$RSYNC_BIN" -a --partial --partial-dir='.cygentig-rsync-partial' --exclude='.cygentig-rsync-partial/' --no-inc-recursive --info=progress2 --outbuf=U --stats "$src/" "$dst" > "$progress_pipe" 2>> "$LOG_FILE" &
  else
    "$RSYNC_BIN" -aE --partial --partial-dir='.cygentig-rsync-partial' --exclude='.cygentig-rsync-partial/' --stats "$src/" "$dst" >> "$LOG_FILE" 2>&1 &
  fi
  local child=$!
  print -r -- "$child" >| "$CHILD_PID_FILE"
  wait "$child"
  local code=$?
  rm -f "$CHILD_PID_FILE"
  if (( RSYNC3 )); then
    wait "$parser" 2>/dev/null || true
    rm -f "$progress_pipe"
  fi
  (( code == 0 )) || { set_status copy_interrupted "Copy interrupted [$index/$total]: $name; it can be resumed" "$index" "$total" "$name"; log "rsync exit code: $code"; return "$code"; }
  touch "$done_marker"
  log "Copy complete: $name"
}

total=${#NORMALIZED_SOURCES[@]}
index=0
if (( VERIFY_ONLY )); then
  for source_path in "${NORMALIZED_SOURCES[@]}"; do
    (( index++ ))
    verify_job "$source_path" "$index" "$total" || exit $?
  done
  set_status all_verified "All $total folders passed content verification." "$total"
  exit 0
fi

for source_path in "${NORMALIZED_SOURCES[@]}"; do
  (( index++ ))
  copy_job "$source_path" "$index" "$total" || exit $?
done
set_status all_copied "All $total folders copied. Content verification is available." "$total"
exit 0
