#!/bin/bash
# マシン → リポジトリ。manifest に載っている項目だけを読み、リポジトリとの差分を見せる
# 使い方: ./capture.sh [--write] [--check] [--public] [id...]
#   既定の書きこみ先は非公開側 ($BOT_DOTFILES_LOCAL)。公開側の項目は --public のときだけ、検査を通ったら書く
#   --write が無ければ表示だけ。--check は差分があれば終了コード 1、確かめられない項目があれば 3
#   認証・履歴・DB・ログに当たる名前は manifest にあっても読まない (終了コード 2)
set -u
cd "$(dirname "$0")" || exit 1
BD_ME=capture.sh
# shellcheck source=lib/common.sh
. lib/common.sh
bd_init
write=0 check=0 public=0 ids=()
for a in "$@"; do
  case $a in
    --write) write=1 ;;
    --check) check=1 ;;
    --public) public=1 ;;
    --apply) bd_die "capture.sh では --write を使います" ;;
    -h|--help) sed -n '2,6p' "$0"; exit 0 ;;
    -*) bd_die "知らない引数: $a" ;;
    *) ids+=("$a") ;;
  esac
done
if [ "$write" = 1 ] && bd_forced_dry; then bd_warn "DRY_RUN=$DRY_RUN なので書きません"; write=0; fi
# テンプレートの項目を install と同じ値で描いて比べるため、各ツールの既定も読む
bd_load_config xfce/config.env desktop/config.env node/config.env
bd_derive_vars
if [ "$public" = 0 ] && [ -z "${BOT_DOTFILES_LOCAL:-}" ]; then
  bd_die "書きこみ先の非公開側が決まっていません。BOT_DOTFILES_LOCAL=<非公開リポジトリの clone> を設定してください (公開側へは --public)"
fi
bd_read_manifest
if [ "$write" = 1 ]; then where=書きこみます; else where="表示だけ (書くときは --write)"; fi
if [ "$public" = 1 ]; then bd_say "== capture → 公開側 ($BD_ROOT): $where"
else bd_say "== capture → 非公開側 ($BOT_DOTFILES_LOCAL): $where"; fi

denylist=$(bd_denylist) || denylist=

# 公開側に書く前の検査: 形の検査と、あれば禁止語 (見つけた語は表示しない)
public_ok(){ # file label
  local f=$1 label=$2 pat n
  scripts/check-shape.sh -- "$f" >/dev/null || { bd_warn "$label: 形の検査に通りません (scripts/check-shape.sh)"; return 1; }
  if [ -n "$denylist" ]; then
    pat=$(bd_tmpfile)
    sed -e 's/\r$//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' "$denylist" | grep -v -e '^$' -e '^#' >"$pat"
    if [ -s "$pat" ]; then
      n=$(grep -ciF -f "$pat" "$f")
      [ "$n" = 0 ] || { bd_warn "$label: 禁止語に当たる行が $n 行あります"; return 1; }
    fi
  else
    bd_warn "禁止語リストが無いので、禁止語の検査はしていません (BOT_DOTFILES_DENYLIST)"
  fi
}

# json-merge の項目: リポジトリにあるキーだけを、マシンの値で取る
pick_json(){ # repo home → stdout
  if command -v jq >/dev/null 2>&1; then
    jq --slurpfile h "$2" '
      def pick(t; h): reduce (t | keys_unsorted[]) as $k ({};
        . + {($k): (if (t[$k] | type) == "object" and (h[$k] | type) == "object" then pick(t[$k]; h[$k])
                    elif (h | has($k)) then h[$k] else t[$k] end)});
      pick(.; $h[0])' "$1"
  else
    python3 - "$1" "$2" <<'PY'
import json, sys
t = json.load(open(sys.argv[1])); h = json.load(open(sys.argv[2]))
def pick(t, h):
    out = {}
    for k, v in t.items():
        if isinstance(v, dict) and isinstance(h.get(k), dict): out[k] = pick(v, h[k])
        else: out[k] = h.get(k, v)
    return out
print(json.dumps(pick(t, h), indent=2, ensure_ascii=False))
PY
  fi
}

for x in "${ids[@]}"; do
  hit=0; for i in "${!M_ID[@]}"; do [ "${M_ID[$i]}" = "$x" ] && hit=1; done
  [ "$hit" = 1 ] || bd_die "manifest に無い id です: $x"
done

