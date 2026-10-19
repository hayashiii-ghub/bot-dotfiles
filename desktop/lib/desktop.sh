# shellcheck shell=bash
# desktop/lib/desktop.sh — desktop-setup / desktop-look / wallpaper-keeper(-all) と desktop/install.sh の共通処理
# install で ~/.local/lib/bot-dotfiles/desktop.sh に入り、同じフォルダの common.sh を読む

BOT_DESKTOP_LIBDIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
for _c in "$BOT_DESKTOP_LIBDIR/common.sh" "$BOT_DESKTOP_LIBDIR/../../lib/common.sh"; do
  # shellcheck source=lib/common.sh
  [ -r "$_c" ] && { . "$_c"; break; }
done
unset _c
command -v bd_load_config >/dev/null || { echo "${0##*/}: common.sh が見つかりません (desktop/install.sh --apply を実行してください)" >&2; exit 1; }

export PATH="$HOME/.local/bin:$PATH"
BOT_ME=${BOT_ME:-${0##*/}}
# shellcheck disable=SC2034  # common.sh が使う
BD_ME=$BOT_ME
die(){ echo "$BOT_ME: $*" >&2; exit 1; }

# 既定 (入れた写し、なければリポジトリの config.env) → look.env → *.local.env → 環境変数
bot_load_conf(){
  local d
  for d in "${BOT_DESKTOP_CONF:-}" "$BOT_DESKTOP_LIBDIR/desktop.config.env" "$BOT_DESKTOP_LIBDIR/../config.env"; do
    [ -n "$d" ] && [ -r "$d" ] && break
    d=
  done
  [ -n "$d" ] || echo "$BOT_ME: desktop の既定の設定が見つかりません (組みこみの既定で続けます)" >&2
  bd_load_config ${d:+"$d"}
  # shellcheck disable=SC2034  # 呼び出し側で使う
  if [ "$BOT_LOOK" = light ]; then
    BOT_WALLPAPER=${WALLPAPER:-${WALLPAPER_LIGHT:-$HOME/Pictures/bots-light-wallpaper.png}}
    BOT_THEME=${THEME_NAME:-${THEME_LIGHT:-Adwaita}}
  else
    BOT_WALLPAPER=${WALLPAPER:-${WALLPAPER_DARK:-$HOME/Pictures/bots-dark-wallpaper.png}}
    BOT_THEME=${THEME_NAME:-${THEME_DARK:-Adwaita-dark}}
  fi
}

# DISPLAY の決め方: 1) DISPLAY 環境変数 2) 設定の BOT_DISPLAY
# 3) $USER の xfwm4 がちょうど1つならその DISPLAY。それ以外はエラー (番号を勝手に決めない)
bot_resolve_display(){
  local src p d=
  local -a pids
  if [ -n "${DISPLAY:-}" ]; then src="DISPLAY"
  elif [ -n "${BOT_DISPLAY:-}" ]; then DISPLAY=$BOT_DISPLAY; src="BOT_DISPLAY"
  else
    mapfile -t pids < <(pgrep -u "$USER" -x xfwm4 2>/dev/null)
    set -- "${pids[@]}"
    if [ "$#" -eq 1 ]; then
      p=$1
      d=$(tr '\0' '\n' <"/proc/$p/environ" 2>/dev/null | sed -n 's/^DISPLAY=//p')
      [ -n "$d" ] || die "xfwm4 (pid $p) の DISPLAY が読めません。DISPLAY=:N か設定の BOT_DISPLAY で指定してください"
      DISPLAY=$d; src="xfwm4 pid $p"
    elif [ "$#" -eq 0 ]; then
      die "ディスプレイが決められません (DISPLAY も BOT_DISPLAY も空で、$USER の xfwm4 も見つからない)。DISPLAY=:N $BOT_ME で指定してください"
    else
      die "ディスプレイが決められません ($USER の xfwm4 が $# 個あって選べない)。DISPLAY=:N $BOT_ME で指定してください"
    fi
  fi
  export DISPLAY
  # shellcheck disable=SC2034  # 呼び出し側で使う
  BOT_DISPLAY_SRC=$src
}

# X が応答するまで待つ (xdpyinfo が成功するまで、最大 $1 秒)
bot_wait_x(){
  local t=${1:-60} i
  for ((i = 0; i < t * 2; i++)); do
    xdpyinfo >/dev/null 2>&1 && return 0
    sleep 0.5
  done
  return 1
}

# この DISPLAY の xfwm4 の pid (無ければ空)
bot_wm_pid(){
  local p r=
  for p in $(pgrep -u "$USER" -x xfwm4 2>/dev/null); do
    tr '\0' '\n' <"/proc/$p/environ" 2>/dev/null | grep -qx "DISPLAY=$DISPLAY" && r=$p
  done
  echo "$r"
}

# この $USER の xfwm4 が動いているディスプレイ番号 (重なりなし)
bot_wm_displays(){
  local p d
  for p in $(pgrep -u "$USER" -x xfwm4 2>/dev/null); do
    d=$(tr '\0' '\n' <"/proc/$p/environ" 2>/dev/null | sed -n 's/^DISPLAY=//p')
    d=${d##*:}; d=${d%%.*}
    case $d in ''|*[!0-9]*) ;; *) echo "$d" ;; esac
  done | sort -nu
}

# xfwm4 から DBUS_SESSION_BUS_ADDRESS をもらう (見つからなければ何もしないで 1)
bot_import_dbus(){
  local p b
  p=$(bot_wm_pid); [ -n "$p" ] || return 1
  b=$(tr '\0' '\n' <"/proc/$p/environ" 2>/dev/null | sed -n 's/^DBUS_SESSION_BUS_ADDRESS=//p')
  [ -n "$b" ] || return 1
  export DBUS_SESSION_BUS_ADDRESS="$b"
}

# keeper は BOT_LOOK を環境変数で受けとらない (受けとると look.env の切りかえに追いつかなくなるため)
bot_start_keeper(){ # [DISPLAY]
  local k=$HOME/.local/bin/wallpaper-keeper d=${1:-$DISPLAY}
  [ -x "$k" ] || { echo "$BOT_ME: $k がありません (desktop/install.sh --apply)" >&2; return 1; }
  (env -u BOT_LOOK -u WALLPAPER -u THEME_NAME DISPLAY="$d" setsid "$k" >/dev/null 2>&1 </dev/null &)
}

# 実際に動かしてみてチェック (126/127 = 無い or 実行できない)。$2 で実行ファイルを指定できる
bot_tool_ok(){
  local t=$1 exe=${2:-$1} rc
  case $t in
    wmctrl|hsetroot) "$exe" -h ;;
    xdotool)         "$exe" version ;;
    xprop|xdpyinfo)  "$exe" -version ;;
    xrefresh)        "$exe" -help ;;
    *)               "$exe" --version ;;
  esac >/dev/null 2>"${BOT_TOOL_ERR:-/dev/null}"
  rc=$?; [ "$rc" -lt 126 ]
}

