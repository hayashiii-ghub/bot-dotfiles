# AGENTS.md — このリポジトリを直す人とエージェントへの約束

このリポジトリは公開されています。書いたものは誰でも読めます。

## 入れないもの

- 秘密: トークン、パスワード、鍵、認証ファイル、その一部。非公開リポジトリにも入れません。
- 個人やマシンの値: 実際のホームのパス (`$HOME` と書く)、ユーザー名、メールアドレス、マシン名、具体的なディスプレイ番号 (`:N` と書く)、使っているサービスの名前、仕事や案件の名前、いつ何を入れたかの記録。
- マシン固有の値は `~/.config/bot-dotfiles/*.local.env` か非公開リポジトリに置きます。ここには一般的な既定値だけを置きます。
- 他の人が書いた文章の写し。リンクだけにします。

## 禁止語

- 公開できない語 (案件名など) は、非公開の禁止語リストで検査します。`$BOT_DOTFILES_DENYLIST`、`~/.config/bot-dotfiles/denylist.txt`、`$BOT_DOTFILES_LOCAL/denylist.txt` の順に探し、最初に見つかったものを使います。
- 禁止語リストそのものは、このリポジトリに入れません。何を消したかも、README やコミットメッセージに書きません。
- 検査で見つけた語は表示しません。ファイル名と件数だけを出します。

## 値は1か所

- 何をどこに置くかは `manifest.tsv` にだけ書きます (列: id、repo のパス、HOME 下の置き先、扱い方、区分)。id の頭 (`xfce-`、`desktop-`) で、どの install.sh が扱うかが決まります。
- 既定値は `<tool>/config.env` にだけ書きます。README には値をくり返しません。
- 見た目 (`BOT_LOOK`) は `~/.config/bot-dotfiles/look.env` だけに覚えます。
- `*.tmpl` と `*.example` は、`@NAME@` を設定の値に置きかえてから置きます。

## スクリプトの作り

- 共通の処理は `lib/common.sh` を使います。
- 既定は表示だけ。`--apply` のときだけ書きます。`DRY_RUN=1` はいつでも書きません。
- 書く前に差分を見せ、同じなら書きません。2回目の `--apply` で何も変わらないようにします。
- `$HOME` の外 (apt、`npm -g`、sudo) は `--apply` かつ `NO_APT` が無いときだけ動かします (ふつうは `bd_run_system` を通す)。
- プロセスを止めません (`pkill` や `kill` を使わない)。例外: `desktop-look` はテーマを変えたときだけ `xfsettingsd --replace` で入れかえます。
- コメントには、コードから読み取れない理由や制約だけを書きます。

## 検査

コミットの前に:

```bash
scripts/setup-hooks.sh            # 最初に1回。hooks/pre-commit が動くようになる
scripts/check-shape.sh            # 形の検査
shellcheck -x <変えたスクリプト>
DRY_RUN=1 ./install-all.sh --apply   # 何も書かれないこと
```

`hooks/pre-commit` は、作者とコミッターのメールが GitHub の noreply でないとき、gitleaks か形の検査か禁止語の検査に当たったときに止めます。`hooks/commit-msg` はコミットメッセージに形の検査と禁止語の検査をかけます。CI (`.github/workflows/scan.yml`) は全履歴に gitleaks を、今のファイルに形の検査と shellcheck をかけます。

テストは一時的な `HOME` で行い、xfconf-query や apt などはスタブに置きかえます。自分の `HOME` に `--apply` しないでください。