ndiff=0 nfail=0 ndenied=0 nskip=0
for i in "${!M_ID[@]}"; do
  id=${M_ID[$i]} repo=${M_REPO[$i]} mode=${M_MODE[$i]} target=${M_TARGET[$i]} origin=${M_ORIGIN[$i]}
  if [ "${#ids[@]}" -gt 0 ]; then
    hit=0; for x in "${ids[@]}"; do [ "$x" = "$id" ] && hit=1; done
    [ "$hit" = 1 ] || continue
  fi
  if bd_denied_path "$repo" || { [ "$target" != - ] && bd_denied_path "$target"; }; then
    bd_warn "$id: 認証・履歴・DB・ログに当たる名前なので読みません (manifest から外してください)"
    ndenied=$((ndenied + 1)); continue
  fi
  src=${M_BASE[$i]}/$repo
  writable=1 why=
  if [ "$public" = 1 ] && [ "$origin" = local ]; then
    continue
  elif [ "$public" = 0 ] && [ "$origin" = public ]; then
    writable=0 why="公開側の項目なので書きません (取りこむなら --public)"
  fi
  if bd_is_template "$src"; then
    writable=0 why="テンプレートなので取りこめません (値は config.env か *.local.env で直す)"
  fi

  got=$(bd_tmpfile)
  if [ "$mode" = xfconf ]; then
    if ! bd_xfconf_usable 2>/dev/null; then bd_say "確かめられない: $id (xfconf が使えない)"; nskip=$((nskip + 1)); continue; fi
    rendered=$(bd_tmpfile)
    if bd_is_template "$src"; then bd_render "$src" >"$rendered" || { bd_say "確かめられない: $id (テンプレートの値が足りない)"; nskip=$((nskip + 1)); continue; }
    else cat "$src" >"$rendered"; fi
    while IFS= read -r line; do
      case $line in ''|'#'*) printf '%s\n' "$line"; continue ;; esac
      IFS=$'\t' read -r ch prop type _ <<<"$line"
      printf '%s\t%s\t%s\t%s\n' "$ch" "$prop" "$type" "$(xfconf-query -c "$ch" -p "$prop" 2>/dev/null)"
    done <"$rendered" >"$got"
    want=$rendered label="$id (xfconf)"
  else
    home=$HOME/$target label="$id (~/$target)"
    if [ -L "$home" ] && bd_denied_path "$(readlink -f "$home")"; then
      bd_warn "$id: リンク先が認証・履歴・DB・ログに当たる名前なので読みません"; ndenied=$((ndenied + 1)); continue
    fi
    if [ ! -e "$home" ]; then bd_say "差分あり: $label (マシンに無い。install していない?)"; ndiff=$((ndiff + 1)); continue; fi
    case $mode in
      json-merge) pick_json "$src" "$home" >"$got" || { bd_warn "$label: JSON が読めません"; nfail=$((nfail + 1)); continue; } ;;
      *) cat "$home" >"$got" ;;
    esac
    want=$src
    if bd_is_template "$src"; then
      want=$(bd_tmpfile)
      bd_render "$src" >"$want" || { bd_say "確かめられない: $label (テンプレートの値が足りない)"; nskip=$((nskip + 1)); continue; }
      # テンプレートの line は「install したら変わるか」で比べる (マシン側のほかの行は差分にしない)
      if [ "$mode" = line ]; then merged=$(bd_tmpfile); bd_merge_lines "$want" "$home" >"$merged"; want=$merged; fi
    fi
  fi

  if cmp -s "$want" "$got"; then bd_say "変更なし: $label"; continue; fi
  ndiff=$((ndiff + 1))
  bd_say "差分あり: $label"
  # 秘密らしいものがあれば、差分も表示しない (表示そのものが漏れになるため)
  if ! bd_secret_scan "$got" "$label"; then
    bd_warn "$label: 差分は表示せず、取りこみもしません"; nfail=$((nfail + 1)); continue
  fi
  if bd_is_text "$got" && bd_is_text "$want"; then
    diff -u --label "$repo (リポジトリ)" --label "$label (マシン)" "$want" "$got" | sed 's/^/    /'
  else
    bd_say "    (バイナリ: $(stat -c %s "$want") → $(stat -c %s "$got") バイト)"
  fi
  if [ "$writable" = 0 ]; then bd_say "    → $why"; continue; fi
  [ "$write" = 1 ] || continue
  if [ "$public" = 1 ] && ! public_ok "$got" "$label"; then bd_warn "$label: 公開側には書きません"; nfail=$((nfail + 1)); continue; fi
  cat "$got" >"$src" && bd_say "    → $src に書きました"
done

bd_say "-- capture: 差分 $ndiff / 確かめられない $nskip / 失敗 $nfail / 拒否 $ndenied"
[ "$ndenied" = 0 ] || exit 2
[ "$nfail" = 0 ] || exit 1
if [ "$check" = 1 ]; then
  [ "$ndiff" -gt 0 ] && exit 1
  [ "$nskip" -gt 0 ] && exit 3
fi
exit 0
