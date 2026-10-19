# shellcheck shell=bash
# lib/common.sh — install / capture / restore と desktop の実行時スクリプトの共通処理 (source して使う)

BD_ME=${BD_ME:-${0##*/}}
# PATH の案内は、スクリプトが ~/.local/bin を足す前の PATH で判断する
export BD_ORIG_PATH=${BD_ORIG_PATH:-$PATH}
BD_CONF_DIR=$HOME/.config/bot-dotfiles
BD_BACKUP_ROOT=$HOME/.local/state/bot-dotfiles/backup
BD_LIB_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# 公開側リポジトリの中から読まれたときだけ決まる (~/.local/lib に入った写しからは manifest を使わない)
BD_ROOT=
[ -r "$BD_LIB_DIR/../manifest.tsv" ] && BD_ROOT=$(cd "$BD_LIB_DIR/.." && pwd)

BD_APPLY=0
BD_N_CHANGED=0 BD_N_SAME=0 BD_N_FAIL=0
BD_LOADED_KEYS=()

bd_say(){ printf '%s\n' "$*"; }
bd_warn(){ printf '%s: 注意: %s\n' "$BD_ME" "$*" >&2; }
bd_die(){ printf '%s: %s\n' "$BD_ME" "$*" >&2; exit 1; }

bd_forced_dry(){ case ${DRY_RUN:-} in ''|0) return 1 ;; *) return 0 ;; esac; }

# --apply を取りのぞいた残りの引数を BD_REST に入れる。DRY_RUN=1 は --apply より強い
bd_init(){
  local a want=0
  BD_REST=()
  for a in "$@"; do
    case $a in
      --apply) want=1 ;;
      --dry-run) want=0 ;;
      *) BD_REST+=("$a") ;;
    esac
  done
  BD_APPLY=$want
  if [ "$want" = 1 ] && bd_forced_dry; then
    bd_warn "DRY_RUN=$DRY_RUN なので --apply を無視して表示だけにします"
    BD_APPLY=0
  fi
  BD_TMPDIR=$(mktemp -d "${TMPDIR:-/tmp}/bot-dotfiles.XXXXXX") || bd_die "一時フォルダが作れません"
  trap 'rm -rf "$BD_TMPDIR"' EXIT
}

bd_tmpfile(){ mktemp "$BD_TMPDIR/f.XXXXXX"; }

bd_mode_banner(){
  if [ "$BD_APPLY" = 1 ]; then bd_say "== $1: 書きこみます (--apply)"
  else bd_say "== $1: 表示だけ (dry-run)。書くときは --apply"; fi
}

# ---------------------------------------------------------------- 設定の重ね読み
# 公開側の既定 → look.env → ~/.config/bot-dotfiles/*.local.env → $BOT_DOTFILES_LOCAL/local/*.local.env → 環境変数
# 設定ファイルは source せず KEY=VALUE だけ読む (書いた人の意図しないコードを動かさないため)

bd__in_env(){ case " $BD_ENV_NAMES " in *" $1 "*) return 0 ;; esac; return 1; }

bd__denied_key(){
  case $1 in
    PATH|HOME|IFS|SHELL|USER|ENV|BASH_ENV|PS4|CDPATH|DISPLAY|DRY_RUN|LD_*|BASH*|BD_*|DBUS_*) return 0 ;;
  esac
  return 1
}

