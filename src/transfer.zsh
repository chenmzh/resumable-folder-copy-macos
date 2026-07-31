#!/bin/zsh

set -u
unsetopt BG_NICE

DEST_ROOT=""
VERIFY_ONLY=0
PREFLIGHT_ONLY=0
PREFLIGHT_FIRST=0
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
    --preflight-only)
      PREFLIGHT_ONLY=1
      shift
      ;;
    --preflight-first)
      PREFLIGHT_FIRST=1
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
PREFLIGHT_CODE_FILE="$STATE_ROOT/preflight-code.txt"
PREFLIGHT_VALUES_FILE="$STATE_ROOT/preflight-values.txt"
PREFLIGHT_CONFIG_FILE="$STATE_ROOT/preflight-config.txt"
SKIPPED_FILE="$STATE_ROOT/skipped-unreadable-files.txt"
SKIPPED_DIRECTORY_FILE="$STATE_ROOT/skipped-unreadable-directories.txt"
SKIPPED_HISTORY_FILE="$STATE_ROOT/skipped-unreadable-history.log"

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

source_key() {
  print -rn -- "$1" | /usr/bin/shasum -a 256 | /usr/bin/awk '{print substr($1,1,16)}'
}

record_skipped_item() {
  local kind="$1" item_path="$2"
  if [[ ! -f "$SKIPPED_FILE" ]] || ! /usr/bin/grep -Fqx "$item_path" "$SKIPPED_FILE" 2>/dev/null; then
    print -r -- "$item_path" >> "$SKIPPED_FILE"
    if [[ "$kind" == directory ]]; then print -r -- "$item_path" >> "$SKIPPED_DIRECTORY_FILE"; fi
    print -r -- "[$(timestamp)] [$kind] $item_path" >> "$SKIPPED_HISTORY_FILE"
    log "Skipped unreadable $kind: $item_path"
  fi
}

exclusion_pattern() {
  local src="$1" item_path="$2" kind="$3"
  local relative="${item_path:${#src}+1}"
  local escaped="$(print -rn -- "$relative" | /usr/bin/sed 's/[][?*\\]/\\&/g')"
  if [[ "$kind" == directory ]]; then print -r -- "/$escaped/"; else print -r -- "/$escaped"; fi
}

write_preflight_config() {
  : >| "$PREFLIGHT_CONFIG_FILE"
  print -r -- "$DEST_ROOT" >> "$PREFLIGHT_CONFIG_FILE"
  local source_path
  for source_path in "${NORMALIZED_SOURCES[@]}"; do print -r -- "$source_path" >> "$PREFLIGHT_CONFIG_FILE"; done
}

write_preflight_result() {
  local code="$1" required="$2" available="$3" reserve="$4" transfer="$5"
  print -r -- "$code" >| "$PREFLIGHT_CODE_FILE"
  {
    print -r -- "$required"
    print -r -- "$available"
    print -r -- "$reserve"
    print -r -- "$transfer"
  } >| "$PREFLIGHT_VALUES_FILE"
}

run_preflight_attempt() {
  local src="$1" dst="$2" listing="$3" error_file="$4"
  shift 4
  local -a exclusions=("$@")
  "$RSYNC_BIN" -an --partial --partial-dir='.cygentig-rsync-partial' \
    --exclude='.cygentig-rsync-partial/' --itemize-changes --out-format='%i|%l|%n' \
    "${exclusions[@]}" "$src/" "$dst/" >| "$listing" 2>| "$error_file" &
  local child=$!
  print -r -- "$child" >| "$CHILD_PID_FILE"
  wait "$child"
  local result=$?
  rm -f "$CHILD_PID_FILE"
  [[ ! -s "$error_file" ]] || /bin/cat "$error_file" >> "$LOG_FILE"
  return "$result"
}