BOT_TOOLS_DIR=${BOT_TOOLS_DIR:-$HOME/.local/lib/bot-tools}
# テストでは別の場所を指せるように
BOT_SYS_BIN=${BOT_SYS_BIN:-/usr/bin}
bot_pkg_of(){ case $1 in xprop|xdpyinfo) echo x11-utils ;; xrefresh) echo x11-xserver-utils ;; *) echo "$1" ;; esac; }

# 保存したバイナリを LD_LIBRARY_PATH 付きで実際に動かして確認 (共有ライブラリ不足も検出)
bot_saved_ok(){
  local t=$1 f rc=0
  f=$(mktemp) || return 1
  LD_LIBRARY_PATH="$BOT_TOOLS_DIR/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" BOT_TOOL_ERR=$f \
    bot_tool_ok "$t" "$BOT_TOOLS_DIR/bin/$t" || rc=1
  grep -q "error while loading shared libraries" "$f" && { cat "$f" >&2; rc=1; }
  rm -f "$f"; return "$rc"
}

bot__install_if_diff(){ # mode src dst → 0 = 書いた, 1 = 同じ, 2 = 失敗
  cmp -s "$2" "$3" && return 1
  install -m "$1" "$2" "$3" || return 2
  return 0
}

# 再起動で apt の中身が消える環境でも動くように、バイナリと共有ライブラリ
# (libc / libm / ローダー以外) を ~/.local/lib/bot-tools に写す。同じなら書かない
bot_save_tool(){
  local t=$1 src=$BOT_SYS_BIN/$1 lib base rc changed=0
  mkdir -p "$BOT_TOOLS_DIR/bin" "$BOT_TOOLS_DIR/lib"
  bot__install_if_diff 755 "$src" "$BOT_TOOLS_DIR/bin/$t"; rc=$?
  [ "$rc" = 2 ] && return 1
  [ "$rc" = 0 ] && changed=1
  if ldd "$src" 2>&1 | grep -q 'not found'; then
    echo "$BOT_ME: $t: ldd で見つからないライブラリがあります: $(ldd "$src" | grep 'not found' | tr -s ' \t' ' ')" >&2
  fi
  while read -r lib; do
    base=${lib##*/}
    case $base in libc.so.*|libm.so.*|ld-linux*|ld64.so*|ld.so*|linux-vdso*) continue ;; esac
    bot__install_if_diff 644 "$(readlink -f "$lib")" "$BOT_TOOLS_DIR/lib/$base"; rc=$?
    [ "$rc" = 2 ] && return 1
    [ "$rc" = 0 ] && changed=1
  done < <(ldd "$src" 2>/dev/null | awk '$2 == "=>" && $3 ~ /^\// {print $3}')
  [ "$changed" = 1 ] && echo "$BOT_ME: $t を $BOT_TOOLS_DIR に保存しました" >&2
  return 0
}

