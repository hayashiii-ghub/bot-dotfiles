#!/bin/bash
# optional/playwright/: E2E テスト用に Playwright と Chromium を入れる (install-all.sh --with playwright のときだけ)
# 既定は表示だけ。npm -g と依存ライブラリ (apt) は --apply かつ NO_APT が無いときだけ動かす
set -u
cd "$(dirname "$0")/../.." || exit 1
BD_ME=playwright/install.sh
# shellcheck source=lib/common.sh
. lib/common.sh
bd_init "$@"
bd_mode_banner playwright
bd_load_config
bd_lock
export PATH="$HOME/.local/bin:$PATH"

# npm -g の置き場が PATH に無いこともあるので、npm に聞く
pw_path(){
  local p
  command -v playwright 2>/dev/null && return 0
  p=$(npm prefix -g 2>/dev/null)/bin/playwright
  [ -x "$p" ] && echo "$p"
}

pw=$(pw_path)
if [ -n "$pw" ]; then
  bd_say "変更なし: playwright $("$pw" --version 2>/dev/null)"
else
  command -v npm >/dev/null || bd_warn "npm がありません (先に node/install.sh --apply)"
  bd_say "変更あり: playwright を npm -g で入れる"
  bd_run_system npm i -g playwright || bd_die "npm i -g playwright に失敗しました"
  pw=$(pw_path)
fi
if [ -z "$pw" ]; then
  [ "$BD_APPLY" = 1 ] && bd_say "playwright が無いので、ここから先はとばします"
  bd_say "    (dry-run) playwright install chromium"
  bd_say "    (dry-run) sudo playwright install-deps chromium"
  exit 0
fi
# ブラウザ本体は ~/.cache/ms-playwright に入る (入っていれば playwright がとばす)
bd_run_home "$pw" install chromium || bd_die "playwright install chromium に失敗しました"

# 依存の共有ライブラリは apt で入る。再起動で apt の中身が消える環境があるので、足りないときだけ入れる
chrome=$(find "$HOME/.cache/ms-playwright" -path '*chromium*' -name chrome -type f 2>/dev/null | sort | tail -n 1)
if [ -n "$chrome" ] && ! ldd "$chrome" 2>/dev/null | grep -q 'not found'; then
  bd_say "変更なし: Chromium の依存ライブラリ"
elif [ "$(id -u)" -eq 0 ]; then
  bd_run_system "$pw" install-deps chromium
elif [ "$BD_APPLY" = 1 ] && [ -z "${NO_APT:-}" ] && ! sudo -n true 2>/dev/null; then
  bd_warn "sudo が使えないので依存は入れていません → sudo \"$pw\" install-deps chromium"
else
  bd_run_system sudo -n "$pw" install-deps chromium
fi
exit 0
