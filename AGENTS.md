# エージェント向け

説明は `README.md`、作業指示は `AGENTS.md` に集約し、別の説明文書は作成前に確認する。

## 公開・安全

- 公開リポジトリ。秘密値・認証ファイル・他人の文章の写しを入れない。秘密値は非公開リポジトリにも入れない。
- 個人・マシン・仕事の固有値や導入履歴を入れない。ホームは `$HOME`、画面は `:N` と書く。固有の設定は `~/.config/bot-dotfiles/*.local.env` か非公開リポジトリへ。
- 禁止語リストは `$BOT_DOTFILES_DENYLIST` → `~/.config/bot-dotfiles/denylist.txt` → `$BOT_DOTFILES_LOCAL/denylist.txt` の順。リスト自体・該当語・削除内容を公開せず、検査結果はファイル名と件数だけにする。
- コミットの作者・コミッターはGitHubのnoreplyメールを使う。

## 実装

- 配置の正本は `manifest.tsv`、既定値は `<tool>/config.env`、見た目は `~/.config/bot-dotfiles/look.env`。値を文書に重複させない。`*.tmpl` と `*.example` の `@NAME@` は設定値で置き換える。
- 共通処理は `lib/common.sh`。既定は差分表示だけで、`--apply` のときだけ書く。`DRY_RUN=1` は常に書かず、同じ内容と2回目の適用は変更なしにする。
- aptや `npm -g` など `$HOME` 外の処理は `--apply` かつ `NO_APT` なしのときだけ、通常は `bd_run_system` を通す。
- プロセスを止めない。例外はテーマ変更時の `desktop-look` による `xfsettingsd --replace` だけ。コメントはコードから読めない理由・制約だけにする。

## 検査

コミット前に実行する。シェルを変えていなければshellcheckは不要。

```bash
scripts/setup-hooks.sh
scripts/check-shape.sh
shellcheck -x <変えたスクリプト>
DRY_RUN=1 ./install-all.sh --apply
```

フックはnoreply・gitleaks・形・禁止語を検査する。CIは全履歴のgitleaks、現在の形とshellcheckを実行する。禁止語リストがない場合の警告を、検査済みと扱わない。
テストは一時的なホームとxfconf-query・apt等のスタブで行い、自分の `$HOME` に `--apply` しない。