preflight_all() {
  local total=${#NORMALIZED_SOURCES[@]} index=0
  local cumulative_delta=0 required_peak=0 total_transfer=0
  local listing="$STATE_ROOT/preflight-listing.$$.txt"
  rm -f "$PREFLIGHT_VALUES_FILE"
  print -r -- "checking" >| "$PREFLIGHT_CODE_FILE"
  write_preflight_config

  local src name dst key done_marker change length relative target old_size temp_peak
  local error_file denied_file exclude_file skip_marker denied pattern
  local result attempts new_directories source_skipped
  local -a exclusions
  for src in "${NORMALIZED_SOURCES[@]}"; do
    (( index++ ))
    name="${src:t}"
    dst="$DEST_ROOT/$name"
    key="$(source_key "$src")"
    done_marker="$STATE_ROOT/${name}.${key}.copy-complete"
    [[ -f "$done_marker" ]] && continue
    error_file="$STATE_ROOT/${name}.${key}.preflight-errors.txt"
    denied_file="$STATE_ROOT/${name}.${key}.unreadable-directories.txt"
    exclude_file="$STATE_ROOT/${name}.${key}.unreadable-excludes.txt"
    skip_marker="$STATE_ROOT/${name}.${key}.unreadable-source-skip"
    rm -f "$skip_marker"
    : >| "$exclude_file"
    exclusions=()
    set_status preflight_scanning "Checking disk space [$index/$total]: $name" "$index" "$total" "$name"
    mkdir -p "$dst"
    attempts=0
    source_skipped=0
    result=1
    while (( attempts < 100 )); do
      (( attempts++ ))
      run_preflight_attempt "$src" "$dst" "$listing" "$error_file" "${exclusions[@]}"
      result=$?
      (( result == 0 )) && break
      if (( result == 23 )); then
        /usr/bin/sed -n \
          -e 's/^rsync: .*readdir("\(.*\)"): Permission denied (13)$/\1/p' \
          -e 's/^rsync: .*opendir "\(.*\)" failed: Permission denied (13)$/\1/p' \
          -e 's/^rsync: .*change_dir "\(.*\)" failed: Permission denied (13)$/\1/p' \
          "$error_file" >| "$denied_file"
        new_directories=0
        while IFS= read -r denied; do
          denied="${denied%/.}"
          denied="${denied%/}"
          [[ "$denied" == "$src" || "$denied" == "$src/"* ]] || continue
          if [[ "$denied" == "$src" ]]; then
            record_skipped_item directory "$denied"
            touch "$skip_marker"
            source_skipped=1
            break
          fi
          pattern="$(exclusion_pattern "$src" "$denied" directory)"
          if ! /usr/bin/grep -Fqx "$pattern" "$exclude_file" 2>/dev/null; then
            print -r -- "$pattern" >> "$exclude_file"
            exclusions+=("--exclude=$pattern")
            record_skipped_item directory "$denied"
            (( new_directories++ ))
          fi
        done < "$denied_file"
        (( source_skipped )) && break
        (( new_directories > 0 )) && continue
      fi
      rm -f "$listing"
      write_preflight_result error 0 0 0 0
      set_status preflight_error "Disk space check failed: $name (see log)" "$name"
      return "$result"
    done
    if (( source_skipped )); then
      set_status preflight_directory_skipped "Unreadable folder skipped during space check [$index/$total]: $name" "$index" "$total" "$name"
      continue
    fi
    if (( result != 0 )); then
      rm -f "$listing"
      write_preflight_result error 0 0 0 0
      set_status preflight_error "Disk space check failed after repeated retries: $name (see log)" "$name"
      return "$result"
    fi

    while IFS='|' read -r change length relative; do
      [[ "$change" == '>f'* ]] || continue
      [[ "$length" == <-> ]] || continue
      target="$dst/$relative"
      old_size=0
      if [[ -f "$target" ]]; then old_size="$(/usr/bin/stat -f '%z' "$target" 2>/dev/null || print 0)"; fi
      (( temp_peak = cumulative_delta + length ))
      (( temp_peak > required_peak )) && required_peak=$temp_peak
      (( cumulative_delta += length - old_size ))
      (( total_transfer += length ))
    done < "$listing"
  done
  rm -f "$listing"

  local available reserve five_gib=5368709120
  available="$(/bin/df -Pk "$DEST_ROOT" 2>/dev/null | /usr/bin/awk 'NR == 2 {printf "%.0f", $4 * 1024}')"
  if [[ "$available" != <-> ]]; then
    write_preflight_result error "$required_peak" 0 0 "$total_transfer"
    set_status preflight_error "Could not read available disk space (see log)" "$DEST_ROOT"
    return 1
  fi
  (( reserve = required_peak / 20 ))
  (( reserve < five_gib )) && reserve=$five_gib
  (( required_peak == 0 )) && reserve=0

  if (( required_peak > available )); then
    write_preflight_result insufficient "$required_peak" "$available" "$reserve" "$total_transfer"
    set_status preflight_insufficient "Not enough disk space." "$required_peak" "$available" "$reserve"
    return 4
  elif (( required_peak + reserve > available )); then
    write_preflight_result warning "$required_peak" "$available" "$reserve" "$total_transfer"
    set_status preflight_warning "Enough space to copy, but below the recommended safety margin." "$required_peak" "$available" "$reserve"
    return 0
  fi
  write_preflight_result ok "$required_peak" "$available" "$reserve" "$total_transfer"
  set_status preflight_ok "Disk space check passed." "$required_peak" "$available" "$reserve"
  return 0
}

verify_job() {
  local src="$1" index="$2" total="$3"
  local name="${src:t}" dst="$DEST_ROOT/${src:t}/"
  local key="$(source_key "$src")"
  local audit="$STATE_ROOT/${name}.${key}.checksum-audit.txt"
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

run_copy_attempt() {
  local src="$1" dst="$2" error_file="$3"
  shift 3
  local -a exclusions=("$@")
  local child code parser progress_pipe
  rm -f "$PROGRESS_FILE"
  if (( RSYNC3 )); then
    progress_pipe="$STATE_ROOT/progress.fifo"
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
    parser=$!
    "$RSYNC_BIN" -a --partial --partial-dir='.cygentig-rsync-partial' \
      --exclude='.cygentig-rsync-partial/' --no-inc-recursive --info=progress2 \
      --outbuf=U --stats "${exclusions[@]}" "$src/" "$dst" > "$progress_pipe" 2>| "$error_file" &
  else
    "$RSYNC_BIN" -aE --partial --partial-dir='.cygentig-rsync-partial' \
      --exclude='.cygentig-rsync-partial/' --stats "${exclusions[@]}" \
      "$src/" "$dst" >> "$LOG_FILE" 2>| "$error_file" &
  fi
  child=$!
  print -r -- "$child" >| "$CHILD_PID_FILE"
  wait "$child"
  code=$?
  rm -f "$CHILD_PID_FILE"
  if (( RSYNC3 )); then
    wait "$parser" 2>/dev/null || true
    rm -f "$progress_pipe"
  fi
  [[ ! -s "$error_file" ]] || /bin/cat "$error_file" >> "$LOG_FILE"
  return "$code"
}

copy_job() {
  local src="$1" index="$2" total="$3"
  local name="${src:t}" dst="$DEST_ROOT/${src:t}/"
  local key="$(source_key "$src")"
  local done_marker="$STATE_ROOT/${name}.${key}.copy-complete"
  local error_file="$STATE_ROOT/${name}.${key}.rsync-errors.txt"
  local denied_file="$STATE_ROOT/${name}.${key}.permission-denied.txt"
  local exclude_file="$STATE_ROOT/${name}.${key}.unreadable-excludes.txt"
  local skip_marker="$STATE_ROOT/${name}.${key}.unreadable-source-skip"
  if [[ -f "$done_marker" ]]; then
    set_status completed_skip "Already complete, skipped [$index/$total]: $name" "$index" "$total" "$name"
    return 0
  fi
  if [[ -f "$skip_marker" ]]; then
    set_status directory_skipped "Unreadable folder skipped [$index/$total]: $name" "$index" "$total" "$name"
    log "Continuing after unreadable source folder: $src"
    return 0
  fi
  mkdir -p "$dst"
  set_status copying "Copying [$index/$total]: $name" "$index" "$total" "$name"
  log "Starting/resuming $src/ -> $dst (rsync: $RSYNC_BIN)"
  local code=1 denied pattern item_kind skipped_count=0 new_skips attempts=0 source_skipped=0
  local -a exclusions=()
  if [[ -f "$exclude_file" ]]; then
    while IFS= read -r pattern; do
      [[ -n "$pattern" ]] || continue
      exclusions+=("--exclude=$pattern")
      (( skipped_count++ ))
    done < "$exclude_file"
  fi

  while (( attempts < 100 )); do
    (( attempts++ ))
    run_copy_attempt "$src" "$dst" "$error_file" "${exclusions[@]}"
    code=$?
    (( code == 0 )) && break
    (( code == 23 )) || break
    /usr/bin/sed -n \
      -e 's/^rsync: .*send_files failed to open "\(.*\)": Permission denied (13)$/\1/p' \
      -e 's/^rsync: .*readdir("\(.*\)"): Permission denied (13)$/\1/p' \
      -e 's/^rsync: .*opendir "\(.*\)" failed: Permission denied (13)$/\1/p' \
      -e 's/^rsync: .*change_dir "\(.*\)" failed: Permission denied (13)$/\1/p' \
      "$error_file" >| "$denied_file"
    new_skips=0
    while IFS= read -r denied; do
      denied="${denied%/.}"
      denied="${denied%/}"
      [[ "$denied" == "$src" || "$denied" == "$src/"* ]] || continue
      item_kind=file
      [[ -d "$denied" ]] && item_kind=directory
      if [[ "$denied" == "$src" ]]; then
        record_skipped_item directory "$denied"
        touch "$skip_marker"
        source_skipped=1
        break
      fi
      pattern="$(exclusion_pattern "$src" "$denied" "$item_kind")"
      if [[ ! -f "$exclude_file" ]] || ! /usr/bin/grep -Fqx "$pattern" "$exclude_file" 2>/dev/null; then
        print -r -- "$pattern" >> "$exclude_file"
        exclusions+=("--exclude=$pattern")
        record_skipped_item "$item_kind" "$denied"
        (( skipped_count++ ))
        (( new_skips++ ))
      fi
    done < "$denied_file"
    if (( source_skipped )); then
      set_status directory_skipped "Unreadable folder skipped [$index/$total]: $name" "$index" "$total" "$name"
      log "Continuing after unreadable source folder: $src"
      return 0
    fi
    (( new_skips > 0 )) || break
    set_status retrying_unreadable "Retrying [$index/$total]: $name; skipping $skipped_count unreadable item(s)" "$index" "$total" "$name" "$skipped_count"
    log "Retrying with $skipped_count unreadable item(s) excluded."
  done

  (( code == 0 )) || { set_status copy_interrupted "Copy interrupted [$index/$total]: $name; it can be resumed" "$index" "$total" "$name"; log "rsync exit code: $code"; return "$code"; }
  if (( skipped_count > 0 )); then
    set_status copied_with_skips "Copied [$index/$total]: $name; skipped $skipped_count unreadable item(s)" "$index" "$total" "$name" "$skipped_count"
    log "Copy completed with $skipped_count unreadable item(s) skipped: $name"
    return 0
  fi
  touch "$done_marker"
  log "Copy complete: $name"
}

total=${#NORMALIZED_SOURCES[@]}
index=0
if (( ! VERIFY_ONLY )); then
  : >| "$SKIPPED_FILE"
  : >| "$SKIPPED_DIRECTORY_FILE"
fi
if (( PREFLIGHT_ONLY )); then
  preflight_all
  exit $?
fi

if (( VERIFY_ONLY )); then
  for source_path in "${NORMALIZED_SOURCES[@]}"; do
    (( index++ ))
    verify_job "$source_path" "$index" "$total" || exit $?
  done
  set_status all_verified "All $total folders passed content verification." "$total"
  exit 0
fi

if (( PREFLIGHT_FIRST )); then
  preflight_all || exit $?
fi

for source_path in "${NORMALIZED_SOURCES[@]}"; do
  (( index++ ))
  copy_job "$source_path" "$index" "$total" || exit $?
done
skipped_total="$(/usr/bin/awk 'END {print NR + 0}' "$SKIPPED_FILE")"
if (( skipped_total > 0 )); then
  set_status all_copied_with_skips "All $total folders processed; $skipped_total unreadable item(s) skipped." "$total" "$skipped_total"
else
  set_status all_copied "All $total folders copied. Content verification is available." "$total"
fi
exit 0
