# emacs-windows-native-gui

秀丸・サクラエディタ・EmEditor・Mery のような Windows ネイティブ GUI エディタの操作感で Emacs を使うための個人設定ファイルです。
日本語環境とポータブル運用を前提に、テキスト編集、個人メモ管理、AI ツール連携の設定を含みます。

> **設計方針**: キーボード操作で完結させる Emacs 設定とは異なり、GUI・マウス操作を併用する前提です。
> メニューバー、ツールバー、タブバー、右クリックメニューを使用し、`Ctrl+C/V/Z`（CUA キーバインド）は Windows アプリと同じ割り当てにしています。
> キーボード編集用に **Meow（モーダル編集）** を組み込んでいます。Ctrl キーは Windows 標準の操作、通常キーは Meow に割り当てています。

![スクリーンショット](screenshot.jpg)

## 特徴

- **ポータブル設計** — `user-emacs-directory` を `init.el` の場所から動的に解決するため、USB やフォルダごと移動しても動作します
- **遅延読み込み** — Obsidian や howm など読み込みに時間がかかる処理は、使用時まで読み込みを遅らせています。ダッシュボードに読み込みパッケージ数と起動時間を表示します
- **ダッシュボード（emacs-dashboard）** — 起動時に、最近開いたファイル、ブックマーク、プロジェクト一覧をカスタムバナー画像とともに表示します
- **CUA モード前提** — `C-c / C-x / C-v / C-z` を Windows 標準のコピー・切り取り・貼り付け・アンドゥに割り当てています。Emacs 標準の `C-x` プレフィックスとは共存させています
- **GUI 要素** — メニューバー、ツールバー（カスタムアイコン）、タブバー、右クリックメニュー（EmEditor 風）を有効にしています
- **日本語対応** — Migemo によるローマ字検索、cp932 ファイルパス対応、mozc-modeless によるモードレス日本語入力を含みます。Windows Terminal などの `-nw`（ターミナル）環境でも、OS の IME 制約を受けずに `Ctrl+\` で日本語を入力できます
- **タブバー（Centaur Tabs）** — 内部バッファ（`*scratch*` など）はタブバー上で後方に配置されます。`F2`（consult-buffer）で一覧から選択・切り替えできます
- **全角スペース・TAB・行末スペースの可視化** — 全角スペースを「`□`」、TAB を「`»`」で表示し、行末のスペースをテーマの警告色の下線で表示します
- **サクラエディタ風の正規表現キーワード強調** — テキストと Markdown 文書で、各種括弧（`「」` `【】` `（）` など）、引用符（`''` `""`）、および丸数字（`①-⑳`）を色分け表示します
- **リアルタイム置換（visual-replace）** — 入力中に、置換後の状態をバッファ上でプレビュー表示します
- **ソフトナローイング（独自実装）** — Narrow 時に、範囲外を非表示にせずグレーアウト表示にします
- **Meow（モーダル編集）+ Puni（構造編集）** — CUAと共存する形でモーダル編集を追加。Helix/Kakoune風の選択内マッチ（`s`）・置換（`r`）・行選択（`x`）・行分割（`C`）・ケース反転（`~`）や、レジスタ対応の切り取り/コピー/貼り付け、Puniによる括弧構造編集（囲み選択・wrap/slurp/barf）などを組み込んでいます
- **EPUB 電子書籍リーダー（nov.el）の機能拡張** — ヘッダーラインへの読書進捗（書籍名・章名・第X/Y章・進捗率%）の常時表示、電子書籍本棚機能（`B` / `my/nov-bookshelf`）、しおり（`m`: 挟む / `b`: ジャンプ / `M`: 一覧）、Vim 風の読書キー（`j`/`k`: 1行、`d`/`u`: 半画面、`o`: 全章目次 Consult ジャンプ）を追加しています

## 主な構成

| セクション | 内容 |
|---|---|
| 1. 起動・基本動作 | ダッシュボード画面（emacs-dashboard）、遅延読み込み（Lazy Loading）、文字コード、バックアップ設定 |
| 3. 外観 | iceberg-theme（テーマファイルの作成のみ。自動適用はしない）、フォント（Utatane。なければ MS Gothic）、ツールバーアイコン（Adwaita） |
| 4. 表示・スクロール | 行番号、スクロール挙動、全角スペース・TAB・行末スペース・正規表現キーワードの可視化 |
| 5. モードライン | カスタムレイアウト、パスホバー表示 |
| 6. タブバー | Centaur Tabs によるバッファタブ |
| 8. キーバインド | CUA 互換、F キー割り当て、`M-o` Hydra ランチャー |
| 11. 補完エコシステム | Vertico + Orderless + Consult + Migemo + Embark |
| 12. multiple-cursors | マルチカーソル編集（`C->` / `C-<`） |
| 13. howm | Obsidian 互換 Markdown メモ（howm-markdown.el）、`#タグ` ボタン、遅延読み込み、consult-ripgrep 連携 |
| 14. Obsidian 連携 | obsidian.el によるノート検索・保存（オンデマンド読み込み） |
| 19. nov.el | EPUB 電子書籍リーダー、読書進捗ヘッダーライン表示、本棚（`B`）、しおり（`m`/`b`/`M`）、スムーズスクロール |
| 21b. Mozc 日本語入力 | mozc-modeless による日本語入力、`C-\\` で手動 ON/OFF トグル。Windows Terminal 等の `-nw`（CUI）環境でも使用でき、ターミナル内で日本語入力が可能 |
| 23. GhostText 連携 | atomic-chrome によるブラウザ入力欄のリアルタイム編集 |
| 24. リアルタイム置換 | visual-replace によるリアルタイムプレビュー付き置換（通常/正規表現） |
| 25. 範囲外のグレーアウト | 独自実装によるソフトナローイング（範囲外のグレーアウト表示） |
| 27. Meow | CUAと共存するモーダル編集。Helix/Kakoune風の選択内マッチ（`s`）・置換（`r`）・行選択（`x`）・行分割（`C`）・Goto（`g`）・選択解除（`ESC`）、F1 操作ガイド、レジスタ対応の切り取り/コピー/貼り付けなど |
| 28. Puni | 括弧・リストの構造を意識した編集（囲み選択、wrap/slurp/barf） |

