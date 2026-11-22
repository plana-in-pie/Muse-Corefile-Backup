#!/bin/bash
# restore-core.sh — 世代スナップショットからの復元（日付指定・相対指定対応）
#
# 使い方：
#   restore-core.sh list
#       世代の一覧（日時つき）を表示する。
#   restore-core.sh show <when>
#       <when> に対して選ばれる世代と、現行ファイルとの差分概要を表示する。書き込みはしない。
#   restore-core.sh apply <when> [file ...]
#       選ばれた世代から復元する。file を省略すると核ファイル8点すべて。
#       実行前に、現行ファイルを pre-restore-<日時>/ へ退避する。
#       対話環境では yes の入力が必要。エージェントが実行する場合は、
#       オーナーの承認を得た後にだけ RESTORE_CONFIRM=1 を付けて実行すること。
#
# <when> の書式：
#   3d            3日前（Nh で時間単位も可。例：12h）
#   2026-11-20    その日の最後の状態（その日の 23:59:59 以前で最新の世代）
#   "2026-11-20 15:00"  その時刻以前で最新の世代
#   20261120-215401     世代を直接指定
# 選択規則：指定時刻以前で最も新しい世代を選ぶ。指定より古い世代しかない場合は失敗する。
#
# 環境変数で上書き可能：
#   CORE_LIVE_DIR    ライブファイルのある場所（既定 $HOME）
#   CORE_RESTORE_DIR 保存先の親（既定 $CORE_LIVE_DIR/workspace/restore）
set -u
HOME_DIR="${CORE_LIVE_DIR:-$HOME}"
RESTORE_DIR="${CORE_RESTORE_DIR:-$HOME_DIR/workspace/restore}"
BASE="$RESTORE_DIR/generations"

FILES=(
  "AGENTS.md"
  "HEARTBEAT.md"
  "IDENTITY.md"
  "MEMORY.md"
  "PROACTIVE_PREFERENCES.md"
  "SOUL.md"
  "TOOLS.md"
  "USER.md"
)

fail() { echo "FAILED $1"; exit 1; }

list_generations() {
  ls -1d "$BASE"/[0-9]* 2>/dev/null | sort | while read -r d; do
    b=$(basename "$d")
    human=$(date -d "${b:0:4}-${b:4:2}-${b:6:2} ${b:9:2}:${b:11:2}:${b:13:2}" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "$b")
    echo "$b  $human"
  done
}

resolve_target_epoch() {
  local when="$1"
  if [[ "$when" =~ ^([0-9]+)d$ ]]; then
    date -d "${BASH_REMATCH[1]} days ago" +%s
  elif [[ "$when" =~ ^([0-9]+)h$ ]]; then
    date -d "${BASH_REMATCH[1]} hours ago" +%s
  elif [[ "$when" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
    date -d "$when 23:59:59" +%s
  elif [[ "$when" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}\ [0-9]{2}:[0-9]{2}(:[0-9]{2})?$ ]]; then
    date -d "$when" +%s
  else
    return 1
  fi
}

pick_generation() {
  local target_epoch="$1" best="" best_epoch=-1
  for d in "$BASE"/[0-9]*; do
    [ -d "$d" ] || continue
    local b=$(basename "$d")
    [[ "$b" =~ ^[0-9]{8}-[0-9]{6}$ ]] || continue
    local e
    e=$(date -d "${b:0:4}-${b:4:2}-${b:6:2} ${b:9:2}:${b:11:2}:${b:13:2}" +%s 2>/dev/null) || continue
    if [ "$e" -le "$target_epoch" ] && [ "$e" -gt "$best_epoch" ]; then
      best="$d"; best_epoch="$e"
    fi
  done
  [ -n "$best" ] || return 1
  echo "$best"
}

show_plan() {
  local gen="$1"; shift
  local targets=("$@")
  [ ${#targets[@]} -gt 0 ] || targets=("${FILES[@]}")
  echo "generation: $gen"
  for f in "${targets[@]}"; do
    if [ ! -f "$gen/$f" ]; then
      echo "  MISSING in generation (live file kept): $f"
    elif cmp -s "$gen/$f" "$HOME_DIR/$f"; then
      echo "  same: $f"
    else
      local gl ll
      gl=$(wc -l < "$gen/$f"); ll=$(wc -l < "$HOME_DIR/$f" 2>/dev/null || echo 0)
      echo "  DIFF: $f (generation ${gl} lines / live ${ll} lines)"
    fi
  done
}

CMD="${1:-}"
case "$CMD" in
  list)
    list_generations
    ;;
  show|apply)
    WHEN="${2:-}"
    [ -n "$WHEN" ] || fail "usage: restore-core.sh $CMD <when> [file ...]"
    shift 2
    if [[ "$WHEN" =~ ^[0-9]{8}-[0-9]{6}$ ]]; then
      GEN="$BASE/$WHEN"
      [ -d "$GEN" ] || fail "generation not found: $WHEN"
    else
      TARGET_EPOCH=$(resolve_target_epoch "$WHEN") || fail "cannot parse <when>: $WHEN"
      GEN=$(pick_generation "$TARGET_EPOCH") || fail "no generation at or before: $WHEN (oldest available: $(list_generations | head -1))"
    fi
    show_plan "$GEN" "$@"
    if [ "$CMD" = "show" ]; then
      echo "show only; nothing written"
      exit 0
    fi
    # apply
    if [ "${RESTORE_CONFIRM:-}" != "1" ]; then
      printf 'Restore the files above from this generation? Type yes: '
      read -r ans
      [ "$ans" = "yes" ] || { echo "aborted"; exit 1; }
    fi
    STAMP=$(date +%Y%m%d-%H%M%S)
    PRE="$RESTORE_DIR/pre-restore-$STAMP"
    mkdir -p "$PRE" || fail "mkdir $PRE"
    for f in "${FILES[@]}"; do
      [ -f "$HOME_DIR/$f" ] && cp -a "$HOME_DIR/$f" "$PRE/$f"
    done
    echo "current state saved to: $PRE"
    targets=("$@")
    [ ${#targets[@]} -gt 0 ] || targets=("${FILES[@]}")
    for f in "${targets[@]}"; do
      [ -f "$GEN/$f" ] || { echo "skipped (missing in generation): $f"; continue; }
      cp -a "$GEN/$f" "$HOME_DIR/$f" || fail "restore $f"
      cmp -s "$GEN/$f" "$HOME_DIR/$f" || fail "verify $f"
      echo "restored: $f"
    done
    echo "OK restored from $GEN"
    ;;
  *)
    echo "usage: restore-core.sh list | show <when> | apply <when> [file ...]" >&2
    exit 1
    ;;
esac
exit 0
