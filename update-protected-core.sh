#!/bin/bash
# update-protected-core.sh — 保護コピー（最後に照合済みの核ファイル）の更新
#
# 役割：核ファイル8点の「照合済みの最新状態」を protected-core/ に単一の写しとして
#   保持する。世代分けはしない（世代は generations/ の役目）。
#   核ファイルの復旧は、この保護コピーを正として行う。
# 実行してよい時（重要）：核ファイルを意図的に編集し、オーナーと内容を確認できた時だけ。
#   未照合の状態を「照合済み」にしないため、それ以外では実行しない。
# 使い方：update-protected-core.sh [source_dir]
#   source_dir を省略するとライブファイル（$CORE_LIVE_DIR）から写す。
#   特定の世代から写す場合は、その8点を揃えたディレクトリを指定する。
# 動作：対象8点を一時領域で組み立ててチェックサムを検証してから、
#   protected-core の中身を入れ替え、SHA256SUMS.txt を作り直し、
#   ファイルを読み取り専用（444）にする。
# 終了コード：0=成功（最終行に "OK ..."）、1=失敗
# 環境変数で上書き可能：
#   CORE_LIVE_DIR    ライブファイルのある場所（既定 $HOME）
#   CORE_RESTORE_DIR 保存先の親（既定 $CORE_LIVE_DIR/workspace/restore）
set -u
HOME_DIR="${CORE_LIVE_DIR:-$HOME}"
RESTORE_DIR="${CORE_RESTORE_DIR:-$HOME_DIR/workspace/restore}"
TARGET="$RESTORE_DIR/protected-core"
SRC="${1:-$HOME_DIR}"

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

TMP=$(mktemp -d) || fail "mktemp"
trap 'rm -rf "$TMP"' EXIT

for f in "${FILES[@]}"; do
  [ -f "$SRC/$f" ] || fail "source missing: $SRC/$f"
  cp -a "$SRC/$f" "$TMP/$f" || fail "copy $f"
done
( cd "$TMP" && sha256sum "${FILES[@]}" > SHA256SUMS.txt ) || fail "sums"
( cd "$TMP" && sha256sum -c SHA256SUMS.txt >/dev/null ) || fail "verify staged"

mkdir -p "$TARGET" || fail "mkdir target"
chmod -R u+w "$TARGET" 2>/dev/null || true
find "$TARGET" -mindepth 1 -delete || fail "clear target"
for f in "${FILES[@]}"; do
  cp -a "$TMP/$f" "$TARGET/$f" || fail "install $f"
done
cp -a "$TMP/SHA256SUMS.txt" "$TARGET/SHA256SUMS.txt" || fail "install sums"
chmod 444 "$TARGET"/*.md "$TARGET/SHA256SUMS.txt" || fail "chmod"

( cd "$TARGET" && sha256sum -c SHA256SUMS.txt >/dev/null ) || fail "verify installed"
echo "OK protected-core updated $(date '+%Y-%m-%d %H:%M') from $SRC"
exit 0