その他：calfw（カレンダー）、Casual（Transient メニュー）、symbol-overlay（カラーマーカー）、Lookup（EPWING 辞書）、nov.el（EPUB）、zoxide 連携、fd / ripgrep 連携、visual-replace（リアルタイム置換）、独自実装のソフトナローイング（範囲外グレーアウト）

## キーバインド早見表

詳細版は **[cheatsheet.md](cheatsheet.md)** を参照してください。

| キー | 動作 |
|---|---|
| `Home` | ダッシュボードの表示 / 再描画（ダッシュボード上では閉じて元のバッファに戻る） |
| `M-o` | Hydra ランチャー（各種サブメニュー） |
| `F4` | アウトラインサイドバー開閉（imenu-list） |
| `F5` | バッファ再読み込み（ディスクから更新確認） |
| `F7` | howm 環境トグル（ON: howm-menu を開く / OFF: howm 関連バッファを閉じる）※ `M-o H` でも可 |
| `F8` | カレンダー（calfw）の開閉 |
| `S-F8` | 週間天気予報（`M-o W` でも可） |
| `C-\\` | mozc（日本語入力）ON / OFF トグル |
| `C->` | 次の同じ単語にカーソル追加（multiple-cursors） |
| `C-<` | 前の同じ単語にカーソル追加（multiple-cursors） |
| `C-c m a` | バッファ内の全同一単語にカーソル追加 |
| `C-c m l` | 選択範囲の各行にカーソル追加 |
| `Alt + ドラッグ` | 矩形選択（`rectangle-mark-mode`）を開始 |
| `C-RET` (Ctrl+Enter) | キーボードによる矩形選択を開始 |
| `ESC` | 矩形選択（または選択範囲）の解除 |
| `C-e` | 行頭・行末のトグル（インデント先頭 ⇆ 本当の行頭 ⇆ 行末） |
| `M-z` (Alt+Z) | vundo — undo ツリーを視覚化してツリー上の任意の過去状態に戻る |
| `M-%` | リアルタイム通常置換（visual-replace） |
| `C-M-%` | リアルタイム正規表現置換（visual-replace） |
| `C-h` | 置換オプションのポップアップメニュー（通常/正規表現、全体/一部） |
| `F1` | ヘルプ（`C-h`を置換に転用したためF1に一本化） |

> [!NOTE]
> Meow（モーダル編集）のキー（NORMAL/INSERT状態など）は上記のCtrl系ショートカットとは別レイヤーです。詳細は **[cheatsheet.md](cheatsheet.md)** の「Meow」セクションを参照してください。

### ダッシュボードでのショートカット

ダッシュボード表示中（`*dashboard*` バッファ）は、次のキーを1回押すと各機能を呼び出せます。

