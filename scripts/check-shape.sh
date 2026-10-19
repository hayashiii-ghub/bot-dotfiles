#!/bin/bash
# 形の検査: 個人のパス・メール・具体的なディスプレイ番号・日付つきの記録が入っていないか
# 使い方: scripts/check-shape.sh            リポジトリの全ファイル (追跡中 + 無視していない新しいもの)
#         scripts/check-shape.sh --staged   コミットしようとしている中身
#         scripts/check-shape.sh -- FILE... 指定したファイル
# 見つけた行の中身は表示しない (ファイル名・行番号・ルール名だけ)
set -u
cd "$(dirname "$0")/.." || exit 1
RULES=(
  'home-path|/home/[A-Za-z0-9._-]+'
  'display-number|DISPLAY=["'"'"']?:[0-9]|(BOT_DISPLAY|KEEPER_DISPLAYS)=["'"'"']?:?[0-9]'
  'email|[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}'
  'dated-record|(19|20)[0-9]{2}-[0-9]{2}-[0-9]{2}|[0-9][^[:space:]]{0,12}時点'
)
# このファイルはルールそのものを書いているので見ない
SELF=scripts/check-shape.sh

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
files=() labels=()
case ${1:-} in
  --staged)
    while IFS= read -r -d '' f; do
      [ "$f" = "$SELF" ] && continue
      out=$tmp/${#files[@]}
      git show ":$f" >"$out" 2>/dev/null || continue
      files+=("$out") labels+=("$f")
    done < <(git diff --cached --name-only -z --diff-filter=ACMR) ;;
  --)
    shift
    for f in "$@"; do files+=("$f") labels+=("$f"); done ;;
  '')
    while IFS= read -r -d '' f; do
      [ "$f" = "$SELF" ] && continue
      [ -f "$f" ] || continue
      files+=("$f") labels+=("$f")
    done < <(git ls-files -z -co --exclude-standard) ;;
  *) sed -n '2,6p' "$0"; exit 2 ;;
esac

bad=0
for i in "${!files[@]}"; do
  f=${files[$i]}
  [ ! -s "$f" ] || grep -Iq '' "$f" || continue
  for r in "${RULES[@]}"; do
    name=${r%%|*} re=${r#*|}
    while IFS=: read -r n _; do
      [ -n "$n" ] || continue
      # GitHub の noreply アドレスと git@ の clone URL は公開してよい
      if [ "$name" = email ] && sed -n "${n}p" "$f" | grep -Eo '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+' | grep -v -e '@users\.noreply\.github\.com$' -e '^git@' | grep -q .; then :
      elif [ "$name" = email ]; then continue; fi
      echo "${labels[$i]}:$n: $name"
      bad=1
    done < <(grep -nE -- "$re" "$f")
  done
done
[ "$bad" = 0 ] && echo "check-shape: OK (${#files[@]} ファイル)"
exit "$bad"