bot__wrapper_text(){
  cat <<EOW
#!/bin/sh
# generated by bot-dotfiles desktop/install.sh: $BOT_SYS_BIN/$1 が無ければ保存したコピーを使う
[ -x $BOT_SYS_BIN/$1 ] && exec $BOT_SYS_BIN/$1 "\$@"
D="\$HOME/.local/lib/bot-tools"
LD_LIBRARY_PATH="\$D/lib\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}" exec "\$D/bin/$1" "\$@"
EOW
}

# ~/.local/bin/$1 にラッパーを置く (同じ名前の別のファイルがあれば上書きしない)
bot_write_wrapper(){
  local t=$1 w=$HOME/.local/bin/$1 f
  f=$(mktemp) || return 1
  bot__wrapper_text "$t" >"$f"
  if [ -e "$w" ] || [ -L "$w" ]; then
    if cmp -s "$f" "$w"; then rm -f "$f"; return 0; fi
    # 前の版が置いたラッパーは自分のものとして置きかえる。それ以外は人が置いたものなので触らない
    if [ -L "$w" ] || ! grep -q '^# generated by .*desktop/install.sh' "$w"; then
      echo "$BOT_ME: $w は別のファイルなので上書きしません (スキップ)" >&2
      rm -f "$f"; return 0
    fi
  fi
  mkdir -p "$HOME/.local/bin"
  bd_backup_file "$w"
  install -m 755 "$f" "$w" && echo "$BOT_ME: ラッパー $w を置きました" >&2
  rm -f "$f"
}

