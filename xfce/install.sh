#!/bin/bash
# xfce/: xfce4-terminal と Thunar の設定 (xfconf と terminalrc)、GTK のブックマーク
# 既定は表示だけ。--apply で書く
set -u
cd "$(dirname "$0")/.." || exit 1
BD_ME=xfce/install.sh
# shellcheck source=lib/common.sh
. lib/common.sh
bd_init "$@"
bd_mode_banner xfce
bd_load_config xfce/config.env

bd_lock
bd_sync_look
bd_derive_vars
bd_read_manifest
bd_apply_rows prefix:xfce-
bd_summary xfce || exit 1
[ "$BD_APPLY" = 1 ] && bd_say "新しく開いたターミナル / Thunar から反映されます"
exit 0
