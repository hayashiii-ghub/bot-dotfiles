# bot-dotfiles

XFCE の Linux デスクトップを、同じ形に整えるためのスクリプト集です。
ターミナルとファイラーの見た目、壁紙とライト/ダーク、ウィンドウの並べ方、Node.js の導入を扱います。

> **English summary** — Scripts to set up an XFCE Linux desktop: terminal/Thunar settings, wallpaper and light/dark look, a three-pane window layout, and Node.js. Everything is a dry run by default; pass `--apply` to write. Changes are shown as diffs first, are idempotent, and are backed up under `~/.local/state/bot-dotfiles/backup/`. Machine-specific values go in untracked `*.local.env` files. No credentials belong in this repository. Scripts are MIT-licensed; see "ライセンス" (License) for the wallpaper images, which are not MIT.

## 前提

- XFCE のデスクトップ (xfconf、xfce4-terminal、Thunar)、bash、apt 系のディストリビューション
- `jq` か `python3` (JSON をまとめるため)、`flock`、`diff`
- あれば使うもの: `gitleaks` (秘密の検査)

## 入れ方

```bash
git clone https://github.com/hayashiii-ghub/bot-dotfiles.git
cd bot-dotfiles
./install-all.sh            # 何が変わるかを見るだけ (何も書かない)
./install-all.sh --apply    # 書く
```

- 既定は **表示だけ** です。変わるところを `diff -u` の形で見せます。
- `--apply` を付けたときだけ書きます。`DRY_RUN=1` のときは、`--apply` があっても書きません。
- 同じ内容なら「変更なし」と出して何もしません。2回目の `--apply` は何も変えません。
- 1つずつ入れることもできます: `xfce/install.sh`、`node/install.sh`、`desktop/install.sh` (どれも `--apply` で書く)。
- Playwright はおこのみです: `./install-all.sh --apply --with playwright`。
- apt や `npm -g` など `$HOME` の外を触るものは、`--apply` のときだけ動きます。`NO_APT=1` なら動かさず、コマンドを表示します。

## 書きかえる場所

何をどこに置くかは [manifest.tsv](manifest.tsv) に1行ずつ書いてあります。install も capture もこの一覧だけを見ます。

| 場所 | 中身 |
|---|---|
| xfconf の `xfce4-terminal` と `thunar` | フォント、配色、表示のしかた |
| `~/.config/xfce4/terminal/terminalrc` | 同じ値 (古い xfce4-terminal 用。ほかのキーは残す) |
| `~/.config/gtk-3.0/bookmarks` | ブックマーク (足りない行だけ足す) |
| `~/.local/bin/` | `desktop-look`、`desktop-setup`、`wallpaper-keeper`、`wallpaper-keeper-all`、X のツールのラッパー |
| `~/.local/lib/bot-dotfiles/` | 上のスクリプトが使う共通処理と既定の設定 |
| `~/.local/lib/bot-tools/` | X のツール (hsetroot、xdotool など) のコピー。再起動で apt の中身が消える環境向け |
| `~/Pictures/bots-*-wallpaper.png` | 壁紙 |
| `~/.config/autostart/wallpaper-keeper.desktop` | ログイン時に wallpaper-keeper を起動 |
| `~/.config/bot-dotfiles/look.env` | 見た目 (dark / light) |
| `~/.local/node-v24/` | Node.js (`node/install.sh`) |

## デスクトップ

```bash
DISPLAY=:N desktop-setup     # 左: ブラウザ / 右上: ターミナル / 右下: Thunar に並べる
DISPLAY=:N desktop-look      # 壁紙とテーマだけ
wallpaper-keeper-all         # 対象の画面ぜんぶで wallpaper-keeper を起動 (何回実行してもよい)
```

- 画面は `DISPLAY` → 設定の `BOT_DISPLAY` → 自分の xfwm4 が1つならその画面、の順で決めます。決められなければ止まります。
- `wallpaper-keeper` は、ほかの何かが壁紙を差しかえたら戻します。画面ごとに `/tmp/wallpaper-keeper<N>.lock` で1つだけ動きます。
- ライト/ダークを切りかえるとき: `BOT_LOOK=light ./install-all.sh --apply`。`look.env` とターミナルの色が変わり、動いている keeper も次の確認で新しい壁紙にします。GTK のテーマは、そのあと `DISPLAY=:N desktop-look` で変わります (xfconf なので全画面に効きます)。

## ローカルの上書き

値は次の順に重ねて読みます。あとのものが勝ちます。

1. 公開側の `<tool>/config.env` (一般的な既定値)
2. `~/.config/bot-dotfiles/look.env` (見た目だけ)
3. `~/.config/bot-dotfiles/*.local.env` (このマシンだけの値。install は書きかえません)
4. `$BOT_DOTFILES_LOCAL/local/*.local.env` (自分用の非公開リポジトリを使うとき)
5. 環境変数