| キー | 動作 |
|---|---|
| `Home` | ダッシュボードを閉じて直前のバッファに戻る |
| `o` | メインメニュー（Hydra ランチャー） |
| `e` | Everything で PC 内検索 |
| `s` | プロジェクト内全文検索（ripgrep） |
| `g` | プロジェクト内ファイル名検索（fd） |
| `f` | 最近使ったファイルを開く |
| `c` | cmd.exe（ConPTY ターミナル） |
| `p` | PowerShell（ConPTY ターミナル） |
| `L` | カレンダー（calfw） |
| `d` | 辞書（Lookup） |
| `w` | ウィンドウ操作サブメニュー |
| `F` | ファイル操作サブメニュー |

### ツールバーの機能割り当て

ツールバーには次の機能が割り当てられています。

| アイコン名 | 割り当て機能 | 関数 | 説明 |
|---|---|---|---|
| `tb-new.png` | 新規ファイル | `find-file` | 新規ファイルを作成して開く |
| `tb-open.png` | ファイルを開く | `menu-find-file-existing` | ダイアログ等を使って既存のファイルを開く |
| `tb-save.png` | 上書き保存 | `save-buffer` | 現在のバッファを保存する |
| `tb-undo.png` | 元に戻す | `undo` | 直前の操作を取り消す |
| `tb-redo.png` | やり直す | `undo-redo` | 取り消した操作をやり直す |
| `tb-cut.png` | 切り取り | `kill-region` | 選択範囲をカットしてキルリングに保存 |
| `tb-copy.png` | コピー | `kill-ring-save` | 選択範囲をコピーしてキルリングに保存 |
| `tb-paste.png` | 貼り付け | `yank` | キルリングから内容を貼り付け |
| `tb-search.png` | Consult検索 | `my/toolbar-consult-menu` | クリック時にポップアップメニューを表示し、consult-line（行検索）または consult-outline（アウトライン検索）を選択して起動 |
| `tb-search-fwd.png` | 後を検索 | `isearch-forward` | 現在地より後方（下）に向かってインクリメンタル検索 |
| `tb-search-bwd.png` | 前を検索 | `isearch-backward` | 現在地より前方（上）に向かってインクリメンタル検索 |
| `tb-replace.png` | 置換 | `my/visual-replace-menu` | 通常/正規表現、全体/カーソル以下の置換オプションを選択するポップアップメニューを表示 |
| `tb-filter.png` | フィルタ表示 | `my/toolbar-filter-menu` | クリック時にポップアップメニューを表示し、`occur-edit`（標準）または `moccur-edit`（Migemo 対応）を選んで `my/emeditor-filter` を起動する。検索条件にマッチする行のみを抽出し、その場で直接編集できる（`C-c C-c` で適用保存） |
| `tb-marker.png` | マーカー設置 | `my/marker-put` | カーソル位置の単語や選択範囲にカラーマーカーを付与／消去 |
| `tb-marker-clear.png` | マーカークリア | `my/toolbar-marker-clear-menu` | クリック時にポップアップメニューを表示し、すべてのマーカーの削除（`C-S-u`）、またはカーソル位置のマーカーの削除（`C-S-k`）を選択 |
| `tb-diff.png` | 差分比較 | `my-compare-with-winmerge` | 現在のファイルを WinMerge で比較。2画面分割中は両方のファイルを比較し、1画面のみの場合は同一ファイルを対象にする |
| `tb-encoding.png` | エンコード変更 | `revert-buffer-with-coding-system` | 文字コードを指定してファイルを読み直す |
| `tb-open-ext.png` | 外部アプリ連携 | `my-open-current-file-in-windows` | 開いているファイルを Windows の関連付けプログラムで開く |
| `tb-split-horiz.png` | 左右に分割 | `split-window-right` | ウィンドウを左右に2分割する |
| `tb-split-vert.png` | 上下に分割 | `split-window-below` | ウィンドウを上下に2分割する |
| `tb-close.png` | ウィンドウ閉じる | `delete-window` | 現在アクティブなウィンドウ（分割画面）を閉じる |
| `tb-close-others.png` | 他ウィンドウ閉じる | `delete-other-windows` | 他の分割ウィンドウをすべて閉じて1画面に戻す |

## ディレクトリ構造とポータブル起動

ポータブル運用を想定した配置例です。`emacs/` フォルダと起動用のバッチファイルをセットで移動・コピーすれば動作します。

