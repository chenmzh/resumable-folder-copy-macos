#!/bin/zsh

set -u
unsetopt BG_NICE

DEST_ROOT=""
VERIFY_ONLY=0
SOURCES=()

while (( $# > 0 )); do
  case "$1" in
    --destination)
      [[ $# -ge 2 ]] || { print -u2 -- "--destination 缺少路径"; exit 2; }
      DEST_ROOT="$2"
      shift 2
      ;;
    --source)
      [[ $# -ge 2 ]] || { print -u2 -- "--source 缺少路径"; exit 2; }
      SOURCES+=("$2")
      shift 2
      ;;
    --verify-only)
      VERIFY_ONLY=1
      shift
      ;;
    *)
      print -u2 -- "未知参数：$1"
      exit 2
      ;;
  esac
done

[[ -n "$DEST_ROOT" && ${#SOURCES[@]} -gt 0 ]] || { print -u2 -- "必须指定目标目录和至少一个源目录"; exit 2; }
DEST_ROOT="${DEST_ROOT:A}"
STATE_ROOT="$DEST_ROOT/.cygentig-transfer"
LOG_FILE="$STATE_ROOT/transfer.log"
STATUS_FILE="$STATE_ROOT/status.txt"
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
status() { print -r -- "$*" >| "$STATUS_FILE"; log "$*"; }

if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  if [[ -f "$PID_FILE" ]] && /bin/kill -0 "$(<"$PID_FILE")" 2>/dev/null; then
    log "已有传输任务在运行，忽略重复启动。"
    exit 0
  fi
  rmdir "$LOCK_DIR" 2>/dev/null || true
  mkdir "$LOCK_DIR" 2>/dev/null || { status "无法取得任务锁，请查看日志"; exit 1; }
fi

print -r -- "$$" >| "$PID_FILE"
cleanup() {
  rm -f "$PID_FILE" "$CHILD_PID_FILE" "$STATE_ROOT/progress.fifo"
  rmdir "$LOCK_DIR" 2>/dev/null || true
}
stop_worker() {
  status "已暂停；未完成文件已保留，可继续"
  if [[ -f "$CHILD_PID_FILE" ]]; then
    /bin/kill -TERM "$(<"$CHILD_PID_FILE")" 2>/dev/null || true
    /bin/sleep 1
  fi
  exit 130
}
trap cleanup EXIT
trap stop_worker INT TERM HUP

[[ -d "$DEST_ROOT" ]] || { status "目标目录不可用：$DEST_ROOT"; exit 2; }

typeset -A SEEN_NAMES
NORMALIZED_SOURCES=()
for raw_source in "${SOURCES[@]}"; do
  source_path="${raw_source:A}"
  [[ -d "$source_path" ]] || { status "源目录不可用：$source_path"; exit 2; }
  name="${source_path:t}"
  key="${name:l}"
  [[ -z "${SEEN_NAMES[$key]:-}" ]] || { status "存在同名源目录：$name"; exit 2; }
  SEEN_NAMES[$key]=1
  target="$DEST_ROOT/$name"
  if [[ "$target" == "$source_path" || "$target" == "$source_path"/* ]]; then
    status "目标位于源目录内部，已拒绝：$source_path"
    exit 2
  fi
  NORMALIZED_SOURCES+=("$source_path")
done

verify_job() {
  local src="$1" index="$2" total="$3"
  local name="${src:t}" dst="$DEST_ROOT/${src:t}/"
  local source_key="$(print -rn -- "$src" | /usr/bin/shasum -a 256 | /usr/bin/awk '{print substr($1,1,16)}')"
  local audit="$STATE_ROOT/${name}.${source_key}.checksum-audit.txt"
  status "慢速校验 [$index/$total]：$name"
  log "开始逐内容校验 $src/ -> $dst"
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
  (( code == 0 )) || { status "校验失败 [$index/$total]：$name（请查看日志）"; return "$code"; }
  [[ ! -s "$audit" ]] || { status "校验发现差异 [$index/$total]：$name"; log "差异详见 $audit"; return 3; }
  log "校验通过：$name"
}

copy_job() {
  local src="$1" index="$2" total="$3"
  local name="${src:t}" dst="$DEST_ROOT/${src:t}/"
  local source_key="$(print -rn -- "$src" | /usr/bin/shasum -a 256 | /usr/bin/awk '{print substr($1,1,16)}')"
  local done_marker="$STATE_ROOT/${name}.${source_key}.copy-complete"
  if [[ -f "$done_marker" ]]; then
    status "已完成，跳过 [$index/$total]：$name"
    return 0
  fi
  mkdir -p "$dst"
  rm -f "$PROGRESS_FILE"
  status "复制中 [$index/$total]：$name"
  log "开始/继续 $src/ -> $dst（rsync: $RSYNC_BIN）"
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
  (( code == 0 )) || { status "复制中断 [$index/$total]：$name；可再次继续"; log "rsync 退出码：$code"; return "$code"; }
  touch "$done_marker"
  log "复制完成：$name"
}

total=${#NORMALIZED_SOURCES[@]}
index=0
if (( VERIFY_ONLY )); then
  for source_path in "${NORMALIZED_SOURCES[@]}"; do
    (( index++ ))
    verify_job "$source_path" "$index" "$total" || exit $?
  done
  status "全部 $total 个目录均已通过逐内容校验"
  exit 0
fi

for source_path in "${NORMALIZED_SOURCES[@]}"; do
  (( index++ ))
  copy_job "$source_path" "$index" "$total" || exit $?
done
status "全部 $total 个目录复制完成；可运行慢速校验"
exit 0
