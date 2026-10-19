#!/bin/bash
# xfce → node → desktop の install.sh を順に実行し、$BOT_DOTFILES_LOCAL があれば非公開側の項目も反映する
# 使い方: ./install-all.sh [--apply] [--with playwright]
# 既定は表示だけ。DRY_RUN=1 なら --apply があっても書かない。途中で失敗しても続けて、最後にまとめを出す
set -u
cd "$(dirname "$0")" || exit 1
BD_ME=install-all.sh
# shellcheck source=lib/common.sh
. lib/common.sh
bd_init "$@"
tools=(xfce node desktop)
set -- "${BD_REST[@]}"
while [ "$#" -gt 0 ]; do
  case $1 in
    --with)
      case ${2:-} in
        playwright) tools+=(optional/playwright) ;;
        *) bd_die "--with に使えるのは playwright だけです" ;;
      esac
      shift 2 ;;
    -h|--help) sed -n '2,4p' "$0"; exit 0 ;;
    *) bd_die "知らない引数: $1" ;;
  esac
done

bd_load_config
[ -n "${BOT_DOTFILES_LOCAL:-}" ] && export BOT_DOTFILES_LOCAL
# node/install.sh が入れた node / npm を、同じ回の playwright から使えるように
export PATH="$HOME/.local/bin:$PATH"
pass=()
[ "$BD_APPLY" = 1 ] && pass=(--apply)
# 全部の install.sh が1つのロックと1つの退避先を使う
bd_lock
bd_pick_backup_ts

ok=() ng=()
for t in "${tools[@]}"; do
  echo
  if bash "$t/install.sh" "${pass[@]}"; then ok+=("$t"); else ng+=("$t"); echo "!!! $t は失敗 (続けます)"; fi
done

if [ -n "${BOT_DOTFILES_LOCAL:-}" ]; then
  echo
  bd_mode_banner "非公開側 ($BOT_DOTFILES_LOCAL)"
  bd_read_manifest
  bd_apply_rows local-only
  if bd_summary local; then ok+=(local); else ng+=(local); fi
fi

echo
echo "=== まとめ"
echo "成功: ${ok[*]:-なし}"
echo "失敗: ${ng[*]:-なし}"
if [ "$BD_APPLY" = 1 ] && [ -d "$BD_BACKUP_ROOT/$BD_BACKUP_TS" ]; then
  echo "退避: $BD_BACKUP_ROOT/$BD_BACKUP_TS (戻すときは ./restore.sh $BD_BACKUP_TS)"
fi
[ "${#ng[@]}" -eq 0 ]
