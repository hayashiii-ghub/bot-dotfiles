# bot-dotfiles

XFCEのLinuxデスクトップの見た目・壁紙・ウィンドウ配置とNode.jsを揃えるスクリプト集。
Bash、apt、xfconf、xfce4-terminal、Thunar、`flock`、`diff`、`jq` または `python3` が必要です。

## 使い方

```bash
git clone https://github.com/hayashiii-ghub/bot-dotfiles.git
cd bot-dotfiles
./install-all.sh            # 差分を見るだけ
./install-all.sh --apply    # 適用する
```

- 既定は表示だけ。`DRY_RUN=1` なら `--apply` でも書きません。`NO_APT=1` でシステムへの導入を止められます。
- 対象と置き先は [manifest.tsv](manifest.tsv)。個別の導入は `xfce/install.sh`、`node/install.sh`、`desktop/install.sh`。Playwrightも入れる場合は `./install-all.sh --apply --with playwright`。
- マシン固有の設定は `~/.config/bot-dotfiles/*.local.env`。秘密値は公開・非公開を問わずGitに入れません。
- 変更前のファイルは `~/.local/state/bot-dotfiles/backup/` に保存します。Node.jsとXツールの大きなコピーは退避しません。`./restore.sh --list` で選び、`./restore.sh <バックアップ名> --apply` で戻します。

```bash
DISPLAY=:N desktop-setup                    # ウィンドウを並べる
DISPLAY=:N desktop-look                     # テーマと壁紙を反映
BOT_LOOK=light ./install-all.sh --apply      # light / dark
./capture.sh                               # マシンとの差分を見る
./capture.sh --public --write               # 検査後、公開側へ取り込む
```

更新後に壁紙の切り替えが反映されない場合は、デスクトップへログインし直してください。
開発・検査の決まりは [AGENTS.md](AGENTS.md)。

## ライセンス

- スクリプトと設定: [MIT](LICENSE)
- 壁紙 (`desktop/wallpaper.png`、`desktop/wallpaper-light.png`): MITの対象外です。個人で使うことと、このツールで使うことはできます。それ以外（再配布、加工しての配布、商用利用など）は持ち主に相談してください。
