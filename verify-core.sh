#!/bin/bash
# verify-core.sh — 核ファイルの照合
#
# 役割：
#   1. 保護コピー（最後に照合済みの状態の写し）自体が壊れていないかを SHA256 で確認する。
#   2. 現在のライブファイルが保護コピーと食い違うファイルを列挙する。
#      食い違い自体は異常とは限らない（意図した編集でも起きる）。
#      「説明できない消失・短縮があるか」を判断する材料として使う。
# 環境変数で上書き可能：
#   CORE_LIVE_DIR    ライブファイルのある場所（既定 $HOME）
#   CORE_RESTORE_DIR 保存先の親（既定 $CORE_LIVE_DIR/workspace/restore）
HOME_DIR="${CORE_LIVE_DIR:-$HOME}"
RESTORE_DIR="${CORE_RESTORE_DIR:-$HOME_DIR/workspace/restore}"
TARGET="$RESTORE_DIR/protected-core"

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

cd "$TARGET" || { echo "FAILED no protected-core at $TARGET"; exit 1; }
echo "== checksums (FAILED = protected copy damaged since last verified save) =="
sha256sum -c SHA256SUMS.txt 2>/dev/null | grep -v ': OK$' || echo "all protected copies intact"
echo "== live files vs protected copies (CHANGED = differs from last verified state) =="
for f in "${FILES[@]}"; do
  if ! cmp -s "$HOME_DIR/$f" "$TARGET/$f"; then echo "CHANGED: $f"; fi
done
echo "done"
