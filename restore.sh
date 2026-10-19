#!/bin/bash
# install で退避したものに戻す
# 使い方: ./restore.sh --list            退避の一覧
#         ./restore.sh <日時> [--apply]   その回の前の状態に戻す (既定は差分の表示だけ)
# 戻すときも、今の状態を新しい日時で退避するので、戻したことを戻せる
set -u
cd "$(dirname "$0")" || exit 1
BD_ME=restore.sh
# shellcheck source=lib/common.sh
. lib/common.sh
bd_init "$@"
set -- "${BD_REST[@]}"

case ${1:-} in
  --list)
    [ -d "$BD_BACKUP_ROOT" ] || { bd_say "退避はまだありません ($BD_BACKUP_ROOT)"; exit 0; }
    found=0
    for d in "$BD_BACKUP_ROOT"/*/; do
      [ -d "$d" ] || continue
      found=1
      ts=$(basename "$d")
      nf=$(find "$d/home" \( -type f -o -type l \) 2>/dev/null | wc -l)
      nc=0 nx=0
      [ -r "$d/created.txt" ] && nc=$(wc -l <"$d/created.txt")
      [ -r "$d/xfconf.tsv" ] && nx=$(wc -l <"$d/xfconf.tsv")
      echo "$ts  ファイル $nf / 新しく作ったもの $nc / xfconf $nx"
    done
    [ "$found" = 1 ] || bd_say "退避はまだありません ($BD_BACKUP_ROOT)"
    exit 0 ;;
  ''|-h|--help) sed -n '2,5p' "$0"; exit 0 ;;
esac
ts=$1
case $ts in */*|.*) bd_die "日時の形がおかしい: $ts" ;; esac
src=$BD_BACKUP_ROOT/$ts
[ -d "$src" ] || bd_die "$src がありません (./restore.sh --list で確かめてください)"
bd_mode_banner "restore $ts"
bd_lock

# 1) 退避したファイルを戻す
if [ -d "$src/home" ]; then
  while IFS= read -r -d '' f; do
    rel=${f#"$src/home/"}
    if [ -L "$f" ]; then
      dst=$HOME/$rel
      if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$(readlink "$f")" ]; then
        bd_say "変更なし: ~/$rel"; BD_N_SAME=$((BD_N_SAME + 1)); continue
      fi
      bd_say "変更あり: ~/$rel (リンク → $(readlink "$f"))"
      BD_N_CHANGED=$((BD_N_CHANGED + 1))
      [ "$BD_APPLY" = 1 ] || continue
      bd_backup_file "$dst"
      mkdir -p "$(dirname "$dst")" && ln -sfn "$(readlink "$f")" "$dst"
      continue
    fi
    # shellcheck disable=SC2088  # 表示用のラベル
    bd_put "$f" "$HOME/$rel" "$(stat -c %a "$f")" "~/$rel" -
  done < <(find "$src/home" \( -type f -o -type l \) -print0 | sort -z)
fi

# 2) その回で新しく作ったファイルは消す
if [ -r "$src/created.txt" ]; then
  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    case /$rel/ in */../*) bd_warn "おかしなパスなのでとばします: $rel"; continue ;; esac
    dst=$HOME/$rel
    if [ ! -e "$dst" ] && [ ! -L "$dst" ]; then bd_say "変更なし: ~/$rel (もう無い)"; BD_N_SAME=$((BD_N_SAME + 1)); continue; fi
    bd_say "変更あり: ~/$rel を消す (この回で新しく作ったもの)"
    BD_N_CHANGED=$((BD_N_CHANGED + 1))
    [ "$BD_APPLY" = 1 ] || continue
    bd_backup_file "$dst"
    rm -f "$dst"
  done <"$src/created.txt"
fi

# 3) xfconf の値を戻す
if [ -r "$src/xfconf.tsv" ]; then
  if bd_xfconf_usable; then
    while IFS=$'\t' read -r ch prop type val; do
      if cur=$(xfconf-query -c "$ch" -p "$prop" 2>/dev/null); then had=1; else had=0 cur=; fi
      if { [ "$val" = __UNSET__ ] && [ "$had" = 0 ]; } || { [ "$had" = 1 ] && [ "$cur" = "$val" ]; }; then
        bd_say "変更なし: xfconf $ch $prop"; BD_N_SAME=$((BD_N_SAME + 1)); continue
      fi
      bd_say "変更あり: xfconf $ch $prop: ${cur:-(なし)} → $([ "$val" = __UNSET__ ] && echo '(なし)' || echo "$val")"
      BD_N_CHANGED=$((BD_N_CHANGED + 1))
      [ "$BD_APPLY" = 1 ] || continue
      bd_backup_dir
      if [ "$had" = 1 ]; then printf '%s\t%s\t%s\t%s\n' "$ch" "$prop" "$type" "$cur"
      else printf '%s\t%s\t%s\t%s\n' "$ch" "$prop" "$type" __UNSET__; fi >>"$BD_BACKUP_DIR/xfconf.tsv"
      if [ "$val" = __UNSET__ ]; then
        xfconf-query -c "$ch" -p "$prop" -r 2>/dev/null || { bd_warn "xfconf $ch $prop を消せませんでした"; BD_N_FAIL=$((BD_N_FAIL + 1)); }
      else
        xfconf-query -c "$ch" -p "$prop" -s "$val" 2>/dev/null ||
          xfconf-query -c "$ch" -p "$prop" -n -t "$type" -s "$val" 2>/dev/null ||
          { bd_warn "xfconf $ch $prop を書けませんでした"; BD_N_FAIL=$((BD_N_FAIL + 1)); }
      fi
    done <"$src/xfconf.tsv"
  else
    bd_warn "xfconf の値 ($(wc -l <"$src/xfconf.tsv") 件) は戻せていません"
  fi
fi

bd_summary "restore $ts"
