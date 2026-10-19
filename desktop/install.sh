#!/bin/bash
# desktop/: 壁紙・desktop-look・desktop-setup・wallpaper-keeper(-all) と、それが使う X のツールを入れる
# 既定は表示だけ。--apply で書く。$HOME の外 (apt) は --apply かつ NO_APT が無いときだけ
set -u
cd "$(dirname "$0")/.." || exit 1
# shellcheck disable=SC2034  # desktop.sh が使う
BOT_ME=desktop/install.sh
# shellcheck source=desktop/lib/desktop.sh
. desktop/lib/desktop.sh
bd_init "$@"
bd_mode_banner desktop
bd_load_config desktop/config.env
bd_lock
bd_sync_look
bd_read_manifest
bd_apply_rows prefix:desktop-

# hsetroot / xdotool / xprop / xdpyinfo / xrefresh / wmctrl: 無ければ apt-get、
# バイナリ + 共有ライブラリを ~/.local/lib/bot-tools に保存し ~/.local/bin にラッパー (別のファイルがあれば上書きしない)
bot_ensure_tools hsetroot xdotool xprop xdpyinfo xrefresh wmctrl ||
  bd_warn "一部の X のツールが使えません (上のメッセージを見てください)"

case ":$BD_ORIG_PATH:" in *":$HOME/.local/bin:"*) ;; *) bd_say "PATH に ~/.local/bin を足してください" ;; esac
bd_summary desktop || exit 1
[ "$BD_APPLY" = 1 ] && bd_say "次は: DISPLAY=:N desktop-setup (見た目だけなら desktop-look)"
exit 0
