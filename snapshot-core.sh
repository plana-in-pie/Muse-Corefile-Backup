#!/bin/bash
# snapshot-core.sh — 核ファイルの世代スナップショット
#
# 役割：核ファイル（ホーム直下の8点）のハッシュが前回世代と変わっていた時だけ、
#   世代フォルダへ写しを保存する。背景の記憶整理や会話の圧縮で MEMORY.md が
#   短縮・消失しても、直前の世代から zip 解凍なしで戻せるようにするための対策。
# 保存先：$CORE_RESTORE_DIR/generations/<YYYYMMDD-HHMMSS>/
# 保持：直近 KEEP 世代（既定96）。変化がなければ何もしない。
# 出力（最終行）：
#   NOCHANGE
#   CREATED <dir>
#   SHRINK <dir> <old_lines>-><new_lines>   … MEMORY.md が前回世代より3行以上減った（消失の疑い）
#   FAILED <reason>
# 終了コード：0=正常、1=失敗
# 環境変数で上書き可能：
#   CORE_LIVE_DIR    ライブファイルのある場所（既定 $HOME）
#   CORE_RESTORE_DIR 保存先の親（既定 $CORE_LIVE_DIR/workspace/restore）
#   CORE_KEEP        保持する世代数（既定 96）
set -u
HOME_DIR="${CORE_LIVE_DIR:-$HOME}"
RESTORE_DIR="${CORE_RESTORE_DIR:-$HOME_DIR/workspace/restore}"
BASE="$RESTORE_DIR/generations"
STATE="$BASE/state.txt"
KEEP="${CORE_KEEP:-96}"

FILES=(
  "MEMORY.md"
  "SOUL.md"
  "AGENTS.md"
  "IDENTITY.md"
  "USER.md"
  "TOOLS.md"
  "PROACTIVE_PREFERENCES.md"
  "HEARTBEAT.md"
)

mkdir -p "$BASE" || { echo "FAILED mkdir $BASE"; exit 1; }

# 現在のハッシュ一覧
CUR=$(mktemp)
trap 'rm -f "$CUR"' EXIT
for f in "${FILES[@]}"; do
  if [ -f "$HOME_DIR/$f" ]; then
    h=$(sha256sum "$HOME_DIR/$f" | awk '{print $1}')
    echo "$h  $f" >> "$CUR"
  fi
done

# 前回と比較
if [ -f "$STATE" ] && cmp -s "$STATE" "$CUR"; then
  echo "NOCHANGE"
  exit 0
fi

# 前回世代の MEMORY 行数（SHRINK 判定用）
OLD_LINES=0
if [ -f "$STATE" ]; then
  LAST_DIR=$(ls -1d "$BASE"/2* 2>/dev/null | tail -1 || true)
  if [ -n "${LAST_DIR:-}" ] && [ -f "$LAST_DIR/MEMORY.md" ]; then
    OLD_LINES=$(wc -l < "$LAST_DIR/MEMORY.md")
  fi
fi

STAMP=$(date +%Y%m%d-%H%M%S)
DIR="$BASE/$STAMP"
mkdir -p "$DIR" || { echo "FAILED mkdir $DIR"; exit 1; }
for f in "${FILES[@]}"; do
  if [ -f "$HOME_DIR/$f" ]; then
    cp -a "$HOME_DIR/$f" "$DIR/$f" || { echo "FAILED copy $f"; exit 1; }
  fi
done
cp "$CUR" "$DIR/SHA256SUMS.txt"
cp "$CUR" "$STATE"

NEW_LINES=$(wc -l < "$HOME_DIR/MEMORY.md")

# 保持：直近 KEEP 世代だけ残す
ls -1d "$BASE"/2* 2>/dev/null | sort | head -n -$KEEP | while read -r d; do rm -rf "$d"; done

if [ "$OLD_LINES" -gt 0 ] && [ "$NEW_LINES" -lt $((OLD_LINES - 2)) ]; then
  echo "SHRINK $DIR $OLD_LINES->$NEW_LINES"
else
  echo "CREATED $DIR"
fi
exit 0