# 各ツールを再起動しても使えるようにする:
#   $BOT_SYS_BIN に無いものだけ apt-get で入れる (--apply かつ NO_APT が無いとき) → バイナリ + 共有ライブラリを保存
#   → 保存したものを実際に動かして確認 → ~/.local/bin にラッパー
# dry-run (BD_APPLY=0) では何をするかを表示するだけ
# ~/.local/bin/<t> が、このツールのラッパーではない実行ファイル (人が置いたもの) か
bot__user_tool(){
  local w=$HOME/.local/bin/$1
  [ -f "$w" ] && [ -x "$w" ] && ! [ -L "$w" ] && ! grep -q '^# generated by .*desktop/install.sh' "$w" 2>/dev/null
}

bot_ensure_tools(){
  local t need=() pkgs=() sudo="" fail=0
  for t in "$@"; do
    [ -x "$BOT_SYS_BIN/$t" ] && continue
    bot__user_tool "$t" && continue
    [ -x "$BOT_TOOLS_DIR/bin/$t" ] && bot_saved_ok "$t" && continue
    need+=("$t"); pkgs+=("$(bot_pkg_of "$t")")
  done
  if [ "${#need[@]}" -gt 0 ]; then
    mapfile -t pkgs < <(printf '%s\n' "${pkgs[@]}" | sort -u)
    if [ "${BD_APPLY:-0}" != 1 ]; then
      echo "    (dry-run) 足りないコマンド: ${need[*]} → apt-get install -y ${pkgs[*]}"
    elif [ -n "${NO_APT:-}" ] || ! command -v apt-get >/dev/null; then
      echo "$BOT_ME: 足りないコマンド: ${need[*]} → sudo apt-get install -y ${pkgs[*]} で入れてください" >&2; fail=1
    elif [ "$(id -u)" -ne 0 ] && ! sudo -n true 2>/dev/null; then
      echo "$BOT_ME: ${need[*]} が無いけれど sudo が使えません → sudo apt-get install -y ${pkgs[*]}" >&2; fail=1
    else
      [ "$(id -u)" -ne 0 ] && sudo="sudo -n"
      echo "$BOT_ME: ${need[*]} を入れます (${pkgs[*]})" >&2
      { $sudo apt-get update && $sudo apt-get install -y "${pkgs[@]}"; } || fail=1
    fi
  fi
  for t in "$@"; do
    # ~/.local/bin に人が置いた実体があればそれを使う (apt も保存もしない)
    if [ ! -x "$BOT_SYS_BIN/$t" ] && bot__user_tool "$t"; then
      echo "    $t: ~/.local/bin/$t をそのまま使います"; continue
    fi
    if [ "${BD_APPLY:-0}" != 1 ]; then
      if [ -x "$BOT_SYS_BIN/$t" ] && ! cmp -s "$BOT_SYS_BIN/$t" "$BOT_TOOLS_DIR/bin/$t"; then
        echo "    (dry-run) $t を $BOT_TOOLS_DIR に保存"
      fi
      if [ -x "$BOT_SYS_BIN/$t" ] || [ -x "$BOT_TOOLS_DIR/bin/$t" ]; then
        if [ ! -e "$HOME/.local/bin/$t" ]; then echo "    (dry-run) ラッパー ~/.local/bin/$t を置く"
        elif ! bot__wrapper_text "$t" | cmp -s - "$HOME/.local/bin/$t" && grep -q '^# generated by .*desktop/install.sh' "$HOME/.local/bin/$t"; then
          echo "    (dry-run) 前の版のラッパー ~/.local/bin/$t を置きかえる"
        fi
      fi
      continue
    fi
    if [ -x "$BOT_SYS_BIN/$t" ]; then
      bot_save_tool "$t" || { echo "$BOT_ME: $t のコピーに失敗しました" >&2; fail=1; continue; }
    elif [ ! -x "$BOT_TOOLS_DIR/bin/$t" ]; then
      echo "$BOT_ME: $t が見つかりません" >&2; fail=1; continue
    fi
    bot_saved_ok "$t" || { echo "$BOT_ME: $t: 保存したコピーが動きません ($BOT_TOOLS_DIR/bin/$t)" >&2; fail=1; }
    bot_write_wrapper "$t"
  done
  return "$fail"
}