```
任意のフォルダ/ (例: emacs_portable/)
├── run-emacs.bat            ← ポータブル起動用バッチファイル（これをダブルクリックして起動します）
├── run-emacs-wt.bat         ← Windows Terminal で Emacs (CUI) を新規起動するバッチ
├── run-emacs-nw.bat         ← 現在のターミナル内で Emacs (CUI) を直接起動するバッチ
├── run-emacs-debug.bat      ← デバッグ起動用バッチファイル
├── emacs/                   ← Emacs 本体（runemacs.exe など）
│   └── bin/
│       └── runemacs.exe
├── .emacs.d/                ← この設定リポジトリ（ユーザー環境のメイン設定）
│   ├── init.el              ← メイン設定ファイル
│   ├── custom.el            ← M-x customize の設定（自動生成）
│   ├── fonts/               ← ポータブルフォント（Utatane など）
│   ├── lisp/                ← 自作の Elisp（auximap.el / auxbookmark.el / stock-charts/）。他者作の conpty.el と lookup/ も init.el が lisp/ から読み込む
│   ├── site-lisp/           ← 他者が作成した Elisp のうち、MELPA 以外から入手したもの（color-moccur.el / moccur-edit.el）
│   ├── images/              ← ツールバーアイコン（tb-*.png、Adwaita アイコン）
│   ├── elpa/                ← package.el が管理するパッケージ群（MELPA から導入したもの。自動生成）
│   └── .cache/              ← キャッシュ・履歴（自動生成。frame-geometry.el と savehist の USB 側コピー、projects、tramp、nov-places など）
└── bin/                     ← 外部コマンド（PATH がなくてもここから自動検出）
    ├── cmigemo.exe          ← Migemo（日本語ローマ字検索）
    ├── fd.exe               ← ファイル検索
    ├── rg.exe               ← ripgrep（全文検索）
    ├── es.exe               ← Everything CLI（locate 連携）
    └── emacs-conpty.exe     ← Windows ConPTY プロキシ
```