例: `~/.config/bot-dotfiles/desktop.local.env`

```bash
BROWSER_EXTRA="my-browser|my-browser|Browser"
KEEPER_DISPLAYS=":N-M"
```

`$BOT_DOTFILES_LOCAL` に非公開リポジトリの場所を入れると、その `manifest.local.tsv` の項目も install-all が扱います (同じ id は非公開側が勝ちます)。

## 取りこみ (マシン → リポジトリ)

```bash
BOT_DOTFILES_LOCAL=~/src/my-dotfiles-private ./capture.sh          # 差分を見るだけ
BOT_DOTFILES_LOCAL=~/src/my-dotfiles-private ./capture.sh --write  # 非公開側に書く
./capture.sh --public --write   # 公開側に書く (秘密・形・禁止語の検査を通ったものだけ)
./capture.sh --check            # 差分があれば終了コード 1、確かめられない項目 (xfconf など) があれば 3
```

manifest に載っていないものは読みません。認証ファイル、履歴、DB、ログに当たる名前は、manifest にあっても読みません (終了コード 2)。

## 戻し方

`--apply` で書きかえる前のファイルは `~/.local/state/bot-dotfiles/backup/<日時>/` に元のパスの形で残ります (xfconf はテキストで)。
新しく作ったファイルは一覧 (`created.txt`) に残り、戻すときに消します。ただし `~/.local/node-v24/` と `~/.local/lib/bot-tools/` (大きいコピー) は退避しません。

```bash
./restore.sh --list             # 一覧
./restore.sh 20260101-120000            # 何が戻るかを見るだけ
./restore.sh 20260101-120000 --apply    # 戻す (今の状態も新しい日時で残る)
```

## 認証情報について

トークン、パスワード、鍵、認証ファイル (`.credentials.json`、`auth.json`、`.netrc` など) は、このリポジトリにも非公開リポジトリにも入れません。install と capture は書く前に検査して、見つけたら止まります。

## こまったとき

- **コマンドが消えた**: 再起動で apt で入れたものが消える環境があります。`./install-all.sh --apply` をもう一度実行してください。X のツールは `~/.local/lib/bot-tools` のコピーから動きます (`/usr/bin` にあればそちらを使う)。
- **保存した X のツールが動かない**: `LD_LIBRARY_PATH=~/.local/lib/bot-tools/lib ~/.local/lib/bot-tools/bin/<name> -h` で確かめます。だめなら `sudo apt-get install -y <パッケージ>` で入れなおします (xprop / xdpyinfo は x11-utils、xrefresh は x11-xserver-utils)。
- **壁紙が戻ってしまう**: `pgrep -af wallpaper-keeper` で動いているか確かめ、いなければ `wallpaper-keeper-all` か `DISPLAY=:N wallpaper-keeper &`。
- **窓がばらばら**: `DISPLAY=:N desktop-setup` で、最小化された窓も戻して並べなおします。並べるのは desktop-setup を呼んだときだけで、ログイン時の autostart は wallpaper-keeper を起こすだけです。
- **ブラウザが開かない**: `BROWSER_CMD` / `BROWSER_EXTRA` / `BROWSER_CANDIDATES` の順に探し、無ければ起動して最大 30 秒ほど待ちます。どれも入っていなければブラウザだけとばします。
- **`node -v` が古い**: `~/.local/bin` が PATH の前のほうに無いと、`/usr/bin/node` が使われます。
- **Playwright**: `--with playwright` で `npm i -g playwright`、`playwright install chromium` (`~/.cache/ms-playwright`)、`sudo playwright install-deps chromium` (apt) を行います。ふつうは画面なし (headless) で動きます。見たいときは `DISPLAY=:N` を付けて headed で。
- **`~/.local/bin/<tool>` に別のファイルがある**: ラッパーは上書きしません。消してから `desktop/install.sh --apply`。
- **ライト/ダークを切りかえても壁紙が戻る**: 前の版の wallpaper-keeper は設定を読みなおさず、同じロックを持ちつづけます。更新したあとは、デスクトップのセッションを入れなおしてください。
- **xfconf がとばされる**: `DISPLAY` が無いと xfconf は書きません。デスクトップのセッションの中で実行してください。

## このリポジトリを直すとき

[AGENTS.md](AGENTS.md) を読んでください。コミットの前に `scripts/setup-hooks.sh` でフックを有効にします。

## 指示書

AI エージェント向けの返答のしかたは [minim](https://minim.shigoto.dev/) を参考にしています (このリポジトリには入れていません)。

## ライセンス

- スクリプトと設定ファイル: [MIT](LICENSE)
- 壁紙 (`desktop/wallpaper.png`、`desktop/wallpaper-light.png`): MIT の対象外です。個人で使うことと、このツールで使うことはできます。それ以外 (再配布、加工しての配布、商用の利用など) は持ち主に相談してください。
