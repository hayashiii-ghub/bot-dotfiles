#!/bin/bash
# このリポジトリの hooks/ を git のフックとして使うようにする (このリポジトリの設定だけを変える)
set -eu
cd "$(dirname "$0")/.."
git config core.hooksPath hooks
echo "core.hooksPath=hooks を設定しました。コミットのたびに hooks/pre-commit と hooks/commit-msg が動きます"
command -v gitleaks >/dev/null 2>&1 || echo "注意: gitleaks が見つかりません。入れておくと秘密の検査もできます" >&2
