#!/bin/bash
# node/: Node.js (NODE_MAJOR 系) を ~/.local/node-v<版> に入れ、~/.local/bin に node / npm / npx のリンクを張る
# 既定は表示だけ (ダウンロードもしない)。--apply で入れる
set -u
cd "$(dirname "$0")/.." || exit 1
BD_ME=node/install.sh
# shellcheck source=lib/common.sh
. lib/common.sh
bd_init "$@"
bd_mode_banner node
bd_load_config node/config.env
MAJOR=${NODE_MAJOR:-24}
DEST=$HOME/.local/node-v$MAJOR BIN=$HOME/.local/bin
BASE=https://nodejs.org/dist/latest-v$MAJOR.x

# install-all は PATH を変えないこともあるので、入れる場所の node を先に見る
cur=$("$BIN/node" -v 2>/dev/null || node -v 2>/dev/null || true)
case $cur in
  "v$MAJOR".*) bd_say "変更なし: node $cur"; exit 0 ;;
esac
bd_say "変更あり: node ${cur:-なし} → Node $MAJOR を $DEST に入れる"
if [ "$BD_APPLY" != 1 ]; then
  bd_say "    (dry-run) $BASE から linux の tarball を取り、SHASUMS256.txt で確かめて展開、$BIN/{node,npm,npx} にリンク"
  exit 0
fi
bd_lock
work=$(mktemp -d); trap 'rm -rf "$work" "$BD_TMPDIR"' EXIT
curl -fsSL "$BASE/SHASUMS256.txt" -o "$work/SHASUMS256.txt" || bd_die "SHASUMS256.txt が取れません"
# xz が無いマシンもあるので、そのときは .tar.gz を使う
if command -v xz >/dev/null; then EXT=xz TARFLAG=J; else EXT=gz TARFLAG=z; fi
case $(uname -m) in
  x86_64) ARCH=x64 ;;
  aarch64|arm64) ARCH=arm64 ;;
  *) bd_die "この CPU ($(uname -m)) 向けの Node はこのスクリプトでは入れられません" ;;
esac
tarball=$(awk -v e="linux-$ARCH.tar.$EXT" '$2 ~ e"$" {print $2}' "$work/SHASUMS256.txt")
[ -n "$tarball" ] || bd_die "SHASUMS256.txt に linux-$ARCH が見つかりません"
curl -fSL "$BASE/$tarball" -o "$work/$tarball" || bd_die "$tarball が取れません"
(cd "$work" && grep " $tarball\$" SHASUMS256.txt | sha256sum -c -) || bd_die "チェックサムが合いません。やめます"
mkdir -p "$work/x" "$BIN"
tar -x"$TARFLAG"f "$work/$tarball" -C "$work/x" --strip-components=1 || bd_die "展開できません"
rm -rf "$DEST.new"; mv "$work/x" "$DEST.new"
[ -e "$DEST" ] && rm -rf "$DEST.old" && mv "$DEST" "$DEST.old"
mv "$DEST.new" "$DEST"; rm -rf "$DEST.old"
for b in node npm npx; do bd_backup_file "$BIN/$b"; ln -sfn "$DEST/bin/$b" "$BIN/$b"; done
bd_say "入れました: $("$BIN/node" -v)"
case ":$BD_ORIG_PATH:" in *":$BIN:"*) ;; *) bd_say "PATH の前のほうに $BIN を足してください" ;; esac