> **`lisp/` と `site-lisp/` の使い分け**: 方針は、自分で書いた Elisp を `lisp/`、他者が作成した Elisp のうち MELPA 以外から入手したものを `site-lisp/` に置くことです（`init.el` 冒頭のコメントに記載）。ただし `conpty.el` と `lookup/` は他者作ですが、`init.el` が `lisp/` から読み込みます。MELPA から導入するパッケージは `elpa/` に自動配置されるため、手動では置きません。詳細は「[`lisp/` と `site-lisp/` の使い分け](#lisp-と-site-lisp-の使い分け)」を参照してください。

> **起動方法**: `run-emacs.bat` を実行すると、環境変数 `HOME` をバッチファイルのあるフォルダ（ポータブルルート）に自動設定した状態で Emacs を起動します。USBや別のPCへフォルダごと持ち運んだ場合も同一の設定で動作します。
> 
> `frame-geometry.el` と `savehist` は、終了時にまず一時ディレクトリ（`%TEMP%`）の `emacs-portable-*` に書き込み、その後 `.cache/` へ非同期でコピーします。
> 
> `bin/` 内の外部コマンドは PATH が通っていれば省略可能です。init.el が PATH → `bin/` の順に自動検出します。

> [!NOTE]
> **Migemo（日本語ローマ字検索）の辞書とDLLについて**:
> - **辞書の配置**: `cmigemo.exe` が置かれている場所から相対的に `dict/utf-8/migemo-dict` となるように辞書ファイルを配置してください（例: `bin/dict/utf-8/migemo-dict`）。
> - **DLLについて**: Emacsの `migemo` パッケージは `cmigemo.exe` を外部プロセスとして呼び出して通信するため、**`migemo.dll` や `cmigemo.dll` などの DLL ファイルは不要**です。

### フォントの準備

本設定は、プログラミング用日本語等幅フォント **[Utatane](https://github.com/nv-h/Utatane)** を使用します。

1. **フォントの入手**: 
   GitHub リポジトリ [https://github.com/nv-h/Utatane](https://github.com/nv-h/Utatane) から、またはご自身でビルドした `Utatane-Regular.ttf` を取得します。
2. **配置先**:
   設定ディレクトリ配下の `.emacs.d/fonts/` フォルダの中に `Utatane-Regular.ttf` を配置してください。
   （※フォントが見つからない場合は、自動的に `MS Gothic` が代替フォントとして適用されます）

## パッケージ一覧

### 補完・検索

| パッケージ | 用途 |
|---|---|
| vertico | 縦型ミニバッファ補完 UI |
| vertico-multiform | コマンドごとの表示方式切り替え |
| vertico-posframe | カーソル近傍ポップアップ表示 |
| orderless | スペース区切りのあいまい補完 |
| consult | 検索コマンド群（ripgrep・fd・locate 連携） |
| embark / embark-consult | 候補への即時アクション |
| marginalia | ミニバッファ候補への注釈表示 |
| corfu | インラインコード補完 |
| cape | corfu 向け補完ソース拡張 |
| migemo | 日本語ローマ字インクリメンタル検索 |
| wgrep | grep 結果バッファを直接編集 |

### メモ・ドキュメント

| パッケージ | 用途 |
|---|---|
| howm | 個人メモ管理（Obsidian 互換 Markdown） |
| obsidian | Obsidian vault との連携 |
| markdown-mode | Markdown 編集・プレビュー |
| markdown-toc | 目次自動生成 |
| imenu-list | アウトラインサイドバー |
| org-download | 画像の drag & drop 貼り付け |
| nov | EPUB リーダー |
| lookup | EPWING 辞書検索 |
| csv-mode | CSV 表示・編集 |

### UI・外観

| パッケージ | 用途 |
|---|---|
| dashboard | 起動時ダッシュボード画面（バナー表示） |
| iceberg-theme | カラーテーマ（テーマファイルの作成のみ。自動適用はしない） |
| modus-themes | 他テーマの依存パッケージ |
| centaur-tabs | バッファタブバー |
| nyan-mode | モードライン Nyan Cat |
| hide-mode-line | 特定のウィンドウでモードラインを非表示にする |
| hydra | キーバインドメニュー |
| casual / casual-symbol-overlay | Transient ベースのメニュー UI |
| symbol-overlay | カーソル下の単語をカラーハイライト |
| calfw / calfw-howm | カレンダー表示 |
| japanese-holidays | 日本の祝日データ |

### 編集補助

| パッケージ | 用途 |
|---|---|
| multiple-cursors | マルチカーソル編集 |
| bicycle | バッファ折りたたみ操作 |
| rainbow-delimiters | 括弧を深さごとに色分け表示 |
| vundo | undo 履歴をツリーで視覚化して任意の時点に戻る（`M-z`） |
| zoxide | 頻繁に使うディレクトリへの移動（`M-o z`） |
| dmacro | 繰り返し操作の自動マクロ実行（`C-t`） |
| visual-replace | リアルタイムプレビュー付き置換 |

### モーダル編集

| パッケージ | 用途 |
|---|---|
| meow | CUAと共存するモーダル編集（NORMAL/INSERT/MOTION状態、レジスタ対応の切り取り/コピー/貼り付けなど） |
| puni | 括弧・リストの構造を意識した編集（囲み選択、wrap/slurp/barf、壊れない Backspace） |

### AI 連携

| パッケージ | 用途 |
|---|---|
| gptel | LLM との対話（`M-o F A` の AI & Antigravity メニューから利用） |

### Windows 連携

| パッケージ | 用途 |
|---|---|
| tr-ime | IME 制御（w32-ime 互換）— 現在は `my/use-mozc-modeless = t` のため **無効** |
| mozc / mozc-modeless | モードレス日本語入力（Google 日本語入力連携）— **現在の主体**。Windows Terminal 上の `-nw` 環境でも OS の IME 制約を受けずに動作 |
| conpty | Windows ConPTY ターミナル（emacs-conpty） |
| atomic-chrome | GhostText 拡張機能と連携したブラウザ入力欄の編集 |

### 全インストールパッケージ一覧 (MELPA)

`init.el` の `use-package` 宣言（`use-package-always-ensure` が `t`）により、起動時に MELPA から自動インストールされるパッケージの一覧です。

- `atomic-chrome` — GhostText 拡張機能との連携用 WebSocket サーバー
- `bicycle` — 見出し折りたたみ（outline-minor-mode 連携）
- `calfw` / `calfw-howm` — カレンダー表示・スケジュール統合
- `cape` — 補完バックエンド拡張（capf）
- `casual` — Transient ベースのメニュー UI
- `casual-symbol-overlay` — transient ベースのカラーマーカーメニュー
- `centaur-tabs` — バッファタブバー表示
- `consult` — 検索コマンド群（ripgrep・fd・locate 連携）
- `corfu` — ポップアップ自動補完 UI
- `csv-mode` — CSV 表示・編集
- `dashboard` — 起動時ダッシュボード画面（バナー画像対応）
- `dmacro` — 繰り返し操作の自動マクロ実行（`C-t`）
- `embark` / `embark-consult` — 選択候補への即時アクションランチャー
- `gptel` — LLM との対話
- `hide-mode-line` — 不要なウィンドウ（サイドバー等）でモードラインを非表示化
- `howm` — 個人メモ管理（Obsidian 互換 Markdown）
- `hydra` — キーバインドメニュー
- `iceberg-theme` — カラーテーマ（テーマファイルの作成のみ。自動適用はしない）
- `imenu-list` — 右サイドバーのアウトライン見出し一覧
- `japanese-holidays` — カレンダー用日本の祝日データ
- `marginalia` — ミニバッファ補完候補へのメタ情報/注釈表示
- `markdown-mode` / `markdown-toc` — Markdown 編集と目次自動生成
- `meow` — CUAと共存するモーダル編集レイヤー
- `migemo` — 日本語ローマ字でのバッファ内検索
- `modus-themes` — 他テーマの依存パッケージ
- `mozc` / `mozc-modeless` — モードレス日本語入力環境
- `multiple-cursors` — 複数箇所同時編集（マルチカーソル）
- `nov` — EPUB 電子書籍リーダー
- `nyan-mode` — モードラインの Nyan Cat 進行度バー
- `obsidian` — Obsidian Vault との連携
- `orderless` — スペース区切りのあいまいマッチ補完
- `org-download` — ドラッグ＆ドロップによる画像保存・Markdown挿入
- `persistent-scratch` — scratch バッファ内容の保存と自動復元
- `pulsar` — カーソル移動・スクロール・ウィンドウ切り替え時の行パルスエフェクト
- `puni` — 括弧・リストの構造を意識した編集（Meow用に囲み選択も追加設定済み）
- `rainbow-delimiters` — 括弧・ブラケットを深さごとに色分け表示
- `symbol-overlay` — カーソル下の単語をカラーハイライト
- `tr-ime` — Windows IME 制御連携（w32-ime 互換）。`my/use-mozc-modeless` が `t` のため無効
- `vertico` / `vertico-posframe` — 縦型ミニバッファ補完とフレーム内ポップアップ化
- `visual-replace` — リアルタイムプレビュー付き置換
- `vundo` — undo 履歴をツリー構造で視覚化し、任意の過去状態に戻る（`M-z`）
- `wgrep` — grep / ripgrep 結果バッファの直接編集機能
- `zoxide` — ディレクトリ履歴ベースの移動

`use-package` で `:ensure nil` を指定しているもの（`uniquify`、`saveplace`、`recentf`、`savehist`、`vertico-multiform`、`conpty`、`color-moccur`、`moccur-edit`、`lookup`）は、Emacs 標準・パッケージ同梱、またはローカルの Elisp のため、MELPA からは導入しません。

### オリジナル実装

パッケージに依存せず init.el に直接実装した機能です。

| 関数 | 用途 |
|---|---|
| my/media-search-and-play | Everything (es.exe) で全ドライブの音楽・動画を検索して再生 |
| my/emeditor-filter | EmEditorのフィルタ風：検索ワードにマッチした行だけを表示し、直接編集・一括保存 |
| my/wgrep-replace | ripgrepで複数ファイルを検索し、結果を直接編集して一括保存 |
| my/ctx-add-quote | 選択範囲または現在行の行頭に引用記号（`> `）を挿入（右クリックメニュー連携） |
| my/ctx-remove-quote | 選択範囲または現在行の行頭の引用記号（`>`）を削除（右クリックメニュー連携） |
| my/revert-buffer-with-confirm | F5 で現在のバッファをディスクから再読み込み（更新確認） |
| my/howm-toggle | F7 または M-o H で howm 環境を ON/OFF トグル |
| my/consult-ripgrep-project | プロジェクトルートから ripgrep 検索 |
| my/consult-ripgrep-word | カーソル下の単語で ripgrep 検索 |
| my/consult-line-migemo | Migemo でバッファ内インクリメンタル検索 |
| my/consult-line-symbol-at-point | カーソル下の単語をポップアップ検索 |
| my/obsidian-ripgrep-migemo | Obsidian vault を Migemo で全文検索 |
| my/document-text-view | xdoc2txt / Pandoc でバイナリ文書をテキスト表示 |
| my/nov-open-epub | EPUB ファイルを nov.el で開く |
| my/nov-bookshelf | 電子書籍本棚：最近読んだ本や登録フォルダ内のEPUB/AZW3を一覧検索して開く（`B`） |
| my/nov-header-line | ヘッダーラインに書籍タイトル・章名・章番号（第X/Y章）・読書進捗率（%）を常時表示 |
| dashboard-init-info（lambda） | package-quickstart 環境下でもロード済みパッケージ数を算出してダッシュボードに表示 |
| my/eww-copy-markdown-link | EWW 閲覧ページのタイトルとURLを Markdown リンク形式でコピー（`w` / `y`） |
| my/eww-search-at-point | カーソル下の単語または選択範囲で即座に EWW Web 検索 |
| my/eww-open-in-new-tab | カーソル下のリンクを新しい EWW タブ（別バッファ）で開く（`M-Enter`） |
| my/eww-jump-to-heading | EWW 記事内の全見出し目次を Consult / imenu で一覧ジャンプ（`o`） |
| my/consult-eww-history | EWW の閲覧履歴を Consult / Vertico でインクリメンタル検索・復元（`H`） |
| my/consult-eww-bookmarks | EWW のブックマークを Consult / Vertico でインクリメンタル検索・ジャンプ（`B`） |
| my/calfw-add-schedule | カレンダー選択日付に howm 予定を直接登録し即座に画面更新（`i` / `a`） |
| my/calfw-create-howm-memo | カレンダー選択日付をタイトルにした howm 予定メモ（Markdown）を作成（`c`） |
| my/weather | 気象庁公式データによる中四国・全国の週間天気予報テーブルを表示（`S-F8` / `M-o W`） |
| my/meow-cut / my/meow-copy / my/meow-paste | Meowの切り取り/コピー/貼り付け（`M-0`〜`M-9`前置でレジスタ0-9を指定可能） |
| my/meow-select-matches-in-region | 選択範囲内のパターンにマッチする全箇所をBeacon化（Helix風選択内マッチ、Smart Case対応） |
| my/meow-replace | ミニバッファ対話式の一括置換（空Enterでコピー内容置換、Helix風） |
| my/meow-split-lines | 選択行を各行カーソル（Beacon）に分割（Helix風の `C`） |
| my/meow-select-whole-buffer | バッファ全体を選択（Helix風の `%`） |
| my/meow-toggle-case | 大文字・小文字トグル反転（Helix風の `~`） |
| my/meow-goto-dispatch | Helix風 Goto ディスパッチャ（`50g` で指定行ジャンプ、`gh`/`gl`/`gg`/`ge`/`gi`） |
| my/meow-cancel-selection | 選択解除、および Beacon（マルチ選択）の解除（`<escape>` / `q`） |
| my/smart-help | F1 操作ガイド（NORMAL / INSERT 状態に応じたヘルプ表示） |
| my/meow-insert-exit | MeowのINSERT終了時、IMEがONなら先にOFFにしてからNORMALへ復帰 |
| my/run-agy-cmd-on-current-file | 現在のファイルを Google Antigravity(agy.exe) に渡し、cmd 外部窓で実行 |
| my/run-agy-powershell-on-current-file | 現在のファイルを Google Antigravity(agy.exe) に渡し、PowerShell 外部窓で実行 |
| my/run-command-cmd-on-current-file | 現在のファイルを引数にして、cmd 外部窓でコマンドを実行（%f=パス） |
| my/run-command-powershell-on-current-file | 現在のファイルを引数にして、PowerShell 外部窓でコマンドを実行（%f=パス） |
| stock-charts | 株式チャートブラウザ（楽天通常 ⇄ 株ドラゴン価格帯別出来高のグリッド表示） |
| consult-stock-chart-all | 東証全上場銘柄（約4,400銘柄）を Consult でインクリメンタル検索し、チャートを表示 |

### 外部コマンド実行（現在ファイルを対象）

開いているファイルに対して、外部のコンソールプログラム（例: `agy.exe` や `python.exe`）を別ウィンドウのターミナルで実行する機能です。
メインメニューから `M-o F` (ファイル操作) を開き、そこから実行できます。

* **自動保存**: 実行時にバッファに変更がある場合は、自動的に上書き保存を行ってから実行します。
* **カレントディレクトリの追従**: 起動するターミナルは、常に現在開いているファイルのディレクトリ（フォルダ）をカレントディレクトリとして開きます。
* **利用可能なシェル**: `cmd.exe` と `PowerShell` に対応しており、それぞれ別のキーバインドがあります。
* **ターミナルウィンドウの自動選択**: `wt.exe`（Windows Terminal）がシステムに存在する場合は自動的に Windows Terminal の新しいタブ／ウィンドウとして起動し、ない場合は標準のコンソール（ConHost）ウィンドウで起動します。

#### キーバインド一覧

| キー | 関数 | 説明 |
|---|---|---|
| `M-o F a` | `my/run-agy-cmd-on-current-file` | `agy` に現在のファイルを渡し、`cmd` 窓で実行します。引数を指定可能です。 |
| `M-o F A p` | `my/run-agy-powershell-on-current-file` | `M-o F A` で AI & Antigravity メニュー（`hydra-ai`）を開き、`p` で `agy` に現在のファイルを渡して `PowerShell` 窓で実行します。引数を指定可能です。 |
| `M-o F x` | `my/run-command-cmd-on-current-file` | 任意の外部コマンドを `cmd` 窓で実行します。入力時に `%f` と書くとファイルパスに置き換わります（ない場合は末尾に追加）。 |
| `M-o F X` | `my/run-command-powershell-on-current-file` | 任意の外部コマンドを `PowerShell` 窓で実行します。入力時に `%f` と書くとファイルパスに置き換わります（ない場合は末尾に追加）。 |

## 動作環境・前提条件

- **OS**: Windows 10 / 11
- **Emacs**: GNU Emacs 31 で確認
- **日本語入力（※ mozc-modeless を使う場合）**:
  - Windows に本家 **「Google 日本語入力」** がインストールされていること（※ `mozkey` などの個別・派生ツールではなく、公式の Google 日本語入力本体が必要です）。
  - **既定の IME に設定する必要はありません**。Windows 全体の IME は Microsoft IME や ATOK のままで動作します。Emacs は変換サーバーとのみ通信します。
  - ポータブルディレクトリの `bin/mozc_emacs_helper.exe` を使用します。
  - （※ `tr-ime` を使用する場合は Google 日本語入力のインストールは不要です）

## `lisp/` と `site-lisp/` の使い分け

Elisp の配置先は、コードの出どころで決めます。

| ディレクトリ | 配置するもの | 該当ファイル |
|---|---|---|
| `lisp/` | 自作の Elisp。および `init.el` が `lisp/` から読み込む `conpty.el`、`lookup/` | `auximap.el`（要 `auximap.exe`）、`auxbookmark.el`（要 `auxbookmark.exe`）、`stock-charts/`（株式チャート表示、東証全銘柄検索）、`conpty.el`（Windows ConPTY ターミナル）、`lookup/`（EPWING 辞書。`lisp/lookup/lisp` を `load-path` に指定） |
| `site-lisp/` | 他者が作成した Elisp のうち、MELPA 以外から入手したもの | `color-moccur.el`、`moccur-edit.el` |
| `elpa/` | MELPA から導入したパッケージ（package.el が自動配置。手動では置かない） | 「全インストールパッケージ一覧」を参照 |

- `init.el` は起動時に `lisp/` と `site-lisp/` を `load-path` へ追加します（ディレクトリが存在する場合のみ）。どちらに置いても `require` / `use-package` で読み込めます。
- サブディレクトリ内のファイルは `load-path` に自動では入らないため、`init.el` で個別に追加しています（`lisp/lookup/lisp`、`lisp/stock-charts`）。

## 注意

### `custom.el` について

`M-x customize` でテーマや設定を変更すると、`custom-set-variables` / `custom-set-faces` が **`custom.el`** に自動書き込みされます。
`init.el` 自体には書き込まれません。

- 新しい環境に持ち込んだ場合、`custom.el` が存在しなくても起動します（テーマ等はデフォルト値になります）。
- `init.el` の先頭付近で `(setq custom-file ...)` と `(load custom-file ...)` を設定しているため、起動時に自動で読み込まれます。

## メンテナンスとカスタマイズについて

`init.el` の構築、チートシートの作成、アセット選定、機能追加、ツールバーアイコンの作成には、AI アシスタント（Claude 3.5 Sonnet / Gemini 1.5/3.5 Flash 等）を使用しています。

設定を変更する場合も、AI アシスタントに `init.el` と要望を渡して編集を依頼できます。

## クレジット

本設定ファイル（Elisp コード等）の転載・配布・コピーは自由に行えます。

ツールバー等で使用しているアイコンアセットの著作権・ライセンスは各作者に帰属します。
* **Silk Icons** (by [famfamfam](http://www.famfamfam.com/lab/icons/silk/)): [CC BY 2.5](https://creativecommons.org/licenses/by/2.5/)
* **Adwaita Icons** (by [GNOME Project](https://gitlab.gnome.org/GNOME/adwaita-icon-theme)): [CC BY-SA 3.0](https://creativecommons.org/licenses/by-sa/3.0/) / GNU LGPL v3