bd__read_env_file(){ # file [1=BOT_LOOK を読んでよい]
  local f=$1 allow_look=${2:-0} line key val n=0
  local re_kv='^([A-Za-z_][A-Za-z0-9_]*)=(.*)$' re_dq='^"([^"]*)"' re_sq="^'([^']*)'"
  [ -r "$f" ] || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    n=$((n + 1))
    line=${line#"${line%%[![:space:]]*}"}
    case $line in ''|'#'*) continue ;; esac
    line=${line#export }
    if ! [[ $line =~ $re_kv ]]; then bd_warn "$f:$n: KEY=VALUE の形ではないので読みません"; continue; fi
    key=${BASH_REMATCH[1]} val=${BASH_REMATCH[2]}
    if [[ $val == \"* ]]; then
      [[ $val =~ $re_dq ]] || { bd_warn "$f:$n: 引用符が閉じていません"; continue; }
      val=${BASH_REMATCH[1]}
    elif [[ $val == \'* ]]; then
      [[ $val =~ $re_sq ]] || { bd_warn "$f:$n: 引用符が閉じていません"; continue; }
      val=${BASH_REMATCH[1]}
    else
      val=${val%%[[:space:]]#*}
      val=${val%"${val##*[![:space:]]}"}
    fi
    # shellcheck disable=SC2088,SC2016  # 書かれた文字の ~ と $HOME をここで HOME にする
    case $val in '~') val=$HOME ;; '~/'*) val=$HOME/${val#'~/'} ;; esac
    # shellcheck disable=SC2016
    val=${val//'${HOME}'/$HOME}
    # shellcheck disable=SC2016
    val=${val//'$HOME'/$HOME}
    if bd__denied_key "$key"; then bd_warn "$f:$n: $key は設定ファイルでは変えられません"; continue; fi
    if [ "$key" = BOT_LOOK ] && [ "$allow_look" != 1 ]; then
      bd_warn "$f:$n: BOT_LOOK は $BD_CONF_DIR/look.env だけで決めます (読みません)"; continue
    fi
    bd__in_env "$key" && continue
    printf -v "$key" '%s' "$val"
    BD_LOADED_KEYS+=("$key")
  done <"$f"
}

bd_load_config(){ # 既定ファイル...
  local f k
  if [ -z "${BD_ENV_SNAP:-}" ]; then
    BD_ENV_SNAP=1
    BD_ENV_NAMES=$(compgen -e | tr '\n' ' ')
  fi
  # 読みなおし (wallpaper-keeper) で、消したキーの古い値が残らないように
  for k in "${BD_LOADED_KEYS[@]}"; do unset "$k"; done
  BD_LOADED_KEYS=()
  for f in "$@"; do bd__read_env_file "$f"; done
  bd__read_env_file "$BD_CONF_DIR/look.env" 1
  for f in "$BD_CONF_DIR"/*.local.env; do [ -e "$f" ] && bd__read_env_file "$f"; done
  if [ -n "${BOT_DOTFILES_LOCAL:-}" ]; then
    if [ -d "$BOT_DOTFILES_LOCAL" ]; then
      for f in "$BOT_DOTFILES_LOCAL"/local/*.local.env; do [ -e "$f" ] && bd__read_env_file "$f"; done
    else
      bd_warn "BOT_DOTFILES_LOCAL ($BOT_DOTFILES_LOCAL) がありません"
    fi
  fi
  if [ -z "${BOT_LOOK:-}" ]; then
    BOT_LOOK=dark
    bd__in_env BOT_LOOK || BD_LOADED_KEYS+=(BOT_LOOK)
  fi
  case $BOT_LOOK in
    dark|light) ;;
    *) bd_warn "BOT_LOOK は dark か light です (今: $BOT_LOOK)。dark として続けます"; BOT_LOOK=dark ;;
  esac
}

# ---------------------------------------------------------------- ロックと退避

bd_lock(){
  local f
  [ "$BD_APPLY" = 1 ] || return 0
  [ -n "${BD_LOCK_HELD:-}" ] && return 0
  f=${BOT_DOTFILES_LOCK:-${XDG_RUNTIME_DIR:-/tmp}/bot-dotfiles-apply.lock}
  exec {BD_LOCK_FD}>>"$f" || bd_die "ロック $f が作れません"
  flock -w "${BOT_DOTFILES_LOCK_WAIT:-120}" "$BD_LOCK_FD" || bd_die "ほかの反映が終わらないので止めます ($f)"
  export BD_LOCK_HELD=$$
}

# 今回の退避先の名前を決める (install-all が決めて、各 install.sh が同じ名前を使う)
bd_pick_backup_ts(){
  local base i=1
  [ -n "${BD_BACKUP_TS:-}" ] && return 0
  BD_BACKUP_TS=$(date +%Y%m%d-%H%M%S)
  base=$BD_BACKUP_TS
  while [ -e "$BD_BACKUP_ROOT/$BD_BACKUP_TS" ]; do BD_BACKUP_TS=$base-$i; i=$((i + 1)); done
  export BD_BACKUP_TS
}

# 何かを書きかえる直前にだけ作る (変更なしの回に空の退避を残さないため)
bd_backup_dir(){
  bd_pick_backup_ts
  BD_BACKUP_DIR=$BD_BACKUP_ROOT/$BD_BACKUP_TS
  mkdir -p "$BD_BACKUP_DIR"
}

bd_backup_file(){ # 絶対パス
  local dst=$1 rel
  rel=${dst#"$HOME"/}
  [ "$rel" != "$dst" ] || bd_die "HOME の外は扱いません: $dst"
  bd_backup_dir
  if [ -e "$dst" ] || [ -L "$dst" ]; then
    # 同じ回で2度目に書くときは、最初の状態を残す
    [ -e "$BD_BACKUP_DIR/home/$rel" ] || [ -L "$BD_BACKUP_DIR/home/$rel" ] && return 0
    mkdir -p "$(dirname "$BD_BACKUP_DIR/home/$rel")"
    cp -pP "$dst" "$BD_BACKUP_DIR/home/$rel"
  else
    touch "$BD_BACKUP_DIR/created.txt"
    grep -qxF -- "$rel" "$BD_BACKUP_DIR/created.txt" || printf '%s\n' "$rel" >>"$BD_BACKUP_DIR/created.txt"
  fi
}

# ---------------------------------------------------------------- 秘密チェック

BD_LEAK_RULES=(
  'sk-key|sk-[A-Za-z0-9_-]{20,}'
  'github-token|gh[pousr]_[A-Za-z0-9]{30,}'
  'github-pat|github_pat_[A-Za-z0-9_]{20,}'
  'slack-token|xox[abposr]-[A-Za-z0-9-]{10,}'
  'aws-key-id|AKIA[0-9A-Z]{16}'
  'private-key|-----BEGIN [A-Z ]*PRIVATE KEY'
  'json-secret-key|"[A-Za-z_-]*([Tt][Oo][Kk][Ee][Nn]|[Pp][Aa][Ss][Ss][Ww][Oo][Rr][Dd]|[Ss][Ee][Cc][Rr][Ee][Tt]|[Aa][Pp][Ii]_?[Kk][Ee][Yy])[A-Za-z_-]*"[[:space:]]*:[[:space:]]*"[^"]{8,}'
  'env-secret-key|^[[:space:]]*(export[[:space:]]+)?[A-Za-z_]*([Tt][Oo][Kk][Ee][Nn]|[Pp][Aa][Ss][Ss][Ww][Oo][Rr][Dd]|[Ss][Ee][Cc][Rr][Ee][Tt]|[Aa][Pp][Ii]_?[Kk][Ee][Yy])[A-Za-z_]*[[:space:]]*=[[:space:]]*[\"'"'"']?[A-Za-z0-9_/+.=-]{8,}'
)

# 禁止語リストの場所: $BOT_DOTFILES_DENYLIST → ~/.config/bot-dotfiles/denylist.txt → $BOT_DOTFILES_LOCAL/denylist.txt
bd_denylist(){
  local f
  for f in "${BOT_DOTFILES_DENYLIST:-}" "$BD_CONF_DIR/denylist.txt" "${BOT_DOTFILES_LOCAL:+$BOT_DOTFILES_LOCAL/denylist.txt}"; do
    [ -n "$f" ] && [ -r "$f" ] && { printf '%s\n' "$f"; return 0; }
  done
  return 1
}

bd_is_text(){ [ ! -s "$1" ] || grep -Iq '' "$1"; }

# 見つけても値は表示しない (表示そのものが漏れになるため)
bd_secret_scan(){ # file label → 0 = 問題なし
  local f=$1 label=$2 r name re hit=0 rc cfg=()
  bd_is_text "$f" || return 0
  if command -v gitleaks >/dev/null 2>&1; then
    [ -n "$BD_ROOT" ] && [ -r "$BD_ROOT/.gitleaks.toml" ] && cfg=(--config "$BD_ROOT/.gitleaks.toml")
    gitleaks dir "${cfg[@]}" --no-banner --redact --exit-code 3 --log-level error "$f" >/dev/null 2>&1
    rc=$?
    case $rc in
      0) ;;
      3) bd_warn "$label: gitleaks が秘密らしいものを見つけました"; hit=1 ;;
      *) bd_warn "$label: gitleaks が動きませんでした (rc=$rc)。簡易チェックだけ続けます" ;;
    esac
  fi
  for r in "${BD_LEAK_RULES[@]}"; do
    name=${r%%|*} re=${r#*|}
    if grep -Eq -- "$re" "$f"; then bd_warn "$label: 秘密らしいもの ($name) があります"; hit=1; fi
  done
  return "$hit"
}

# capture で manifest にあっても読まないもの (認証・履歴・DB・ログ)
bd_denied_path(){ # repo のパスか HOME 下のパス
  local p=$1 b
  b=${p##*/}
  b=${b,,}
  case $b in
    .claude.json|.credentials.json|auth.json|*history*|*.sqlite*|*.db|*token*|*.pem|*.key|id_*|.netrc|.npmrc|*.log) return 0 ;;
  esac
  case /$p/ in
    */sessions/*|*/.claude/projects/*) return 0 ;;
  esac
  return 1
}

# ---------------------------------------------------------------- manifest

# manifest の行を自分で反映する install.sh (ほかの頭の非公開側の行は install-all が最後に反映する)
bd__known_tool(){ case $1 in xfce|desktop) return 0 ;; esac; return 1; }

bd__read_manifest_file(){ # file base origin
  local file=$1 base=$2 origin=$3 id repo target mode class extra i n=0 found
  while IFS=$'\t' read -r id repo target mode class extra || [ -n "$id" ]; do
    n=$((n + 1))
    case $id in ''|'#'*) continue ;; esac
    if [ -n "$extra" ] || [ -z "$class" ]; then bd_warn "$file:$n: 列は5つです (id repo target mode class)"; BD_MANIFEST_ERR=1; continue; fi
    case $mode in copy|json-merge|xfconf|line|bin) ;; *) bd_warn "$file:$n: 扱い方 $mode は使えません"; BD_MANIFEST_ERR=1; continue ;; esac
    case $class in shared|per-display|layout) ;; *) bd_warn "$file:$n: 区分 $class は使えません"; BD_MANIFEST_ERR=1; continue ;; esac
    case /$repo/ in */../*|//*) bd_warn "$file:$n: repo のパスがおかしい: $repo"; BD_MANIFEST_ERR=1; continue ;; esac
    if [ "$mode" = xfconf ]; then
      [ "$target" = - ] || { bd_warn "$file:$n: xfconf の置き先は - と書きます"; BD_MANIFEST_ERR=1; continue; }
    else
      case /$target/ in */../*|//*|/-/) bd_warn "$file:$n: 置き先は HOME からの相対パスです: $target"; BD_MANIFEST_ERR=1; continue ;; esac
    fi
    [ -e "$base/$repo" ] || { bd_warn "$file:$n: $repo がありません"; BD_MANIFEST_ERR=1; continue; }
    found=
    for i in "${!M_ID[@]}"; do [ "${M_ID[$i]}" = "$id" ] && found=$i; done
    if [ -n "$found" ]; then
      if [ "$origin" = local ] && [ "${M_ORIGIN[$found]}" = public ]; then
        M_BASE[found]=$base M_REPO[found]=$repo M_TARGET[found]=$target M_MODE[found]=$mode M_CLASS[found]=$class
        M_ORIGIN[found]=local M_OVERRIDE[found]=1
      else
        bd_warn "$file:$n: id $id が重なっています"; BD_MANIFEST_ERR=1
      fi
      continue
    fi
    M_ID+=("$id") M_BASE+=("$base") M_REPO+=("$repo") M_TARGET+=("$target") M_MODE+=("$mode")
    M_CLASS+=("$class") M_ORIGIN+=("$origin") M_OVERRIDE+=(0)
  done <"$file"
}

# 公開側 manifest.tsv と、$BOT_DOTFILES_LOCAL/manifest.local.tsv (同じ id は非公開側が勝つ)
bd_read_manifest(){
  M_ID=() M_BASE=() M_REPO=() M_TARGET=() M_MODE=() M_CLASS=() M_ORIGIN=() M_OVERRIDE=()
  BD_MANIFEST_ERR=0
  [ -n "$BD_ROOT" ] || bd_die "公開側リポジトリの中の lib/common.sh から実行してください"
  bd__read_manifest_file "$BD_ROOT/manifest.tsv" "$BD_ROOT" public
  if [ -n "${BOT_DOTFILES_LOCAL:-}" ] && [ -r "$BOT_DOTFILES_LOCAL/manifest.local.tsv" ]; then
    bd__read_manifest_file "$BOT_DOTFILES_LOCAL/manifest.local.tsv" "$(cd "$BOT_DOTFILES_LOCAL" && pwd)" local
  fi
  [ "$BD_MANIFEST_ERR" = 0 ] || bd_die "manifest に間違いがあるので止めます"
}

bd_is_template(){ case $1 in *.tmpl|*.example) return 0 ;; esac; return 1; }

# @NAME@ を変数 NAME の値に置きかえる。決まっていない名前があれば失敗
bd_render(){ # src → stdout
  local src=$1 n
  local -a kv=()
  while read -r n; do
    [ -n "$n" ] || continue
    [ -n "${!n+x}" ] || { bd_warn "$src: @$n@ の値が決まっていません"; return 1; }
    kv+=("BDR_$n=${!n}")
  done < <(grep -o '@[A-Z][A-Z0-9_]*@' "$src" | tr -d @ | sort -u)
  # shellcheck disable=SC2016  # awk のプログラム
  env "${kv[@]}" awk '{
    out = ""
    while (match($0, /@[A-Z][A-Z0-9_]*@/)) {
      out = out substr($0, 1, RSTART - 1) ENVIRON["BDR_" substr($0, RSTART + 1, RLENGTH - 2)]
      $0 = substr($0, RSTART + RLENGTH)
    }
    print out $0
  }' "$src"
}

# 置き先の行を残し、同じキーの行は置きかえ、足りない行は最後に足す
# キー: 「名前=」で始まる行はその名前、それ以外は最初の空白までの語
bd_merge_lines(){ # src dst → stdout
  local dst=$2
  [ -e "$dst" ] || dst=/dev/null
  awk -v src="$1" '
    function key(l,   k, a) {
      if (l ~ /^[A-Za-z0-9_.-]+=/) { k = l; sub(/=.*/, "=", k); return k }
      split(l, a, /[ \t]/); return a[1]
    }
    BEGIN { while ((getline l < src) > 0) { if (l == "") continue; n++; L[n] = l; K[n] = key(l) } }
    {
      k = key($0)
      if ($0 != "") for (i = 1; i <= n; i++) if (K[i] == k) {
        if (!done[i]) { print L[i]; done[i] = 1 }
        next
      }
      print
    }
    END { for (i = 1; i <= n; i++) if (!done[i]) print L[i] }
  ' "$dst"
}

bd_merge_json(){ # dst src → stdout (dst のほかのキーは残す)
  local dst=$1 src=$2 base
  base=$(bd_tmpfile)
  if [ -s "$dst" ]; then cat "$dst" >"$base"; else echo '{}' >"$base"; fi
  if command -v jq >/dev/null 2>&1; then
    jq -s '.[0] * .[1]' "$base" "$src"
  else
    python3 - "$base" "$src" <<'PY'
import json, sys
a = json.load(open(sys.argv[1])); b = json.load(open(sys.argv[2]))
def merge(x, y):
    for k, v in y.items():
        x[k] = merge(x[k], v) if isinstance(v, dict) and isinstance(x.get(k), dict) else v
    return x
print(json.dumps(merge(a, b), indent=2, ensure_ascii=False))
PY
  fi
}

# 置き先 (途中のフォルダのリンクもふくめて) を解決し、HOME の中なら HOME からのパスで返す。外なら書かない
bd_resolve_target(){ # 置き先 ラベル → stdout
  local p=$1 rest='' rh r
  rh=$(readlink -f "$HOME")
  while [ ! -e "$p" ] && [ ! -L "$p" ] && [ "$p" != "$HOME" ]; do rest=/${p##*/}$rest; p=${p%/*}; done
  r=$(readlink -f "$p")$rest
  case $r in
    "$rh"/*) printf '%s\n' "$HOME/${r#"$rh"/}" ;;
    *) bd_warn "$2: 置き先 (リンク先) が HOME の外なので書きません"; return 1 ;;
  esac
}

bd__show_diff(){ # 今のファイル 新しいファイル ラベル
  local old=$1 new=$2 label=$3 a=/dev/null
  { [ -e "$old" ] || [ -L "$old" ]; } && a=$old
  if [ "$a" = /dev/null ] && bd_is_text "$new" && [ "$(wc -l <"$new")" -gt 20 ]; then
    bd_say "    (新しいファイル: $(wc -l <"$new") 行)"
  elif bd_is_text "$new" && { [ "$a" = /dev/null ] || bd_is_text "$a"; }; then
    diff -u --label "$label (いま)" --label "$label (あと)" "$a" "$new" | sed 's/^/    /'
  else
    bd_say "    (バイナリ: $(stat -c %s "$a" 2>/dev/null || echo 0) → $(stat -c %s "$new") バイト)"
  fi
}

# 差分を見せて、--apply のときだけ退避してから置く。perm は keep (今の権限のまま) か 755 など
# 秘密チェックはリポジトリから来た中身 (scan) にかける。マージ後の全体にかけると、
# もともとマシンにあった値で止まってしまうため。- ならかけない (restore)
bd_put(){ # 新しい中身 置き先 perm ラベル [scan]
  local new=$1 dst=$2 perm=$3 label=$4 scan=${5:-$1} mode cur='' tmp
  [ -e "$dst" ] && cur=$(stat -c %a "$dst")
  if [ "$perm" = keep ]; then mode=${cur:-644}; else mode=$perm; fi
  if [ -e "$dst" ] && [ ! -L "$dst" ] && cmp -s "$new" "$dst" && [ "$cur" = "$mode" ]; then
    bd_say "変更なし: $label"
    BD_N_SAME=$((BD_N_SAME + 1))
    return 0
  fi
  bd_say "変更あり: $label"
  if [ -e "$dst" ] && cmp -s "$new" "$dst"; then bd_say "    (権限 ${cur:-?} → $mode)"
  else bd__show_diff "$dst" "$new" "$label"; fi
  BD_N_CHANGED=$((BD_N_CHANGED + 1))
  [ "$BD_APPLY" = 1 ] || return 0
  if [ "$scan" != - ] && ! bd_secret_scan "$scan" "$label"; then
    bd_warn "$label: 書きこみをやめました"
    BD_N_FAIL=$((BD_N_FAIL + 1))
    return 1
  fi
  bd_backup_file "$dst"
  mkdir -p "$(dirname "$dst")"
  # 同じフォルダの一時ファイルから mv する (途中で止まっても半端なファイルを残さないため)
  tmp=$(mktemp "$(dirname "$dst")/.bot-dotfiles.XXXXXX") || { BD_N_FAIL=$((BD_N_FAIL + 1)); return 1; }
  if ! { cat "$new" >"$tmp" && chmod "$mode" "$tmp" && mv -f "$tmp" "$dst"; }; then
    rm -f "$tmp"; bd_warn "$label: 書けませんでした"; BD_N_FAIL=$((BD_N_FAIL + 1)); return 1
  fi
}

# ---------------------------------------------------------------- xfconf

bd_xfconf_usable(){
  command -v xfconf-query >/dev/null 2>&1 || { bd_warn "xfconf-query が無いので xfconf はとばします"; return 1; }
  # XFCONF_FORCE=1: DISPLAY が無くても D-Bus のセッションがあるときに使う
  [ -n "${DISPLAY:-}" ] || [ -n "${XFCONF_FORCE:-}" ] || { bd_warn "DISPLAY が無いので xfconf はとばします"; return 1; }
}

bd__xfconf_lines(){ grep -v -e '^[[:space:]]*#' -e '^[[:space:]]*$' "$1"; }

bd_apply_xfconf(){ # 描画済みファイル ラベル
  local f=$1 label=$2 ch prop type val cur had
  if ! bd_xfconf_usable; then
    if [ "$BD_APPLY" != 1 ]; then
      while IFS=$'\t' read -r ch prop type val; do
        bd_say "    (確かめられない) xfconf $ch $prop = $val"
      done < <(bd__xfconf_lines "$f")
    fi
    return 0
  fi
  while IFS=$'\t' read -r ch prop type val; do
    if cur=$(xfconf-query -c "$ch" -p "$prop" 2>/dev/null); then had=1; else had=0 cur=; fi
    if [ "$had" = 1 ] && [ "$cur" = "$val" ]; then
      bd_say "変更なし: $label: $ch $prop"
      BD_N_SAME=$((BD_N_SAME + 1))
      continue
    fi
    bd_say "変更あり: $label: $ch $prop"
    if [ "$had" = 1 ]; then bd_say "    - $cur"; else bd_say "    - (なし)"; fi
    bd_say "    + $val"
    BD_N_CHANGED=$((BD_N_CHANGED + 1))
    [ "$BD_APPLY" = 1 ] || continue
    bd_backup_dir
    if ! awk -F'\t' -v c="$ch" -v p="$prop" '$1 == c && $2 == p { f = 1 } END { exit !f }' "$BD_BACKUP_DIR/xfconf.tsv" 2>/dev/null; then
      if [ "$had" = 1 ]; then printf '%s\t%s\t%s\t%s\n' "$ch" "$prop" "$type" "$cur"
      else printf '%s\t%s\t%s\t%s\n' "$ch" "$prop" "$type" "__UNSET__"; fi >>"$BD_BACKUP_DIR/xfconf.tsv"
    fi
    if ! xfconf-query -c "$ch" -p "$prop" -s "$val" 2>/dev/null &&
       ! xfconf-query -c "$ch" -p "$prop" -n -t "$type" -s "$val" 2>/dev/null; then
      bd_warn "xfconf $ch $prop を書けませんでした"
      BD_N_FAIL=$((BD_N_FAIL + 1))
    fi
  done < <(bd__xfconf_lines "$f")
}

# ---------------------------------------------------------------- manifest の項目を反映

bd_apply_row(){ # index
  local i=$1 src mode dst want label merged perm scan
  src=${M_BASE[$i]}/${M_REPO[$i]} mode=${M_MODE[$i]}
  want=$(bd_tmpfile) scan=$want
  if bd_is_template "$src"; then
    bd_render "$src" >"$want" || { BD_N_FAIL=$((BD_N_FAIL + 1)); return 1; }
  else
    cat "$src" >"$want"
  fi
  if [ "$mode" = xfconf ]; then
    bd_apply_xfconf "$want" "${M_ID[$i]}"
    return
  fi
  dst=$HOME/${M_TARGET[$i]} label="${M_ID[$i]} (~/${M_TARGET[$i]})"
  dst=$(bd_resolve_target "$dst" "$label") || { BD_N_FAIL=$((BD_N_FAIL + 1)); return 1; }
  perm=keep
  case $mode in
    bin) perm=755 ;;
    line)
      merged=$(bd_tmpfile)
      bd_merge_lines "$want" "$dst" >"$merged" || { BD_N_FAIL=$((BD_N_FAIL + 1)); return 1; }
      want=$merged ;;
    json-merge)
      merged=$(bd_tmpfile)
      bd_merge_json "$dst" "$want" >"$merged" || {
        bd_warn "$label: JSON をまとめられませんでした (今のファイルが壊れている?)"; BD_N_FAIL=$((BD_N_FAIL + 1)); return 1
      }
      want=$merged ;;
  esac
  bd_put "$want" "$dst" "$perm" "$label" "$scan"
}

# 引数: prefix:<id の頭> か local-only (非公開側だけにある項目)
bd_apply_rows(){
  local sel=$1 i
  for i in "${!M_ID[@]}"; do
    case $sel in
      prefix:*) [[ ${M_ID[$i]} == "${sel#prefix:}"* ]] || continue ;;
      local-only) [[ ${M_ORIGIN[$i]} == local && ${M_OVERRIDE[$i]} == 0 ]] || continue
                  bd__known_tool "${M_ID[$i]%%-*}" && continue ;;
    esac
    bd_apply_row "$i"
  done
}

# テンプレートが使う値を決める: NAME_DARK / NAME_LIGHT から NAME (NAME を直接書いたらそれが勝つ)
# 読みなおしで古い値が残らないように、決めた名前も BD_LOADED_KEYS に入れる
bd_derive_vars(){
  local k base n suf=DARK
  [ "$BOT_LOOK" = light ] && suf=LIGHT
  # 環境変数で渡した *_DARK も見るため、読みこんだキーではなく全部の変数から探す
  for k in $(compgen -v); do
    case $k in *_DARK) ;; *) continue ;; esac
    base=${k%_DARK} n=${k%_DARK}_$suf
    [ -n "${!base:-}" ] && continue
    printf -v "$base" '%s' "${!n:-}"
    BD_LOADED_KEYS+=("$base")
  done
  # terminalrc は TRUE / FALSE で書く
  if [ -n "${TERM_FONT_USE_SYSTEM:-}" ] && [ -z "${TERM_FONT_USE_SYSTEM_RC:-}" ]; then
    TERM_FONT_USE_SYSTEM_RC=FALSE
    [ "$TERM_FONT_USE_SYSTEM" = true ] && TERM_FONT_USE_SYSTEM_RC=TRUE
    BD_LOADED_KEYS+=(TERM_FONT_USE_SYSTEM_RC)
  fi
}

# BOT_LOOK を look.env に覚える (環境変数で指定されたとき、またはまだ無いとき)
bd_sync_look(){
  local f=$BD_CONF_DIR/look.env want old
  [ -e "$f" ] && ! bd__in_env BOT_LOOK && return 0
  # 前の版は desktop.env に見た目を覚えていた。黙って dark に戻さないように引きつぐ
  if [ ! -e "$f" ] && ! bd__in_env BOT_LOOK && [ -r "$BD_CONF_DIR/desktop.env" ]; then
    # shellcheck disable=SC2016  # sed の正規表現
    old=$(sed -n 's/^: "\${BOT_LOOK:=\([a-z]*\)}".*/\1/p' "$BD_CONF_DIR/desktop.env" | head -n 1)
    if [ "$old" = light ]; then
      bd_say "前の版の desktop.env から BOT_LOOK=light を引きつぎます"
      BOT_LOOK=light
    fi
  fi
  want=$(bd_tmpfile)
  printf '# xfce と desktop が読む見た目 (dark か light)。変えるときは BOT_LOOK=light ./install-all.sh --apply\nBOT_LOOK=%s\n' "$BOT_LOOK" >"$want"
  bd_put "$want" "$f" keep "look (~/.config/bot-dotfiles/look.env)"
}

# $HOME の外を触るコマンド (apt / npm -g / sudo): --apply かつ NO_APT が無いときだけ動かす
bd_run_system(){
  if [ "$BD_APPLY" = 1 ] && [ -z "${NO_APT:-}" ]; then "$@"; return; fi
  if [ "$BD_APPLY" = 1 ]; then bd_say "    (NO_APT なので動かさない) $*"; else bd_say "    (dry-run) $*"; fi
}

# $HOME の中だけを触るコマンド: --apply のときだけ動かす
bd_run_home(){
  if [ "$BD_APPLY" = 1 ]; then "$@"; return; fi
  bd_say "    (dry-run) $*"
}

bd_summary(){ # 名前
  local what=変更あり
  [ "$BD_APPLY" = 1 ] && what=変更した
  bd_say "-- $1: $what $BD_N_CHANGED / 変更なし $BD_N_SAME / 失敗 $BD_N_FAIL"
  [ "$BD_N_FAIL" = 0 ]
}
