;; -*- lexical-binding: t -*-
;; =====================================================================
;; init.el — Windows Emacs 個人設定
;; =====================================================================

;; 起動直後にまずウィンドウ（初期フレーム）を画面に即座に表示する
(when (display-graphic-p)
  (set-frame-parameter nil 'visibility t)
  (redisplay t))

;; ネットワークエラー対策 (unknown address family)
;; IPv6 を無効にして IPv4 を優先するように設定します
(setq network-lookup-address-preference 'ipv4)

;; ポータブル環境対応：user-emacs-directory を init.el の場所から動的に設定する
;; これにより USB 等で持ち運んでも絶対パスに依存しない
(setq user-emacs-directory
      (file-name-directory (or load-file-name buffer-file-name)))

;; ── Elisp ロードパス設定（自作: lisp/ ＆ 外部: site-lisp/）──
(let ((lisp-dir (expand-file-name "lisp" user-emacs-directory))
      (site-lisp-dir (expand-file-name "site-lisp" user-emacs-directory)))
  (when (file-directory-p lisp-dir)
    (add-to-list 'load-path lisp-dir))
  (when (file-directory-p site-lisp-dir)
    (add-to-list 'load-path site-lisp-dir)))

;; ポータブル環境用：.authinfo をホームディレクトリではなく .emacs.d の中に配置する設定
(setq auth-sources
      (list (expand-file-name ".authinfo" user-emacs-directory)
            (expand-file-name ".authinfo.gpg" user-emacs-directory)))

;; ── GnuPG / EasyPG (EPA) 設定 ──
;; Git for Windows 付属の gpg.exe を自動検出して設定
(let ((git-gpg-candidates
       (list
        "C:/Program Files/Git/usr/bin/gpg.exe"
        "C:/Program Files (x86)/Git/usr/bin/gpg.exe"
        (and (getenv "LOCALAPPDATA") (expand-file-name "Programs/Git/usr/bin/gpg.exe" (getenv "LOCALAPPDATA")))
        (and (getenv "USERPROFILE") (expand-file-name "scoop/apps/git/current/usr/bin/gpg.exe" (getenv "USERPROFILE"))))))
  (unless (executable-find "gpg")
    (catch 'found
      (dolist (p git-gpg-candidates)
        (when (and p (file-exists-p p))
          (setq epg-gpg-program p)
          (throw 'found t))))))

;; EasyPG の有効化
(require 'epa-file)
(epa-file-enable)

;; パスフレーズを Emacs のミニバッファ内で直接入力可能にする（Windowsでのフリーズ防止）
(setq epg-pinentry-mode 'loopback)

;; M-x customize の設定を専用ファイルに分離（init.el への自動書き込みを防止）
;; これにより custom-set-variables / custom-set-faces は custom.el に書かれる
;; （※実際のロード処理は、パッケージ初期化後の競合を防ぐため init.el の末尾で行います）
(setq custom-file (expand-file-name "custom.el" user-emacs-directory))

;; テーマ切り替え時の "Loading theme could run malicious Lisp code! Really
;; load?" という確認プロンプトを毎回出さないようにする(全テーマを安全と
;; みなす)
(setq custom-safe-themes t)
(advice-add 'custom-theme-load-confirm :override (lambda (&rest _) t))

;; 終了時の固まり対策（共通ローカルキャッシュ ＋ USBへの非同期同期）
;; user-emacs-directory は USB 等のポータブル/ネットワークドライブ上にある
;; ことがあり、そこへ終了時に直接・同期的に書き込むと、応答の遅いドライブで
;; 固まる原因になります。
;; そこで「終了時に自動保存する系」のファイル（frame位置、scratch、履歴等）は、
;; ① まず高速な Windows ローカルの一時ディレクトリに即座に書き込み（＝Emacsの
;;    終了はここでは絶対に固まらない）、
;; ② その後、書き込んだ内容を非同期のバックグラウンドプロセスで USB 側にも
;;    コピーする（完了を待たないので、これも Emacs の終了をブロックしない）
;; という2段構成にすることで、USB側へのデータ永続化と
;; 終了時のブロッキング防止を両立させています。
;; （USBが低速・未接続でもコピーが失敗するだけで、Emacs自体は影響を受けません）
;;
;; 新規ディレクトリは作成せず既存の一時フォルダを利用
;; %LOCALAPPDATA%\emacs\ のような専用フォルダを新設せず、Windowsに元々ある
;; 一時ディレクトリ（temporary-file-directory、通常は %TEMP%）を直接使う。
;; ファイル名には "emacs-portable-" というプレフィックスを付け、
;; 他アプリの一時ファイルと名前が衝突しないようにする。
(defvar my/local-cache-dir
  temporary-file-directory
  "終了時に自動保存する系のファイルを、まず即座に書き込むローカルディレクトリ。
新規フォルダを作らないよう、Windows標準の一時ディレクトリをそのまま使う。")

(defun my/local-cache-file (name)
  "NAME に対応する、ローカル一時ディレクトリ上のファイルパスを返す。
他アプリのファイルと衝突しないよう \"emacs-portable-\" を前置する。"
  (expand-file-name (concat "emacs-portable-" name) my/local-cache-dir))

(defun my/async-copy-to-usb (local-file usb-file)
  "LOCAL-FILE の内容を非同期で USB-FILE へコピーする。
コピー完了を待たずに即座に返るため、Emacsの終了処理をブロックしない。
USBが低速・未接続の場合はコピーが失敗するだけで、Emacs側には影響しない。"
  (when (file-exists-p local-file)
    (ignore-errors (make-directory (file-name-directory usb-file) t))
    (let ((proc (ignore-errors
                  (start-process "my-usb-sync" nil "cmd" "/c" "copy" "/y"
                                 (convert-standard-filename local-file)
                                 (convert-standard-filename usb-file)))))
      (when proc
        ;; Emacs終了時にこのプロセスの完了を待たせない／確認させない
        (set-process-query-on-exit-flag proc nil)))))

(defun my/maybe-pull-from-usb (local-file usb-file)
  "起動時、LOCAL-FILE がまだ無ければ USB-FILE から一度だけ取り込む。
別のPCでこのUSBを挿した直後など、ローカルキャッシュがまだ無い場合に、
USB側に残っている前回の状態を引き継ぐためのものです。"
  (when (and (not (file-exists-p local-file))
             (file-exists-p usb-file))
    (ignore-errors
      (make-directory (file-name-directory local-file) t)
      (copy-file usb-file local-file t))))

;; ── キャッシュ・履歴・一時ファイルを .cache/ に集約 ──
(let ((cache-dir (expand-file-name ".cache/" user-emacs-directory)))
  (unless (file-directory-p cache-dir)
    (make-directory cache-dir t))
  (setq project-list-file           (expand-file-name "projects" cache-dir)
        tramp-persistency-file-name (expand-file-name "tramp" cache-dir)
        nov-save-place-file         (expand-file-name "nov-places" cache-dir)
        eww-bookmarks-directory     cache-dir
        mc/list-file                (expand-file-name ".mc-lists.el" cache-dir)
        auto-save-list-file-prefix  (expand-file-name "auto-save-list/.saves-" cache-dir)
        transient-levels-file       (expand-file-name "transient/levels.el" cache-dir)
        transient-values-file       (expand-file-name "transient/values.el" cache-dir)
        transient-history-file      (expand-file-name "transient/history.el" cache-dir)
        url-configuration-directory (expand-file-name "url/" cache-dir)))

;; =====================================================================
;; 1. 起動・基本動作
;; =====================================================================

;; スクラッチバッファのメッセージを非表示
;;(setq initial-scratch-message "")
;; スプラッシュ画面の ON/OFF はこの変数で切り替える
;;   nil → 表示する（デフォルト）
;;   t   → 表示しない
(defvar my/disable-splash t)

;; ロゴを表示するために inhibit 設定を確実に nil にする
;; （my/disable-splash が t の場合は表示しない）
(setq inhibit-startup-message my/disable-splash)
(setq inhibit-startup-screen  my/disable-splash)

;; obsidian パッケージが起動時に command-line-args にディレクトリを追加するため
;; Emacs がスプラッシュ画面をスキップしてしまう。
;; window-setup-hook で強制的に表示することで回避する。
(add-hook 'window-setup-hook
          (lambda ()
            (when (and (not my/disable-splash)
                       fancy-splash-image
                       (file-exists-p fancy-splash-image))
              (fancy-startup-screen))))

;; 言語環境を日本語に
(set-language-environment "Japanese")

;; UTF-8 を優先しつつ、UTF-16/CP932 などのファイル自動判定は残す
;; （buffer-file-coding-system のデフォルトは、後段の tr-ime
;;   セクションで w32-ime-initialize 実行後に再設定している。
;;   ここで設定しても tr-ime 側に上書きされてしまうため）
(prefer-coding-system 'utf-8)
(set-terminal-coding-system 'utf-8)
(set-keyboard-coding-system 'utf-8)
(set-selection-coding-system 'utf-16le-dos)

;; --- 新規ファイル作成時の文字コード・改行コード自動設定 ---
;; .bat/.cmd と .ps1 のみ、新規作成時に Windows 互換の文字コード・CRLF を自動割り当て
(defun my/custom-new-file-coding-system ()
  "新規ファイル作成時、.bat/.cmd や .ps1 に適切な文字コード・改行コードを割り当てます。"
  (when buffer-file-name
    (cond
     ;; バッチファイル (.bat, .cmd) → CP932 / CRLF
     ((string-match-p "\\.\\(bat\\|cmd\\)\\'" buffer-file-name)
      (setq buffer-file-coding-system 'japanese-cp932-dos))
     ;; PowerShell スクリプト (.ps1) → UTF-8 BOM付き / CRLF
     ((string-match-p "\\.ps1\\'" buffer-file-name)
      (setq buffer-file-coding-system 'utf-8-with-signature-dos))))
  nil) ; 他のフック処理を阻害しないよう必ず nil を返す

(add-hook 'find-file-not-found-functions #'my/custom-new-file-coding-system)

;; -nw (端末版) 起動時に Windows 本体の IME を確実に OFF (英数直接入力) で開始する
(when (and (eq system-type 'windows-nt) (not (display-graphic-p)))
  (add-hook 'emacs-startup-hook
            (lambda ()
              (when (fboundp 'w32-set-ime-open-status)
                (ignore-errors (w32-set-ime-open-status nil))))))

;; 「yes/no」を「y/n」の1文字で済ます（Emacs 28+ の正式な書き方）
(setq use-short-answers t)

;; ナローイング機能（編集範囲の限定）を有効化
(put 'narrow-to-region 'disabled nil)

;; ビープ音を消す
(setq ring-bell-function 'ignore)

;; バックアップファイル（〜付き）を作らない
(setq make-backup-files nil)

;; ロックファイル（.#filename）を作らない
;; make-backup-files と同じ思想。USB/ネットワークドライブ上に余計な
;; 一時ファイル（ロックファイル）を残さないための設定。
(setq create-lockfiles nil)

;; Dired等でファイルを削除する際、完全削除ではなくWindowsのごみ箱に送る
;; （誤操作からの復旧が効くようにする）
(setq delete-by-moving-to-trash t)

;; サブプロセスからの読み込みバッファを増やし、応答をもたつかせない
;; （ripgrep・fd 経由の検索 / conpty / Antigravity CLI など、
;;   外部プロセスとのやり取りが多い構成のため）
(setq read-process-output-max (* 1024 1024)) ; 1MB

;; 実行中の外部プロセスがあっても、終了時に確認ダイアログを出さない
;; （conpty / GhostText連携 / xdoc2txt など外部プロセスを多用するため、
;;   確認待ちで終了処理が止まっているのを「固まった」と誤認しやすい）
(setq confirm-kill-processes nil)

;; フレームサイズをピクセル単位で指定できるようにする
;; （frame-geometry.el による前回サイズの復元を、文字セル単位の
;;   丸め誤差なく正確に行うため）
(setq frame-resize-pixelwise t)

;; タブ幅を4にする（デフォルトは8で間延びして見えるため）
(setq-default tab-width 4)

;; ディレクトリ作成などでWindowsネイティブのダイアログを出さず、
;; 常にミニバッファでの操作に統一する
(setq use-dialog-box nil)
(setq use-file-dialog nil)

;; ミニバッファ履歴（savehist）の上限と重複排除
(setq history-length 1000)
(setq history-delete-duplicates t)

;; 100MBまでは警告なしでファイルを開く
;; （画像コレクションやアーカイブを扱う際に地味に便利）
(setq large-file-warning-threshold 100000000)

;; スクロール時の描画を一部省略して高速化する
;; （pixel-scroll-precision-mode と組み合わせて使う）
(setq fast-but-imprecise-scrolling t)

;; コメントやdescribe-function等の表示で使われる引用符をストレートクォートに統一する
(setq text-quoting-style 'straight)

;; Windows環境でのキー長押しスクロール遅延・コマ落ちを防ぐため無効化
(when (fboundp 'pixel-scroll-precision-mode)
  (pixel-scroll-precision-mode -1))

;; --- 外部でのファイル変更検知 ＆ スマート確認設定 ---
(defvar-local my/auto-revert-declined-modtime nil
  "ユーザーが再読み込みを拒否した時点のファイル更新日時。
次回外部でファイルが再度変更されるまで、同一の変更に対する確認を抑制します。")

(defun my/buffer-matches-file-p ()
  "未変更バッファの内容がディスク上のファイルと同一なら non-nil。
大きいファイル（2MB超）は比較しない。"
  (let ((file buffer-file-name)
        (cs   buffer-file-coding-system)
        (buf  (current-buffer)))
    (and file
         (file-readable-p file)
         (< (or (file-attribute-size (file-attributes file)) most-positive-fixnum)
            2000000)
         (with-temp-buffer
           (let ((coding-system-for-read cs))
             (insert-file-contents file))
           (let ((disk (buffer-substring-no-properties (point-min) (point-max))))
             (with-current-buffer buf
               (save-restriction
                 (widen)
                 (string= disk (buffer-substring-no-properties (point-min) (point-max))))))))))

(defun my/auto-revert-handler-around (orig-fun &rest args)
  "外部変更検知時に確認プロンプトを出し、拒否されたら次の変更までスキップする。"
  (if (and buffer-file-name
           (file-exists-p buffer-file-name)
           (not (verify-visited-file-modtime (current-buffer))))
      (let ((cur-modtime (file-attribute-modification-time (file-attributes buffer-file-name))))
        (cond
         ;; 現在アクティブなバッファでない場合は確認を出さずに保留（裏のタブにある間は邪魔しない）
         ((not (eq (current-buffer) (window-buffer (selected-window))))
          nil)
         ;; すでに拒否したタイムスタンプと同じなら、次の変更まで沈黙
         ((and my/auto-revert-declined-modtime
               (equal cur-modtime my/auto-revert-declined-modtime))
          nil)
         ;; ミニバッファ入力中はユーザーの邪魔をしない
         ((minibuffer-window-active-p (selected-window))
          nil)
         ;; 内容がディスクと同一なら日時の誤差だけなので、黙って記録し直す
         ((and (not (buffer-modified-p)) (my/buffer-matches-file-p))
          (set-visited-file-modtime)
          nil)
         ;; それ以外ならユーザーに確認
         (t
          (if (y-or-n-p (format "ファイル「%s」が外部で変更されました。再読み込みしますか？ "
                                (file-name-nondirectory buffer-file-name)))
              (progn
                (setq my/auto-revert-declined-modtime nil)
                (apply orig-fun args))
            ;; 「no」を選んだ場合：タイムスタンプを記憶して次回以降沈黙
            (setq my/auto-revert-declined-modtime cur-modtime)
            (message "再読み込みをスキップしました (F5 で手動更新可能)")))))
    ;; 変更がないか通常処理
    (apply orig-fun args)))

(advice-add 'auto-revert-handler :around #'my/auto-revert-handler-around)

;; タブやウィンドウを切り替えた瞬間に、外部変更があれば即座にチェック
(defun my/auto-revert-check-on-switch (&optional _)
  "バッファ切り替え時に、現在のバッファが外部変更されていれば即座にチェックする。"
  (when (and (bound-and-true-p auto-revert-mode)
             buffer-file-name
             (file-exists-p buffer-file-name)
             (not (verify-visited-file-modtime (current-buffer))))
    (auto-revert-handler)))
(add-hook 'window-selection-change-functions #'my/auto-revert-check-on-switch)

;; 外部でのファイル変更を自動検知して反映
(global-auto-revert-mode 1)

;; 同名バッファをディレクトリ名で区別する（<2> のような番号ではなく
;; dir/file.txt のような表示にする）
(use-package uniquify
  :ensure nil
  :custom
  (uniquify-buffer-name-style 'forward))

;; 1行が異常に長いファイル（minifyされたJS・巨大ログ等）を開いたときの
;; フリーズ防止（該当ファイルは自動的に軽量表示に切り替わる）
(when (fboundp 'global-so-long-mode)
  (global-so-long-mode 1))

;; 次回ファイルを開いた時に、前回のカーソル位置から再開
(use-package saveplace
  :ensure nil
  :config
  ;; ============================================================
  ;; 終了時の固まり対策（拡張）
  ;; with-timeout はファイルI/Oブロック中に機能しないため、
  ;; 保存先を確実にローカルな AppData に変更して固まりを防ぐ。
  ;; ポータブル版が USB/ネットワーク上にあっても問題なくなる。
  ;; ============================================================

  ;; 保存先を Windows のローカル AppData に固定する
  ;; （USB ドライブ上の .emacs.d に直接書くと固まる環境への対策）
  (setq save-place-file
        (my/local-cache-file "save-place"))

  ;; USB側（ポータブルディレクトリ）の対応ファイル。
  ;; 起動時にローカルキャッシュが無ければここから取り込み、
  ;; 終了時にはローカル保存後、非同期でここへコピーし返す。
  (defvar my/save-place-usb-file
    (expand-file-name ".cache/save-place" user-emacs-directory))
  (my/maybe-pull-from-usb save-place-file my/save-place-usb-file)

  (defun my/save-place-save-safe ()
    "save-place をローカルへ安全に保存し、USBへは非同期でコピーします。
with-timeout はファイルI/O中に効かないため、condition-case で
書き込みエラーを握りつぶして確実に終了できるようにします。"
    (condition-case err
        (let ((inhibit-message t))
          ;; ローカルファイルへの書き込みなので通常は即座に終わる
          (save-place-kill-emacs-hook))
      (error
       (message "save-place の保存をスキップしました: %s" (error-message-string err))))
    (my/async-copy-to-usb save-place-file my/save-place-usb-file))

  ;; 標準フックを外して安全版を登録
  (remove-hook 'kill-emacs-hook #'save-place-kill-emacs-hook)
  (add-hook    'kill-emacs-hook #'my/save-place-save-safe)

  (save-place-mode 1))

;; ミニバッファの再帰呼び出しを許可（コマンド実行中に別のコマンドを呼べる）
(setq enable-recursive-minibuffers t)
(minibuffer-depth-indicate-mode 1)

;; txtファイルはtextモードに
(add-to-list 'auto-mode-alist '("\\.txt\\'" . text-mode))

;; --- Dired (ファイル管理) の強化 ---
(setq dired-dwim-target t)             ; 2画面分割時、コピー先などを自動提案
(setq dired-listing-switches "-alh")   ; サイズを KB/MB で表示
(with-eval-after-load 'dired
  ;; Dired 内で "E" を押すと Windows の関連付けアプリで開く
  (define-key dired-mode-map (kbd "E")
    (lambda () (interactive)
      (let ((file (dired-get-file-for-visit)))
        (w32-shell-execute "open" file)))))

;; カラー強制表示（GUI環境 / Windows 向け）
(setenv "TERM" "xterm-256color")
(setenv "COLORTERM" "truecolor")

;; =====================================================================
;; 1b. フレームサイズの記憶（前回終了時のサイズで起動）
;; ─ バッファは復元しない。位置・サイズだけ保存する。
;; =====================================================================

(defvar my/frame-geometry-file
  (my/local-cache-file "frame-geometry.el")
  "フレーム位置・サイズを保存するファイル（ローカルキャッシュ側）。
USB等のポータブルドライブへの直接書き込みで終了時に固まらないよう、
まずローカルの AppData 配下に書き込む。")

(defvar my/frame-geometry-usb-file
  (expand-file-name ".cache/frame-geometry.el" user-emacs-directory)
  "フレーム位置・サイズのUSB（ポータブルディレクトリ）側コピー。")

;; 別のPCでこのUSBを挿した直後などは、ローカルキャッシュにまだ
;; 何もないので、あればUSB側から一度だけ取り込んでおく
(my/maybe-pull-from-usb my/frame-geometry-file my/frame-geometry-usb-file)

(defun my/save-frame-geometry ()
  "終了時にフレームの位置とサイズをローカルへ保存し、USBへは非同期でコピーします。
書き込み先はローカルディスクだが、念のためエラーを握りつぶして
確実に終了できるようにする（save-place と同じ安全策）。"
  (condition-case err
      (let* ((frame  (selected-frame))
             (params (list (cons 'left   (frame-parameter frame 'left))
                           (cons 'top    (frame-parameter frame 'top))
                           (cons 'width  (frame-parameter frame 'width))
                           (cons 'height (frame-parameter frame 'height)))))
        (with-temp-file my/frame-geometry-file
          (insert ";; -*- lexical-binding: t; -*-\n")
          (insert ";; 自動生成ファイル。手動で編集しないでください。\n")
          (insert (format "(setq initial-frame-alist '%S)\n" params))))
    (error
     (message "frame-geometry の保存をスキップしました: %s" (error-message-string err))))
  (my/async-copy-to-usb my/frame-geometry-file my/frame-geometry-usb-file))

;; 起動時に復元・終了時に保存
;; early-init.el がない環境では init.el の先頭で直接ロードするのが確実
(when (file-exists-p my/frame-geometry-file)
  (load my/frame-geometry-file nil t))
(add-hook 'kill-emacs-hook #'my/save-frame-geometry)



;; =====================================================================
;; 2. パッケージ管理（MELPA）
;; =====================================================================

(require 'package)
(setq package-archives
      '(("gnu"   . "https://elpa.gnu.org/packages/")
        ("nongnu" . "https://elpa.nongnu.org/nongnu/") 
        ("melpa" . "https://melpa.org/packages/")))
;; package-quickstart 有効時は自動でロードされるため重複実行を回避
(unless package-quickstart
  (package-initialize))

;; パッケージアーカイブがローカルに存在しない初回起動時のみ取得（毎回のネット接続待ちを防止）
(unless (file-exists-p (expand-file-name "archives/melpa" package-user-dir))
  (message "初回パッケージリストを取得中...")
  (package-refresh-contents))

;; use-package が未インストールの場合は自動インストール（Emacs 29 未満向け）
(unless (package-installed-p 'use-package)
  (package-install 'use-package))

(require 'use-package-ensure)
(setq use-package-always-ensure t)

;; *scratch* バッファの内容を終了時に保存し、起動時に復元する
(use-package persistent-scratch
  :config
  ;; デフォルトの保存先は user-emacs-directory 配下（＝ポータブルドライブ上）
  ;; になるため、終了時の固まり対策としてまずローカルキャッシュに変更する。
  (setq persistent-scratch-save-file
        (my/local-cache-file "persistent-scratch"))
  (defvar my/persistent-scratch-usb-file
    (expand-file-name ".cache/persistent-scratch" user-emacs-directory))
  (my/maybe-pull-from-usb persistent-scratch-save-file my/persistent-scratch-usb-file)

  (persistent-scratch-setup-default)
  ;; 自動保存（idle時・バッファ変更時）も有効にする
  (persistent-scratch-autosave-mode 1)

  ;; persistent-scratch-save が呼ばれる度（終了時／idle自動保存時）に
  ;; USBへも非同期でコピーする。終了を待たせないだけでなく、
  ;; 普段の自動保存のタイミングでもUSB側が追従してくれる。
  (advice-add 'persistent-scratch-save :after
              (lambda (&rest _)
                (my/async-copy-to-usb persistent-scratch-save-file
                                       my/persistent-scratch-usb-file))))

;; --- 起動時ダッシュボード画面 (emacs-dashboard) ---
(use-package dashboard
  :ensure t
  :demand t
  :bind
  (("<home>" . dashboard-refresh-buffer)
   :map dashboard-mode-map
   ("<home>" . quit-window)
   ("RET" . my/dashboard-safe-return)
   ("o" . hydra-launcher/body)
   ("e" . consult-locate)
   ("s" . my/consult-ripgrep-project)
   ("g" . my/consult-fd-project)
   ("f" . consult-recent-file)
   ("c" . conpty)
   ("p" . conpty-powershell)
   ("L" . my/open-calendar)
   ("d" . lookup)
   ("w" . hydra-window/body)
   ("F" . hydra-file/body))
  :config
  ;; クイックメニュー欄など、ボタン化されていない行でRETを押すと
  ;; dashboard-returnが読み取り専用バッファを操作しようとしてエラーになるため、
  ;; ボタンが実際にある位置でだけ dashboard-return を呼ぶようにする。
  (defun my/dashboard-safe-return ()
    "ポイント位置にボタンがあるときだけ dashboard-return を実行する。"
    (interactive)
    (if (button-at (point))
        (dashboard-return)
      (message "この行には項目がありません（ショートカットキーをお使いください）")))

  ;; 起動時にダッシュボードを表示する
  (dashboard-setup-startup-hook)
  
  ;; 指定のバナー画像を設定 (ポータブル対応)
  (let ((banner-path (expand-file-name "images/banner.png" user-emacs-directory)))
    (if (file-exists-p banner-path)
        (setq dashboard-startup-banner banner-path)
      (setq dashboard-startup-banner 'official))) ; 画像がない場合は標準ロゴ
  
  ;; タイトルメッセージ (ロゴのすぐ下にバージョン入りで表示)
  (setq dashboard-banner-logo-title (format "Welcome to GNU Emacs portable version %s" emacs-version))
  
  ;; 中央寄せ表示
  (setq dashboard-center-content t)
  
  ;; 表示するセクションと件数
  (setq dashboard-items '((recents  . 5)   ; 最近開いたファイル
                          (projects . 5)   ; プロジェクト一覧
                          (bookmarks . 5)  ; ブックマーク
                          (custom . nil))) ; クイックメニュー (カスタム)
  
  ;; カスタムセクションの描画関数
  (defun my/dashboard-insert-hydra-guide (list-size)
    (insert "\n=== クイックメニュー (キーを押して直接実行 / [o] で全ランチャー表示) ===\n\n")
    (insert "  [e] Everything (PC検索)   [s] プロジェクト検索     [g] ファイル検索 (fd)\n")
    (insert "  [f] 最近使ったファイル     [w] ウィンドウ操作メニュー [d] 辞書検索 (Lookup)\n")
    (insert "  [L] カレンダー (calfw)     [p] PowerShell (conpty)  [c] cmd.exe (conpty)\n")
    (insert "  [F] ファイル操作メニュー   [o] メインメニュー (Hydra)\n"))

  ;; ジェネレーターの登録
  (add-to-list 'dashboard-item-generators '(custom . my/dashboard-insert-hydra-guide))

  ;; アイコン表示（Windows環境での文字化け防止のため無効化）
  (setq dashboard-set-heading-icons nil)
  (setq dashboard-set-file-icons nil)
  
  ;; フッターの非表示 (ロゴ下部分にバージョンを表示したため非表示)
  (setq dashboard-show-footer nil)
  
  ;; クイックスタート環境でも正しくパッケージ数をカウントして表示
  (setq dashboard-init-info
        (lambda ()
          (let ((pkg-count (or (when (bound-and-true-p package-activated-list)
                                 (length package-activated-list))
                               (when (bound-and-true-p package-selected-packages)
                                 (length package-selected-packages))
                               0))
                (init-time (dashboard-init--time)))
            (format "[%d packages loaded in %s]" pkg-count init-time))))

  (setq dashboard-show-shortcuts t)
  (setq dashboard-set-navigator t))


;; =====================================================================
;; 3. 外観（テーマ・フォント・UI）
;; =====================================================================

;; Iceberg テーマ（conao3/iceberg-theme.el）
;; パッケージのインストールとテーマファイルの作成のみ行い、自動適用はしません。
(use-package iceberg-theme
  :ensure t
  :config
  (iceberg-theme-create-theme-file))

;; タブバー設定の初期化（過去のバグリセット）
(setq default-frame-alist (assq-delete-all 'tab-bar-lines default-frame-alist))

;; ★フォントポータブル仕様：.emacs.d/fonts/ のフォントを起動時に一時登録して最優先適用
;; 使いたいフォントファイル名はここで変更してください
(condition-case nil
    (let* ((my-fonts-dir   (expand-file-name "fonts/" user-emacs-directory))
           (my-font-file   "Utatane-Regular.ttf")
           (my-font-path   (expand-file-name my-font-file my-fonts-dir))
           (my-font-name   "Utatane")
           (my-font-setting (format "%s-13" my-font-name)))
      (when (file-exists-p my-font-path)
        (w32-register-font my-font-path))
      (let ((final-font (if (member my-font-name (font-family-list))
                            my-font-setting
                          "MS Gothic-13")))
        (set-face-attribute 'default        nil :font final-font)
        (set-face-attribute 'fixed-pitch    nil :font final-font)
        (set-face-attribute 'variable-pitch nil :font final-font)))
  (error (message "標準フォントで起動しました。")))

;; メニューバー・ツールバー・スクロールバーを表示
(menu-bar-mode 1)
(tool-bar-mode 1)
(set-scroll-bar-mode 'right)

(defun my/toolbar-consult-menu (event)
  "ツールバーをクリックした際に、Consult-line または Consult-outline を起動するメニューを表示します。"
  (interactive "e")
  (let ((menu (make-sparse-keymap "Consult検索")))
    (define-key menu [outline]
      '(menu-item "バッファ内アウトライン検索" consult-outline
                  :help "見出し（アウトライン）を一覧検索してジャンプします"))
    (define-key menu [line]
      '(menu-item "バッファ内行検索" consult-line
                  :keys "C-f"
                  :help "バッファ内のテキストを行ごとに高速検索してジャンプします"))
    (popup-menu menu event)))

(defun my/toolbar-filter-menu (event)
  "ツールバーをクリックした際に、moccur-edit または occur-edit を起動するメニューを表示します。"
  (interactive "e")
  (let ((menu (make-sparse-keymap "フィルタ検索")))
    (define-key menu [occur]
      '(menu-item "フィルタ (occur-edit - 標準)"
                  (lambda () (interactive) (my/emeditor-filter 'occur))
                  :keys "C-c f"
                  :help "標準の occur-edit を使用してフィルタします"))
    (define-key menu [moccur]
      '(menu-item "フィルタ (moccur-edit - Migemo対応)"
                  (lambda () (interactive) (my/emeditor-filter 'moccur))
                  :help "color-moccur (Migemo対応) を使用してフィルタします"
                  :enable (and (locate-library "color-moccur")
                               (locate-library "moccur-edit"))))
    (popup-menu menu event)))

;; ツールバーを Adwaita アイコンで全面置き換え
;; アイコン画像の場所：~/.emacs.d/images/ に tb-*.png を配置してください
;;    （adwaita-icons.zip の中身をそのままコピー）

(defun my/tb-image (name)
  "~/.emacs.d/images/<name>.png を読み込んで image オブジェクトを返す。
見つからなければ nil。"
  (let ((path (expand-file-name (concat "images/" name ".png")
                                user-emacs-directory)))
    (when (file-exists-p path)
      (create-image path 'png nil :ascent 'center))))

(defun my/tb-add (key command icon-name help)
  "ツールバーにボタンを1つ追加する。アイコンがなければテキストボタンになる。"
  (let ((img (my/tb-image icon-name)))
    (define-key tool-bar-map (vector key)
      (if img
          `(menu-item ,help ,command :image ,img :help ,help)
        `(menu-item ,help ,command :help ,help)))))

(defun my/tb-sep (key)
  "ツールバーにセパレータを追加する。"
  (define-key tool-bar-map (vector key) '(menu-item "--")))

;; window-setup-hook でツールバーをまるごと再構築する
;; （標準ツールバーを一度クリアして Adwaita アイコンで並べ直す）
(add-hook 'window-setup-hook
          (lambda ()
            ;; 標準ボタンをすべて削除してまっさらにする
            (setq tool-bar-map (make-sparse-keymap))
            ;; make-sparse-keymap は後から追加したものが前に表示されるため
            ;; 逆順（末尾→先頭）で登録する
            ;; カスタムボタン（逆順）
            (my/tb-add '21b-close-win 'delete-window                    "tb-close"        "このウィンドウを閉じる")
            (my/tb-add '22-close-oth 'delete-other-windows             "tb-close-others" "他のウィンドウをすべて閉じる")
            (my/tb-add '21-split-v   'split-window-below               "tb-split-vert"   "画面を上下に2分割")
            (my/tb-add '20-split-h   'split-window-right               "tb-split-horiz"  "画面を左右に2分割")
            (my/tb-add '19-open-ext  'my-open-current-file-in-windows  "tb-open-ext"     "Windowsの関連付けプログラムで開く")
            (my/tb-add '18-encoding  'revert-buffer-with-coding-system "tb-encoding"     "文字コードを指定して開き直す")
            (my/tb-add '17-diff      'my-compare-with-winmerge         "tb-diff"         "WinMergeで差分を比較")
            (my/tb-sep '16-sep)
            ;; カラーマーカー
            (my/tb-add '15-marker-clr 'my/toolbar-marker-clear-menu    "tb-marker-clear" "マーカーを削除")
            (my/tb-add '14-marker-put 'my/marker-put                   "tb-marker"       "カラーマーカー付け/消し")
            (my/tb-sep '13-sep)
            ;; 検索・置換
            (my/tb-add '12c-replace   'my/visual-replace-menu   "tb-replace"      "置換")
            (my/tb-add '12b-filter    'my/toolbar-filter-menu   "tb-filter"       "フィルタ（マッチ行のみ表示・直接編集）")
            (my/tb-add '12-search-bwd 'isearch-backward         "tb-search-bwd"   "前を検索")
            (my/tb-add '11-search-fwd 'isearch-forward          "tb-search-fwd"   "後を検索")
            (my/tb-add '10b-consult   'my/toolbar-consult-menu  "tb-search"       "Consult検索 (行・アウトライン)")
            (my/tb-sep '10-sep)
            ;; 編集
            (my/tb-add '09-paste     'yank                             "tb-paste"        "貼り付け")
            (my/tb-add '08-copy      'kill-ring-save                   "tb-copy"         "コピー")
            (my/tb-add '07-cut       'kill-region                      "tb-cut"          "切り取り")
            (my/tb-sep '06-sep)
            (my/tb-add '06-redo      'undo-redo                        "tb-redo"         "やり直す")
            (my/tb-add '05-undo      'undo                             "tb-undo"         "元に戻す")
            (my/tb-sep '04-sep)
            ;; ファイル操作
            (my/tb-add '03-save      'save-buffer                      "tb-save"         "保存")
            (my/tb-add '02-open      'menu-find-file-existing          "tb-open"         "ファイルを開く")
            (my/tb-add '01-new       'find-file                        "tb-new"          "新規ファイルを開く")))

;; 現在の編集行を常時ハイライトする (hl-line)
(global-hl-line-mode 1)

;; カーソルを見失わないように、移動・スクロール・ウィンドウ切り替え時に行を光らせる (pulsar)
(use-package pulsar
  :ensure t
  :config
  (pulsar-global-mode 1)

  ;; ウィンドウ切り替え時にフォーカス先をパルス
  (setq pulsar-pulse-on-window-change t)

  ;; パルスの滑らかさ・フェード速度設定
  (setq pulsar-iterations 15)       ; パルスのフェード回数
  (setq pulsar-delay 0.04)          ; 反復ごとのディレイ（約0.6秒）

  ;; パルスの色（テーマに合わせて鮮やかなシアンを設定）
  (setq pulsar-face 'pulsar-cyan)
  (defun my/update-pulsar-color (&rest _)
    (let ((dark (eq (frame-parameter nil 'background-mode) 'dark)))
      (set-face-attribute 'pulsar-cyan nil
                          :background (if dark "#008b8b" "#8eecf4")
                          :foreground 'unspecified)))
  (my/update-pulsar-color)
  (add-hook 'enable-theme-functions #'my/update-pulsar-color)

  ;; パルスを発生させるコマンドを追加
  ;; （スクロール、isearch、recenter 等は標準で登録されています）
  (dolist (cmd '(consult-line
                 consult-outline
                 consult-buffer
                 consult-recent-file
                 consult-ripgrep
                 my/consult-ripgrep-project
                 my/consult-fd-project
                 other-window
                 handle-switch-frame
                 mouse-set-point
                 pixel-scroll-interpolate-down
                 pixel-scroll-interpolate-up))
    (add-to-list 'pulsar-pulse-functions cmd)))

;; にゃんこバー（タイムライン進行度バー）
(use-package nyan-mode
  :config
  (setq nyan-wavy-trail t)
  (setq nyan-minimum-window-width 40)
  ;; 既定は0.2秒(1秒に5回)ごとにモードライン全体を再描画している。
  ;; 1秒に1回に落として再描画頻度を1/5にする。
  (setq nyan-animation-frame-interval 1.0)
  (nyan-mode 1)
  (nyan-start-animation))


;; 最近開いたファイルの履歴
(use-package recentf
  :ensure nil
  :config
  (setq recentf-max-saved-items 100)
  (setq recentf-exclude
        '("/\\.emacs\\.d/elpa/" "/emacs/share/"
          "^/\\(?:ssh\\|scp\\|ftp\\):"     ; リモートファイルを除外（固まり防止）
          "\\.recentf$"))                   ; recentf ファイル自体を除外

  ;; ============================================================
  ;; ファイル生存確認（existence check）の ON/OFF スイッチ
  ;;   nil → 確認しない（起動・動作が速い。ネットワークドライブ多用時に推奨）
  ;;   t   → 確認する  （消えたファイルが履歴から自動で消える）
  ;; ============================================================
  (defvar my/recentf-existence-check nil
    "non-nil のとき recentf のファイル生存確認を有効にします。")

  (if my/recentf-existence-check
      (setq recentf-auto-cleanup 'mode)
    (setq recentf-auto-cleanup 'never))

  ;; recentf の保存ファイルを UTF-8 で書き出す（Windows環境での文字化け防止）
  (setq recentf-save-file-coding-system 'utf-8)

  ;; 定期自動保存はオフ（終了時のみ保存）
  (setq recentf-auto-save-timer nil)

  ;; ============================================================
  ;; 終了時の固まり対策
  ;; recentf-save-file のデフォルトは user-emacs-directory 配下
  ;; （＝USB等のポータブルドライブ上）になるため、まずローカルキャッシュに
  ;; 保存先を変更する（with-timeout は同期I/Oのブロック中には効かないため、
  ;; これが本質的な対策）。保存後にUSBへは非同期でコピーする。
  ;; ============================================================
  (setq recentf-save-file
        (my/local-cache-file "recentf"))
  (defvar my/recentf-usb-file
    (expand-file-name ".cache/recentf" user-emacs-directory))
  (my/maybe-pull-from-usb recentf-save-file my/recentf-usb-file)

  (defun my/recentf-save-safe ()
    "recentf をローカルへ保存し、USBへは非同期でコピーします。
念のためタイムアウトも残していますが、ローカルディスクへの書き込みなので
通常は即座に終わります。"
    (let ((inhibit-message t))          ; 「Saving recentf...」メッセージを抑制
      (with-timeout (3 (message "recentf の保存をスキップしました（タイムアウト）"))
        (recentf-save-list)))
    (my/async-copy-to-usb recentf-save-file my/recentf-usb-file))

  ;; 標準フックを外して安全版を登録
  (remove-hook 'kill-emacs-hook #'recentf-save-list)
  (add-hook    'kill-emacs-hook #'my/recentf-save-safe)

  (let ((inhibit-message t))
    (recentf-mode 1)))

;; recentf の代用：ミニバッファ履歴保存機能（savehist）
(use-package savehist
  :ensure nil
  :init
  ;; user-emacs-directory（ポータブルドライブ上）への直接書き込みは
  ;; 終了時に固まる原因になるため、まずローカルキャッシュに保存先を変更する。
  (setq savehist-file (my/local-cache-file "savehist"))
  (defvar my/savehist-usb-file
    (expand-file-name ".cache/savehist" user-emacs-directory))
  (my/maybe-pull-from-usb savehist-file my/savehist-usb-file)

  (setq savehist-additional-variables '(file-name-history)) ; ファイルを開いた履歴を強制記録
  (savehist-mode 1)
  :config
  (defun my/savehist-autosave-safe ()
    "エラーを握りつぶして確実に終了できるようにした savehist の保存版。"
    (condition-case err
        (let ((inhibit-message t))
          (savehist-autosave))
      (error
       (message "savehist の保存をスキップしました: %s" (error-message-string err)))))
  (remove-hook 'kill-emacs-hook #'savehist-autosave)
  (add-hook    'kill-emacs-hook #'my/savehist-autosave-safe)

  ;; savehist-autosave は終了時だけでなく idle タイマーでも呼ばれるため、
  ;; 関数自体にadviceを付けて、保存の度にUSBへも非同期でコピーする。
  (advice-add 'savehist-autosave :after
              (lambda (&rest _)
                (my/async-copy-to-usb savehist-file my/savehist-usb-file))))


;; =====================================================================
;; 4. 表示・スクロール・行番号
;; =====================================================================

;; 対応カッコをハイライト
(show-paren-mode 1)
(setq show-paren-delay 0)
(setq show-paren-style 'mixed)

;; カッコの自動補完（electric-pair-mode）
(electric-pair-mode 1)

;; 対応するカッコを深さごとに色分けして見やすくする（rainbow-delimiters）
(use-package rainbow-delimiters
  :ensure t
  :hook (prog-mode . rainbow-delimiters-mode))

;; 単語で折り返し
(global-visual-line-mode 1)

;; スクロール設定（高速・スムーズ化チューニング）
(setq scroll-conservatively 101)        ; 再中央揃えの再計算を抑制
(setq scroll-margin 0)                  ; 画面端に達するまで無駄な再描画を抑制
(setq scroll-step 1)                    ; 1行ずつ追従
(setq scroll-preserve-screen-position t); 画面位置を維持
(setq auto-window-vscroll nil)           ; 縦スクロール時の可変高計算をスキップ
(setq mouse-wheel-progressive-speed nil)
(setq mouse-wheel-follow-mouse t)

(require 'view)

;; 行番号を常時表示（最低3桁幅で固定）
(global-display-line-numbers-mode 1)
(setq display-line-numbers-width 3)
(setq display-line-numbers-grow-only t)

;; 全角スペース・TABをテーマに合わせた色で可視化（半角スペースは非表示）
(require 'whitespace)
(require 'color)

;; point1: space-mark を有効にしつつ、styleから「spaces（半角）」を除外。
;; これにより「全角スペース」と「TAB」だけがwhitespaceの管理対象になります。
(setq whitespace-style '(face tabs tab-mark space-mark newline newline-mark))

;; point2: 可視化する文字のマッピング
;; 半角スペースはマッピング自体を空にして完全に非表示（透明）にします。
(setq whitespace-display-mappings
      '((space-mark   ?\u3000 [?\u25a1] [?_ ?_])       ;; 全角スペース → 「□」
        (tab-mark     ?\t     [?\u00BB ?\t] [?\\ ?\t]) ;; TAB → 「»」
        (newline-mark ?\n     [?\u21b5 ?\n] [?$ ?\n])))  ;; 改行 → 「↵」

(global-whitespace-mode 1)

;; point3: whitespaceの見た目をテーマの色から動的に生成する
;; whitespace.el のデフォルトフェイスは "grey20" 等の固定背景色を
;; 敷く仕様になっており、iceberg のような青みがかった背景から浮いて
;; 目立ちすぎてしまいます。そこで背景ボックスをやめ、テーマの背景色から
;; 「少しだけ明るい/暗い」文字色を自動生成して馴染ませます（beaconの
;; テーマ追従と同じ仕組みなので、iceberg以外に切り替えても自動追従します）。
(defun my/update-whitespace-faces (&rest _)
  "現在のテーマの背景色から、whitespaceの表示色を控えめに再生成する。"
  (let* ((dark (eq (frame-parameter nil 'background-mode) 'dark))
         (bg-raw (face-background 'default nil t))
         (bg (if (and (stringp bg-raw)
                      (ignore-errors (color-defined-p bg-raw)))
                 bg-raw
               (if dark "#1f2430" "#ffffff")))
         (fg (face-foreground 'default nil t))
         ;; 背景よりわずかに明るい/暗い程度の、主張しない色を作る
         (tab-color   (color-lighten-name bg (if dark 18 -10)))
         (space-color (color-lighten-name bg (if dark 12 -6))))
  (dolist (spec `((whitespace-tab     . ,tab-color)
                (whitespace-space   . ,space-color)
                (whitespace-newline . ,space-color)))
      (set-face-attribute (car spec) nil
                           :background 'unspecified   ; 灰色の箱をやめる
                           :foreground (cdr spec)
                           :underline nil
                           :weight 'normal
                           :inverse-video nil))
    ;; 行末の余分な空白だけは視認性を優先し、テーマのwarning系色に寄せる
    (set-face-attribute 'whitespace-trailing nil
                         :background 'unspecified
                         :foreground (or (face-foreground 'font-lock-warning-face nil t) fg)
                         :underline t)))

;; 初期反映 + テーマ切り替え時にも自動追従
(my/update-whitespace-faces)
(add-hook 'enable-theme-functions #'my/update-whitespace-faces)

;; サクラエディタ風の正規表現キーワード強調表示（テキスト・Markdown用）
;; 各種括弧や引用符（「」『』()（）[]［］【】《》<>〈〉"" '' など）や丸数字①-⑳を色分けします。
(defconst my/text-highlight-keywords
  '(("「[^」]*」" . font-lock-string-face)
    ("『[^』]*』" . font-lock-string-face)
    ("([^)]*)" . font-lock-comment-face)
    ("（[^）]*）" . font-lock-comment-face)
    ("\\[[^]]*\\]" . font-lock-comment-face)
    ("［[^］]*］" . font-lock-comment-face)
    ("<<[^>]*>>" . font-lock-constant-face)
    ("<[^>]*>" . font-lock-constant-face)
    ("〈[^〉]*〉" . font-lock-constant-face)
    ("＜[^＞]*＞" . font-lock-constant-face)
    ("《[^》]*》" . font-lock-constant-face)
    ("【[^】]*】" . font-lock-keyword-face)
    ("[①-⑳]" . font-lock-warning-face)
    ("'[^']*'" . font-lock-string-face)
    ("\"[^\"]*\"" . font-lock-string-face)))

(font-lock-add-keywords 'text-mode my/text-highlight-keywords)


;; =====================================================================
;; 5. モードライン（情報行）のカスタマイズ（カスタムレイアウト ＆ パスホバー版）
;; =====================================================================

(line-number-mode 1)
(column-number-mode 1)

;; バッファの文字数を表示
(defun my-mode-line-character-count ()
  "現在のバッファの文字数を返します。"
  (format " [%s文字] " (number-to-string (buffer-size))))

;; 文字コード名をコンパクトに表示（[U8] や [SJIS] などの形式）
(defun my-modeline-coding-system ()
  "文字コード名をコンパクトに表示します。"
  (let* ((coding-sym (coding-system-base buffer-file-coding-system))
         (coding     (symbol-name coding-sym))
         (has-bom    (string-match "with-signature" coding))
         (suffix     (if has-bom "+BOM" "")))
    (cond
     ((string-match "utf-16"                    coding) (format " [U16%s] "  suffix))
     ((string-match "utf-8"                     coding) (format " [U8%s] "   suffix))
     ((string-match "japanese-cp932\\|shift_jis" coding) (format " [SJIS%s] " suffix))
     ((string-match "euc-jp"                    coding) (format " [EUC%s] "  suffix))
     (t (let ((short (replace-regexp-in-string
                      "-with-signature\\|-dos\\|-unix\\|-mac" "" coding)))
          (format " [%s%s] " (upcase short) suffix))))))

;; Cosense風：ファイルを編集した瞬間に「[*]」に変わる未保存マーク
;; ① [-] にも薄いグレーをつけて3状態を視覚的に区別
(defun my-modeline-modification-status ()
  "バッファの編集状態（未保存）をCosense風の記号で返します。"
  (cond
   ((not (buffer-file-name))
    (propertize " [-] " 'face '(:foreground "gray50")))          ; ファイルなし：グレー
   ((buffer-modified-p)
    (propertize " [*] " 'face '(:foreground "Orange" :weight bold))) ; 未保存：オレンジ
   (t
    (propertize " [ ] " 'face '(:foreground "gray70")))))        ; 保存済み：薄グレー

;; モード表示：現在のメジャーモード名を (Mode名) の形式で返す
(defun my-modeline-major-mode ()
  "現在のメジャーモード名を (mode名) の形式で返します。"
  (format " (%s) " (replace-regexp-in-string "-mode$" "" (symbol-name major-mode))))

;; ナローイング中（標準またはソフトナローイング）の表示
(defun my-modeline-narrow-status ()
  "ナローイング中の場合に [narrow] を返します。"
  (if (or (bound-and-true-p my/fancy-narrow-mode)
          (buffer-narrowed-p))
      (propertize " [narrow] " 'face '(:foreground "Orange" :weight bold))
    ""))

;; ホバーでフルパスが表示されるファイル名
(defun my-modeline-buffer-name-with-path-help ()
  "マウスホバー時にフルパスをポップアップ表示するバッファ名を返します。"
  (let ((full-path (or buffer-file-name (buffer-name))))
    (propertize "%b"
                'face '(:weight bold)
                'help-echo full-path))) ; マウスを乗せたときに Windows 風にフルパスをポップアップ

;; 時計の表示形式
(setq display-time-string-forms '((format-time-string "%Y/%m/%d(%a) %H:%M:%S")))
(setq display-time-interval 1)   ; 秒表示するので1秒ごとに更新する(既定は60秒)
(setq display-time-24hr-format t)
(setq display-time-mail-string "")
(display-time-mode 1)

;; モードラインの表示項目と並び順の設定
(setq-default mode-line-format
  (list
   '(:eval (my-modeline-modification-status))        ; 1. [*]
   '(:eval (my-modeline-buffer-name-with-path-help)) ; 2. ノート.md（ホバーでフルパス）
   '(:eval (my-modeline-major-mode))                 ; 3. (markdown)
   '(:eval (my-modeline-narrow-status))              ; [narrow] (ナローイング中のみ表示)
   '(:eval (my-modeline-coding-system))              ; 4. [U8]
   " "
   "行:%l/列:%c"                                     ; 5. 行:1/列:1
   " "
   '(:eval (my-mode-line-character-count))           ; 6. [121文字]
   " "
   '(:eval (when (bound-and-true-p nyan-mode) (nyan-create))) ; 7. ...ニャンコ...
   ;; 時計を右端に寄せる
   '(:eval (let* ((clock-str (or (and (boundp 'display-time-string) display-time-string) ""))
                  (margin    (max 0 (- (window-total-width) (length clock-str) 42))))
             (propertize " " 'display `(space :align-to ,margin))))
   '(:propertize display-time-string face bold)
   " "))

;; 不要なサイドバー・ツリー等のウィンドウでモードラインを非表示にする
(use-package hide-mode-line
  :ensure t
  :hook
  ((neotree-mode imenu-list-major-mode minimap-mode) . hide-mode-line-mode))

;; タイトルバーのカスタマイズ（ドライブ名大文字化 ＆ パソコン名自動取得版）
(setq frame-title-format
      (list
       ;; 1. (フルパス) の先頭（ドライブ名）を大文字にして表示
       '(:eval (let ((path (or buffer-file-name (buffer-name))))
                 (format "%s" (if (string-match "^[a-z]:" path)
                                  ;; ドライブ文字だけ大文字にする（capitalize はパス全体に作用するため使わない）
                                  (concat (upcase (substring path 0 1)) (substring path 1))
                                path))))
       ;; 2.  Gnu Emacs at パソコン名（system-name関数でPC名を正しく取得）
       '(:eval (format " - GNU Emacs @ %s" system-name))))

;; =====================================================================
;; 6. タブバー（Centaur Tabs）
;; =====================================================================

(use-package centaur-tabs
  :demand t
  :config
  (setq centaur-tabs-set-bar   'top)
  (setq centaur-tabs-set-icons nil)
  (setq centaur-tabs-style     "bar")
  (setq centaur-tabs-height    26)
  (setq centaur-tabs-set-close-button t) ; 閉じるボタン（Xボタン）を有効にする
  ;; 通常バッファと内部バッファ（*scratch* など）の2グループに分け、
  ;; 内部バッファは右側（後方）のグループとして表示する。
  ;; centaur-tabs はグループをアルファベット順などで並べるため、
  ;; 内部バッファ側のグループ名を後方に来る文字列にしている。
  (defun centaur-tabs-buffer-groups ()
    (list
     (if (string-prefix-p "*" (buffer-name))
         "zzz-Internal"   ; 内部バッファ → 右側に表示
       "Buffers")))       ; 通常バッファ

  ;; タブは全部表示する（非表示ルールを無効化）
  (defun centaur-tabs-hide-tab (buffer) nil)
  ;; 注意: zzz-Internal グループのタブは編集中バッファのグループ表示中は
  ;; タブバー上に見えなくなるが、F2 (consult-buffer) で一覧から選択・
  ;; 切り替えは常に可能。
  (centaur-tabs-mode 1)
  :bind
  (("C-<tab>"   . centaur-tabs-forward)
   ("C-S-<tab>" . centaur-tabs-backward)))

;; =====================================================================
;; 6b. ブラウザ風バッファ履歴移動 ＆ quick-back（位置ピン留めジャンプ）
;; =====================================================================

;; --- ブラウザ風バッファ履歴移動 (Alt+← で過去へ、Alt+→ で進む) ---
;; いくつ前でも履歴をさかのぼって戻ることができ、戻りすぎたら進めます
(global-set-key (kbd "M-<left>")  #'switch-to-prev-buffer)
(global-set-key (kbd "M-<right>") #'switch-to-next-buffer)

;; --- どこでも一発ピン留め (C-') ＆ ピン消去 (C-S-' / C-u C-') ---
;; 範囲選択（青い反転）を起こさずに、足跡履歴（consult-mark）へピン留めする
(defun my/quick-pin-clear ()
  "現在のファイルのピン（足跡履歴）をすべて消去する。"
  (interactive)
  (setq mark-ring nil)
  (message "このファイルのピン（足跡履歴）をすべてクリアしました"))

(defun my/quick-pin-set (&optional clear)
  "現在位置を範囲選択を起こさずにピン留め（足跡記録）する。
C-u を前置するか、Ctrl+Shift+' を押すとこのファイルのピンを全消去する。"
  (interactive "P")
  (if clear
      (my/quick-pin-clear)
    (push-mark nil t nil)
    (message "現在位置をピン留めしました [%s] (SPC m で一覧 / C-S-' でクリア)"
             (buffer-name))))

;; キーバインド
(global-set-key (kbd "C-'")   #'my/quick-pin-set)
;; 消去キー: Ctrl+Shift+'（JIS/US配列両対応）
(global-set-key (kbd "C-\"")  #'my/quick-pin-clear)
(global-set-key (kbd "C-S-'") #'my/quick-pin-clear)



;; =====================================================================
;; 7. Windows 連携コマンド
;; =====================================================================


;; 現在のファイルを Windows の関連付けプログラムで開く
(defun my-open-current-file-in-windows ()
  "今開いているファイルをWindowsの関連付けプログラムで開きます。"
  (interactive)
  (cond
   ((not buffer-file-name)
    (message "外部で開けるファイルバッファではありません。"))
   ((not (file-exists-p buffer-file-name))
    (message "ファイルがまだ保存されていません。"))
   (t
    (w32-shell-execute "open" buffer-file-name)
    (message "外部プログラムで開きました: %s" (file-name-nondirectory buffer-file-name)))))

(defun my/open-any-file-in-windows (file)
  "ミニバッファで選択した任意のファイルをWindowsの関連付けプログラムで開きます。"
  (interactive
   (list (read-file-name "外部アプリで開くファイルを選択: " nil nil t)))
  (if (and file (file-exists-p file))
      (progn
        (w32-shell-execute "open" file)
        (message "外部プログラムで開きました: %s" (file-name-nondirectory file)))
    (message "有効なファイルではありません: %s" file)))

(defun my/open-recent-file-in-windows ()
  "最近使ったファイルリストから選択し、Windowsの関連付けプログラムで直接開きます。"
  (interactive)
  (let* ((recent-files recentf-list)
         (file (completing-read "外部アプリで開く最近のファイル: " recent-files nil t)))
    (if (and file (file-exists-p file))
        (progn
          (w32-shell-execute "open" file)
          (message "外部プログラムで開きました: %s" (file-name-nondirectory file)))
      (message "有効なファイルではありません: %s" file))))

;; =====================================================================
;; Everything (es.exe) 連携：全ドライブ 音楽・動画リアルタイム検索・再生
;; =====================================================================

(defcustom my/media-es-program
  (or (let ((p "C:/Users/gocho/AppData/Local/Programs/emacs_portable/bin/es.exe"))
        (when (file-exists-p p) p))
      (let ((p "C:/Program Files/PPX/tools/es.exe"))
        (when (file-exists-p p) p))
      (executable-find "es.exe")
      "es.exe")
  "Path to the Everything CLI (es.exe) executable."
  :type 'file
  :group 'convenience)

(defcustom my/media-extensions
  '("mp3" "flac" "wav" "m4a" "aac" "ogg" "opus" "wma"
    "mp4" "mkv" "avi" "wmv" "webm" "ts" "mov")
  "List of media file extensions (audio and video) to search."
  :type '(repeat string)
  :group 'convenience)

(defvar my/media--candidates-cache nil
  "In-memory cached list of formatted completion candidates.")

(defvar my/media-cache-file
  (expand-file-name "media-list.cache"
                    (expand-file-name ".cache" user-emacs-directory))
  "File path to persist media list cache across Emacs sessions.")

(defun my/media-clear-cache ()
  "Clear in-memory and on-disk media files cache."
  (interactive)
  (setq my/media--candidates-cache nil)
  (when (file-exists-p my/media-cache-file)
    (ignore-errors (delete-file my/media-cache-file)))
  (message "[Media] キャッシュを消去しました。"))

(defun my/media-fetch-files ()
  "Fetch all media files across all drives using `my/media-es-program`."
  (unless (and my/media-es-program (file-exists-p my/media-es-program))
    (user-error "es.exe が見つかりません: %s" my/media-es-program))
  (let* ((ext-query (concat "ext:" (string-join my/media-extensions ";")))
         (temp-file (make-temp-file "media_es_" nil ".txt"))
         (args (list ext-query "-export-txt" (subst-char-in-string ?/ ?\\ temp-file) "-utf8-bom"))
         (lines nil))
    (unwind-protect
        (progn
          (apply #'process-file my/media-es-program nil nil nil args)
          (if (and (file-exists-p temp-file) (> (file-attribute-size (file-attributes temp-file)) 0))
              (with-temp-buffer
                (let ((coding-system-for-read 'utf-8))
                  (insert-file-contents temp-file))
                (setq lines (split-string (buffer-string) "[\r\n]+" t)))
            ;; フォールバック：標準出力から CP932 (Shift_JIS) で取得
            (let* ((coding-system-for-read (if (eq system-type 'windows-nt) 'cp932-dos 'utf-8-dos))
                   (output (with-output-to-string
                             (with-current-buffer standard-output
                               (apply #'process-file my/media-es-program nil t nil (list ext-query))))))
              (setq lines (split-string output "[\r\n]+" t)))))
      (when (file-exists-p temp-file)
        (ignore-errors (delete-file temp-file))))
    (mapcar (lambda (line) (replace-regexp-in-string "\\\\" "/" (string-trim line))) lines)))

(defun my/media-candidates (file-list)
  "Format FILE-LIST into completion candidates with badges and text properties."
  (let ((id 0))
    (mapcar
     (lambda (fpath)
       (setq id (1+ id))
       (let* ((fname (file-name-nondirectory fpath))
              (dir   (file-name-directory fpath))
              (ext   (downcase (or (file-name-extension fpath) "")))
              (is-vid (member ext '("mp4" "mkv" "avi" "wmv" "webm" "ts" "mov")))
              (type-face (if is-vid 'font-lock-warning-face 'font-lock-keyword-face))
              (suffix (propertize (format "\0%d" id) 'invisible t))
              (disp (format "%-50s [%s]  %s%s"
                            fname
                            (propertize (upcase ext) 'face type-face)
                            (propertize (or dir "") 'face 'font-lock-comment-face)
                            suffix)))
         (propertize disp 'media-path fpath)))
     file-list)))

(defun my/media-get-candidates (&optional refresh)
  "Return formatted candidates from memory cache, disk cache, or es.exe."
  (cond
   ;; 1. 起動中はメモリキャッシュから即座に返す (0ms)
   ((and (not refresh) my/media--candidates-cache)
    my/media--candidates-cache)
   ;; 2. メモリになくてもディスクキャッシュがあれば高速復元
   ((and (not refresh)
         (file-exists-p my/media-cache-file)
         (> (file-attribute-size (file-attributes my/media-cache-file)) 0))
    (message "[Media] キャッシュから高速読み込み中...")
    (condition-case nil
        (with-temp-buffer
          (let ((coding-system-for-read 'utf-8))
            (insert-file-contents my/media-cache-file))
          (let ((files (split-string (buffer-string) "[\r\n]+" t)))
            (setq my/media--candidates-cache (my/media-candidates files))
            (message "[Media] キャッシュから %d 件を瞬時に読み込みました。" (length files))
            my/media--candidates-cache))
      (error (my/media-get-candidates t))))
   ;; 3. 初回または C-u (refresh) 時は Everything から取得してキャッシュ保存
   (t
    (message "[Media] Everything から全メディアファイルを検索中...")
    (let ((files (my/media-fetch-files)))
      (if (null files)
          (progn (message "[Media] メディアファイルが見つかりませんでした。") nil)
        (ignore-errors
          (let ((cache-dir (file-name-directory my/media-cache-file)))
            (unless (file-exists-p cache-dir)
              (make-directory cache-dir t)))
          (with-temp-file my/media-cache-file
            (let ((coding-system-for-write 'utf-8))
              (insert (string-join files "\n")))))
        (setq my/media--candidates-cache (my/media-candidates files))
        (message "[Media] %d 件の音楽・動画を取得・キャッシュしました。" (length files))
        my/media--candidates-cache)))))

;;;###autoload
(defun my/media-search-and-play (&optional refresh)
  "Everything (es.exe) で全ドライブの音楽・動画をリアルタイム検索して再生する。
C-u 付きで実行するとキャッシュを破棄して最新状態を再取得します。"
  (interactive "P")
  (let ((candidates (my/media-get-candidates refresh)))
    (when candidates
      (let* ((chosen (let ((orderless-matching-styles
                            '(orderless-literal orderless-regexp orderless-migemo)))
                       (completing-read
                        (format "メディア検索 (%d 件): " (length candidates))
                        candidates nil t)))
             (fpath (when chosen
                      (or (get-text-property 0 'media-path chosen)
                          (let ((m (car (member chosen candidates))))
                            (and m (get-text-property 0 'media-path m)))))))
        (if (not fpath)
            (message "キャンセルされました。")
          (if (file-exists-p fpath)
              (progn
                (message "再生: %s" (file-name-nondirectory fpath))
                (if (eq system-type 'windows-nt)
                    (w32-shell-execute "open" (subst-char-in-string ?/ ?\\ fpath))
                  (call-process "xdg-open" nil 0 nil fpath)))
            (message "ファイルが存在しません: %s" fpath)))))))

(defalias 'media-play #'my/media-search-and-play)
(defalias 'mp3-play #'my/media-search-and-play)
(defalias 'mp3-play-clear-cache #'my/media-clear-cache)


;; タブバー・モードラインのダブルクリックで外部プログラム起動
(with-eval-after-load 'centaur-tabs
  (define-key centaur-tabs-mode-map
    [header-line double-mouse-1] 'my-open-current-file-in-windows)
  ;; ---------------------------------------------------------------
  ;; タブ左クリック・中クリックの挙動修正
  ;; タブ本体は centaur-tabs-default-map を使用。
  ;; mouse-1 → 選択（明示固定）
  ;; mouse-2 → ignore（nil だと "undefined" エラーになる）
  ;; ---------------------------------------------------------------
  (defun my/centaur-tabs-fix-mouse-bindings ()
    (when (and (boundp 'centaur-tabs-default-map)
               (boundp 'centaur-tabs-display-line))
      (define-key centaur-tabs-default-map
        (vector centaur-tabs-display-line 'mouse-1) 'centaur-tabs-do-select)
      (define-key centaur-tabs-default-map
        (vector centaur-tabs-display-line 'mouse-2) #'ignore)))
  (if (featurep 'centaur-tabs-functions)
      (my/centaur-tabs-fix-mouse-bindings)
    (with-eval-after-load 'centaur-tabs-functions
      (my/centaur-tabs-fix-mouse-bindings))))
(global-set-key [mode-line double-mouse-1] 'my-open-current-file-in-windows)

;; WinMerge で差分比較
(defun my/winmerge-same-name-files (file)
  "FILE と同名（ディレクトリ違い）のファイルを開いているバッファのパス一覧を返す。
バッファの使用が新しい順に並ぶ。"
  (let ((name (downcase (file-name-nondirectory file)))
        result)
    (dolist (buf (buffer-list))
      (let ((f (buffer-file-name buf)))
        (when (and f
                   (string= (downcase (file-name-nondirectory f)) name)
                   (not (file-equal-p f file))
                   (not (member f result)))
          (push f result))))
    (nreverse result)))

(defun my/winmerge-auto-save-file ()
  "現在のバッファの自動保存ファイル（#名前#）が存在すればそのパスを返す。
未保存の変更があれば、最新の内容を反映するため先に自動保存を実行する。"
  (when buffer-auto-save-file-name
    (when (buffer-modified-p)
      (do-auto-save t t))          ; 現在のバッファだけ・メッセージなしで自動保存
    (when (file-exists-p buffer-auto-save-file-name)
      buffer-auto-save-file-name)))

(defun my-compare-with-winmerge ()
  "今開いているファイルをWinMergeで差分比較します。
比較先は次の優先順位で決めます。
1. 同名（ディレクトリ違い）のファイルを開いていればそれ（複数あれば選択）
2. 2画面分割中なら、もう一方の画面のファイル
3. 未保存の変更があれば自動保存ファイル（#名前#）
4. それ以外は同一ファイル"
  (interactive)
  (let ((winmerge-path
         (or (executable-find "WinMergeU.exe")
             (cl-find-if #'file-exists-p
                         (list (expand-file-name "WinMerge/WinMergeU.exe" (or (getenv "ProgramFiles") "C:/Program Files"))
                               (expand-file-name "WinMerge/WinMergeU.exe" (or (getenv "ProgramFiles(x86)") "C:/Program Files (x86)")))))))
    (if (not winmerge-path)
        (message "WinMergeU.exe が見つかりませんでした。インストールパスを確認してください。")
      (if (not buffer-file-name)
          (message "現在開いているバッファはファイルではありません。")
        (let* ((file1 buffer-file-name)
               (same  (my/winmerge-same-name-files file1))
               (file2
                (cond
                 ;; 1. 同名ファイルが1つだけ → それと比較
                 ((and same (null (cdr same))) (car same))
                 ;; 1. 複数 → 選択（最近使ったものが初期値）
                 (same (completing-read "比較先（同名ファイル）: " same nil t nil nil (car same)))
                 ;; 2〜4. なければ隣の画面のファイル → 自動保存ファイル → 同一ファイル
                 (t (let ((other-win (next-window)))
                      (cond
                       ((and (not (eq (selected-window) other-win))
                             (buffer-file-name (window-buffer other-win)))
                        (buffer-file-name (window-buffer other-win)))
                       ((my/winmerge-auto-save-file))
                       (t file1)))))))
          (w32-shell-execute "open" winmerge-path
                             (format "\"%s\" \"%s\"" file1 file2))
          (message "WinMergeで比較中: %s ⇔ %s"
                   (abbreviate-file-name file1)
                   (abbreviate-file-name file2)))))))

(global-set-key (kbd "C-S-d") 'my-compare-with-winmerge)


;; =====================================================================
;; 8. キーバインド
;; =====================================================================

;; --- CUA モード（Windows風 C-c/C-v/C-z）---
(cua-mode 1)
(setq cua-keep-region-after-copy nil)  ; コピー後も選択範囲をクリア
(delete-selection-mode t)              ; 選択範囲に直接上書き入力できるようにする
(setq select-enable-clipboard t)
(setq save-interprogram-paste-before-kill t)

;; CUA モードの C-x キー設定
;; cua-mode は標準で「選択中は C-x で切り取り、非選択中は C-x プレフィックス」を
;; 自動的にハンドリングするため、上書き不要。
;; cua-enable-cua-keys を明示的に t にして標準動作を保証する。
(setq cua-enable-cua-keys t)

;; =====================================================================
;; Alt+ドラッグで矩形選択する
;; ─ 標準の secondary-selection（M-drag-mouse-1）を上書きし、
;;   Windows系エディタのような Alt+ドラッグ矩形選択に置き換える
;; =====================================================================

(defun my/mouse-drag-rectangle (start-event)
  "Alt+ドラッグで矩形選択(rectangle-mark-mode)を行う。"
  (interactive "e")
  (mouse-minibuffer-check start-event)
  (let* ((start-posn (event-start start-event))
         (start-point (posn-point start-posn))
         (start-window (posn-window start-posn))
         event)
    (select-window start-window)
    (goto-char start-point)
    (push-mark start-point nil t)
    (rectangle-mark-mode 1)
    (track-mouse
      (catch 'my/rectangle-drag-done
        (while t
          (setq event (read-event))
          ;; 溜まっている移動イベントは古いものを捨てて最新の1つだけ処理する
          ;; （これによりドラッグ中の余分な再描画を減らし、引っかかりを軽減する）
          (while (and (mouse-movement-p event) (input-pending-p))
            (setq event (read-event)))
          (let* ((posn (event-end event))
                 (point (and posn (posn-point posn))))
            (when point
              (goto-char point)))
          (unless (or (mouse-movement-p event)
                      (memq (car-safe event) '(switch-frame select-window)))
            (throw 'my/rectangle-drag-done t)))))))

;; secondary-selection 用のデフォルトバインドを解除してから割り当てる
;; ※ マウスイベント+Modifierは (kbd "...") ではなくベクタ形式で指定する
(global-unset-key [M-down-mouse-1])
(global-set-key [M-down-mouse-1] #'my/mouse-drag-rectangle)

;; Windows風に Esc キーでも矩形選択を解除できるようにする
(with-eval-after-load 'rect
  (define-key rectangle-mark-mode-map (kbd "<escape>") #'keyboard-quit))

;; Windows 系ショートカット
(global-set-key (kbd "C-z") 'undo)
(global-set-key (kbd "C-y") 'undo-redo)

;; C-z (undo) の直感的な拡張として Alt+Z (M-z) に vundo を割り当て
(use-package vundo
  :ensure t
  :bind (("M-z" . vundo))
  :config
  ;; vundo 起動中は矢印キーで直感的にツリーを移動できるようにする
  (with-eval-after-load 'vundo
    (define-key vundo-mode-map (kbd "<right>") #'vundo-forward)
    (define-key vundo-mode-map (kbd "<left>")  #'vundo-backward)
    (define-key vundo-mode-map (kbd "<down>")  #'vundo-next)
    (define-key vundo-mode-map (kbd "<up>")    #'vundo-previous)))

(global-set-key (kbd "C-s") 'save-buffer)

;; C-a に全選択・全選択解除のトグルを割り当て
;; すでにバッファ全体が選択されている場合は選択解除、そうでなければ全選択する
(defun my/select-all-toggle ()
  "全選択と選択解除をトグルします。
リージョンがアクティブかつバッファ全体を覆っている場合は選択解除し、
それ以外の場合はバッファ全体を選択します。"
  (interactive)
  (if (and (use-region-p)
           (= (region-beginning) (point-min))
           (= (region-end) (point-max)))
      (deactivate-mark)
    (mark-whole-buffer)))
(global-set-key (kbd "C-a") 'my/select-all-toggle)
(global-set-key (kbd "C-o") 'menu-find-file-existing) ; Windows ネイティブダイアログで開く
(global-set-key (kbd "C-w") 'kill-current-buffer)
;; Ctrl+Q / Alt+F4 で確認付き Emacs 終了（Antigravity CLI / ターミナルへ安全に戻る）
(defun my/confirm-kill-emacs ()
  "Emacsを終了するか確認してから終了する。"
  (interactive)
  (when (y-or-n-p "Emacs を終了しますか？ ")
    (save-buffers-kill-terminal)))

(global-set-key (kbd "C-q") #'my/confirm-kill-emacs)        ; Ctrl+Q で確認付き終了 (MS-Edit風)
(global-set-key (kbd "M-<f4>") #'my/confirm-kill-emacs)     ; Alt+F4 で確認付き終了
(global-set-key (kbd "C-x C-c") #'my/confirm-kill-emacs)    ; C-x C-c で確認付き終了

;; C-e に行頭（インデント先頭）・行末のスマートトグルを割り当て
(defun my/toggle-beginning-end-of-line-smart ()
  "行末, インデントの先頭, 本当の行頭をトグルで移動します。
カーソルが行末にある場合：インデント先頭へ移動。（ただし空行等の場合は本当の行頭へ）
カーソルがインデント先頭にある場合：本当の行頭と異なる場合は本当の行頭へ、同じ場合は行末へ移動。
それ以外の場合：行末へ移動。"
  (interactive)
  (let ((orig-point (point)))
    (back-to-indentation)
    (let ((indent-point (point)))
      (goto-char orig-point)
      (cond
       ;; 1. 行末にいる場合
       ((eolp)
        (if (= (point) indent-point)
            (move-beginning-of-line nil)
          (goto-char indent-point)))
       ;; 2. インデント先頭にいる場合
       ((= orig-point indent-point)
        (let ((bol-point (save-excursion
                           (move-beginning-of-line nil)
                           (point))))
          (if (= indent-point bol-point)
              (move-end-of-line nil)
            (move-beginning-of-line nil))))
       ;; 3. それ以外（本当の行頭、行の中途など）
       (t
        (move-end-of-line nil))))))
(global-set-key (kbd "C-e") #'my/toggle-beginning-end-of-line-smart)

;; C-c = : xyzzy 風 calc-onthespot（選択範囲 or カーソル直前の数式を自動計算・置換）
;; 関数本体は右クリックメニューセクションで定義されているため、
;; with-eval-after-load ではなく after-init-hook で遅延バインドする
(add-hook 'after-init-hook
          (lambda ()
            (global-set-key (kbd "C-c =") #'my/ctx-calc-onthespot)))

;; F キー系
(global-set-key [f4]         'speedbar-get-focus) ;; F4 でスピードバー
;; F5: 現在のバッファをディスクから再読み込み（更新確認）
(defun my/revert-buffer-with-confirm ()
  "現在のバッファをディスクから再読み込み（更新）するか確認して実行します。"
  (interactive)
  (if (not buffer-file-name)
      (message "このバッファには関連付けられたファイルがありません")
    (if (not (file-exists-p buffer-file-name))
        (message "ファイルが存在しません: %s" buffer-file-name)
      (let* ((stale (not (verify-visited-file-modtime (current-buffer))))
             (prompt (if (buffer-modified-p)
                         (format "バッファ「%s」は未保存の変更があります。破棄してディスクから再読み込みしますか？ "
                                 (buffer-name))
                       (if stale
                           (format "ファイル「%s」は外部で変更されています。再読み込みしますか？ "
                                   (buffer-name))
                         (format "バッファ「%s」をディスクから再読み込みしますか？ "
                                 (buffer-name))))))
        (if (y-or-n-p prompt)
            (progn
              (revert-buffer t t t)
              (setq-local my/auto-revert-declined-modtime nil)
              (message "バッファ「%s」を再読み込みしました" (buffer-name)))
          (message "再読み込みをキャンセルしました"))))))

(global-set-key [f5] #'my/revert-buffer-with-confirm) ;; F5 で更新（確認付き）

;; F7: howm 環境 ON/OFF トグル
;; 　howm バッファが存在する → howm-kill-all で全消去（OFF）
;; 　howm バッファがない     → howm-menu を開く（ON）
(defun my/howm-toggle ()
  "howm 関連バッファが存在すればすべて消去・ウィンドウを閉じる。なければ howm-menu を開く。"
  (interactive)
  (if (cl-some (lambda (buf)
                 (with-current-buffer buf
                   (or (memq major-mode '(howm-menu-mode
                                          howm-view-summary-mode
                                          howm-view-contents-mode
                                          howm-mode))
                       (string-match-p "\\`\\*howm[MCS]" (buffer-name buf)))))
               (buffer-list))
      (progn
        (dolist (buf (buffer-list))
          (let ((name (buffer-name buf)))
            (when (or (string-match-p "\\`\\*howm[MCS]" name)
                      (string-match-p "\\`\\*Ilist\\*" name)
                      (with-current-buffer buf
                        (memq major-mode '(howm-menu-mode
                                           howm-view-summary-mode
                                           howm-view-contents-mode
                                           howm-mode))))
              (when-let* ((win (get-buffer-window buf)))
                (unless (one-window-p t)
                  (delete-window win)))
              (kill-buffer buf))))
        (message "howm をすべて閉じました"))
    (howm-menu)))
;; F7: howm 環境 ON/OFF トグル
(global-set-key [f7] #'my/howm-toggle)
(global-set-key (kbd "<f7>") #'my/howm-toggle)

;; Ctrl+F7: howm の対象フォルダ切り替え (Vault 全体 / サブフォルダ)
(global-set-key [C-f7] #'my/howm-switch-folder)
(global-set-key (kbd "C-<f7>") #'my/howm-switch-folder)

;; Shift+F7: howm メモフォルダ内を consult-ripgrep で全文検索
(defun my/howm-ripgrep (&optional initial)
  "howm メモフォルダ (howm-directory) 内を consult-ripgrep で全文検索します。
選択範囲があればそれを初期入力値にします。"
  (interactive
   (list (when (use-region-p)
           (buffer-substring-no-properties (region-beginning) (region-end)))))
  (consult-ripgrep howm-directory initial))
(global-set-key [S-f7] #'my/howm-ripgrep)       ;; Shift+F7 で howm メモ全文検索
(global-set-key (kbd "<S-f7>") #'my/howm-ripgrep)

;; F8: カレンダー (calfw)
(global-set-key [f8] #'my/open-calendar)
(global-set-key (kbd "<f8>") #'my/open-calendar)

;; Shift+F8: 週間天気予報 (weather)
(global-set-key [S-f8] #'my/weather)
(global-set-key (kbd "<S-f8>") #'my/weather)

(global-set-key (kbd "<menu>") 'context-menu-open) ;; Menu キーで右クリック

;; F3: 検索開始 / 次を検索（兼用、前方）
;; S-F3: 検索開始 / 前を検索（兼用、後方）
;; isearch-mode 外で isearch-forward/backward を直接呼ぶと
;; 「検索文字列なし」状態でも repeat 扱いになり
;; "no previous search string" エラーになるため、
;; isearch-mode かどうかで呼び分けるラッパーを用意する。
(defun my/isearch-forward-or-repeat ()
  (interactive)
  (if isearch-mode
      (isearch-repeat-forward)
    (isearch-forward)))

(defun my/isearch-backward-or-repeat ()
  (interactive)
  (if isearch-mode
      (isearch-repeat-backward)
    (isearch-backward)))

(global-set-key (kbd "<f3>")   'my/isearch-forward-or-repeat)
(global-set-key (kbd "S-<f3>") 'my/isearch-backward-or-repeat)

;; Meowの n/N（Vim風「次/前を検索」）用に用意した関数。
;; ※ 現在は n を meow-search のままにしているため未使用(定義だけ残置)。
;;   検討の結果また n/N に割り当てたくなったら、Meowのnormal-define-key
;;   側で '("n" . my/isearch-repeat-forward-anywhere) のように呼べば良い。
;; isearch-repeat-forward/backwardはisearch-mode中でないと呼べないため、
;; isearch-mode外では isearch-yank-string で確定済みの検索文字列を
;; 注入してから検索する。現在位置が既にマッチ上にある場合に同じ場所へ
;; 留まらないよう、検索開始前に1文字ずらしておく。
(defun my/isearch-repeat-forward-anywhere ()
  (interactive)
  (if isearch-mode
      (isearch-repeat-forward)
    (if (and isearch-string (not (string-empty-p isearch-string)))
        (progn
          (unless (eobp) (forward-char 1))
          (isearch-forward)
          (isearch-yank-string isearch-string)
          (isearch-exit))
      (message "検索文字列がありません（先に / で検索してください）"))))

(defun my/isearch-repeat-backward-anywhere ()
  (interactive)
  (if isearch-mode
      (isearch-repeat-backward)
    (if (and isearch-string (not (string-empty-p isearch-string)))
        (progn
          (unless (bobp) (backward-char 1))
          (isearch-backward)
          (isearch-yank-string isearch-string)
          (isearch-exit))
      (message "検索文字列がありません（先に / で検索してください）"))))

(with-eval-after-load 'isearch
  (define-key isearch-mode-map (kbd "<f3>")   'isearch-repeat-forward)
  (define-key isearch-mode-map (kbd "S-<f3>") 'isearch-repeat-backward)
  ;; 矢印キーでもC-s/C-r連打と同じことができるように
  (define-key isearch-mode-map (kbd "<down>") 'isearch-repeat-forward)
  (define-key isearch-mode-map (kbd "<up>")   'isearch-repeat-backward))


;; =====================================================================
;; 9. Windows シェル連携
;; =====================================================================

;; emacs-conpty (Windows ConPTY Proxy)
;; ビルド済みの emacs-conpty.exe を使用して、日本語やエスケープシーケンスを正しく表示します。
(let ((conpty-dir (expand-file-name "lisp/" user-emacs-directory)))
  (when (file-directory-p conpty-dir)
    (add-to-list 'load-path conpty-dir)
    (use-package conpty
      :ensure nil
      :commands (conpty conpty-powershell)
      :config
      (setq conpty-program (expand-file-name "bin/emacs-conpty.exe"
                                             (expand-file-name ".." user-emacs-directory))))))

;; ドラッグ＆ドロップでファイルを開く挙動を強制的に有効化
(setq dnd-protocol-alist
      '(("^file:///" . dnd-open-local-file)
        ("^file://"  . dnd-open-local-file)
        ("^file:"    . dnd-open-local-file)))

;; =====================================================================
;; 10. Migemo（日本語ローマ字検索）
;; =====================================================================

(use-package migemo
  :config
  (setq migemo-command
        (or (executable-find "cmigemo")
            (expand-file-name "bin/cmigemo.exe" (expand-file-name ".." user-emacs-directory))))
  (setq migemo-options '("-q" "-e"))
  (if-let* ((cmigemo-path (executable-find "cmigemo")))
      (progn
        (setq migemo-dictionary
              (expand-file-name "dict/utf-8/migemo-dict"
                                (file-name-directory cmigemo-path)))
        (setq migemo-user-dictionary  nil)
        (setq migemo-regex-dictionary nil)
        (setq migemo-coding-system    'utf-8-unix)
        (migemo-init)
        ;; migemo.el は isearch 統合を標準搭載しており、migemo-init 後は
        ;; 既定(t)で有効。つまり F3/Shift-F3（isearch-forward/backward）は
        ;; 既にMigemo対応済みのため、別途 isearch-migemo 等の追加は不要。
        (setq migemo-isearch-enable-p t))
    (message "【お知らせ】cmigemo が見つからないため Migemo を無効化しています。")))


;; =====================================================================
;; 10b. color-moccur ＆ moccur-edit（Migemo対応検索・一括編集）
;; =====================================================================

(add-to-list 'load-path (expand-file-name "site-lisp" user-emacs-directory))

(use-package color-moccur
  :ensure nil
  :commands (moccur moccur-search-files moccur-search-files-with-color)
  :bind (:map isearch-mode-map
         ("M-o" . isearch-moccur))
  :config
  ;; Migemoを利用できる環境であればMigemoを使う
  (when (and (executable-find "cmigemo") (require 'migemo nil t))
    (setq moccur-use-migemo t))
  
  ;; スペース区切りでAND検索を可能にする
  (setq moccur-split-word t)

  ;; moccur表示中にヘッダーラインに操作説明を表示
  (advice-add 'moccur-mode :after
              (lambda (&rest _)
                (setq header-line-format
                      (propertize
                       "  [moccur表示中]  |  r: 編集モードに入る  |  q: 閉じる"
                       'face '(:background "#1a3a5c" :foreground "#aed6f1" :weight bold))))))

(use-package moccur-edit
  :ensure nil
  :after color-moccur
  :config
  ;; moccur-edit編集中にヘッダーラインを編集モード用に切り替え
  (advice-add 'moccur-edit-mode-in :after
              (lambda (&rest _)
                (setq header-line-format
                      (propertize
                       "  [moccur編集中]  |  C-c C-c: 変更を元ファイルに保存  |  C-c C-k: 編集をキャンセル"
                       'face '(:background "#3a1a1a" :foreground "#f4b8b8" :weight bold)))))

  ;; 編集モード終了時にヘッダーラインを元に戻す
  (advice-add 'moccur-edit-reset-key :after
              (lambda (&rest _)
                (setq header-line-format
                      (propertize
                       "  [moccur表示中]  |  r: 編集モードに入る  |  q: 閉じる"
                       'face '(:background "#1a3a5c" :foreground "#aed6f1" :weight bold))))))


;; =====================================================================
;; 11. 補完エコシステム（Vertico / Orderless / Consult / Embark / Hydra）
;; =====================================================================

(use-package vertico
  :init (vertico-mode)
  :config
  (setq vertico-count 20))

;; vertico-posframe — 候補リストをカーソル近くにポップアップ表示
;; consult-line / consult-ripgrep 等の候補をミニバッファではなく
;; フレーム内のポップアップウィンドウに表示する
;; vertico-multiform + vertico-posframe の組み合わせで
;; my/consult-line-symbol-at-point（popup-search相当）だけ posframe を使い、
;; 他はすべて通常のミニバッファ表示にする。
(use-package vertico-posframe
  :after vertico
  :config
  ;; posframe のデフォルト設定（posframe が使われるコマンド向け）
  (setq vertico-posframe-poshandler #'posframe-poshandler-point-bottom-left-corner)
  (setq vertico-posframe-width  100
        vertico-posframe-height 20)
  (setq vertico-posframe-border-width 2))

;; vertico-multiform でコマンドごとの表示方式を切り替える
;; my/consult-line-symbol-at-point だけ posframe、それ以外はデフォルト（ミニバッファ）
(use-package vertico-multiform
  :ensure nil  ; vertico に同梱
  :after vertico-posframe
  :config
  (setq vertico-multiform-commands
        '((my/consult-line-symbol-at-point posframe)
          (my/context-menu-popup-search posframe)))
  (vertico-multiform-mode 1))

(use-package orderless
  :custom
  (completion-styles '(orderless basic))
  (completion-category-overrides '((file (styles basic partial-completion))))
  :config
  ;; Migemo を orderless のマッチ戦略として追加
  (defun orderless-migemo (component)
    (if (and (fboundp 'migemo-get-pattern) (featurep 'migemo))
        (let ((pattern (migemo-get-pattern component)))
          (condition-case nil
              (progn (string-match pattern "") pattern)
            (invalid-regexp component)))
      component))
  (setq orderless-matching-styles
        '(orderless-literal
          orderless-regexp
          orderless-initialism   ; 頭文字マッチ (例: "fb" で "foo-bar")
          ;;orderless-flex         ; まさに fzf 風の曖昧マッチ (例: "ax" で "apple-index") 
          ;;\b（keyword）と入力しないと検索結果にノイズが多く乗るのでOFF
          orderless-migemo)))   ; ローマ字日本語マッチ

(use-package marginalia
  :init (marginalia-mode))

;; --- Corfu (ポップアップ補完 UI) ---
(use-package corfu
  :custom
  (corfu-auto t)                 ; 入力中に自動でポップアップ
  (corfu-auto-delay 0.1)         ; ポップアップまでの遅延（秒）
  (corfu-auto-prefix 2)          ; 2文字以上で補完開始
  (corfu-cycle t)                ; 候補をループさせる
  :init
  (global-corfu-mode)
  ;; TAB での補完挙動を調整（インデント済みなら補完を開始）
  (setq tab-always-indent 'complete))

;; --- Cape (補完バックエンド拡張) ---
(use-package cape
  :init
  ;; dabbrev (バッファ内の単語) を補完候補に追加
  (add-to-list 'completion-at-point-functions #'cape-dabbrev)
  ;; ファイルパスを補完候補に追加
  (add-to-list 'completion-at-point-functions #'cape-file)
  ;; Elisp のコードブロック内での補完
  (add-to-list 'completion-at-point-functions #'cape-elisp-block))

;; ispell の辞書が存在しないため ispell-completion-at-point を無効化する
;; （Corfu が毎回 "No plain word-list found" エラーを出すのを防ぐ）
(with-eval-after-load 'ispell
  ;; ポータブル環境に辞書がないため、ispell 補完を完全に無効化
  (setq ispell-alternate-dictionary nil)
  ;; ispell-completion-at-point が capf に追加されても動かないようにする
  (defun ispell-completion-at-point () nil))

;; ispell-completion-at-point をグローバル capf リストから除去
(setq completion-at-point-functions
      (remove #'ispell-completion-at-point completion-at-point-functions))


;; --- Hydra メニュー ---
(use-package hydra)

;; プロジェクトルートから ripgrep 検索
(defun my/consult-ripgrep-project ()
  "現在の project.el ルートを対象に consult-ripgrep を実行します。"
  (interactive)
  (if-let* ((project (project-current)))
      (consult-ripgrep (project-root project))
    (call-interactively #'consult-ripgrep)))

(defun my/consult-ripgrep-word (&optional dir)
  "カーソル位置の単語を完全一致で ripgrep 検索する。
\b の代わりに lookbehind/lookahead を使うことで fd-find のようなハイフン含む
単語も正しくマッチする。C-u を付けると検索ディレクトリを選択できる。"
  (interactive "P")
  (let* ((search-dir
          (cond
           (dir (read-directory-name "検索ディレクトリ: " nil nil t))
           ((project-current) (project-root (project-current)))
           (t nil)))
         (default (thing-at-point 'symbol t)) ; word ではなく symbol でハイフン込みで取得
         (word (read-string
                (format "単語検索%s: "
                        (if default (format " [%s]" default) ""))
                nil nil default)))
    ;; (?<!\w)(?<!-) : 直前が英数字またはハイフンでない（PCRE2 では [\w-] はブラケット内不可）
    ;; (?!\w)(?!-)  : 直後が英数字またはハイフンでない
    (consult-ripgrep search-dir (concat "(?<!\w)(?<!-)" word "(?!\w)(?!-)"))))

;; C-c r w に割り当て
(global-set-key (kbd "C-c r w") #'my/consult-ripgrep-word)

;; Migemo を強制して consult-line を起動
(defun my/consult-line-migemo ()
  "通常検索と Migemo（ローマ字で日本語検索）を併用して consult-line を起動します。
選択範囲がある場合はその文字列を初期入力としてセットします。"
  (interactive)
  (let ((consult--regexp-compiler #'my/consult-migemo-compiler)
        (initial (when (use-region-p)
                   (prog1 (buffer-substring-no-properties
                           (region-beginning) (region-end))
                     (deactivate-mark)))))
    (consult-line initial)))

;; 選択範囲があればその文字列を、なければカーソル下の単語を consult-line で検索
(defun my/consult-line-symbol-at-point ()
  "選択範囲（またはカーソル下の単語）を即 consult-line 検索する。
選択範囲の場合はそのまま、単語の場合は単語境界マッチ。"
  (interactive)
  (cond
   ((use-region-p)
    (let ((text (buffer-substring-no-properties (region-beginning) (region-end))))
      (deactivate-mark)
      (consult-line (regexp-quote text))))
   (t
    (let ((word (thing-at-point 'symbol t)))
      (if word
          (consult-line (concat "\\<" (regexp-quote word) "\\>"))
        (consult-line))))))

(global-set-key (kbd "C-c l") #'my/consult-line-symbol-at-point)

;; コピー・切り取り時にミニバッファへ通知メッセージを表示
(defun my/kill-ring-notify (orig-fn beg end &rest args)
  "kill-ring-save / kill-region の後にコピー・切り取り文字数を通知する。"
  (let ((text (buffer-substring-no-properties beg end)))
    (apply orig-fn beg end args)
    (message "クリップボード: [%s]%s"
             (truncate-string-to-width text 40 nil nil "…")
             (if (> (length text) 40) "" ""))))
(advice-add 'kill-ring-save :around #'my/kill-ring-notify)
(advice-add 'kill-region     :around #'my/kill-ring-notify)
;; CUA モードの C-c コピーは cua-copy-region を使うため別途通知
(defun my/cua-copy-notify (&rest args)
  "cua-copy-region の後にコピー内容を通知する。"
  (when (use-region-p)
    (let ((text (buffer-substring-no-properties (region-beginning) (region-end))))
      (message "クリップボード: [%s]%s"
               (truncate-string-to-width text 40 nil nil "…")
               (if (> (length text) 40) "" "")))))
(advice-add 'cua-copy-region :after #'my/cua-copy-notify)

;; ウィンドウ・バッファ管理メニュー（:color red で閉じるまで連打可能）
(defhydra hydra-window (:color red :hint nil)
  "
  === WINDOW & BUFFER (M-o w) ===
  [分割]                    [移動・サイズ]              [閉じる]
  [2] 上下に分割          [o] 次のウィンドウへ      [0] このウィンドウを閉じる
  [3] 左右に分割          [O] 前のウィンドウへ      [1] 他をすべて閉じる
                            [=] 幅・高さをそろえる    [k] バッファを閉じる
                            [+] 高さを広げる          [K] バッファ＋ウィンドウを閉じる
                            [-] 高さを縮める
  ----------------------------------------------------------------------
  [q] 閉じる
"
  ;; 分割
  ("2" split-window-below)
  ("3" split-window-right)
  ;; 移動・サイズ調整
  ("o" other-window)
  ("O" (other-window -1))
  ("=" balance-windows)
  ("+" enlarge-window)
  ("-" shrink-window)
  ;; 閉じる
  ("0" delete-window)
  ("1" delete-other-windows)
  ("k" kill-current-buffer)
  ("K" (progn (kill-current-buffer) (delete-window)))
  ("q" nil :color blue))

(defun my/run-in-external-terminal (shell cmd)
  "CMD を SHELL ('cmd または 'powershell) の外部ターミナルウィンドウで実行します。
wt.exe があれば Windows Terminal で、なければ標準のコンソール（ConHost）で起動します。"
  (let* ((wt (or (executable-find "wt.exe") (executable-find "wt")))
         (file-path (buffer-file-name))
         (run-dir (if file-path
                      (expand-file-name (file-name-directory file-path))
                    (expand-file-name default-directory)))
         ;; PowerShell 用: 1行の -Command 文字列にまとめて渡す方式は、
         ;; Windows のコマンドライン再構成の過程でパス中の "(" ")" 等の
         ;; 特殊文字と噛み合わずクォートが壊れることがある(例:
         ;; フォルダ名に "(Wed)" のような括弧が入っていると、agy 側が
         ;; 受け取る引数にクォート文字がそのまま混入してしまう)。
         ;; 一時 .ps1 ファイルに書き出して `-File' で実行する方式にすれば、
         ;; コマンドライン再構成を経由しないのでこの種の崩れが起きない。
         (ps-script-file (and (eq shell 'powershell) (make-temp-file "emacs-run-" nil ".ps1")))
         (ps-args (when ps-script-file
                    (with-temp-file ps-script-file
                      (insert "Set-Location -LiteralPath '"
                              (replace-regexp-in-string "'" "''" run-dir t t)
                              "'\n"
                              cmd
                              "\n"
                              "Remove-Item -Force -LiteralPath $PSCommandPath\n"))
                    (format "-NoExit -ExecutionPolicy Bypass -File \"%s\"" ps-script-file))))
    (cond
     (wt
      (cond
       ((eq shell 'cmd)
        (w32-shell-execute
         "open" wt
         (concat "cmd.exe /k cd /d \"" run-dir "\" && " cmd)))
       ((eq shell 'powershell)
        (w32-shell-execute
         "open" wt
         (concat "powershell.exe " ps-args)))))
     (t
      (cond
       ((eq shell 'cmd)
        (w32-shell-execute
         "open" "cmd.exe"
         (concat "/k cd /d \"" run-dir "\" && " cmd)))
       ((eq shell 'powershell)
        (w32-shell-execute
         "open" "powershell.exe"
         ps-args)))))))

(defun my/run-command-cmd-on-current-file (cmd)
  "現在のファイルを引数にして、cmd.exe 経由で外部コマンドを外部ターミナルで実行します。
%f は現在のファイルパスに置き換わります（なければ末尾に追加）。"
  (interactive "s[cmd] 実行する外部コマンド (例: python, agy(Antigravity) -y): ")
  (let ((file (buffer-file-name)))
    (if (not file)
        (user-error "このバッファはファイルに対応していません")
      (when (buffer-modified-p)
        (save-buffer))
      (let* ((quoted-file (shell-quote-argument file))
             (final-cmd (if (string-match-p "%f" cmd)
                            (replace-regexp-in-string "%f" quoted-file cmd t t)
                          (concat cmd " " quoted-file))))
        (my/run-in-external-terminal 'cmd final-cmd)))))

(defun my/ps-quote-argument (file)
  "PowerShell 用にファイルパスをシングルクォートで囲む。
ダブルクォートは w32-shell-execute 経由でWindowsに剥ぎ取られるため
シングルクォートを使う。PowerShell のシングルクォートは括弧等を含む
パスをリテラルとして安全に渡せる。内部にシングルクォートがあれば '' に変換。"
  (concat "'" (replace-regexp-in-string "'" "''" file t t) "'"))

(defun my/run-command-powershell-on-current-file (cmd)
  "現在のファイルを引数にして、PowerShell 経由で外部コマンドを外部ターミナルで実行します。
%f は現在のファイルパスに置き換わります（なければ末尾に追加）。"
  (interactive "s[PowerShell] 実行する外部コマンド (例: python, agy(Antigravity) -y): ")
  (let ((file (buffer-file-name)))
    (if (not file)
        (user-error "このバッファはファイルに対応していません")
      (when (buffer-modified-p)
        (save-buffer))
      (let* ((quoted-file (my/ps-quote-argument file))
             (final-cmd (if (string-match-p "%f" cmd)
                            (replace-regexp-in-string "%f" quoted-file cmd t t)
                          (concat cmd " " quoted-file))))
        (my/run-in-external-terminal 'powershell final-cmd)))))

(defun my/run-agy-cmd-on-current-file (args)
  "現在のファイルを Antigravity (agy.exe) に渡し、cmd.exe 経由で外部ターミナルで実行します。"
  (interactive "s[cmd] Antigravity(agy) の追加オプション (必要なら入力、例: --model xxx): ")
  (let ((file (buffer-file-name)))
    (if (not file)
        (user-error "このバッファはファイルに対応していません")
      (when (buffer-modified-p)
        (save-buffer))
      ;; agy はファイルパスを裸の位置引数として渡すと
      ;; "unexpected argument" エラーになる。-i (--prompt-interactive)
      ;; の初期プロンプトとしてファイルパスを渡す。
      (let* ((quoted-file (shell-quote-argument file))
             (cmd (if (string-empty-p args)
                      (concat "agy -i " quoted-file)
                    (concat "agy " args " -i " quoted-file))))
        (my/run-in-external-terminal 'cmd cmd)))))

(defun my/run-agy-powershell-on-current-file (args)
  "現在のファイルを Antigravity (agy.exe) に渡し、PowerShell 経由で外部ターミナルで実行します。"
  (interactive "s[PowerShell] Antigravity(agy) の追加オプション (必要なら入力、例: --model xxx): ")
  (let ((file (buffer-file-name)))
    (if (not file)
        (user-error "このバッファはファイルに対応していません")
      (when (buffer-modified-p)
        (save-buffer))
      (let* ((quoted-file (my/ps-quote-argument file))
             (cmd (if (string-empty-p args)
                      (concat "agy -i " quoted-file)
                    (concat "agy " args " -i " quoted-file))))
        (my/run-in-external-terminal 'powershell cmd)))))

;; --- Antigravity CLI ＆ gptel 連携（バッファ/選択範囲送信） ---

(defun my/agy-export-context (start end)
  "指定範囲のテキストをフォーマットし、一時ファイルとクリップボードに出力する。"
  (let* ((text (buffer-substring-no-properties start end))
         (mode major-mode)
         (mode-str (replace-regexp-in-string "-mode$" "" (symbol-name mode)))
         (file-path (buffer-file-name))
         (file-name (if file-path (file-name-nondirectory file-path) (buffer-name)))
         (line-start (line-number-at-pos start))
         (line-end (line-number-at-pos end))
         (is-full (and (= start (point-min)) (= end (point-max))))
         (range-str (if is-full "バッファ全体" (format "行 %d〜%d" line-start line-end)))
         (header (format "【対象: %s (%s, %s)】" file-name mode-str range-str))
         (formatted (format "%s\n\n```%s\n%s\n```\n" header mode-str text))
         (tmp-dir (expand-file-name "tmp" user-emacs-directory))
         (ctx-file (expand-file-name "agy-context.md" tmp-dir)))
    (unless (file-directory-p tmp-dir)
      (make-directory tmp-dir t))
    (with-temp-file ctx-file
      (let ((coding-system-for-write 'utf-8-unix))
        (insert formatted)))
    (w32-set-clipboard-data formatted)
    ctx-file))

(defun my/agy-launch-terminal (context-file &optional prompt continue)
  "PowerShell (Windows Terminal) で run-agy.ps1 を起動する。"
  (let* ((wt (or (executable-find "wt.exe") (executable-find "wt")))
         (pwsh-exe (or (executable-find "pwsh.exe") (executable-find "pwsh")))
         (shell-bin (if pwsh-exe "pwsh.exe" "powershell.exe"))
         (file-path (buffer-file-name))
         (work-dir (if file-path
                       (file-name-directory file-path)
                     default-directory))
         (script-file (expand-file-name "run-agy.ps1" user-emacs-directory))
         (prompt-arg (if (and prompt (not (string-empty-p prompt)))
                         (format " -Prompt \"%s\"" (replace-regexp-in-string "\"" "`\"" prompt))
                       ""))
         (ctx-arg (if context-file (format " -ContextFile \"%s\"" context-file) ""))
         (ps-args (if continue
                      (format "-NoExit -ExecutionPolicy Bypass -File \"%s\" -WorkDir \"%s\" -Continue"
                              script-file work-dir)
                    (format "-NoExit -ExecutionPolicy Bypass -File \"%s\" -WorkDir \"%s\"%s%s"
                            script-file work-dir ctx-arg prompt-arg))))
    (if wt
        (w32-shell-execute "open" wt (concat shell-bin " " ps-args))
      (w32-shell-execute "open" shell-bin ps-args))))

(defun my/agy-send-region (start end &optional prompt)
  "選択範囲を Antigravity (PowerShell) に送信する。"
  (interactive
   (if (use-region-p)
       (list (region-beginning) (region-end)
             (read-string "Antigravity への指示 (EnterでPowerShellで入力): "))
     (user-error "範囲が選択されていません")))
  (let ((ctx-file (my/agy-export-context start end)))
    (deactivate-mark)
    (my/agy-launch-terminal ctx-file prompt)
    (message "Antigravity CLI (PowerShell) を起動しました。")))

(defun my/agy-send-buffer (&optional prompt)
  "バッファ全体を Antigravity (PowerShell) に送信する。"
  (interactive
   (list (read-string "Antigravity への指示 (EnterでPowerShellで入力): ")))
  (let ((ctx-file (my/agy-export-context (point-min) (point-max))))
    (when (use-region-p) (deactivate-mark))
    (my/agy-launch-terminal ctx-file prompt)
    (message "Antigravity CLI (PowerShell) を起動しました。")))

(defun my/agy-send-dwim (&optional prompt)
  "選択範囲があれば選択範囲、なければバッファ全体を Antigravity に送信する。"
  (interactive
   (list (read-string "Antigravity への指示 (EnterでPowerShellで入力): ")))
  (if (use-region-p)
      (my/agy-send-region (region-beginning) (region-end) prompt)
    (my/agy-send-buffer prompt)))

(defun my/agy-continue ()
  "直前の Antigravity セッションを再開する (agy -c)。"
  (interactive)
  (my/agy-launch-terminal nil nil t)
  (message "直前の Antigravity セッションを再開しました。"))

;; gptel 操作ガイド Hydra
(defhydra hydra-gptel-help (:color blue :hint nil)
  "
  === gptel AI チャット操作ガイド ===  [F1 / q] 閉じる
  [基本操作]
  [C-c RET]  メッセージを送信 (問いかけ送信)
  [C-c g m]  モデル切替・パラメータ設定 (gptel-menu)
  [C-c g c]  現在のバッファ全体をコンテキストに追加/解除 (gptel-add)
  [M-o A]    AI & Antigravity 全体メニュー (hydra-ai)

  [問いかけの手順 (チャット)]
  1. バッファ末尾に聞きたい質問や指示を日本語で入力します。
  2. 【C-c RET】(Ctrl を押しながら Enter) を押すと AI に送信されます。
  3. 回答が出た後、さらに下に続けて質問を書いて C-c RET を押せば対話が続きます。

  [問いかけの手順 (ファイル編集中)]
  ・質問したい範囲を選択して右クリック ＞「AI アシスタント」＞「質問・指示を入力して送信」
  ・または M-o A を押して [a] (自動判別) / [s] (指示入力) を選ぶ
  ------------------------------------------------------------------------------------------
  [m] モデル切替 (gptel-menu)   [s] 質問・指示を入力   [A] Antigravity(PS)   [q / F1] 閉じる
"
  ("m" gptel-menu)
  ("s" (my/gptel-context-send nil))
  ("A" hydra-ai/body)
  ("<f1>" nil :color blue)
  ("<F1>" nil :color blue)
  ("q" nil :color blue))

;; AI ＆ Antigravity 専用ランチャーメニュー
(defhydra hydra-ai (:color blue :hint nil)
  "
  === AI & ANTIGRAVITY ASSISTANT ===
  [Antigravity CLI (PowerShell)]            [gptel (インライン / チャット)]
  [a] 自動判別送信 (選択範囲 or バッファ)    [g] チャットバッファを開く (*AI-Chat*)
  [r] 選択範囲を送信                        [s] 質問・指示を入力して送信 (ポップアップ)
  [b] バッファ全体を送信                    [m] モデル切替・設定 (gptel-menu)
  [c] 直前のセッションを再開 (agy -c)       [e] コード／文章を解説
  [p] PowerShell で agy 起動 (引数自由)    [x] 文章を校正・推敲
  ------------------------------------------------------------------------------------------
  [?] gptel 操作ガイド (F1)                 [M] メインランチャーに戻る (M-o)   [q] 閉じる
"
  ("a" my/agy-send-dwim)
  ("r" my/agy-send-region)
  ("b" my/agy-send-buffer)
  ("c" my/agy-continue)
  ("p" my/run-agy-powershell-on-current-file)
  ("g" (gptel "*AI-Chat*"))
  ("s" (my/gptel-context-send nil))
  ("m" gptel-menu)
  ("e" (my/gptel-context-send nil "以下のコード／文章を分かりやすく日本語で解説してください：\n\n"))
  ("x" (my/gptel-context-send nil "以下の文章の誤字脱字を直し、より自然で分かりやすい文章に推敲してください：\n\n"))
  ("?" hydra-gptel-help/body)
  ("h" hydra-gptel-help/body)
  ("M" hydra-launcher/body)
  ("q" nil :color blue))

;; ファイル操作メニュー
(defhydra hydra-file (:color blue :hint nil)
  "
  === FILE OPERATIONS (M-o F) ===
  [開く・保存]                           [外部アプリで直接開く]
  [o] ファイルを開く                   [e] 現在のファイルを外部で開く
  [r] 最近のファイル                   [E] 任意のファイルを外部で開く
  [s] 上書き保存                       [R] 最近のファイルを外部で開く
  [m] 音楽・動画を検索して再生 (Everything)
  [k] バッファを閉じる                 [AI・外部コマンド実行]
                                         [A] AI & Antigravity メニュー (hydra-ai)
                                         [a] Antigravity(agy) を cmd で実行
                                         [x] コマンドを実行 (cmd, %%%%f=パス)
                                         [X] コマンドを実行 (PS, %%%%f=パス)
                                         [その他]
                                         [d] WinMerge で差分比較
                                         [c] 文字コード指定で開き直す
                                         [p] Pandoc で別形式に変換
                                         [K] EPUBをKindle (azw/azw3) に変換
  ----------------------------------------------------------------------
  [q] 閉じる
"
  ("o" find-file)
  ("r" consult-recent-file)
  ("s" save-buffer)
  ("S" write-file)
  ("k" kill-current-buffer)
  ("e" my-open-current-file-in-windows)
  ("E" my/open-any-file-in-windows)
  ("R" my/open-recent-file-in-windows)
  ("m" my/media-search-and-play)
  ("A" hydra-ai/body)
  ("a" my/run-agy-cmd-on-current-file)
  ("x" my/run-command-cmd-on-current-file)
  ("X" my/run-command-powershell-on-current-file)
  ("d" my-compare-with-winmerge)
  ("c" revert-buffer-with-coding-system)
  ("p" my/pandoc-convert-to-format)
  ("K" my/epub-to-kindle-convert)
  ("q" nil :color blue))



;; Obsidian Vault 操作関数（migemo 対応検索含む）
(defun my/obsidian-ripgrep-migemo ()
  "Obsidian Vault 内を migemo（ローマ字）で全文検索します。"
  (interactive)
  (require 'obsidian)
  (let ((orderless-matching-styles '(orderless-migemo)))
    (consult-ripgrep obsidian-directory)))

(defun my/obsidian-find-file-migemo ()
  "Obsidian Vault 内のファイルを migemo でファイル名検索します。"
  (interactive)
  (require 'obsidian)
  (let ((orderless-matching-styles '(orderless-migemo))
        (default-directory obsidian-directory))
    (consult-find obsidian-directory)))

;; Obsidian サブメニュー
(defhydra hydra-obsidian (:color blue :hint nil)
  "
  === OBSIDIAN VAULT (M-o o) ===
  [ファイル操作]                         [検索]
  [f] ファイルを開く                   [s] Vault内全文検索 (rg)
  [n] 新規ノート作成                   [r] ローマ字全文検索 (Migemo rg)
  [i] リンクを挿入                     [F] ファイル名検索 (Migemo)
  [c] リンク先ファイルを作成
  ----------------------------------------------------------------------
  [p] メインメニューに戻る            [q] 閉じる
"
  ;; obsidian-find-file は現行の obsidian.el では非対話的な内部関数になっており、
  ;; ファイルジャンプ用の対話コマンドは obsidian-jump に置き換わっている
  ("f" (progn (require 'obsidian) (call-interactively #'obsidian-jump)))
  ("n" (progn (require 'obsidian) (call-interactively #'obsidian-capture)))
  ("i" (progn (require 'obsidian) (call-interactively #'obsidian-insert-link)))
  ("c" (progn (require 'obsidian) (call-interactively #'obsidian-create-missing-file)))
  ("s" (progn (require 'obsidian) (consult-ripgrep obsidian-directory)))
  ("r" my/obsidian-ripgrep-migemo)
  ("F" my/obsidian-find-file-migemo)
  ("p" hydra-launcher/body :color blue)
  ("q" nil :color blue))

;; Markdown サブメニュー（hydra-launcher より先に定義する）
;; ※ markdown-mode は :defer ロードのため、キーを押した瞬間に require して確実に関数を解決する
(defhydra hydra-markdown (:color blue :hint nil)
  "
  === MARKDOWN & TAGS (M-o m) ===
  [装飾・タグ打ち]                       [ナビゲーション・リンク]
  [1] 見出し1 (H1)                     [l] リンク挿入 (Obsidian風)
  [2] 見出し2 (H2)                     [i] 画像リンクの挿入
  [b] 太字 (Bold)                      [t] 目次 (TOC) の生成/更新
  [k] 斜体 (Italic)                    [o] 見出し検索ジャンプ (consult-outline)
  [c] コードブロック (Code)            [O] サイドバー開閉 (imenu-list)
  ----------------------------------------------------------------------
  [p] メインメニューに戻る            [q] 閉じる
"
  ("1" (progn (require 'markdown-mode) (call-interactively #'markdown-insert-header-1)))
  ("2" (progn (require 'markdown-mode) (call-interactively #'markdown-insert-header-2)))
  ("b" (progn (require 'markdown-mode) (call-interactively #'markdown-insert-bold)))
  ("k" (progn (require 'markdown-mode) (call-interactively #'markdown-insert-italic)))
  ("c" (progn (require 'markdown-mode) (call-interactively #'markdown-insert-gfm-code-block)))
  ("l" (progn (require 'markdown-mode) (call-interactively #'markdown-insert-link)))
  ("i" (progn (require 'markdown-mode) (call-interactively #'markdown-insert-image)))
  ("t" (progn (require 'markdown-toc)  (call-interactively #'markdown-toc-generate-or-update)))
  ("o" consult-outline)
  ("O" imenu-list-smart-toggle)
  ("p" hydra-launcher/body :color blue)
  ("q" nil :color blue))

;; Calc サブメニュー（hydra-launcher より先に定義する）
(defhydra hydra-calc (:color blue :hint nil)
  "
  === CALC 電卓 (M-o C) ===
  [起動]                                  [入力モード]
  [c] Calc を開く                       [a] 代数モード ON  (普通の記法)
  [m] Casual メニュー [電卓内: C-o]     [r] RPN モード ON  (スタック式)
  ----------------------------------------------------------------------
  [0] スタック全消去 (AC)  [直キー: C-u 0 DEL]
  ----------------------------------------------------------------------
  ※ 全設定の初期化（フルリセット）は [C-x * 0] です。
  ----------------------------------------------------------------------
  [p] メインメニューに戻る            [q] 閉じる
"
  ("c" calc)
  ("m" (progn (calc) (casual-calc-tmenu)))
  ("a" (progn (calc)
              (unless calc-algebraic-mode
                (calc-algebraic-mode nil))
              (message "代数モード（中置記法）に切り替えました")))
  ("r" (progn (calc)
              (when calc-algebraic-mode
                (calc-algebraic-mode nil))
              (message "RPN モード（スタック式）に切り替えました")))
  ("0" (progn (calc)
              (calc-pop-stack (calc-stack-size))))
  ("p" hydra-launcher/body :color blue)
  ("q" nil :color blue))

;; テキスト変換 サブメニュー（hydra-launcher より先に定義する）
(defhydra hydra-text (:color blue :hint nil)
  "
  === テキスト変換 (M-o T) ===
  [並べ替え・重複]                         [ナローイング]
  [s] 行を昇順ソート         [S] 行を降順ソート   [n] 選択範囲に限定 (Narrow)
  [u] 重複行を削除 (uniq)                           [w] 限定を解除 (Widen)
  ----------------------------------------------------------------------
  [文字種変換（選択範囲）]
  [z] 半角 → 全角            [Z] 全角 → 半角
  ----------------------------------------------------------------------
  [b] メインメニューに戻る   [q] 閉じる
"
  ("s" (progn (when (use-region-p) (sort-lines nil (region-beginning) (region-end)))))
  ("S" (progn (when (use-region-p) (sort-lines t   (region-beginning) (region-end)))))
  ("u" (progn (when (use-region-p) (delete-duplicate-lines (region-beginning) (region-end)))))
  ("z" (progn (when (use-region-p) (japanese-hankaku-region (region-beginning) (region-end) t))))
  ("Z" (progn (when (use-region-p) (japanese-zenkaku-region (region-beginning) (region-end)))))
  ("n" my/fancy-narrow-to-region)
  ("w" my/fancy-widen)
  ("b" hydra-launcher/body :color blue)
  ("q" nil :color blue))

;; カラーマーカー サブメニュー（hydra-launcher より先に定義する）
(defhydra hydra-marker (:color blue :hint nil)
  "
  === カラーマーカー (M-o M) ===
  [マーカー操作]                         [ジャンプ]
  [m] マーカーをトグル（付ける/外す） [n] 次のマーカーへ
  [k] マーカーを1つ削除                [p] 前のマーカーへ
  [u] 全マーカーを削除                [d] 定義箇所へジャンプ
  [c] Casual メニュー（マーカー上で）
  ----------------------------------------------------------------------
  [b] メインメニューに戻る            [q] 閉じる
"
  ("m" my/marker-put)
  ("k" my/marker-remove-at-point)
  ("u" my/marker-remove-all)
  ("c" casual-symbol-overlay-tmenu)
  ("n" symbol-overlay-jump-next)
  ("p" symbol-overlay-jump-prev)
  ("d" symbol-overlay-jump-to-definition)
  ("b" hydra-launcher/body :color blue)
  ("q" nil :color blue))

;; プロジェクト操作 サブメニュー（hydra-launcher より先に定義する）
(defhydra hydra-project (:color blue :hint nil)
  "
  === PROJECT NAVIGATOR (M-o p / C-c C-p) ===
  [検索・移動]                                      [プロジェクト操作]
  [f] ファイル検索 (consult-fd)                     [p] 別プロジェクト切替 (project-switch-project)
  [s] 全文検索 (consult-ripgrep)                    [d] ルートフォルダ (project-dired)
  [g] ローマ字ファイル検索 (consult-fd-migemo)      [b] バッファ切替 (project-switch-to-buffer)
  [z] Zoxide移動 (zoxide-find-file)                 [k] 全バッファ閉じる (project-kill-buffers)
  [e] Everything (consult-locate)                   [r] 最近使ったファイル (consult-recent-file)
  ------------------------------------------------------------------------------------------
  【裏技】フォルダ内に空の「.project」を置くだけで Git不要でルート認識されます！
  ------------------------------------------------------------------------------------------
  [m] メインランチャーに戻る (hydra-launcher)       [q] 閉じる
"
  ("f" my/consult-fd-project)
  ("s" my/consult-ripgrep-project)
  ("g" my/consult-fd-migemo)
  ("z" zoxide-find-file)
  ("e" consult-locate)
  ("p" project-switch-project)
  ("d" project-dired)
  ("b" project-switch-to-buffer)
  ("r" consult-recent-file)
  ("k" project-kill-buffers)
  ("m" hydra-launcher/body :color blue)
  ("q" nil :color blue))

;; メインランチャーメニュー
(defhydra hydra-launcher (:color blue :hint nil)
  "
  === EMACS NAVIGATOR (M-o) ===
  [検索・移動]                                      [各種メニュー・ツール]
  [e] Everything (consult-locate)                   [p] プロジェクトメニュー (hydra-project)
  [s] プロジェクト内検索 (consult-ripgrep)          [m] Markdown メニュー (hydra-markdown)
  [g] プロジェクトファイル検索 (consult-fd)         [o] Obsidian メニュー (hydra-obsidian)
  [f] 最近使ったファイル (consult-recent-file)      [w] ウィンドウ操作 (hydra-window)
  [r] ローマ字検索 (consult-line-migemo)            [F] ファイル操作 (hydra-file)
  [O] 一括編集 (moccur)                             [S] Consult 探索メニュー (hydra-consult)
  [n] 新しいウィンドウ (make-frame)                 [d] 辞書 (lookup)
  [c] cmd.exe (conpty)                              [P] PowerShell (conpty-powershell)
  [E] EPUBリーダー (nov.el)                         [C] 電卓メニュー (calc)
  [T] テキスト変換 (hydra-text)                     [W] 週間天気予報 (my/weather)
  [H] howmメモ (my/howm-toggle)                     [A] AI & Antigravity (hydra-ai)
  ------------------------------------------------------------------------------------------
  [?] Meow 操作ガイド                               [q] 閉じる
"
  ("e" consult-locate)
  ("s" my/consult-ripgrep-project)
  ("S" (if (fboundp 'hydra-consult/body) (hydra-consult/body)))
  ("g" my/consult-fd-project)
  ("G" my/consult-fd-here)
  ("p" hydra-project/body)
  ("f" consult-recent-file)
  ("b" consult-bookmark)
  ("r" my/consult-line-migemo)
  ("n" make-frame)
  ("E" my/nov-open-epub)
  ("m" hydra-markdown/body)
  ("o" hydra-obsidian/body)
  ("w" hydra-window/body)
  ("F" hydra-file/body)
  ("A" hydra-ai/body)
  ("a" hydra-ai/body)
  ("M" hydra-marker/body)
  ("c" conpty)
  ("P" conpty-powershell)
  ("L" my/open-calendar)
  ("W" my/weather)
  ("H" my/howm-toggle)
  ("C" hydra-calc/body)
  ("T" hydra-text/body)
  ("d" lookup)
  ("O" moccur)
  ("?" (if (fboundp 'hydra-meow-help/body) (hydra-meow-help/body) (message "Meow は未ロードです")))
  ("q" nil :color blue))

;; --- Hydra をメニューバーに統合 ---
(with-eval-after-load 'hydra
  (let ((menu-map (make-sparse-keymap "Navigator")))
    ;; Navigator メニュー内の項目
    (define-key menu-map [hydra-everything] '(menu-item "Everything PC内検索" consult-locate :keys "M-o e"))
    (define-key menu-map [hydra-project]    '(menu-item "プロジェクトメニュー" hydra-project/body :keys "M-o p / C-c C-p"))
    (define-key menu-map [hydra-fd-project] '(menu-item "ファイル名検索 fd" my/consult-fd-project :keys "M-o g"))
    (define-key menu-map [hydra-fd-here]    '(menu-item "ファイル名検索 fd ここから" my/consult-fd-here :keys "M-o G"))
    (define-key menu-map [separator-1]      '(menu-item "--"))
    (define-key menu-map [hydra-epub]       '(menu-item "EPUB リーダー" my/nov-open-epub :keys "M-o E"))
    (define-key menu-map [hydra-new-frame]  '(menu-item "新しいウィンドウを開く" make-frame :keys "M-o n"))
    (define-key menu-map [separator-2]      '(menu-item "--"))
    (define-key menu-map [hydra-meow-guide] '(menu-item "Meow 操作ガイド" (lambda () (interactive) (if (fboundp 'hydra-meow-help/body) (hydra-meow-help/body) (message "Meow は未ロードです"))) :keys "M-o ?"))
    (define-key menu-map [hydra-marker]     '(menu-item "カラーマーカー" hydra-marker/body :keys "M-o M"))
    (define-key menu-map [hydra-calc]       '(menu-item "電卓" hydra-calc/body :keys "M-o C"))
    (define-key menu-map [hydra-calendar]   '(menu-item "カレンダー" my/open-calendar :keys "M-o L"))
    (define-key menu-map [hydra-howm]       '(menu-item "howm メモ環境 (ON/OFF)" my/howm-toggle :keys "F8 / M-o H"))
    (define-key menu-map [hydra-file]       '(menu-item "ファイル操作" hydra-file/body :keys "M-o F"))
    (define-key menu-map [hydra-window]     '(menu-item "ウィンドウ操作" hydra-window/body :keys "M-o w"))
    (define-key menu-map [separator-2b]     '(menu-item "--"))
    (define-key menu-map [hydra-conpty-cmd] '(menu-item "cmd.exe (conpty)" conpty :keys "M-o c"))
    (define-key menu-map [hydra-conpty-ps]  '(menu-item "PowerShell (conpty)" conpty-powershell :keys "M-o P"))
    (define-key menu-map [separator-3]      '(menu-item "--"))
    (define-key menu-map [hydra-obsidian]   '(menu-item "Obsidian メニュー" hydra-obsidian/body :keys "M-o o"))
    (define-key menu-map [hydra-markdown]   '(menu-item "Markdown メニュー" hydra-markdown/body :keys "M-o m"))
    (define-key menu-map [hydra-moccur]     '(menu-item "moccur 一括編集" moccur :keys "M-o O"))
    (define-key menu-map [separator-4]      '(menu-item "--"))
    (define-key menu-map [hydra-main]       '(menu-item "メインランチャーを開く" hydra-launcher/body :keys "M-o"))

    ;; メニューバーの末尾（Help の右）に Fn_key と Navigator を追加
    (let ((fn-map (make-sparse-keymap "Fn_key")))
      (define-key fn-map [fn-f9]   '(menu-item "F9: メール開閉 (auximap)" auximap-toggle :keys "F9"))
      (define-key fn-map [fn-s-f8] '(menu-item "S-F8: 週間天気予報" my/weather :keys "S-F8"))
      (define-key fn-map [fn-f8]   '(menu-item "F8: カレンダー (howm予定連携)" my/open-calendar :keys "F8"))
      (define-key fn-map [fn-s-f7] '(menu-item "S-F7: howm メモ全文検索" my/howm-ripgrep :keys "S-F7"))
      (define-key fn-map [fn-f7]   '(menu-item "F7: howm メモ環境 (ON/OFF)" my/howm-toggle :keys "F7"))
      (define-key fn-map [fn-sep3] '(menu-item "--"))
      (define-key fn-map [fn-f6]   '(menu-item "F6: 電卓 (Calc)" calc :keys "F6"))
      (define-key fn-map [fn-f5]   '(menu-item "F5: バッファ再読み込み (更新確認)" my/revert-buffer-with-confirm :keys "F5"))
      (define-key fn-map [fn-f4]   '(menu-item "F4: 目次サイドバー開閉 (imenu-list)" imenu-list-smart-toggle :keys "F4"))
      (define-key fn-map [fn-sep2] '(menu-item "--"))
      (define-key fn-map [fn-s-f3] '(menu-item "S-F3: 検索開始 / 前を検索" my/isearch-backward-or-repeat :keys "S-F3"))
      (define-key fn-map [fn-f3]   '(menu-item "F3: 検索開始 / 次を検索" my/isearch-forward-or-repeat :keys "F3"))
      (define-key fn-map [fn-f2]   '(menu-item "F2: バッファ切り替え (consult-buffer)" consult-buffer :keys "F2"))
      (define-key fn-map [fn-sep1] '(menu-item "--"))
      (define-key fn-map [fn-s-f1] '(menu-item "S-F1: Emacs 標準ヘルプ" help-command :keys "S-F1"))
      (define-key fn-map [fn-f1]   '(menu-item "F1: スマート操作ガイド" my/smart-help :keys "F1"))
      (define-key global-map [menu-bar fn-keys] (cons "Fn_key" fn-map)))

    (define-key global-map [menu-bar navigator] (cons "Navigator" menu-map))
    ;; File を左端にし、既存の Help の右隣に Fn_key -> Navigator と並べる
    (setq menu-bar-final-items '(help-menu fn-keys navigator))))

;; --- consult ---
(use-package consult
  :bind (("C-f"   . my/consult-line-migemo)
         ("M-y"   . consult-yank-pop)
         ("C-r"   . consult-outline)
         ("C-S-f" . my-consult-ripgrep-with-help)
         ("C-S-g" . my/consult-fd-project)
         ("C-S-h" . my/consult-fd-here)
         ("C-c e" . consult-locate)
         ("<f2>"  . consult-buffer)
         ("<f8>"  . my/open-calendar)
         ("C-x r b" . consult-bookmark)
         ("M-g m" . consult-mark)
         ("M-g M" . consult-global-mark)
         ("M-o"   . hydra-launcher/body))
  :config
  ;; my/cua-cut-or-prefix 経由では ctl-x-map が正しく引けるが、
  ;; 念のため直接バインドして確実に動作させる
  (define-key ctl-x-map "b" #'consult-buffer)
  (define-key ctl-x-map "k" #'kill-buffer)
  (define-key ctl-x-r-map "b" #'consult-bookmark)

  (setq consult-async-split-style 'perl) ; # 区切りで AND 検索（例: -F ミネルヴィニ#株）
  (setq consult-ripgrep-args
        (concat "rg --null --line-buffered --color=never --max-columns=1000 "
                "--path-separator / --smart-case --no-heading "
                "--with-filename --line-number --search-zip "
                "--encoding auto"))
  ;; ripgrep の出力は UTF-8 のため、日本語パスが文字化けしないようにする
  (defun my/consult-ripgrep-utf8 (orig &rest args)
    (let ((coding-system-for-read 'utf-8)
          (coding-system-for-write 'utf-8))
      (apply orig args)))
  (advice-add 'consult-ripgrep :around #'my/consult-ripgrep-utf8)

  (defun my/consult-migemo-regexp (component)
    "COMPONENT を consult 用の Emacs 正規表現に変換する。"
    (condition-case nil
        (if (and (featurep 'migemo)
                 (fboundp 'migemo-get-pattern)
                 (string-match-p "\\`[[:ascii:]]+\\'" component))
            (migemo-get-pattern component)
          (regexp-quote component))
      (error (regexp-quote component))))

  (defun my/consult-migemo-compiler (input type ignore-case)
    "consult 用に Migemo と固定文字列検索を両立する compiler。"
    (let* ((components (consult--split-escaped input))
           (emacs-regexps
            (mapcar #'my/consult-migemo-regexp components))
           (rg-regexps
            (mapcar (lambda (regexp)
                      (consult--convert-regexp regexp type))
                    emacs-regexps)))
      (cons rg-regexps
            (when-let* ((regexps (seq-filter #'consult--valid-regexp-p
                                             emacs-regexps)))
              (apply-partially #'consult--highlight-regexps
                               regexps ignore-case)))))

  (defun my-consult-ripgrep-with-help ()
    "打ち方ヒント付きで consult-ripgrep を起動します。
日本語直接入力は rg の標準検索として扱います。"
    (interactive)
    (let ((consult-async-indicator nil)
          (consult-ripgrep-args
           (concat consult-ripgrep-args " --engine=default")))
      (consult-ripgrep)))

  ;; C-S-f 検索後、結果バッファで wgrep のヒントをミニバッファに表示
  (defun my/wgrep-hint (&rest _)
    "consult-ripgrep 実行後に wgrep の操作ヒントを表示する。"
    (run-with-idle-timer
     0.3 nil
     (lambda ()
       (message "wgrep: C-c C-e で編集モード → C-c C-c で一括保存 / C-c C-k でキャンセル"))))
  (advice-add 'my-consult-ripgrep-with-help :after #'my/wgrep-hint)

  (defun my/consult-fd-project ()
    "現在の project.el ルートを対象に consult-fd を実行します。"
    (interactive)
    (if-let* ((project (project-current)))
        (consult-fd (project-root project))
      (call-interactively #'consult-fd)))

  (defun my/consult-fd-here ()
    "現在開いているファイルと同じディレクトリを起点に consult-fd を実行します。
バッファがファイルに紐付いていない場合は default-directory を使います。"
    (interactive)
    (let ((dir (if buffer-file-name
                   (file-name-directory buffer-file-name)
                 default-directory)))
      (consult-fd dir)))

  (defun my/consult-fd-migemo ()
    "Migemo（ローマ字）を使って高速にファイル名検索 (consult-fd) を行います。"
    (interactive)
    (let ((orderless-matching-styles '(orderless-migemo)))
      (consult-fd))))

(use-package embark
  :bind (("C-." . embark-act))
  :config
  (define-key embark-file-map (kbd "e") #'my/open-any-file-in-windows)
  (define-key embark-file-map (kbd "E") #'my/open-any-file-in-windows))
(use-package embark-consult)
(use-package wgrep)

;; =====================================================================
;; EmEditor フィルタ / wgrep わかりやすいラッパー
;; =====================================================================

(defun my/emeditor-filter (&optional engine)
  "EmEditor の〈フィルタ〉機能風：マッチ行だけを表示して直接編集できます。
引数 ENGINE が 'moccur または 'occur の場合はそのエンジンを使用し、
指定がない場合はダイアログや completing-read で選択します。

【手順】
  1. 検索ワードを入力（選択中の文字列・カーソル下の単語が自動入力）
  2. マッチした行だけがフィルタバッファに表示される
  3. フィルタバッファ上で直接テキストを書き換えられる
  4. C-c C-c : 変更を元ファイルに一括反映して保存
  5. q       : フィルタを閉じる（未保存の変更は破棄される）"
  (interactive)
  (let* ((default (if (use-region-p)
                      (buffer-substring-no-properties (region-beginning) (region-end))
                    (thing-at-point 'symbol t)))
         (pattern (read-regexp
                   (format "フィルタ（表示する行 of パターン）%s: "
                           (if default (format " [%s]" default) ""))
                   default))
         ;; color-moccur と moccur-edit がインストールされているかチェック
         (has-moccur (and (locate-library "color-moccur")
                          (locate-library "moccur-edit"))))
    (when (and pattern (not (string-empty-p pattern)))
      (let ((choice
             (cond
              ;; 引数で指定されている場合
              ((eq engine 'moccur) "moccur-edit")
              ((eq engine 'occur) "occur-edit")
              ;; 両方使える場合はメニューを出す
              (has-moccur
               (completing-read "使用する検索・編集エンジン: "
                                '("moccur-edit (Migemo対応)" "occur-edit (標準)")
                                nil t nil nil "moccur-edit (Migemo対応)"))
              ;; occur-edit のみ（標準）
              (t "occur-edit"))))
        (if (string-match-p "moccur-edit" choice)
            ;; moccur-edit を起動
            (progn
              (require 'color-moccur)
              (require 'moccur-edit)
              (moccur pattern)
              (when-let* ((moccur-buf (get-buffer "*Moccur*")))
                (pop-to-buffer moccur-buf)
                (moccur-edit-mode-in)
                (message "moccur-edit でフィルタ中: C-c C-c で保存")))
          ;; 標準の occur-edit を起動
          (progn
            (require 'replace) ;; occur/occur-edit 用
            (occur pattern)
            (when-let* ((occur-buf (get-buffer "*Occur*")))
              (pop-to-buffer occur-buf)
              (occur-edit-mode)
              (message "occur-edit でフィルタ中: C-c C-c で保存"))))))))

(defun my/wgrep-replace ()
  "EmEditor の〈複数ファイル置換〉風：ripgrep 検索 → 結果を直接編集 → 一括保存。

【手順】
  1. 検索ワードを入力（プロジェクトルート全体が対象）
  2. 検索結果バッファが開く（ファイル名・行番号・内容が一覧表示）
  3. C-c C-p : 編集モードに入る（行を直接書き換えられるようになる）
  4. 検索ワードを置換ワードに書き換える（C-M-% などの通常の置換操作も可）
  5. C-c C-c : 変更を全ファイルに一括保存
  6. C-c C-k : 変更をキャンセル"
  (interactive)
  (message "ripgrep 検索後、C-c C-p で編集モード → C-c C-c で一括保存")
  (call-interactively #'consult-ripgrep))

;; キーバインドの割り当て
(add-hook 'after-init-hook
          (lambda ()
            (global-set-key (kbd "C-c f") #'my/emeditor-filter)
            (global-set-key (kbd "C-c F") #'my/wgrep-replace)))

;; occur-edit-mode のキーをわかりやすく設定
(with-eval-after-load 'replace
  ;; query-replace / replace-string で読み取り専用テキストをスキップして置換できるようにする
  (setq query-replace-skip-read-only t)

  ;; ESC で occur-edit-mode を抜けて read-only の occur-mode に戻る
  ;; （read-only 状態では q が通常通り quit-window として機能する）
  (define-key occur-edit-mode-map (kbd "<escape>")
    (lambda ()
      (interactive)
      (occur-mode)))  ; 編集モードを解除して read-only に戻る

  ;; 保存のヒントをヘッダーに表示するフック
  (add-hook 'occur-edit-mode-hook
            (lambda ()
              (setq header-line-format
                    (propertize
                     "  [フィルタ編集中]  |  C-c C-c: 変更を保存  |  ESC: 編集終了(→qで閉じる)"
                     'face '(:background "#1a3a5c" :foreground "#aed6f1" :weight bold)))))

  ;; 読み取り専用の occur-mode に戻ったときのヘッダー表示フック
  (add-hook 'occur-mode-hook
            (lambda ()
              (setq header-line-format
                    (propertize
                     "  [フィルタ表示中]  |  e: 編集モードに入る  |  q: 閉じる"
                     'face '(:background "#1a3a5c" :foreground "#aed6f1" :weight bold))))))

;; wgrep の編集モード開始時にヘッダーを表示
(with-eval-after-load 'wgrep
  (add-hook 'wgrep-setup-hook
            (lambda ()
              (setq header-line-format
                    (propertize
                     "  [wgrep 編集中]  |  C-c C-c: 変更を全ファイルに保存  |  C-c C-k: キャンセル"
                     'face '(:background "#3a1a1a" :foreground "#f4b8b8" :weight bold))))))

;; --- consult の外部コマンドパス設定（fd / es.exe）---
;; consult-fd・consult-locate ともに consult 本体に含まれるため別途インストール不要
;; use-package :config より確実に適用するため with-eval-after-load で設定する
(with-eval-after-load 'consult
  ;; fd のパスを自動検出: 1) PATH 2) ポータブル bin/ 3) 見つからなければお知らせ
  (let ((fd-exe (or (executable-find "fd")
                    (executable-find "fd.exe")
                    (let ((portable (expand-file-name "bin/fd.exe"
                                                      (expand-file-name ".." user-emacs-directory))))
                      (and (file-exists-p portable) portable)))))
    (if fd-exe
        (setq consult-fd-args (list fd-exe "--color=never" "--full-path"))
      (message "【お知らせ】fd が見つかりません。fd-find をインストールするか portable/bin/ に置いてください。")))

  ;; es.exe のパスを自動検出
  ;; 優先順位: 1) PATH 2) ポータブル bin/ 3) 定番インストール先
  (let ((es-exe (or (executable-find "es.exe")
                    (executable-find "es")
                    (let ((portable (expand-file-name "bin/es.exe"
                                                      (expand-file-name ".." user-emacs-directory))))
                      (and (file-exists-p portable) portable))
                    (cl-find-if #'file-exists-p
                                (list (expand-file-name "Everything/es.exe" (or (getenv "ProgramFiles") "C:/Program Files"))
                                      (expand-file-name "Everything/es.exe" (or (getenv "ProgramFiles(x86)") "C:/Program Files (x86)"))
                                      "C:/tools/Everything/es.exe")))))
    (if es-exe
        (setq consult-locate-args (list (replace-regexp-in-string "\\\\" "/" es-exe) "-i" "-p" "-r"))
      (message "【お知らせ】es.exe が見つかりません。Everything をインストールするか portable/bin/ に置いてください。"))))

;; =====================================================================
;; Consult 探索メニュー (専用ランチャー)
;; =====================================================================
(defhydra hydra-consult (:color blue :hint nil)
  "
  === Consult 探索メニュー ===
  [バッファ・ファイル]                          [テキスト・コード検索]
  [b] 全バッファ・履歴 (consult-buffer)          [l] 行検索 (consult-line)
  [f] 最近開いたファイル (consult-recent-file)  [s] 全文検索 (consult-ripgrep)
  [g] ファイル名検索 (consult-fd)               [w] 単語全文検索 (my/consult-ripgrep-word)
  [e] PC全体検索 (consult-locate)               [o] 見出し一覧 (consult-outline)
                                                [i] 関数/クラス一覧 (consult-imenu)
  [足跡・ピン留め・履歴]                        [その他・便利ツール]
  [m] このファイルの足跡 (consult-mark)         [t] テーマ試着 (consult-theme)
  [M] 全ファイルの足跡 (consult-global-mark)    [r] レジスタ一覧 (consult-register)
  ['] 現在地にピン留め (my/quick-pin-set)       [F1] 全体ガイドへ
  [c] ピン全消去 (my/quick-pin-clear)
  [B] ブックマーク一覧 (consult-bookmark)
  [y] コピー履歴から貼付 (consult-yank-pop)
  --------------------------------------------------------------------------------------
  [q / ESC] 閉じる
"
  ("b" consult-buffer)
  ("f" consult-recent-file)
  ("g" my/consult-fd-project)
  ("G" my/consult-fd-here)
  ("e" consult-locate)
  ("l" my/consult-line-migemo)
  ("s" my-consult-ripgrep-with-help)
  ("w" my/consult-ripgrep-word)
  ("o" consult-outline)
  ("i" consult-imenu)
  ("m" consult-mark)
  ("M" consult-global-mark)
  ("'" my/quick-pin-set)
  ("c" my/quick-pin-clear)
  ("B" consult-bookmark)
  ("y" consult-yank-pop)
  ("t" consult-theme)
  ("r" consult-register)
  ("<f1>" my/smart-help)
  ("q" nil :color blue)
  ("<escape>" nil :color blue))

;; グローバルキー (どのモードからでも起動可能)
(global-set-key (kbd "M-s")   #'hydra-consult/body)
(global-set-key (kbd "C-c s") #'hydra-consult/body)



;; --- YouTube検索 (consult + yt-dlp) ---
;; yt-dlp の ytsearchN: 擬似URLを利用し、consult でインクリメンタル検索する。
;; 選択した動画はブラウザで開く。
;; marginalia で再生時間・投稿者を表示し、候補移動に合わせてサムネイルを
;; サイドウィンドウにプレビュー表示する（vertico 前提）。
(defvar my/youtube-search-history nil)
(defvar my/youtube--thumbnail-buffer-name "*youtube-thumbnail*")
(defvar my/youtube--thumbnail-cache (make-hash-table :test 'equal)
  "サムネイル画像URLから image オブジェクトへのキャッシュ。値が'pendingの間は取得中。")

(defvar my/youtube--yt-dlp-exe
  ;; fd.exe / es.exe と同じ探索順: 1) PATH 2) ポータブル bin/
  (or (executable-find "yt-dlp")
      (executable-find "yt-dlp.exe")
      (let ((portable (expand-file-name "bin/yt-dlp.exe"
                                        (expand-file-name ".." user-emacs-directory))))
        (and (file-exists-p portable) portable)))
  "yt-dlp実行ファイルへのパス。見つからない場合はnil。")

(unless my/youtube--yt-dlp-exe
  (message "【お知らせ】yt-dlp が見つかりません。PATH に通すか portable/bin/ に yt-dlp.exe を置いてください。"))

(defun my/youtube--format-duration (seconds)
  "SECONDS を \"h:mm:ss\" または \"m:ss\" 形式の文字列にする。"
  (if (not (numberp seconds))
      "?:??"
    (let* ((seconds (truncate seconds))
           (h (/ seconds 3600))
           (m (/ (mod seconds 3600) 60))
           (s (mod seconds 60)))
      (if (> h 0)
          (format "%d:%02d:%02d" h m s)
        (format "%d:%02d" m s)))))

(defvar my/youtube-search-count 100
  "YouTube検索で取得する候補の件数。")

(defun my/youtube-search--builder (input)
  "yt-dlp検索コマンドを組み立てる。"
  (when my/youtube--yt-dlp-exe
    (let ((n (number-to-string my/youtube-search-count)))
      `(,my/youtube--yt-dlp-exe "--flat-playlist" "-j" "--playlist-end" ,n
        ,(concat "ytsearch" n ":" input)))))

(defun my/youtube-search--transform-line (line)
  "yt-dlpのJSON1行をタイトル文字列に変換し、各種情報をプロパティに埋め込む。
失敗した行はnilを返す（consult--async-filterで除外される）。"
  (condition-case nil
      (let* ((data (json-parse-string line :object-type 'alist))
             (title (alist-get 'title data))
             (id (alist-get 'id data))
             (duration (alist-get 'duration data))
             (uploader (or (alist-get 'uploader data)
                           (alist-get 'channel data)
                           "")))
        (propertize
         title
         'youtube-url (format "https://www.youtube.com/watch?v=%s" id)
         ;; 動画IDから直接サムネイルURLを組み立てる（常に取得できる）
         'youtube-thumbnail (format "https://i.ytimg.com/vi/%s/hqdefault.jpg" id)
         'youtube-duration (my/youtube--format-duration duration)
         'youtube-uploader uploader))
    (error nil)))

(defun my/youtube--fetch-thumbnail (url callback)
  "URL のサムネイル画像を非同期取得し、取得できたら CALLBACK に image を渡す。
キャッシュ済みなら即座に CALLBACK を呼ぶ。"
  (let ((cached (gethash url my/youtube--thumbnail-cache)))
    (cond
     ((and cached (not (eq cached 'pending))) (funcall callback cached))
     (cached nil)  ; 取得中なら何もしない
     (t
      (puthash url 'pending my/youtube--thumbnail-cache)
      (url-retrieve
       url
       (lambda (status)
         (goto-char (point-min))
         (when (search-forward "\n\n" nil t)
           (let ((data (buffer-substring (point) (point-max))))
             (condition-case nil
                 (let ((image (create-image data nil t :max-width 320 :max-height 180)))
                   (puthash url image my/youtube--thumbnail-cache)
                   (funcall callback image))
               (error (remhash url my/youtube--thumbnail-cache)))))
         (kill-buffer (current-buffer)))
       nil t)))))

(defun my/youtube--show-thumbnail (image)
  "IMAGE をサムネイル用サイドウィンドウに表示する。"
  (let ((buf (get-buffer-create my/youtube--thumbnail-buffer-name)))
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert-image image)))
    (unless (get-buffer-window buf)
      (display-buffer
       buf
       '(display-buffer-in-side-window (side . right) (window-width . 36))))))

(defun my/youtube--update-thumbnail-preview ()
  "vertico の現在の候補に応じてサムネイルプレビューを更新する。"
  (when (fboundp 'vertico--candidate)
    (when-let* ((cand (ignore-errors (vertico--candidate)))
                (url (get-text-property 0 'youtube-thumbnail cand)))
      (my/youtube--fetch-thumbnail url #'my/youtube--show-thumbnail))))

(defun my/youtube--minibuffer-setup ()
  "サムネイルプレビュー用フックをこのミニバッファ内だけで有効にする。"
  (add-hook 'post-command-hook #'my/youtube--update-thumbnail-preview nil t))

(with-eval-after-load 'marginalia
  (defun my/youtube--marginalia-annotate (cand)
    "候補 CAND の右側に再生時間と投稿者を表示する。"
    (let ((duration (get-text-property 0 'youtube-duration cand))
          (uploader (get-text-property 0 'youtube-uploader cand)))
      (marginalia--fields
       (uploader :truncate 0.4 :face 'marginalia-type)
       (duration :face 'marginalia-size))))
  ;; marginalia 2.x で marginalia-annotator-registry は marginalia-annotators に
  ;; 改名され、旧名の互換エイリアスも廃止されたため、存在する方を使う。
  (add-to-list (if (boundp 'marginalia-annotators)
                    'marginalia-annotators
                  'marginalia-annotator-registry)
               '(youtube-video my/youtube--marginalia-annotate builtin none)))

(defun my/consult-youtube ()
  "YouTubeをインクリメンタル検索する。
再生時間・投稿者を候補一覧に、サムネイルをサイドウィンドウに表示する。
選択した動画はブラウザで開く。"
  (interactive)
  (unless my/youtube--yt-dlp-exe
    (user-error "yt-dlp が見つかりません。PATH に通すか portable/bin/ に yt-dlp.exe を置いてください"))
  (let* ((source
          (consult--async-pipeline
           (consult--process-collection #'my/youtube-search--builder
                                         :min-input 2)
           (consult--async-map #'my/youtube-search--transform-line)
           (consult--async-filter #'identity)))
         (selected
          (unwind-protect
              (progn
                (add-hook 'minibuffer-setup-hook #'my/youtube--minibuffer-setup)
                (consult--read
                 source
                 :prompt "YouTube検索: "
                 :sort nil
                 :require-match t
                 :history 'my/youtube-search-history
                 :lookup #'consult--lookup-member
                 :category 'youtube-video))
            (remove-hook 'minibuffer-setup-hook #'my/youtube--minibuffer-setup)
            (when-let* ((buf (get-buffer my/youtube--thumbnail-buffer-name)))
              (delete-windows-on buf)
              (kill-buffer buf)))))
    (if-let* ((url (get-text-property 0 'youtube-url selected)))
        (let ((chrome-path
               (cl-find-if #'file-exists-p
                           '("C:/Program Files/Google/Chrome/Application/chrome.exe"
                             "C:/Program Files (x86)/Google/Chrome/Application/chrome.exe"))))
          (if chrome-path
              (start-process "youtube-app" nil chrome-path (format "--app=%s" url))
            (browse-url url)))
      (message "選択した候補からURLを取得できませんでした: %S" selected))))

(defalias 'consult-youtube #'my/consult-youtube)

;; --- project.el と fd の連携 ---
(with-eval-after-load 'project
  (defun my/project-files-in-directory (dir)
    "DIR 内のファイルを `fd` を使って高速に取得します。"
    (let* ((fd-exe (or (executable-find "fd")
                       (executable-find "fd.exe")
                       (let ((portable (expand-file-name "bin/fd.exe"
                                                         (expand-file-name ".." user-emacs-directory))))
                         (and (file-exists-p portable) portable))
                       "fd"))           ; フォールバック（エラーメッセージが出る）
           (default-directory dir))
      (process-lines fd-exe "--type" "f" "--strip-cwd-prefix" "--hidden" "--follow" "--exclude" ".git")))

  (defun my/project-files (project)
    "project-files の挙動を `fd` に置き換えます。"
    (my/project-files-in-directory (project-root project)))

  (advice-add 'project-files :override #'my/project-files))



;; modus-themes（gnome2テーマ等の依存対策）
(use-package modus-themes)

;; 右クリックメニューを永続化
(context-menu-mode 1)

;; =====================================================================
;; 11b. IME 連携（tr-ime）
;; ─ Windows IME をEmacsと統合する
;; ─ モードライン表示・ミニバッファ自動OFF・カーソル色変更
;; =====================================================================

(defvar my/use-mozc-modeless t
  "Non-nil なら Windows IME/tr-ime ではなく mozc-modeless を使う。")

;; 背景色の明暗を判定して IME/mozc ON 時のカーソル色を自動選択する
;; tr-ime・mozc-modeless 両方から使うためトップレベルで定義する
(defun my/background-luminance ()
  "現在の背景色の明度を 0.0〜1.0 で返す。"
  (let* ((bg (face-background 'default nil t))
         (rgb (color-name-to-rgb (or bg "black")))
         (r (nth 0 rgb)) (g (nth 1 rgb)) (b (nth 2 rgb)))
    (+ (* 0.299 r) (* 0.587 g) (* 0.114 b))))

(defun my/ime-on-cursor-color ()
  "背景色の明暗から coral / cyan のうち見やすい方を返す。"
  (if (> (my/background-luminance) 0.5)
      "coral"    ; 明るい背景 → coral（暗め）
    "cyan"))     ; 暗い背景   → cyan（明るめ）

(defun my/default-cursor-color ()
  "デフォルトのカーソル色（フェイスの foreground）を返す。"
  (or (face-foreground 'cursor nil t)
      (face-foreground 'default nil t)
      "white"))

(use-package tr-ime
  :if (not my/use-mozc-modeless)
  :config
  (tr-ime-standard-install)
  (setq default-input-method "W32-IME")

  ;; モードラインの IME 状態表示
  ;; [--] = IME OFF  [あ] = IME ON
  ;; モードライン表示は使わない（カーソル色のみで判別）
  (setq-default w32-ime-mode-line-state-indicator "")
  (setq w32-ime-mode-line-state-indicator-list '("" "" ""))
  (w32-ime-initialize)

  ;; tr-ime-standard-install / w32-ime-initialize が
  ;; buffer-file-coding-system のデフォルトを japanese-cp932 系に
  ;; 書き換えてしまうため、ここで UTF-8 に戻す。
  ;; （*scratch* など「ファイルと紐付かないバッファ」が SJIS になる対策）
  (setq-default buffer-file-coding-system 'utf-8)



  ;; IME ON → 自動選択色、OFF → 通常の文字色に戻す
  (add-hook 'w32-ime-on-hook
            (lambda ()
              (set-cursor-color (my/ime-on-cursor-color))
              (setq cursor-type 'box)))
  (add-hook 'w32-ime-off-hook
            (lambda ()
              (set-cursor-color (my/default-cursor-color))
              (setq cursor-type 'box)))

  ;; テーマ切り替え時にも OFF 状態のカーソル色を追従させる
  (add-hook 'enable-theme-functions
            (lambda (_theme)
              (unless current-input-method
                (set-cursor-color (my/default-cursor-color)))))

  ;; ミニバッファ入力時は IME を自動でOFF
  (add-hook 'minibuffer-setup-hook #'deactivate-input-method)

  ;; isearch 中も IME をOFF（検索語は英数字が多いため）
  (add-hook 'isearch-mode-hook
            (lambda () (deactivate-input-method)))

  ;; フレーム作成時（make-frame）にも IME を初期化
  (add-hook 'after-make-frame-functions
            (lambda (f)
              (with-selected-frame f
                (w32-ime-initialize)))))

;; Quail の TAB 補完で *Quail Completions* が開くのを止める。
(with-eval-after-load 'quail
  (define-key quail-translation-keymap (kbd "TAB") nil)
  (define-key quail-translation-keymap (kbd "<tab>") nil))


;; =====================================================================
;; 12. multiple-cursors（マルチカーソル）
;; =====================================================================

(use-package multiple-cursors
  ;; CUA モードの C-z（矩形選択開始）と競合しないよう mc 操作は C-c m プレフィックスに集約
  ;; よく使う操作だけ単キーにも割り当て
  ;;   C->        … 次の同じ単語にカーソル追加
  ;;   C-<        … 前の同じ単語にカーソル追加
  ;;   C-c m a    … バッファ内の全同一単語にカーソル追加
  ;;   C-c m l    … 選択範囲の各行にカーソル追加
  ;;   C-c m e    … 行末にカーソルを揃えて追加
  :bind
  (("C->"       . mc/mark-next-like-this)        ; 次の同じ単語
   ("C-<"       . mc/mark-previous-like-this)    ; 前の同じ単語
   ("C-c m a"   . mc/mark-all-like-this)         ; 全同一単語
   ("C-c m l"   . mc/edit-lines)                 ; 選択範囲の各行
   ("C-c m e"   . mc/edit-ends-of-lines)))       ; 各行の行末

;; =====================================================================
;; 12b. Zoxide 連携（頻繁に使うディレクトリへの高速移動）
;; =====================================================================
;; 前提: zoxide.exe が PATH または bin/ に配置済みであること
;;   https://github.com/ajeetdsouza/zoxide
;; M-o z で zoxide-find-file を呼び出す（hydra-launcher に登録済み）

(use-package zoxide
  :ensure t)

;; =====================================================================
;; 12b. Markdown モード
;; =====================================================================

(use-package markdown-mode
  :mode (("README\\.md\\'" . gfm-mode)
         ("\\.md\\'"       . markdown-mode))
  :init
  (setq markdown-command "multimarkdown")
  :config
  (setq markdown-header-scaling nil)
  (markdown-reload-extensions))

;; 目次生成プラグイン
(use-package markdown-toc)


;; =====================================================================
;; 12b. Markdown アウトライン機能
;; ─ imenu-list : 右サイドバーに見出し一覧を常時表示
;; ─ outline-minor-mode : 見出し単位で折りたたみ（bicycle で TAB 操作）
;; =====================================================================

;; --- imenu-list（右サイドバーアウトライン） ---
(use-package imenu-list
  :commands imenu-list-smart-toggle
  :config
  (setq imenu-list-position 'right)   ; 右端に表示
  (setq imenu-list-size     0.25)     ; 画面幅の最大 25% (1/4)
  (setq imenu-list-focus-after-activation nil) ; 開いてもエディタ側にフォーカスを残す
  (setq imenu-list-auto-resize t)     ; 項目数に合わせて自動リサイズ

  ;; 自動リサイズ時も横幅が画面の 1/4 (25%) を超えないよう上限キャップを設定
  (defun my/imenu-list-resize-window-capped (&rest _)
    "imenu-list の横幅が画面幅の 1/4 (25%) を超えないよう制限してリサイズする。"
    (when (and (boundp 'imenu-list--line-entries) imenu-list--line-entries)
      (let* ((max-w (max 20 (/ (frame-width) 4)))  ; 最大でも画面幅の 25% (1/4)
             (fit-window-to-buffer-horizontally t))
        (dolist (win (get-buffer-window-list (imenu-list-get-buffer-create)))
          (fit-window-to-buffer win nil nil max-w 15)))))
  (advice-add 'imenu-list-resize-window :override #'my/imenu-list-resize-window-capped)

  ;; nov-mode（EPUB リーダー）対策：
  ;; nov.el の imenu インデックスは、章ドキュメントの位置情報として "c0.xhtml" 等の
  ;; ファイル名文字列を持つため、imenu-list--current-entry の数値比較 (<=) で
  ;; (wrong-type-argument number-or-marker-p ...) エラーが発生する。
  ;; nov-mode では現在閲覧中の章ドキュメントと一致する目次項目を安全に取得し、
  ;; かつ型エラーによる描画・ジャンプのクラッシュを完全に防ぐ。
  (defun my/imenu-list--current-entry-nov-support (orig-fun &rest args)
    (let ((buf (or (bound-and-true-p imenu-list--displayed-buffer) (current-buffer))))
      (if (and (buffer-live-p buf)
               (with-current-buffer buf (derived-mode-p 'nov-mode)))
          (with-current-buffer buf
            (when (and (bound-and-true-p nov-documents)
                       (bound-and-true-p nov-documents-index)
                       (< nov-documents-index (length nov-documents)))
              (let* ((current-path (cdr (aref nov-documents nov-documents-index)))
                     (current-file (file-name-nondirectory current-path)))
                (cl-find-if
                 (lambda (entry)
                   (when (listp (cdr entry))
                     (let ((pos (cadr entry)))
                       (and (stringp pos)
                            (or (string-suffix-p pos current-path)
                                (string= (file-name-nondirectory pos) current-file))))))
                 imenu-list--line-entries))))
        (condition-case nil
            (apply orig-fun args)
          (wrong-type-argument nil)))))
  (advice-add 'imenu-list--current-entry :around #'my/imenu-list--current-entry-nov-support))

;; Markdown を開いたら自動でサイドバーを表示する
;; （markdown-mode は imenu-generic-expression を自前でセットするため
;;   imenu-create-index-function の上書きは不要）
(defun my/imenu-list-open-for-markdown ()
  "markdown-mode バッファを開いたときにアウトラインサイドバーを自動表示します。
howm-mode が有効な場合（howm 経由で開いた md）は表示しません。"
  (when (and (derived-mode-p 'markdown-mode)
             (not (bound-and-true-p howm-mode)))
    (let ((src-win (selected-window)))
      (imenu-list-smart-toggle)
      ;; トグル後もエディタ側にフォーカスを戻す
      ;; selected-window を事前に保存しておくことで
      ;; get-buffer-window が nil を返す競合を回避する
      (when (window-live-p src-win)
        (select-window src-win)))))

;; markdown-mode での自動表示は無効（F4 または M-o m O で手動開閉）
;; (add-hook 'markdown-mode-hook #'my/imenu-list-open-for-markdown)

;; --- outline-minor-mode + bicycle（TAB/S-TAB で折りたたみ） ---
;; bicycle : outline の TAB サイクルを有効にする軽量パッケージ
(use-package bicycle
  :after outline
  :bind (:map outline-minor-mode-map
         ([C-tab]     . bicycle-cycle)          ; C-TAB : このセクションだけ開閉
         ([S-tab]     . bicycle-cycle-global)   ; S-TAB : バッファ全体を一括開閉
         ([backtab]   . bicycle-cycle-global))) ; Shift-TAB（端末互換）

;; markdown-mode で outline-minor-mode を有効化
;; outline-regexp は行頭の # + 空白 にマッチさせる（本文中の ##タグ 等を除外）
;; outline-regexp を差し替えると markdown-outline-level が nil を返し
;; consult-outline が wrong-type-argument になるため、outline-level も自前で設定する
(add-hook 'markdown-mode-hook
          (lambda ()
            (setq-local outline-regexp "^#+\\s-")
            (setq-local outline-level
                        (lambda ()
                          (save-excursion
                            (beginning-of-line)
                            (skip-chars-forward "#"))))
            (outline-minor-mode 1)))

;; --- キーバインド ---
;;   F4        … imenu-list サイドバーをトグル（既存の Speedbar より便利）
;;   M-o m o   … consult-outline（既存の hydra-markdown の "o" キー）
;;   C-TAB     … 現在の見出しセクションを折りたたみ/展開 (bicycle)
;;   S-TAB     … バッファ全体を一括折りたたみ/展開   (bicycle)
(global-set-key [f4] 'imenu-list-smart-toggle)   ; F4 でサイドバー開閉（Speedbar を置き換え）


;; =====================================================================
;; 13. howm + howm-markdown（Obsidian 互換 Markdown メモ環境）
;; =====================================================================

;; howm-markdown.el を howm より先に読み込む
;; （# をタイトルヘッダーにする等、Markdown 互換設定を事前に行う）
(use-package howm
  :defer t
  :commands (howm-menu howm-list-all howm-create howm-remember howm-mode)
  :init
  ;; howm-markdown を howm ロード前に適用
  (require 'howm-markdown)

  ;; Obsidian Vault ルートとデフォルトフォルダ
  (defvar my/howm-vault-root
    (expand-file-name "Documents/Obsidian-memo" (or (getenv "USERPROFILE") "~"))
    "Obsidian Vault のルートディレクトリ。")
  (defvar my/howm-default-subfolder "01_kami"
    "新規メモのデフォルト保存先サブフォルダ。")

  ;; 初期状態は Vault 全体を対象にし、新規メモは 01_kami 配下に保存
  (setq howm-directory my/howm-vault-root)
  (setq howm-keyword-file (expand-file-name ".howm-keys" howm-directory))
  (setq howm-file-name-format (format "%s/%%Y%%m%%d-%%H%%M%%S.md" my/howm-default-subfolder))

  ;; サブフォルダ一覧取得 & Consult 切り替え関数
  (defun my/howm-get-vault-subfolders ()
    "Vault 内の有効なサブフォルダ名一覧を取得します。"
    (when (file-directory-p my/howm-vault-root)
      (let ((entries (directory-files my/howm-vault-root t "^[^.]")))
        (mapcar (lambda (d) (file-relative-name d my/howm-vault-root))
                (seq-filter #'file-directory-p entries)))))

  (defun my/howm-switch-folder ()
    "howm の対象ディレクトリを Vault 全体または特定のサブフォルダに切り替えます。
[Vault 全体] の場合は全サブフォルダを一覧・検索し、新規メモは 01_kami に作成します。
特定のサブフォルダを選んだ場合は、そのフォルダ内にスコープを絞り込みます。"
    (interactive)
    (let* ((subfolders (my/howm-get-vault-subfolders))
           (all-choice "[Vault 全体] (すべてのサブフォルダ)")
           (candidates (cons all-choice subfolders))
           (current-label
            (if (string= (file-name-as-directory (expand-file-name howm-directory))
                         (file-name-as-directory (expand-file-name my/howm-vault-root)))
                all-choice
              (file-relative-name howm-directory my/howm-vault-root)))
           (choice (completing-read (format "howm 対象フォルダ (現在: %s): " current-label)
                                    candidates nil t)))
      (if (string= choice all-choice)
          (progn
            (setq howm-directory my/howm-vault-root)
            (setq howm-file-name-format (format "%s/%%Y%%m%%d-%%H%%M%%S.md" my/howm-default-subfolder))
            (message "howm を [Vault 全体] に切り替えました（新規メモ作成先: %s）" my/howm-default-subfolder))
        (let ((target-dir (expand-file-name choice my/howm-vault-root)))
          (setq howm-directory target-dir)
          (setq howm-file-name-format "%Y%m%d-%H%M%S.md")
          (message "howm を [%s] に切り替えました" choice)))
      (setq howm-keyword-file (expand-file-name ".howm-keys" howm-directory))
      (when (get-buffer "*howm-menu*")
        (with-current-buffer "*howm-menu*"
          (howm-menu-refresh)))))

  ;; howm メモは常に UTF-8 で読み込み・新規作成・保存する
  (setq howm-process-coding-system 'utf-8)
  (add-hook 'howm-create-file-hook
            (lambda ()
              (set-buffer-file-coding-system 'utf-8 t)))
  (add-hook 'howm-mode-hook
            (lambda ()
              (set-buffer-file-coding-system 'utf-8 t)))
  (add-to-list 'file-coding-system-alist
               (cons (concat "^" (regexp-quote (expand-file-name howm-directory)) ".*\\.md\\'")
                     'utf-8))

  ;; 保存時に1行目の # タイトル をファイル名に反映させる
  (defun my-howm-update-filename-with-title ()
    "保存時に1行目のタイトル # title をファイル名に反映させます。"
    (when (and (or (derived-mode-p 'howm-mode) (derived-mode-p 'markdown-mode))
               (buffer-file-name)
               (file-exists-p (buffer-file-name)))
      (let* ((old-path (buffer-file-name))
             (old-name (file-name-nondirectory old-path))
             (dir (file-name-directory old-path))
             (title nil))
        (save-excursion
          (goto-char (point-min))
          ;; Markdown の # タイトル 形式を抽出
          (when (re-search-forward "^# \(.+\)$" (line-end-position) t)
            (setq title (match-string-no-properties 1))))
        (when (and title
                   (not (string-match-p "\`[[:space:]]*\'" title)))
          (let* ((base-name (file-name-sans-extension old-name))
                 (date-part (if (string-match "_" base-name)
                                (substring base-name 0 (match-beginning 0))
                              base-name))
                 (safe-title (replace-regexp-in-string "[\\/:*?\"<>|]" "" title))
                 (new-name (format "%s_%s.md" date-part safe-title))
                 (new-path (expand-file-name new-name dir)))
            (unless (or (string= old-name new-name)
                        (file-exists-p new-path))
              (rename-file old-path new-path t)
              (set-visited-file-name new-path)
              (set-buffer-modified-p nil)
              (message "タイトル変更に合わせてリネームしました: %s" new-name)))))))

  (add-hook 'howm-after-save-hook 'my-howm-update-filename-with-title)

  :config
  ;; テンプレート（# タイトル 形式・howm-markdown に合わせて変更）
  (setq howm-template-date-format "%Y-%m-%d %H:%M")
  (setq howm-template "# %cursor\n#memo\n[%date]\n\n")

  ;; #タグ を consult-ripgrep で検索する（Obsidian 形式のタグリンク対応）
  (defun my-howm-search-hashtag-at-point ()
    "カーソル位置の #タグ を consult-ripgrep で howm ディレクトリ内検索する。"
    (interactive)
    (let* ((sym (thing-at-point 'symbol t))
           (tag (when sym (concat "#" sym))))
      (if tag
          (consult-ripgrep howm-directory tag)
        (message "カーソルがタグの上にありません"))))

  ;; #タグ をクリック／RET でジャンプできるボタンとして装飾する
  (defun my-howm-make-hashtag-buttons ()
    "バッファ内の #タグ をクリッカブルなボタンにする。"
    (save-excursion
      (goto-char (point-min))
      (while (re-search-forward "#[[:alnum:]_-]+" nil t)
        (let ((tag (match-string-no-properties 0)))
          (make-button (match-beginning 0) (match-end 0)
                       'action (lambda (_btn)
                                 (consult-ripgrep howm-directory tag))
                       'follow-link t
                       'help-echo (concat "クリックで " tag " を検索"))))))

  (add-hook 'howm-mode-hook 'my-howm-make-hashtag-buttons)

  ;; キーバインド：C-c # でタグ検索
  (define-key howm-mode-map (kbd "C-c #") 'my-howm-search-hashtag-at-point)

  ;; howmS / howmC 画面で q を押したとき、ウィンドウごと確実に閉じる
  (with-eval-after-load 'howm-view
    (define-key howm-view-summary-mode-map (kbd "q") #'quit-window)
    (define-key howm-view-contents-mode-map (kbd "q") #'quit-window))

  ;; howm-kill-all 実行後にミニバッファのプロンプトをクリアする
  (advice-add 'howm-kill-all :after (lambda (&rest _) (message nil)))

  ;; Obsidian 固有フォルダを除外
  (with-eval-after-load 'howm-vars
    (add-to-list 'howm-excluded-dirs ".obsidian")
    (add-to-list 'howm-excluded-dirs ".trash"))

  ;; C-c , D でフォルダ切り替え可能に
  (define-key howm-mode-map (kbd "C-c , D") #'my/howm-switch-folder)
  (with-eval-after-load 'howm-menu
    (define-key howm-menu-mode-map (kbd "D") #'my/howm-switch-folder))

  ;; howm × Obsidian 操作ガイド (Hydra / F1)
  (defhydra hydra-howm-help (:color blue :hint nil)
    "
  === howm × Obsidian 操作ガイド ===  [F7 / F1 / q] 閉じる
  [メモ作成・編集]                    [検索・一覧]
  c     : 新規メモ (01_kami に保存)   a     : 全メモ一覧 (howm-list-all)
  C-c , c: howm新規作成               l     : 最近のメモ (howm-list-recent)
  C-c v : 画像貼り付け (img/)         S-F7  : Vault全体を全文検索 (rg)
  C-c # : #タグを全文検索             s / g : howm内蔵検索 (grep)
  ----------------------------------------------------------------------
  [サブフォルダ切り替え (Obsidian)]   [カレンダー・画面操作]
  D / C-F7 : フォルダ切替 (Consult)   F8    : カレンダー開閉 (calfw)
             (Vault全体 ⇔ 各フォルダ) q     : ウィンドウを閉じる
             ※初期状態: Vault全体走査  RET   : 選択項目のメモを開く
  ----------------------------------------------------------------------
"
    ("c" howm-create :color blue)
    ("a" howm-list-all :color blue)
    ("l" howm-list-recent :color blue)
    ("D" my/howm-switch-folder :color blue)
    ("d" my/howm-switch-folder :color blue)
    ("s" howm-list-grep :color blue)
    ("g" howm-list-grep :color blue)
    ("S-F7" my/howm-ripgrep :color blue)
    ("<S-f7>" my/howm-ripgrep :color blue)
    ("F8" my/open-calendar :color blue)
    ("<f8>" my/open-calendar :color blue)
    ("v" my/howm-paste-image :color blue)
    ("q" nil :color blue)
    ("<escape>" nil :color blue)
    ("<f1>" nil :color blue)
    ("<F1>" nil :color blue)
    ("<f7>" nil :color blue)
    ("<F7>" nil :color blue))

  (define-key howm-mode-map (kbd "<f1>") (lambda () (interactive) (if (fboundp 'hydra-howm-help/body) (hydra-howm-help/body) (describe-mode))))
  (with-eval-after-load 'howm-menu
    (define-key howm-menu-mode-map (kbd "<f1>") (lambda () (interactive) (if (fboundp 'hydra-howm-help/body) (hydra-howm-help/body) (describe-mode))))
    (define-key howm-menu-mode-map (kbd "?") (lambda () (interactive) (if (fboundp 'hydra-howm-help/body) (hydra-howm-help/body) (describe-mode))))))


;; ④ Cosense × Markdown ハイブリッド・シンタックスハイライト
(defun my-howm-hybrid-syntax-highlighter ()
  "howm 内で Cosense (Scrapbox) と Markdown の両方の記法を強調表示します。"
  (font-lock-add-keywords
   nil `(
         ;; --- Markdown Style ---
         ;; # 見出し, ## 見出し
         ("^\\(#+ \\)\\(.*\\)$" 2 '(:weight bold :foreground "gold") t)
         ;; **太字**
         ("\\*\\*\\([^*]+\\)\\*\\*" 1 '(:weight bold :foreground "white") t)
         ;; `コード`
         ("`\\([^`]+\\)`" 1 '(:foreground "LightSalmon" :background "#333333") t)
         ;; [表示名](URL)
         ("\\[\\([^]]+\\)\\](\\([^)]+\\))" 0 '(:foreground "SkyBlue" :underline t) t)
         ))
  (font-lock-flush))

(defun my-howm-indent-setup ()
  "howm でスペースによる箇条書きと階層化を楽にします。"
  ;; TAB で深く、S-TAB で浅く
  (local-set-key (kbd "TAB") (lambda () (interactive) (save-excursion (beginning-of-line) (insert " "))))
  (local-set-key (kbd "<backtab>") (lambda () (interactive) (save-excursion (beginning-of-line) (when (looking-at " ") (delete-char 1)))))
  ;; 改行時にインデントを引き継ぐ
  (setq-local indent-line-function 'indent-relative-first-indent-point))

(add-hook 'howm-mode-hook 'my-howm-indent-setup)
(add-hook 'howm-mode-hook 'my-howm-hybrid-syntax-highlighter)

;; howm でメモを開いたとき、markdown-mode-hook より遅れて Ilist が開いてしまう
;; タイミング問題への対処：howm-mode-hook で Ilist ウィンドウを閉じる
(add-hook 'howm-mode-hook
          (lambda ()
            (when-let* ((ilist-win (get-buffer-window "*Ilist*")))
              (delete-window ilist-win))))

;; ⑤ 画像のインライン表示（iimage-mode）
;; Markdown形式の ![](img/...) も画像として認識するように設定
(add-hook 'howm-mode-hook 'iimage-mode)
(add-hook 'markdown-mode-hook 'iimage-mode)
(with-eval-after-load 'iimage
  ;; altテキスト付きの画像記法にも対応
  (setq iimage-mode-image-regex-alist
        (cons '("!\\[.*?\\](\\([^)]+\\))" . 1)
              iimage-mode-image-regex-alist))

  ;; Windows環境でのフリーズ対策:
  ;; Web上の画像URL（http://, https://）や UNC パス（//...）が含まれている場合、
  ;; locate-file が Windows のネットワーク探索（SMB/WebDAV）を走らせて
  ;; タイムアウトするまで数分間 Emacs 全体がフリーズするのを防ぐ。
  (defun my/iimage-mode-buffer-skip-urls (orig-fn &rest args)
    "URL や UNC パスによる Windows ネットワーク解決タイムアウト（フリーズ）を抑止。"
    (cl-letf* ((orig-locate-file (symbol-function 'locate-file))
               ((symbol-function 'locate-file)
                (lambda (filename path &rest r)
                  (if (or (string-prefix-p "//" filename)
                          (string-prefix-p "\\\\" filename)
                          (string-match-p "\\`[a-zA-Z]+://" filename))
                      nil
                    (apply orig-locate-file filename path r)))))
      (apply orig-fn args)))

  (advice-add 'iimage-mode-buffer :around #'my/iimage-mode-buffer-skip-urls))
(setq max-image-size 4.0)

;; ⑥⑦ org-download を howm/markdown で使う
;;     クリップボード貼り付け（C-c v）・ドラッグドロップ両対応
(use-package org-download
  :defer t
  :commands (org-download-clipboard org-download-enable)
  :config

  ;; howm/markdown バッファでの保存先を「メモと同じフォルダの img/」に設定
  (defun my-org-download-dir ()
    "howm または markdown バッファならメモと同じフォルダの img/ を返す。それ以外は nil。"
    (when (and (or (derived-mode-p 'howm-mode) (derived-mode-p 'markdown-mode)) 
               (buffer-file-name))
      (expand-file-name "img" (file-name-directory (buffer-file-name)))))

  (defun my-org-download-set-dir ()
    (when-let* ((dir (my-org-download-dir)))
      (setq-local org-download-image-dir dir)))
  (add-hook 'howm-mode-hook 'my-org-download-set-dir)
  (add-hook 'markdown-mode-hook 'my-org-download-set-dir)

  ;; 保存後に挿入するリンク形式を Markdown 形式 ![](...) に変える
  (defun my-org-download-insert-link (filename)
    "org-download が画像を保存した後、Markdown形式でパスを挿入して iimage-mode を更新する。"
    (when (or (derived-mode-p 'howm-mode) (derived-mode-p 'markdown-mode))
      (let ((inhibit-modification-hooks t))
        (save-excursion
          ;; org-download が標準で挿入する [[file:...]] リンクを削除
          (when (re-search-backward "^\\[\\[file:" (line-beginning-position -3) t)
            (delete-region (line-beginning-position) (line-beginning-position 2)))))
      ;; Markdown標準の画像記法で挿入（Obsidian対応）
      (let ((rel-path (file-relative-name filename (file-name-directory (buffer-file-name)))))
        (insert (format "![](%s)\n" rel-path)))
      (when (fboundp 'iimage-mode-buffer)
        (iimage-mode-buffer t))
      (message "画像を保存しました → %s" (file-name-nondirectory filename))))

  (add-hook 'org-download-after-download-hook
            (lambda () (my-org-download-insert-link org-download-last-file)))

  ;; C-c v でクリップボードの画像を貼り付け
  (defun my-howm-paste-image ()
    "クリップボードの画像を img/ に保存して Markdown 形式で挿入します。"
    (interactive)
    (unless (buffer-file-name)
      (user-error "先にメモをファイルとして保存してください"))
    (my-org-download-set-dir)
    (org-download-clipboard))

  (with-eval-after-load 'howm
    (define-key howm-mode-map (kbd "C-c v") 'my-howm-paste-image))
  (with-eval-after-load 'markdown-mode
    (define-key markdown-mode-map (kbd "C-c v") 'my-howm-paste-image))

  ;; ドラッグドロップ対応
  (add-hook 'howm-mode-hook 'org-download-enable))


;; =====================================================================
;; 14. Obsidian との連携 (完全遅延読み込み)
;; ─ 起動時の全ファイルスキャンによるフリーズを防止するため、
;;   キーを押した時 (C-c o ...) に初めてオンデマンドでロードします
;; =====================================================================

(use-package obsidian
  :defer t
  :commands (obsidian-jump
             obsidian-insert-link
             obsidian-create-missing-file
             obsidian-mode)
  :bind
  (("C-c o f" . obsidian-jump)
   ("C-c o i" . obsidian-insert-link)
   ("C-c o c" . obsidian-create-missing-file))
  :init
  ;; 起動前・ロード前でもディレクトリ変数は事前定義しておく
  (setq obsidian-directory (expand-file-name "Documents/Obsidian-memo"
                                            (or (getenv "USERPROFILE") "~")))
  (setq obsidian-default-directory obsidian-directory)
  :config
  ;; WikiLink（[[...]]）を無効化してMarkdown形式 [title](file.md) を使う
  (setq obsidian-wiki-link-style nil)
  (setq obsidian-wiki-link-p     nil))


;; =====================================================================
;; 15. カレンダー (calfw)
;; =====================================================================

(use-package calfw
  :commands calfw-open-calendar-buffer
  :config
  ;; 見栄えの調整（罫線など）
  (setq calfw-fchar-junction         ?+
        calfw-fchar-vertical-line    ?|
        calfw-fchar-horizontal-line  ?-
        calfw-fchar-left-junction    ?+
        calfw-fchar-right-junction   ?+
        calfw-fchar-top-junction     ?+
        calfw-fchar-bottom-junction  ?+)

  ;; カレンダー描画幅に安全マージンを持たせ、スクロールバーや枠線との干渉・はみ出しを確実に防止
  ;; （7列あるため -8文字引くことで確実に各マス目が1文字縮み、右端に8〜14文字の確実な余白を確保）
  (advice-add 'calfw-default-window-dims :filter-return
              (lambda (dims)
                (let* ((body-w (window-body-width (selected-window)))
                       (safe-w (max 40 (- body-w 8))))
                  (cons safe-w (cdr dims)))))

  ;; カレンダーバッファ専用の表示最適化フック
  (add-hook 'calfw-calendar-mode-hook
            (lambda ()
              (setq-local display-line-numbers nil) ; 行番号を完全に無効化（横幅圧迫を防止）
              (display-line-numbers-mode -1) ; 行番号を無効化（はみ出し防止）
              (visual-line-mode -1)          ; 折り返しを無効化（枠線崩れ防止）
              (setq-local truncate-lines t)  ; 切り詰め
              (whitespace-mode -1)))         ; 空白マークをOFF

  ;; ウィンドウサイズ変更（分割やリサイズ）時にカレンダー幅を自動で再フィット
  (add-hook 'window-size-change-functions
            (lambda (frame)
              (let ((buf (get-buffer "*cfw-calendar*")))
                (when (and buf (get-buffer-window buf frame))
                  (with-current-buffer buf
                    (when (fboundp 'calfw-refresh-calendar-buffer)
                      (calfw-refresh-calendar-buffer))))))))

(use-package calfw-howm
  :after (calfw howm)
  :config
  ;; howm の予定を表示する際のタイトルを調整
  (setq calfw-howm-schedule-summary-transformer
        (lambda (s) (if (string-match "^\\[\\(.*?\\)\\]" s) (match-string 1 s) s))))

;; 祝日設定
(use-package japanese-holidays
  :defer t
  :config
  (setq calendar-holidays
        (append japanese-holidays holiday-local-holidays holiday-other-holidays)))

;; howm メモ（作成日）を calfw カレンダーに表示するデータソース
(defun my/calfw-howm-memo-period-to-calendar (begin end)
  "BEGIN から END までの期間に作成された howm メモを calfw 形式で返す。"
  (let* ((dir (or (bound-and-true-p howm-directory)
                  (expand-file-name "Documents/Obsidian-memo" (getenv "USERPROFILE"))))
         (begin-abs (calendar-absolute-from-gregorian begin))
         (end-abs (calendar-absolute-from-gregorian end))
         (contents nil))
    (when (file-directory-p dir)
      (dolist (filepath (directory-files-recursively dir "\\`[0-9]\\{8\\}-.*\\.md\\'" nil
                                                    (lambda (d)
                                                      (not (string-prefix-p "." (file-name-nondirectory d))))))
        (let ((filename (file-name-nondirectory filepath)))
          (when (string-match "\\`\\([0-9]\\{4\\}\\)\\([0-9]\\{2\\}\\)\\([0-9]\\{2\\}\\)-" filename)
            (let* ((year (string-to-number (match-string 1 filename)))
                   (month (string-to-number (match-string 2 filename)))
                   (day (string-to-number (match-string 3 filename)))
                   (date (list month day year))
                   (date-abs (calendar-absolute-from-gregorian date)))
              (when (and (<= begin-abs date-abs) (<= date-abs end-abs))
                (let ((title
                       (if (string-match "_\\(.+\\)\\.md\\'" filename)
                           (match-string 1 filename)
                         (with-temp-buffer
                           (insert-file-contents filepath nil 0 200)
                           (goto-char (point-min))
                           (let ((first-line (buffer-substring-no-properties
                                              (line-beginning-position)
                                              (line-end-position))))
                             (replace-regexp-in-string "^[#* \t\\[\\]]+" "" first-line))))))
                  (when (or (null title) (string-blank-p title))
                    (setq title (file-name-sans-extension filename)))
                  (when (> (length title) 16)
                    (setq title (concat (substring title 0 15) "…")))
                  (let ((item-text (format "・%s" title)))
                    (setq contents (calfw--contents-add date item-text contents))))))))))
    contents))

(defun my/calfw-howm-memo-create-source (&optional name color)
  "howm メモの作成日をカレンダーに表示する calfw ソースを生成する。"
  (make-calfw-source
   :name (or name "howm-memo")
   :color (or color "#98be65")
   :data #'my/calfw-howm-memo-period-to-calendar))

(defun my/open-calendar ()
  "howm の予定とメモを統合したカレンダーを開閉（トグル）します。"
  (interactive)
  (let ((cal-buf (get-buffer "*cfw-calendar*")))
    (cond
     ;; 1. 現在のバッファがカレンダーの場合: 即座に閉じる
     ((or (derived-mode-p 'calfw-calendar-mode 'cfw:calendar-mode)
          (eq (current-buffer) cal-buf))
      (quit-window))
     ;; 2. 画面上のウィンドウにカレンダーが表示されている場合: そのウィンドウを閉じる
     ((and cal-buf (get-buffer-window cal-buf))
      (quit-window nil (get-buffer-window cal-buf)))
     ;; 3. カレンダーバッファが存在して裏に隠れている場合: 表示して最新化
     (cal-buf
      (switch-to-buffer cal-buf)
      (when (fboundp 'calfw-refresh-calendar-buffer)
        (calfw-refresh-calendar-buffer)))
     ;; 4. カレンダーバッファがまだない場合: 新規に作成して開く
     (t
      (require 'calfw)
      (require 'calfw-howm)
      (calfw-open-calendar-buffer
       :contents-sources
       (list
        (calfw-howm-create-source "howm" "SkyBlue") ; howm の予定
        (my/calfw-howm-memo-create-source "memo" "#98be65"))) ; howm のメモ（予定とは区別）
      ;; 新規作成後も現在のウィンドウ幅に合わせて確実に即座リサイズ
      (when (fboundp 'calfw-refresh-calendar-buffer)
        (calfw-refresh-calendar-buffer))))))

;; カレンダー画面からの howm 予定追加 ＆ ガイド連携
(defun my/calfw-add-schedule ()
  "カレンダーで選択中の日付に howm の予定（Markdown形式）を追加して即座に再描画する。"
  (interactive)
  (let* ((mdy (calfw-cursor-to-nearest-date))
         (m (calendar-extract-month mdy))
         (d (calendar-extract-day mdy))
         (y (calendar-extract-year mdy))
         (date-str (format "%04d-%02d-%02d" y m d))
         (input (read-string (format "予定を追加 [%s]: " date-str))))
    (when (and input (not (string-blank-p input)))
      (let* ((now (current-time))
             (now-str (format-time-string "%Y-%m-%d %H:%M" now))
             (file-name (format-time-string "%Y%m%d-%H%M%S_schedule.md" now))
             (save-dir (expand-file-name (or (bound-and-true-p my/howm-default-subfolder) "01_kami")
                                         (or (bound-and-true-p my/howm-vault-root) howm-directory)))
             (file-path (expand-file-name file-name save-dir))
             (schedule-text
              (if (string-match "\\`\\([0-9]\\{1,2\\}:[0-9]\\{2\\}\\)[[:space:]]+\\(.*\\)\\'" input)
                  (let ((time (match-string 1 input))
                        (title (match-string 2 input)))
                    (format "[%s %s]@ %s" date-str time title))
                (format "[%s]@ %s" date-str input)))
             (content (format "# %s\n#schedule #howm\n[%s]\n\n%s\n"
                              schedule-text now-str schedule-text)))
        (unless (file-directory-p save-dir)
          (make-directory save-dir t))
        (with-temp-file file-path
          (insert content))
        (when (fboundp 'howm-keyword-update)
          (howm-keyword-update))
        (calfw-refresh-calendar-buffer)
        (message "予定を登録しました: %s" schedule-text)))))

(defun my/calfw-create-howm-memo ()
  "カレンダーで選択中の日付の howm 予定メモ（Markdown）を新規作成・編集する。"
  (interactive)
  (let* ((mdy (calfw-cursor-to-nearest-date))
         (m (calendar-extract-month mdy))
         (d (calendar-extract-day mdy))
         (y (calendar-extract-year mdy))
         (date-str (format "%04d-%02d-%02d" y m d))
         (now (current-time))
         (now-str (format-time-string "%Y-%m-%d %H:%M" now))
         (file-name (format-time-string "%Y%m%d-%H%M%S.md" now))
         (save-dir (expand-file-name (or (bound-and-true-p my/howm-default-subfolder) "01_kami")
                                     (or (bound-and-true-p my/howm-vault-root) howm-directory)))
         (file-path (expand-file-name file-name save-dir)))
    (unless (file-directory-p save-dir)
      (make-directory save-dir t))
    (find-file file-path)
    (insert (format "# [%s]@ \n#schedule #howm\n[%s]\n\n" date-str now-str))
    (forward-line -4)
    (end-of-line)))

;; カレンダー選択日のメモを howmC を介さず「普通にファイルを開く（閉じたらカレンダーに自動復帰）」
(defun my/calfw-open-file-at-date ()
  "カレンダーで選択中の日付のメモ・予定ファイルを、howmC を使わず普通に開きます。
1件なら即座に開き、複数あればタイトル一覧から選択できます。
メモを閉じる（C-w等）と、自動的にカレンダー画面に復帰します。"
  (interactive)
  (let* ((mdy (calfw-cursor-to-nearest-date))
         (cal-buf (current-buffer))
         (cal-win (selected-window))
         (m (calendar-extract-month mdy))
         (d (calendar-extract-day   mdy))
         (y (calendar-extract-year  mdy))
         (date-compact (format "%04d%02d%02d" y m d))
         (date-hyphen (format "%04d-%02d-%02d" y m d))
         (dir (or (bound-and-true-p howm-directory)
                  (expand-file-name "Documents/Obsidian-memo" (getenv "USERPROFILE"))))
         (matched-files nil)
         (open-and-setup
          (lambda (filepath)
            (find-file filepath)
            (when (buffer-live-p cal-buf)
              (setq-local my/calfw-return-buffer cal-buf)
              (setq-local my/calfw-return-window cal-win)
              (add-hook 'kill-buffer-hook
                        (lambda ()
                          (let ((c my/calfw-return-buffer)
                                (w my/calfw-return-window))
                            (run-at-time 0 nil
                                         (lambda (buf win)
                                           (when (and (buffer-live-p buf) (window-live-p win))
                                             (set-window-buffer win buf)))
                                         c w)))
                        nil t)))))
    (when (file-directory-p dir)
      (dolist (f (directory-files-recursively dir "\\.md\\'" nil
                                              (lambda (d)
                                                (not (string-prefix-p "." (file-name-nondirectory d))))))
        (let ((fname (file-name-nondirectory f)))
          (when (and (not (string-match-p "\\`0000" fname))
                     (or (string-match-p (concat "\\`" date-compact) fname)
                         (with-temp-buffer
                           (insert-file-contents f nil 0 500)
                           (goto-char (point-min))
                           (search-forward (format "[%s]" date-hyphen) nil t))))
            (push f matched-files)))))
    (cond
     ((null matched-files)
      (message "指定日 [%04d-%02d-%02d] のメモ・予定はありません" y m d))
     ((= 1 (length matched-files))
      (funcall open-and-setup (car matched-files)))
     (t
      (let* ((cands
              (mapcar
               (lambda (f)
                 (let* ((fname (file-name-nondirectory f))
                        (title
                         (if (string-match "_\\(.+\\)\\.md\\'" fname)
                             (match-string 1 fname)
                           (with-temp-buffer
                             (insert-file-contents f nil 0 200)
                             (goto-char (point-min))
                             (let ((first-line (buffer-substring-no-properties
                                                (line-beginning-position)
                                                (line-end-position))))
                               (replace-regexp-in-string "^[#* \t\\[\\]]+" "" first-line))))))
                   (when (or (null title) (string-blank-p title))
                     (setq title fname))
                   (cons (format "%s (%s)" title fname) f)))
               (nreverse matched-files)))
             (choice (completing-read "開くメモを選択: " (mapcar #'car cands) nil t)))
        (when choice
          (funcall open-and-setup (cdr (assoc choice cands)))))))))

;; カレンダー選択日の「通常メモ」を新規作成
(defun my/calfw-create-normal-memo ()
  "カレンダーで選択中の日付で howm 通常メモ（Markdown）を新規作成します。
閉じると自動的にカレンダー画面に復帰し、カレンダーを再描画します。"
  (interactive)
  (let* ((mdy (calfw-cursor-to-nearest-date))
         (cal-buf (current-buffer))
         (cal-win (selected-window))
         (m (calendar-extract-month mdy))
         (d (calendar-extract-day   mdy))
         (y (calendar-extract-year  mdy))
         (date-str (format "%04d-%02d-%02d" y m d))
         (now (current-time))
         (time-str (format-time-string "%H%M%S" now))
         (file-name (format "%04d%02d%02d-%s.md" y m d time-str))
         (save-dir (expand-file-name (or (bound-and-true-p my/howm-default-subfolder) "01_kami")
                                     (or (bound-and-true-p my/howm-vault-root) howm-directory)))
         (file-path (expand-file-name file-name save-dir)))
    (unless (file-directory-p save-dir)
      (make-directory save-dir t))
    (find-file file-path)
    (insert (format "# \n#memo\n[%s %s]\n\n" date-str (format-time-string "%H:%M" now)))
    (goto-char (point-min))
    (end-of-line)
    (when (buffer-live-p cal-buf)
      (setq-local my/calfw-return-buffer cal-buf)
      (setq-local my/calfw-return-window cal-win)
      (add-hook 'kill-buffer-hook
                (lambda ()
                  (let ((c my/calfw-return-buffer)
                        (w my/calfw-return-window))
                    (run-at-time 0 nil
                                 (lambda (buf win)
                                   (when (and (buffer-live-p buf) (window-live-p win))
                                     (set-window-buffer win buf)
                                     (with-current-buffer buf
                                       (when (fboundp 'calfw-refresh-calendar-buffer)
                                         (calfw-refresh-calendar-buffer)))))
                                 c w)))
                nil t))))

;; カレンダー専用 操作ガイド (F1 / ?)
(defhydra hydra-calfw-help (:color blue :hint nil)
  "
  === カレンダー (calfw) 操作ガイド ===  [F8 / F1 / q] 閉じる
  [予定・メモ操作]          [日付移動]                [表示切替]
  i / a : クイック予定追加  h / j / k / l : 左 下 上 右  M : 月表示 (Month)
  c     : 予定メモを新規作成 ← / ↓ / ↑ / → : 左 下 上 右  W : 週表示 (Week)
  m     : 通常メモを新規作成 t / .         : 今日へ移動  T : 2週間表示
  RET   : その日のメモを開く M-g           : 日付指定    D : 日表示 (Day)
  SPC   : 選択項目の詳細    --------------------------------------------
  ----------------------------------------------------------------------
  g     : 最新表示に更新    TAB / S-TAB   : 次/前の項目 q : カレンダーを閉じる
  ----------------------------------------------------------------------
"
  ("i" my/calfw-add-schedule :color blue)
  ("a" my/calfw-add-schedule :color blue)
  ("c" my/calfw-create-howm-memo :color blue)
  ("m" my/calfw-create-normal-memo :color blue)
  ("RET" my/calfw-open-file-at-date :color blue)
  ("SPC" calfw-show-details-command :color blue)
  ("h" calfw-navi-previous-day-command)
  ("l" calfw-navi-next-day-command)
  ("j" calfw-navi-next-week-command)
  ("k" calfw-navi-previous-week-command)
  ("t" calfw-navi-goto-today-command :color blue)
  ("." calfw-navi-goto-today-command :color blue)
  ("M-g" calfw-navi-goto-date-command :color blue)
  ("M" calfw-change-view-month :color blue)
  ("W" calfw-change-view-week :color blue)
  ("T" calfw-change-view-two-weeks :color blue)
  ("D" calfw-change-view-day :color blue)
  ("g" calfw-refresh-calendar-buffer :color blue)
  ("q" nil :color blue)
  ("<escape>" nil :color blue)
  ("<f1>" nil :color blue)
  ("<F1>" nil :color blue)
  ("<f8>" nil :color blue)
  ("<F8>" nil :color blue))

(with-eval-after-load 'calfw
  (define-key calfw-calendar-mode-map (kbd "i") #'my/calfw-add-schedule)
  (define-key calfw-calendar-mode-map (kbd "a") #'my/calfw-add-schedule)
  (define-key calfw-calendar-mode-map (kbd "c") #'my/calfw-create-howm-memo)
  (define-key calfw-calendar-mode-map (kbd "m") #'my/calfw-create-normal-memo)
  (define-key calfw-calendar-mode-map (kbd "RET") #'my/calfw-open-file-at-date)
  (define-key calfw-calendar-mode-map (kbd "<f8>") #'my/open-calendar)
  (define-key calfw-calendar-mode-map (kbd "?") (lambda () (interactive) (if (fboundp 'hydra-calfw-help/body) (hydra-calfw-help/body) (describe-mode))))
  (define-key calfw-calendar-mode-map (kbd "<f1>") (lambda () (interactive) (if (fboundp 'hydra-calfw-help/body) (hydra-calfw-help/body) (describe-mode)))))


;; =====================================================================
;; 15b. 🌦️ 中四国・全国 週間天気予報 (気象庁公式データ連携 / Pure Elisp)
;; ─ Python不要、APIキー不要、Windows標準のcurlと内蔵JSONパーサーで即座に表示
;; ─ M-o W または M-x weather で一発起動
;; =====================================================================

(require 'json)
(require 'cl-lib)

(defconst my/weather-groups
  '(("【中国地方】"
     (("広島" . "34")
      ("岡山" . "33")
      ("松江" . "32")
      ("鳥取" . "31")
      ("山口" . "35")))
    ("【四国地方】"
     (("高松" . "37")
      ("松山" . "38")
      ("徳島" . "36")
      ("高知" . "39")))
    ("【主要都市】"
     (("大阪" . "27")
      ("福岡" . "40")
      ("東京" . "13")))))

(defun my/weather--code-to-icon (code)
  "気象庁の天気コードから絵文字アイコン・文字を返す。"
  (if (or (null code) (string-empty-p (format "%s" code)))
      "  -- "
    (let ((c (aref (format "%s" code) 0)))
      (cond
       ((eq c ?1) "☀️晴")
       ((eq c ?2) "☁️曇")
       ((eq c ?3) "🌧️雨")
       ((eq c ?4) "❄️雪")
       (t "・")))))

(defun my/weather--format-date (iso-str)
  "ISO日付文字列から 'M/D(曜)' 形式を生成する。"
  (if (and iso-str (string-match "\\`[0-9]\\{4\\}-\\([0-9]\\{2\\}\\)-\\([0-9]\\{2\\}\\)" iso-str))
      (let* ((m (string-to-number (match-string 1 iso-str)))
             (d (string-to-number (match-string 2 iso-str)))
             (y (string-to-number (substring iso-str 0 4)))
             (time (encode-time 0 0 0 d m y))
             (w (nth (string-to-number (format-time-string "%w" time))
                     '("日" "月" "火" "水" "木" "金" "土"))))
        (format "%d/%d(%s)" m d w))
    "--/--"))

(defun my/weather-fetch-data ()
  "気象庁 API から中四国・主要都市の天気データを一括取得して連想リストで返す。"
  (let ((url "https://www.jma.go.jp/bosai/forecast/data/forecast/{340000,330000,320000,310000,350000,370000,380000,360000,390000,270000,400000,130000}.json")
        (curl (or (executable-find "curl") "C:/Windows/System32/curl.exe"))
        (coding-system-for-read 'utf-8)
        (res-alist nil))
    (with-temp-buffer
      (call-process curl nil t nil "-s" "-k" "--ssl-no-revoke" url)
      (goto-char (point-min))
      (while (not (eobp))
        (skip-chars-forward " \t\r\n")
        (unless (eobp)
          (condition-case nil
              (let* ((data (json-parse-buffer :object-type 'plist :array-type 'list))
                     (week (nth 1 data))
                     (week-ts (plist-get week :timeSeries))
                     (area0 (car (plist-get (car week-ts) :areas)))
                     (area-code (plist-get (plist-get area0 :area) :code))
                     (prefix (substring (format "%s" area-code) 0 2)))
                (push (cons prefix data) res-alist))
            (error (goto-char (point-max)))))))
    res-alist))

(defun my/weather ()
  "中四国および主要都市の今日から向こう1週間の天気予報テーブルを上下2段（4日＋4日）で表示する。"
  (interactive)
  (message "気象庁から最新の天気予報を取得中...")
  (when (and (eq system-type 'windows-nt) (fboundp 'set-fontset-font))
    (set-fontset-font t 'emoji (font-spec :family "Segoe UI Emoji") nil 'prepend)
    (set-fontset-font t 'symbol (font-spec :family "Segoe UI Emoji") nil 'prepend))
  (let* ((data-alist (my/weather-fetch-data))
         (buf (get-buffer-create "*Weather*"))
         (sample (cdr (car data-alist)))
         (short-sample (nth 0 sample))
         (week-sample (nth 1 sample))
         (today-iso (car (plist-get (car (plist-get short-sample :timeSeries)) :timeDefines)))
         (today-date (my/weather--format-date today-iso))
         (week-dates-iso (plist-get (car (plist-get week-sample :timeSeries)) :timeDefines))
         (week-dates (mapcar #'my/weather--format-date week-dates-iso))
         (dates (if today-date (cons today-date week-dates) week-dates))
         ;; 全都市の気象データをパースしてリスト化
         (city-weather-list
          (mapcar
           (lambda (group)
             (cons (car group)
                   (mapcar
                    (lambda (city)
                      (let* ((city-name (car city))
                             (prefix (cdr city))
                             (cdata (cdr (assoc prefix data-alist)))
                             (short-data (nth 0 cdata))
                             (week-data (nth 1 cdata))
                             ;; 週間予報データ
                             (w-ts (plist-get week-data :timeSeries))
                             (w-codes (plist-get (car (plist-get (nth 0 w-ts) :areas)) :weatherCodes))
                             (w-pops (plist-get (car (plist-get (nth 0 w-ts) :areas)) :pops))
                             (temp-area (car (plist-get (nth 1 w-ts) :areas)))
                             (w-mins (copy-sequence (plist-get temp-area :tempsMin)))
                             (w-maxs (copy-sequence (plist-get temp-area :tempsMax)))
                             ;; 今日の短期予報データ
                             (s-ts (plist-get short-data :timeSeries))
                             (today-code (when s-ts (nth 0 (plist-get (car (plist-get (nth 0 s-ts) :areas)) :weatherCodes))))
                             (s-pops (when s-ts (plist-get (car (plist-get (nth 1 s-ts) :areas)) :pops)))
                             (s-temps (when s-ts (plist-get (car (plist-get (nth 2 s-ts) :areas)) :temps)))
                             (today-pop (when s-pops (format "%s%%" (or (car s-pops) "--"))))
                             (today-tmax (if (and s-temps (nth 0 s-temps)) (format "%s°" (nth 0 s-temps)) "--°"))
                             (today-tmin "--°"))
                        ;; 明日（週間予報の初日）の気温・降水確率を短期予報で補正
                        (when s-temps
                          (setcar w-maxs (or (nth 3 s-temps) (nth 0 s-temps)))
                          (when (>= (length s-temps) 3)
                            (setcar w-mins (nth 2 s-temps))))
                        (when (and s-pops (>= (length s-pops) 5))
                          (setcar w-pops (nth 4 s-pops)))
                        ;; 今日 + 週間予報の 8日分リストを構築
                        (let* ((all-codes (if today-code (cons today-code w-codes) w-codes))
                               (all-pops (if today-pop
                                             (cons today-pop (mapcar (lambda (p) (if (and p (not (string-empty-p (format "%s" p)))) (format "%2s%%" p) "--%")) w-pops))
                                           (mapcar (lambda (p) (if (and p (not (string-empty-p (format "%s" p)))) (format "%2s%%" p) "--%")) w-pops)))
                               (all-tmax (if today-tmax
                                             (cons today-tmax (mapcar (lambda (tx) (if (and tx (not (string-empty-p (format "%s" tx)))) (format "%2s°" tx) "--°")) w-maxs))
                                           (mapcar (lambda (tx) (if (and tx (not (string-empty-p (format "%s" tx)))) (format "%2s°" tx) "--°")) w-maxs)))
                               (all-tmin (if today-tmin
                                             (cons today-tmin (mapcar (lambda (tn) (if (and tn (not (string-empty-p (format "%s" tn)))) (format "%2s°" tn) "--°")) w-mins))
                                           (mapcar (lambda (tn) (if (and tn (not (string-empty-p (format "%s" tn)))) (format "%2s°" tn) "--°")) w-mins))))
                          (list city-name all-codes all-pops all-tmax all-tmin))))
                    (cadr group))))
           my/weather-groups)))
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (erase-buffer)
        ;; テーブル描画用クロージャ（前半4日 / 後半4日）
        (cl-labels ((render-block (title start-idx end-idx is-first)
                      (let* ((sub-dates (cl-subseq dates start-idx (min end-idx (length dates))))
                             (sep-line (concat "--------+-"
                                               (mapconcat (lambda (_) "--------------") sub-dates "-+-")
                                               "\n")))
                        (insert "==========================================================================\n")
                        (if is-first
                            (insert (format " 🌦️ 中四国・全国 天気予報【%s】                [r] 更新  [q] 閉じる\n" title))
                          (insert (format " 🌦️ 天気予報【%s】\n" title)))
                        (insert "==========================================================================\n")
                        (insert " 都市   | " (mapconcat (lambda (d) (format "%-14s" d)) sub-dates "| ") "\n")
                        (insert sep-line)
                        (dolist (group city-weather-list)
                          (insert (car group) "\n")
                          (dolist (item (cdr group))
                            (let ((city-name (nth 0 item))
                                  (codes (nth 1 item))
                                  (pops (nth 2 item))
                                  (tmaxs (nth 3 item))
                                  (tmins (nth 4 item)))
                              (insert (format " %-4s | " city-name))
                              (cl-loop for i from start-idx to (1- (min end-idx (length dates))) do
                                       (let* ((code (nth i codes))
                                              (icon (my/weather--code-to-icon code))
                                              (pop (or (nth i pops) "--%"))
                                              (tmax (or (nth i tmaxs) "--°"))
                                              (tmin (or (nth i tmins) "--°"))
                                              (cell (format "%s %s/%s %s" icon tmax tmin pop)))
                                         (insert (format "%-14s| " cell))))
                              (insert "\n")))
                          (insert sep-line))
                        (insert "\n"))))
          ;; 前半4日（今日〜3日後）
          (render-block "前半4日: 今日〜3日後" 0 4 t)
          ;; 後半4日（4日後〜7日後）
          (render-block "後半4日: 4日後〜7日後" 4 8 nil))
        (goto-char (point-min))
        (special-mode)
        (local-set-key (kbd "r") #'my/weather)
        (local-set-key (kbd "q") #'quit-window)))
    (pop-to-buffer buf)
    (message "天気予報を更新しました（4日＋4日 上下2段）")))

(defalias 'weather #'my/weather)


;; =====================================================================
;; 16. Casual（Transient メニュー UI）
;; ─ Calc を普通の電卓のように使いやすくする
;; ─ Calc 内で C-o でメニューを呼び出す。q または C-g で閉じる
;; =====================================================================

;; Transient を最新版に更新（casual が 0.6.0+ を要求するため）
(setq package-install-upgrade-built-in t)

;; 代数入力モード（algebraic mode）をデフォルトにする
;; → 1 + 2 * 3 RET のような普通の中置記法で入力できる
;; → RPN に戻したい場合は Calc 内で m a をトグル
(setq calc-algebraic-mode t)

(use-package casual
  :after calc
  :bind (:map calc-mode-map
         ("C-o" . casual-calc-tmenu)
         :map calc-alg-map
         ("C-o" . casual-calc-tmenu)))

;; Calc 起動時に操作・リセット方法のヒントをミニバッファに自動表示する
(add-hook 'calc-mode-hook
          (lambda ()
            (run-with-idle-timer
             0.1 nil
             (lambda ()
               (message "Calc: [C-o] メニュー表示  /  [C-u 0 DEL] スタック全消去  /  [C-x * 0] 初期化")))))

;; F6 で Calc を即起動（電卓を呼び出す感覚で）
(global-set-key [f6] #'calc)
(global-set-key (kbd "<f6>") #'calc)

;; M-x calculator で表示が切れる問題への対策（ウィンドウ高さを最低4行に拡張）
(add-hook 'calculator-mode-hook
          (lambda ()
            (unless (window-minibuffer-p)
              (let ((target-height 4))
                (when (< (window-height) target-height)
                  (window-resize nil (- target-height (window-height))))))))


;; =====================================================================
;; 17. カラーマーカー（symbol-overlay）
;; ─ カーソル位置の単語を色付きハイライト（複数色・同時使用可）
;; ─ EmEditor のカラーマーカーに近い使い勝手
;; =====================================================================

(use-package symbol-overlay
  :config
  ;; スマートマーカー：選択範囲があればその文字列全体にマーク（バッファ全域）
  ;;                   選択範囲がなければカーソル下の単語に symbol-overlay を使用
  (defvar my/hi-lock-colors
    '("yellow" "LightGreen" "cyan" "pink" "orange" "plum1" "LightSalmon")
    "hi-lock で順番に使う色のリスト。")
  (defvar my/hi-lock-color-index 0
    "次に使う my/hi-lock-colors のインデックス。")

  (defun my/marker-put ()
    "選択範囲があればその文字列をバッファ全域にハイライト。
なければ symbol-overlay-put でカーソル下の単語をハイライト。
同じ文字列に既にマーカーがあればトグルで削除する。"
    (interactive)
    (if (use-region-p)
        (let* ((text (buffer-substring-no-properties
                      (region-beginning) (region-end)))
               (pattern (regexp-quote text)))
          (deactivate-mark)
          ;; hi-lock-mode が無効なら有効化してから参照する
          (unless (bound-and-true-p hi-lock-mode) (hi-lock-mode 1))
          (if (assoc pattern hi-lock-interactive-patterns)
              (hi-lock-unface-buffer pattern)
            ;; face を interned シンボルで登録することで assoc 検索が確実に機能する
            (let* ((color (nth (mod my/hi-lock-color-index
                                    (length my/hi-lock-colors))
                               my/hi-lock-colors))
                   (face-sym (intern (format "my/hi-lock-face-%d"
                                             my/hi-lock-color-index))))
              (setq my/hi-lock-color-index (1+ my/hi-lock-color-index))
              (unless (facep face-sym)
                (make-face face-sym)
                (set-face-attribute face-sym nil
                                    :background color :foreground "black"))
              (hi-lock-face-buffer pattern face-sym))))
      (symbol-overlay-put)))

  (defun my/marker-remove-at-point ()
    "カーソル位置のカラーマーカー（hi-lock または symbol-overlay）を削除します。
カーソル位置にない場合は、ハイライトされているパターンを選択して削除します。"
    (interactive)
    (cond
     ;; 1. 選択範囲がある場合
     ((use-region-p)
      (let* ((text (buffer-substring-no-properties (region-beginning) (region-end)))
             (pattern (regexp-quote text)))
        (deactivate-mark)
        (hi-lock-unface-buffer pattern)))
     ;; 2. カーソル位置に symbol-overlay のハイライトがある場合
     ((and (fboundp 'symbol-overlay-get-symbol)
           (let ((sym (symbol-overlay-get-symbol t)))
             (and sym (symbol-overlay-assoc sym))))
      (symbol-overlay-put))
     ;; 3. カーソル位置の単語が hi-lock でハイライトされている場合
     ((let* ((word (thing-at-point 'word t))
             (pattern (and word (regexp-quote word))))
        (and pattern (assoc pattern hi-lock-interactive-patterns)))
      (let* ((word (thing-at-point 'word t))
             (pattern (regexp-quote word)))
        (hi-lock-unface-buffer pattern)))
     ;; 4. それ以外は、対話的に削除する hi-lock パターンを選択
     (t
      (call-interactively #'hi-lock-unface-buffer))))

  (defun my/marker-remove-all ()
    "hi-lock と symbol-overlay 両方のマーカーをすべて削除する。"
    (interactive)
    (hi-lock-unface-buffer t)
    (setq my/hi-lock-color-index 0)
    (symbol-overlay-remove-all))

  (defun my/toolbar-marker-clear-menu (event)
    "ツールバーをクリックした際に、マーカー削除メニューを表示します。"
    (interactive "e")
    (let ((menu (make-sparse-keymap "マーカー削除")))
      (define-key menu [all]
        '(menu-item "すべてのマーカーを削除" my/marker-remove-all
                    :keys "C-S-u"
                    :help "すべてのカラーマーカーを一括削除します"))
      (define-key menu [one]
        '(menu-item "カーソル位置のマーカーを削除" my/marker-remove-at-point
                    :keys "C-S-k"
                    :help "カーソル位置（または選択範囲）のカラーマーカーを1つ削除します"))
      (popup-menu menu event)))

  ;; マーカーをトグル（同じキーで付け外し）
  (global-set-key (kbd "C-S-m")        #'my/marker-put)
  ;; カーソル位置のマーカーを削除
  (global-set-key (kbd "C-S-k")        #'my/marker-remove-at-point)
  ;; 全マーカーを一括削除
  (global-set-key (kbd "C-S-u")        #'my/marker-remove-all)
  ;; 同じ色のマーカー間をジャンプ
  (global-set-key (kbd "C-S-n")        #'symbol-overlay-jump-next)
  (global-set-key (kbd "C-S-p")        #'symbol-overlay-jump-prev)
  ;; consult-ripgrep で選択後、カーソル下の単語を自動ハイライト
  (defun my/symbol-overlay-after-consult (&rest _)
    "consult 系コマンド実行後にカーソル下の単語を自動ハイライトする。"
    (symbol-overlay-remove-all)
    (symbol-overlay-put))
  (advice-add 'consult-ripgrep          :after #'my/symbol-overlay-after-consult)
  (advice-add 'my/consult-ripgrep-word  :after #'my/symbol-overlay-after-consult)
  (advice-add 'my/consult-ripgrep-project :after #'my/symbol-overlay-after-consult))

;; casual-symbol-overlay：Transient メニューで操作
;; ※ symbol-overlay でハイライトした単語の上にカーソルがある時だけ有効
;; ※ C-o はグローバルで find-file に使用済みのため C-S-m（マーカー上で押す）を割り当て
(use-package casual-symbol-overlay
  :after symbol-overlay
  :bind (:map symbol-overlay-map
         ("C-S-m" . casual-symbol-overlay-tmenu)))


;; =====================================================================
;; 18. EPWING 辞書連携 (Lookup)
;; =====================================================================

(use-package lookup
  :ensure nil
  :load-path "lisp/lookup/lisp"
  :commands (lookup lookup-region lookup-pattern)
  :init
  (setq lookup-enable-splash nil)
  :config
  ;; 辞書データの場所を指定してください
  ;; 例: '("/path/to/dict1" "/path/to/dict2")
  (setq lookup-search-agents
        '(
          ;; EPWING 辞書の設定テンプレート
          ;; 下記の "C:/path/to/your/epwing/dictionary" を実際のパスに書き換えてください
          (ndeb "C:/path/to/your/epwing/dictionary")
          ))

  ;; eblook.exe のパス（bin フォルダにコピー済み）
  (setq ndeb-program-name (expand-file-name "bin/eblook.exe" 
                                            (expand-file-name ".." user-emacs-directory)))

  ;; 外観の調整
  (setq lookup-display-format 'plain)
  (setq lookup-use-kakasi nil))




;; =====================================================================
;; 19. EPUB リーダー (nov.el)
;; ─ EPUB 電子書籍を Emacs 内で美しく、軽快に閲覧
;; ─ Windows 10/11 標準搭載の tar.exe を使って外部 unzip 依存を完全回避
;; =====================================================================

(use-package nov
  :ensure t
  :mode ("\\.epub\\'" . nov-mode)
  :init
  ;; 章名取得のヘルパー関数（起動時から即座に定義して redisplay エラーを防止）
  (defun nov-current-document-title ()
    "現在のEPUB章名を取得します。取得できない場合は空文字列を返します。"
    (or (ignore-errors
          (when (and (bound-and-true-p nov-documents)
                     (bound-and-true-p nov-documents-index)
                     (< nov-documents-index (length nov-documents)))
            (let* ((current-doc (aref nov-documents nov-documents-index))
                   (current-path (cdr current-doc))
                   (current-file (and current-path (file-name-nondirectory current-path))))
              ;; Imenu 目次リストから現在のファイルに該当する見出し名を探す
              (when (bound-and-true-p imenu--index-alist)
                (car (cl-find-if
                      (lambda (entry)
                        (and (listp (cdr entry))
                             (let ((pos (cadr entry)))
                               (and (stringp pos)
                                    (or (string-suffix-p pos current-path)
                                        (string= (file-name-nondirectory pos) current-file))))))
                      imenu--index-alist))))))
        ""))

  ;; 読書進捗ヘッダーライン（書籍タイトル・章名・進捗率を表示）
  (defun my/nov-header-line ()
    (condition-case nil
        (if (and (bound-and-true-p nov-documents) (> (length nov-documents) 0))
            (let* ((title (or (alist-get 'title nov-metadata)
                              (if nov-file-name
                                  (file-name-sans-extension (file-name-nondirectory nov-file-name))
                                (buffer-name))))
                   (chap (or (and (fboundp 'nov-current-document-title)
                                  (nov-current-document-title))
                             ""))
                   (idx (1+ (or nov-documents-index 0)))
                   (total (length nov-documents))
                   (pct (/ (* idx 100) (max 1 total))))
              (format " [%s] %s [第 %d/%d 章 (%d%%)]"
                      (propertize title 'face 'bold)
                      (if (string-empty-p chap) "" (format "› %s " (propertize chap 'face 'italic)))
                      idx total pct))
          "")
      (error "")))
  :config
  ;; Windows 対策：Windows 標準の tar.exe を unzip として使う設定
  (when (eq system-type 'windows-nt)
    (setq nov-unzip-program (executable-find "tar")
          nov-unzip-args '("-xC" directory "-f" filename)))

  ;; EPUB内の画像表示をウィンドウサイズの50%を上限に合わせる設定
  (setq shr-max-image-proportion 0.5)

  ;; 章移動時の nov-render-document は shr で大量のDOMを一気に構築するため、
  ;; 標準のGCしきい値のままだと描画中に何度もGCが走ってカクつく・固まって
  ;; 見える原因になる。描画中だけしきい値を一時的に引き上げる。
  (defun my/nov-render-document--boost-gc (orig-fn &rest args)
    (let ((gc-cons-threshold (max gc-cons-threshold (* 256 1024 1024))))
      (apply orig-fn args)))
  (advice-add 'nov-render-document :around #'my/nov-render-document--boost-gc)

  (defun my/nov-mode-hook ()
    (setq-local line-spacing 0.2)
    (setq-local fill-column 80)
    (setq-local header-line-format '((:eval (my/nov-header-line))))
    (visual-line-mode 1))
  (add-hook 'nov-mode-hook #'my/nov-mode-hook)

  ;; nov-mode キーバインド（1行スクロール、半画面スクロール、しおり、本棚、目次）
  (with-eval-after-load 'nov
    (define-key nov-mode-map (kbd "j") (lambda () (interactive) (scroll-up-line 1)))
    (define-key nov-mode-map (kbd "k") (lambda () (interactive) (scroll-down-line 1)))
    (define-key nov-mode-map (kbd "d") #'nov-scroll-up)
    (define-key nov-mode-map (kbd "u") #'nov-scroll-down)
    (define-key nov-mode-map (kbd "m") #'bookmark-set)
    (define-key nov-mode-map (kbd "b") #'bookmark-jump)
    (define-key nov-mode-map (kbd "M") (lambda () (interactive) (if (fboundp 'consult-bookmark) (consult-bookmark) (list-bookmarks))))
    (define-key nov-mode-map (kbd "B") #'my/nov-bookshelf)
    (define-key nov-mode-map (kbd "o") (lambda () (interactive) (if (fboundp 'consult-imenu) (consult-imenu) (imenu))))
    (define-key nov-mode-map (kbd "?") (lambda () (interactive) (if (fboundp 'hydra-nov-help/body) (hydra-nov-help/body) (describe-mode)))))

  ;; nov.el EPUBリーダー 日本語操作ガイド (F1 / ?)
  (defhydra hydra-nov-help (:color blue :hint nil)
    "
  === nov.el EPUBリーダー 操作ガイド ===  [F1 / q] 閉じる
  [スクロール・移動]        [章・目次移動]            [しおり・本棚]
  Space / d : ページ送り    ] / N : 次の章            m : しおりを挟む (Bookmark)
  BS    / u : ページ戻し    [ / P : 前の章            b : しおりへジャンプ
  j     / k : 1行送り/戻し  o     : 目次 (Consult)    M : しおり一覧 (Consult)
  [表示・文字サイズ]        t     : 目次ページ        B : 本棚 (書籍一覧を開く)
  + / - / 0 : 拡大/縮小/標準 F4    : 目次サイドバー    d : 書籍詳細
  ----------------------------------------------------------------------
"
    (" " nov-scroll-up :color blue)
    ("n" nov-scroll-up :color blue)
    ("d" nov-scroll-up :color blue)
    ("<backspace>" nov-scroll-down :color blue)
    ("p" nov-scroll-down :color blue)
    ("u" nov-scroll-down :color blue)
    ("j" (lambda () (interactive) (scroll-up-line 1)) :color blue)
    ("k" (lambda () (interactive) (scroll-down-line 1)) :color blue)
    ("]" nov-next-document :color blue)
    ("N" nov-next-document :color blue)
    ("[" nov-previous-document :color blue)
    ("P" nov-previous-document :color blue)
    ("o" (lambda () (interactive) (if (fboundp 'consult-imenu) (consult-imenu) (imenu))) :color blue)
    ("<f4>" (lambda () (interactive) (if (fboundp 'imenu-list-smart-toggle) (imenu-list-smart-toggle) (speedbar-get-focus))) :color blue)
    ("t" nov-goto-toc :color blue)
    ("m" bookmark-set :color blue)
    ("b" bookmark-jump :color blue)
    ("M" (lambda () (interactive) (if (fboundp 'consult-bookmark) (consult-bookmark) (list-bookmarks))) :color blue)
    ("B" my/nov-bookshelf :color blue)
    ("d" nov-display-metadata :color blue)
    ("+" text-scale-increase :color blue)
    ("-" text-scale-decrease :color blue)
    ("0" (lambda () (interactive) (text-scale-set 0)) :color blue)
    ("q" nil :color blue)
    ("<escape>" nil :color blue)
    ("<f1>" nil :color blue)
    ("<F1>" nil :color blue)))

;; Calibre の ebook-convert を探す（PATH → 環境変数 ProgramFiles 系の順）
(defun my/find-calibre-converter ()
  "ebook-convert.exe のパスを返す。見つからなければ nil。"
  (or (executable-find "ebook-convert")
      (cl-find-if #'file-exists-p
                  (list (expand-file-name "Calibre2/ebook-convert.exe" (or (getenv "ProgramFiles") "C:/Program Files"))
                        (expand-file-name "Calibre2/ebook-convert.exe" (or (getenv "ProgramFiles(x86)") "C:/Program Files (x86)"))))))

;; 電子書籍ライブラリ・本棚機能 (Consult 連携)
(defcustom my/nov-books-directories
  (let ((env-dir (getenv "EBOOKS_DIR")))
    (if (and env-dir (file-directory-p env-dir))
        (list env-dir)
      nil))
  "EPUB / AZW3 書籍ファイルを探索するディレクトリのリスト。
環境変数 `EBOOKS_DIR` または本変数で設定可能です（未設定時は個人フォルダを自動探索しません）。"
  :type '(repeat directory)
  :group 'nov)

(defun my/nov-bookshelf ()
  "本棚メニュー: 最近開いた書籍や指定ディレクトリ内の電子書籍（EPUB/AZW3）を一覧・検索して開きます。"
  (interactive)
  (let ((candidates '()))
    ;; 1. recentf から最近読んだ書籍を収集
    (when (boundp 'recentf-list)
      (dolist (f recentf-list)
        (when (and (stringp f)
                   (string-match-p "\\.\\(epub\\|azw3?\\)\\'" f)
                   (file-exists-p f))
          (push (cons (format "[最近] %s  (%s)"
                              (file-name-nondirectory f)
                              (file-name-directory f))
                      f)
                candidates))))
    ;; 2. 指定ディレクトリから探索
    (dolist (dir my/nov-books-directories)
      (when (and dir (file-directory-p dir))
        (dolist (f (ignore-errors
                     (directory-files-recursively dir "\\.\\(epub\\|azw3?\\)\\'" nil
                                                  (lambda (d) (not (string-match-p "/\\." d))))))
          (let ((entry (cons (format "%s  (%s)"
                                     (file-name-nondirectory f)
                                     (file-name-directory f))
                             f)))
            (unless (rassoc f candidates)
              (push entry candidates))))))
    (setq candidates (nreverse candidates))
    (push (cons "[ファイル選択ダイアログから開く...]" 'choose-file) candidates)
    (let* ((prompt "本棚から開く書籍を選択: ")
           (cands-alist candidates)
           (selected (if (fboundp 'consult--read)
                         (consult--read (mapcar #'car cands-alist) :prompt prompt :sort nil)
                       (completing-read prompt (mapcar #'car cands-alist) nil t)))
           (target (cdr (assoc selected cands-alist))))
      (cond
       ((eq target 'choose-file)
        (my/nov-open-epub))
       (target
        (find-file target))))))

(defun my/nov-open-epub ()
  "EPUB ファイルを選択して開きます。"
  (interactive)
  (let ((file (read-file-name "EPUB を選択: " nil nil t nil
                              (lambda (name)
                                (string-match-p "\\.epub\\'" name)))))
    (when (and file (file-exists-p file))
      (find-file file))))

(defun my/nov-open-kindle-on-the-fly (filename &optional original-buffer)
  "Calibre の ebook-convert を使用して、AZW3/AZW をバックグラウンドで EPUB に変換し、開きます。
ORIGINAL-BUFFER を指定した場合、変換・オープンが完了した後にそのバッファを閉じます
（auto-mode-alist 経由で自動変換したときの、元の AZW/AZW3 バイナリバッファの後始末用）。"
  (interactive "fKindle (AZW3/AZW) ファイルを選択: ")
  (let* ((temp-dir (temporary-file-directory))
         (epub-file (expand-file-name (concat (file-name-base filename) ".epub") temp-dir))
         ;; Calibre のコマンドラインツールを探す（標準のインストールパスも自動探索）
         (converter (my/find-calibre-converter)))
    (cond
     ((not (file-exists-p filename))
      (message "ファイルが存在しません: %s" filename))
     ((not converter)
      (message "【お知らせ】Calibre が見つからないため自動変換できません。手動で EPUB に変換してください。"))
     (t
      (message "Kindle 本から EPUB へ変換中（バックグラウンド処理）...")
      ;; 非同期プロセスで変換（Emacs がフリーズするのを防ぐ）
      (make-process
       :name "kindle-to-epub"
       :buffer nil
       :command (list converter filename epub-file)
       :sentinel (lambda (process event)
                   (when (string-match-p "finished" event)
                     (if (file-exists-p epub-file)
                         (progn
                           (message "変換完了！書籍を開きます。")
                           (find-file epub-file)
                           ;; 変換元の AZW/AZW3 バイナリバッファは役目を終えたので閉じる
                           (when (and original-buffer (buffer-live-p original-buffer))
                             (kill-buffer original-buffer)))
                       (message "エラー: 変換後のファイルが見つかりません。")))))))))

;; .azw と .azw3 ファイルを C-x C-f で開いたときにも自動でこの関数にルーティングする
(defun my/nov-open-kindle-on-the-fly-auto ()
  "auto-mode-alist 経由で AZW/AZW3 ファイルを開くためのラッパー。
EPUB への変換とオープンが終わったら、元の AZW/AZW3 バッファは自動で閉じる。"
  (let ((filename (buffer-file-name))
        (original-buffer (current-buffer)))
    (when filename
      (my/nov-open-kindle-on-the-fly filename original-buffer))))

(dolist (pattern '("\\.azw3\\'" "\\.azw\\'"))
  (add-to-list 'auto-mode-alist (cons pattern #'my/nov-open-kindle-on-the-fly-auto)))


;; =====================================================================
;; 20. ドキュメントビューア ＆ 変換 (xdoc2txt / Pandoc 連携)
;; ─ Word / PDF / Excel 等からテキストを抽出して Emacs 内で直接閲覧
;; ─ 現在のバッファを Pandoc で別形式 (docx, epub, pdf 等) に高速変換
;; =====================================================================

(defun my/document-text-view ()
  "xdoc2txt または pandoc を使って、Word/PDF/Excel などのテキストを抽出し、Emacs 内で直接閲覧します。"
  (interactive)
  (let* ((filename (buffer-file-name))
         (xdoc2txt (executable-find "xdoc2txt.exe"))
         (pandoc (executable-find "pandoc"))
         (ext (and filename (file-name-extension filename))))
    (when filename
      ;; 一旦バッファをクリアし、プレーンテキスト表示にする
      (setq-local buffer-file-name nil)        ; 保存ダイアログが出ないよう nil に設定
      (let ((inhibit-read-only t)
            ;; xdoc2txt には -8 で UTF-8 出力させているので、Emacs側の
            ;; デコードも UTF-8 に固定する（未指定だと環境依存のコーディング
            ;; システム [cp932 等] で解釈されて文字化けすることがある）。
            ;; pandoc の出力も常に UTF-8 なので同様に固定してよい。
            (coding-system-for-read 'utf-8)
            (coding-system-for-write 'utf-8))
        ;; 閲覧専用バッファであり Undo は不要。大きな PDF/Office 文書だと
        ;; erase-buffer + 巨大テキストの insert で undo-outer-limit を超えて
        ;; 警告が出るため、抽出処理の間は Undo 記録自体を止めておく。
        (buffer-disable-undo)
        (erase-buffer)
        (message "テキストを抽出中...")
        (cond
         ;; 1. xdoc2txt があれば最優先で使用 (PDF, docx, xlsx, pptx 等を高速網羅)
         (xdoc2txt
          (call-process xdoc2txt nil t nil "-8" filename))
         ;; 2. xdoc2txt がなく、pandoc があり、対象が docx などの場合
         ((and pandoc (member ext '("docx" "epub" "html" "md" "rst")))
          (call-process pandoc nil t nil "-t" "plain" filename))
         ;; 3. どちらもない場合
         (t
          (insert "エラー: xdoc2txt または pandoc が見つかりません。\n"
                  "バイナリファイルのテキスト抽出機能を利用するには、いずれかの実行ファイルを PATH に追加してください。")))
        ;; バッファ自体のコーディングシステムも UTF-8 に固定しておく
        ;; （保存はしないが、表示・再検索・コピー時の扱いを安定させるため）
        (set-buffer-file-coding-system 'utf-8 t)
        (goto-char (point-min))
        (set-buffer-modified-p nil)
        (view-mode 1)
        (message "テキスト抽出完了 (閲覧モード)")))))

;; 各種ドキュメントファイルを C-x C-f で開いたときに自動でテキスト閲覧モードにする
(dolist (pattern '("\\.docx\\'" "\\.pdf\\'" "\\.xlsx\\'" "\\.pptx\\'"
                   "\\.doc\\'" "\\.xls\\'" "\\.ppt\\'"
                   "\\.jtd\\'" "\\.jtt\\'"   ; 一太郎
                   "\\.eml\\'"))             ; メール (Outlook Express形式)
  (add-to-list 'auto-mode-alist (cons pattern #'my/document-text-view)))

(defun my/pandoc-convert-to-format (out-format)
  "現在のバッファ（Markdown等）を Pandoc を使って別フォーマットに変換します。"
  (interactive
   (list (completing-read "出力フォーマット: "
                          '("epub" "html" "pdf" "docx" "odt" "org" "markdown" "plain"))))
  (let* ((filename (buffer-file-name))
         (pandoc (executable-find "pandoc")))
    (cond
     ((not filename)
      (message "エラー: バッファをファイルとして保存してから実行してください。"))
     ((not pandoc)
      (message "エラー: pandoc が見つかりません。PATH に追加してください。"))
     (t
      (let* ((out-file (concat (file-name-sans-extension filename) "." out-format))
             (exit-code (call-process pandoc nil nil nil
                                      filename "-o" out-file)))
        (if (= exit-code 0)
            (message "変換完了！出力先: %s" (file-name-nondirectory out-file))
          (message "エラー: 変換に失敗しました。")))))))

(defun my/epub-to-kindle-convert (filename &optional format)
  "EPUB ファイルを AZW または AZW3 形式に変換します。"
  (interactive
   (let* ((current-file (buffer-file-name))
          (default-file (and current-file
                             (string-match-p "\\.epub\\'" current-file)
                             current-file))
          (file (read-file-name "EPUB ファイルを選択: " nil default-file t nil
                                (lambda (name)
                                  (or (file-directory-p name)
                                      (string-match-p "\\.epub\\'" name)))))
          (fmt (completing-read "出力形式: " '("azw3" "azw" "both") nil t "both")))
     (list file fmt)))
  (let* ((converter (my/find-calibre-converter))
         (format (or format "both")))
    (cond
     ((not (file-exists-p filename))
      (message "ファイルが存在しません: %s" filename))
     ((not converter)
      (message "【お知らせ】Calibre (ebook-convert.exe) が見つかりませんでした。インストールパスを確認してください。"))
     (t
      (let ((formats (if (string= format "both") '("azw" "azw3") (list format))))
        (dolist (fmt formats)
          (let* ((out-file (concat (file-name-sans-extension filename) "." fmt))
                 (out-name (file-name-nondirectory out-file)))
            (message "%s へ変換中（バックグラウンド処理）..." out-name)
            (make-process
             :name (concat "epub-to-" fmt)
             :buffer nil
             :command (list converter filename out-file)
             :sentinel (lambda (process event)
                         (when (string-match-p "finished" event)
                           (message "変換完了！出力先: %s" out-file)))))))))))


;; =====================================================================
;; 21. CSV モード
;; =====================================================================
;; rainbow-csv は MELPA 未登録のため、csv-mode 標準のフィールド番号表示で代用
;; （モードラインに現在の列番号が表示される）

(use-package csv-mode
  :ensure t
  :mode ("\.csv\'" "\.tsv\'")
  :config
  (setq csv-separators '("," "\t")))  ; カンマとタブ両対応


;; =====================================================================
;; 21b. Mozc 日本語入力（モードレス）
;; =====================================================================
;; 前提:
;;   - Windows に本家「Google 日本語入力」がインストールされていること
;;     （※mozkey 等ではなく本家本体が必要。常用する既定IMEにしておく必要はありません）
;;   - mozc_emacs_helper.exe を bin/ に配置済み
;;     (https://github.com/smzht/mozc_emacs_helper の ver_2.31.5810.100)

(use-package mozc
  :ensure t
  :if my/use-mozc-modeless
  :config
  (setq default-input-method "japanese-mozc")
  (setq mozc-helper-program-name
        (let ((portable (expand-file-name "bin/mozc_emacs_helper.exe"
                                           (expand-file-name ".." user-emacs-directory))))
          (if (file-exists-p portable)
              portable
            "mozc_emacs_helper")))


  ;; Windows の mozc では SendKey 応答が direct モードなら hiragana に切り替える
  (advice-add 'mozc-session-execute-command :filter-return
              (lambda (output)
                (when (and output
                           (eq (mozc-protobuf-get output 'output 'mode) 'direct))
                  (mozc-session-sendkey '(Hankaku/Zenkaku)))
                output))

  ;; SJIS など UTF-8 以外のバッファでも mozc_emacs_helper との通信が
  ;; 文字化けしないよう、通信時のコーディングシステムを UTF-8 に固定する。
  ;; （カレントバッファのエンコーディングに process-coding-system が
  ;;   引っ張られて文字化けする問題への対処）
  ;; ※ "Wrong response from the Server" エラーが出るため一時的に無効化
  ;; (advice-add 'mozc-session-execute-command :around
  ;;             (lambda (orig &rest args)
  ;;               (let ((coding-system-for-read  'utf-8)
  ;;                     (coding-system-for-write 'utf-8))
  ;;                 (apply orig args))))
  )

(use-package mozc-modeless
  :ensure t
  :if my/use-mozc-modeless
  :after mozc
  :config
  (global-mozc-modeless-mode 1)

  ;; C-\ で mozc-mode を手動 ON/OFF できるようにする
  ;; OFF 時は deactivate の抑制をスキップする
  (defvar my/mozc-manual-off nil
    "Non-nil なら mozc-mode を手動で OFF にしている状態。")

  (defun my/mozc-toggle ()
    "mozc-mode を手動でトグルする。"
    (interactive)
    (if my/mozc-manual-off
        ;; OFF → ON
        (progn
          (setq my/mozc-manual-off nil)
          (activate-input-method "japanese-mozc")
          (message "Mozc ON"))
      ;; ON → OFF
      (progn
        (setq my/mozc-manual-off t)
        (deactivate-input-method)
        (message "Mozc OFF"))))

  (global-set-key (kbd "C-\\") #'my/mozc-toggle)

  ;; M-<kanji>（Alt+漢字／Alt+E/J）は IME 切り替え時の誤爆イベントなので無視する
  (global-set-key (kbd "M-<kanji>") #'ignore)
  (with-eval-after-load 'mozc-modeless
    (define-key mozc-modeless-mode-map (kbd "M-<kanji>") #'ignore))

  ;; deactivate-input-method が mozc-mode をバッファローカルに OFF に
  ;; してしまうのを防ぐ（手動OFFのときは抑制しない）
  (defun my/mozc-modeless-inhibit-deactivate (&rest _args)
    (when (and (bound-and-true-p mozc-modeless-mode)
               (not my/mozc-manual-off))
      (setq current-input-method "japanese-mozc")))
  (advice-add 'deactivate-input-method :after
              #'my/mozc-modeless-inhibit-deactivate)

)





;; =====================================================================
;; 23. GhostText 連携（ブラウザ入力欄の編集）
;; =====================================================================
;; ブラウザの GhostText 拡張機能と連携し、Emacs でブラウザ上のテキストエリアを
;; リアルタイム編集できるようにします。
;; =====================================================================

(use-package atomic-chrome
  :ensure t
  :config
  ;; デフォルトのメジャーモード（多くの入力欄がMarkdownであるため）
  (setq atomic-chrome-default-major-mode 'markdown-mode)
  ;; 同一フレーム内の新しいウィンドウでバッファを開く
  (setq atomic-chrome-buffer-open-style 'window)
  ;; ドメインとメジャーモードの対応マップ
  (setq atomic-chrome-url-major-mode-alist
        '(("github\\.com" . gfm-mode)
          ("qiita\\.com" . markdown-mode)
          ("zenn\\.dev" . markdown-mode)
          ("backlog\\.jp" . markdown-mode)
          ("slack\\.com" . markdown-mode)))

  ;; WebSocket切断時にバッファが自動キルされるのを防ぐアドバイス
  (defun my/atomic-chrome-on-close-no-kill (socket)
    "WebSocket切断時にバッファをキルせず、編集中のデータを保護します。"
    (let ((buffer (atomic-chrome-get-buffer-by-socket socket)))
      (when buffer
        (remhash buffer atomic-chrome-buffer-table)
        (ignore-errors (websocket-close socket)) ; 明示的にソケットをクローズしてブラウザ側の青枠を消す
        (message "GhostText: 接続が切断されました。編集内容を保護するためバッファを維持します。"))))
  (advice-add 'atomic-chrome-on-close :override #'my/atomic-chrome-on-close-no-kill)

  ;; 連携用 WebSocket サーバーを起動
  (atomic-chrome-start-server))


;; =====================================================================
;; GUIカスタマイズ設定（custom-set-variables）は、init.elの先頭で
;; custom.el を読み込むことで一本化されています。
;; =====================================================================

;; =====================================================================
;; 右クリックメニュー（EmEditor 風コンテキストメニュー）
;; =====================================================================
;; Emacs 28 以降の context-menu-mode を使用します。
;; =====================================================================

(require 'url-util)
(require 'japan-util)  ; 全角↔半角・ひらがな↔カタカナ変換

;; 右クリックメニューを有効化
(when (fboundp 'context-menu-mode)
  (context-menu-mode 1))

;; --- 補助関数 ---

(defun my/ctx-google-search (click)
  "選択範囲またはクリック位置の単語を Google で検索します。"
  (interactive "e")
  (let ((phrase (if (use-region-p)
                    (buffer-substring-no-properties (region-beginning) (region-end))
                  (save-excursion
                    (mouse-set-point click)
                    (thing-at-point 'word t)))))
    (if (and phrase (not (string-empty-p phrase)))
        (browse-url (concat "https://www.google.com/search?q=" (url-hexify-string phrase)))
      (message "検索するテキストが見つかりません"))))

(defun my/ctx-url-encode-region (start end)
  "選択範囲を URL エンコードします。"
  (interactive "r")
  (let ((encoded (url-hexify-string (buffer-substring-no-properties start end))))
    (delete-region start end)
    (insert encoded)))

(defun my/ctx-url-decode-region (start end)
  "選択範囲を URL デコードします。"
  (interactive "r")
  (let ((decoded (url-unhex-string (buffer-substring-no-properties start end))))
    (delete-region start end)
    (insert decoded)))

(defun my/ctx-copy-file-path ()
  "編集中ファイルのフルパスをクリップボードにコピーします。"
  (interactive)
  (if buffer-file-name
      (let ((path (file-truename buffer-file-name)))
        (kill-new path)
        (message "パスをコピーしました: %s" path))
    (message "このバッファはファイルに関連付けられていません")))

(defun my/ctx-copy-file-name ()
  "編集中ファイルのファイル名（拡張子付き）のみをクリップボードにコピーします。"
  (interactive)
  (if buffer-file-name
      (let ((name (file-name-nondirectory buffer-file-name)))
        (kill-new name)
        (message "ファイル名をコピーしました: %s" name))
    (message "このバッファはファイルに関連付けられていません")))

(defun my/ctx-copy-dir-path ()
  "編集中ファイルのディレクトリパスをクリップボードにコピーします。"
  (interactive)
  (if buffer-file-name
      (let ((dir (file-name-directory (file-truename buffer-file-name))))
        (kill-new dir)
        (message "フォルダパスをコピーしました: %s" dir))
    (message "このバッファはファイルに関連付けられていません")))

(defun my/ctx-open-folder ()
  "ファイルの保存先フォルダをエクスプローラーで開きます。"
  (interactive)
  (if buffer-file-name
      (let ((dir (file-name-directory (file-truename buffer-file-name))))
        (w32-shell-execute "explore" (subst-char-in-string ?/ ?\\ dir))
        (message "エクスプローラーで開きました: %s" dir))
    (message "このバッファはファイルに関連付けられていません")))

(defun my/ctx-calc-onthespot ()
  "xyzzy の calc-onthespot 風: 選択範囲または直前の数式を計算して置き換えます。

動作:
  ・テキストを選択している場合 → 選択範囲全体を数式として評価
  ・選択がない場合             → カーソル直前の数式を自動検出して評価

検出できる文字: 数字 / + - * / ^ ( ) . , % ! スペース タブ"
  (interactive)
  (let* ((start (if (use-region-p)
                    (region-beginning)
                  ;; カーソル直前の数式を自動検出（xyzzy 風）
                  (save-excursion
                    (skip-chars-backward "-0-9.+*/^(), \t%!")
                    (point))))
         (end   (if (use-region-p) (region-end) (point)))
         (expr  (string-trim (buffer-substring-no-properties start end))))
    (cond
     ((string-empty-p expr)
      (message "数式が見つかりません（カーソル直前に数式を入力してください）"))
     (t
      (let ((result (condition-case err
                        (calc-eval expr)
                      (error (format "[ERROR: %s]" (error-message-string err))))))
        (if (string-prefix-p "[" result)
            (message "計算エラー: %s  (式: %s)" result expr)
          (when (use-region-p) (deactivate-mark))
          (delete-region start end)
          (insert result)
          (message "%s = %s" expr result)))))))

(defun my/ctx-insert-line-prefix (prefix)
  "選択範囲の各行、または現在の行の行頭に指定のプレフィックスを挿入します。"
  (let ((start (if (use-region-p) (region-beginning) (line-beginning-position)))
        (end (if (use-region-p) (region-end) (line-end-position))))
    (save-excursion
      (goto-char start)
      (beginning-of-line)
      (let ((end-marker (copy-marker end)))
        (while (< (point) end-marker)
          (insert prefix)
          (forward-line 1))
        (set-marker end-marker nil)))))

(defun my/ctx-delete-line-prefix (regexp)
  "選択範囲の各行、または現在の行の行頭にある指定の正規表現パターンを削除します。"
  (let ((start (if (use-region-p) (region-beginning) (line-beginning-position)))
        (end (if (use-region-p) (region-end) (line-end-position))))
    (save-excursion
      (goto-char start)
      (beginning-of-line)
      (let ((end-marker (copy-marker end)))
        (while (< (point) end-marker)
          (if (looking-at regexp)
              (replace-match ""))
          (forward-line 1))
        (set-marker end-marker nil)))))

(defun my/ctx-add-quote ()
  "選択範囲の各行または現在の行 of 行頭に '>' を挿入します。"
  (interactive)
  (my/ctx-insert-line-prefix "> ")
  (message "行頭に引用記号 (>) を挿入しました"))

(defun my/ctx-remove-quote ()
  "選択範囲の各行または現在の行 of 行頭の '>' を削除します。"
  (interactive)
  (my/ctx-delete-line-prefix "^> ?")
  (message "行頭の引用記号 (>) を削除しました"))

;; --- コンテキストメニュー本体 ---

(defun my/context-menu-popup-search (e)
  "選択範囲またはカーソル下の単語で小窓（posframe）検索を開きます。"
  (interactive "e")
  (unless (use-region-p) (mouse-set-point e))
  (my/consult-line-symbol-at-point))

(defun my/gptel-context-send (e &optional task-prompt)
  "右クリックメニューから選択範囲（またはバッファ全体）をAIに送信し、
*AI-Response* バッファに回答を表示します。
送信直後に選択範囲のハイライトを解除します。"
  (interactive "e")
  (unless (use-region-p) (mouse-set-point e))
  (require 'gptel)
  (let* ((has-region (use-region-p))
         (src-text (if has-region
                       (buffer-substring-no-properties (region-beginning) (region-end))
                     (buffer-substring-no-properties (point-min) (point-max))))
         (src-mode major-mode)
         (src-file (buffer-name))
         (instruction (or task-prompt
                          (read-string "AIへの指示・質問: "))))
    ;; 送信直後に選択ハイライトを解除（選択範囲が消えない問題の解消）
    (when (use-region-p)
      (deactivate-mark))
    (when (or (null instruction) (string-blank-p instruction))
      (user-error "指示がキャンセルされました"))
    (let* ((resp-buf (get-buffer-create "*AI-Response*"))
           (backend-name (if (and (boundp 'gptel-backend) gptel-backend)
                             (gptel-backend-name gptel-backend)
                           "AI"))
           (full-prompt (format "%s\n\n```%s\n%s\n```"
                                instruction
                                (replace-regexp-in-string "-mode$" "" (symbol-name src-mode))
                                src-text)))
      ;; レスポンスバッファを準備
      (with-current-buffer resp-buf
        (let ((inhibit-read-only t))
          (erase-buffer)
          (if (fboundp 'markdown-mode)
              (markdown-mode)
            (text-mode))
          (insert (format "# %s アシスタントへの問い合わせ\n\n- **対象**: `%s` (%s)\n- **指示**: %s\n\n---\n\n*回答を受信中...*\n\n"
                          backend-name
                          src-file
                          (if has-region "選択範囲" "バッファ全体")
                          instruction))))
      (display-buffer resp-buf)
      ;; gptel-request で非同期リクエスト
      (gptel-request full-prompt
        :callback
        (lambda (response info)
          (if (not response)
              (with-current-buffer resp-buf
                (let ((inhibit-read-only t))
                  (goto-char (point-max))
                  (insert "\n\n**エラー**: AIからの応答を受信できませんでした。")))
            (with-current-buffer resp-buf
              (let ((inhibit-read-only t))
                (goto-char (point-max))
                (if (search-backward "*回答を受信中...*" nil t)
                    (delete-region (match-beginning 0) (point-max))
                  (goto-char (point-max)))
                (insert response "\n\n---\n*完了*"))))))
      (message "AI (%s) へ問い合わせを送信しました..." backend-name))))

(defun my/gptel-send-to-chat (e)
  "選択範囲（またはバッファ全体）をチャットバッファ *AI-Chat* に転送して開きます。"
  (interactive "e")
  (unless (use-region-p) (mouse-set-point e))
  (require 'gptel)
  (let* ((has-region (use-region-p))
         (src-text (if has-region
                       (buffer-substring-no-properties (region-beginning) (region-end))
                     (buffer-substring-no-properties (point-min) (point-max))))
         (src-mode major-mode)
         (src-file (buffer-name)))
    (when (use-region-p)
      (deactivate-mark))
    (let ((chat-buf (gptel "*AI-Chat*")))
      (with-current-buffer chat-buf
        (goto-char (point-max))
        (unless (bolp) (insert "\n"))
        (insert (format "\n【%s (%s)】\n```%s\n%s\n```\n\n"
                        src-file
                        (if has-region "選択範囲" "バッファ全体")
                        (replace-regexp-in-string "-mode$" "" (symbol-name src-mode))
                        src-text)))
      (pop-to-buffer chat-buf)
      (message "チャットバッファに対象テキストを転送しました。"))))

(defun my/emeditor-context-menu (menu click)
  "EmEditor 風の右クリックメニュー項目を追加します。"

  ;; ── 区切り線 ──
  (define-key-after menu [my-sep-top] menu-bar-separator)

  ;; ── バッファ内検索（C-c l / popup-search 相当）──
  (define-key-after menu [my-popup-search]
    '(menu-item "バッファ内検索 (popup-search)"
                my/context-menu-popup-search
                :keys "C-c l"
                :help "選択範囲またはカーソル下の単語でバッファ内をライブ検索します"))

  ;; ── EmEditor フィルタ風・wgrep ──
  (define-key-after menu [my-filter]
    `(menu-item "フィルタ: マッチ行だけ表示・編集"
                (lambda (_e) (interactive "e") (my/emeditor-filter))
                :keys "C-c f"
                :help "EmEditorのフィルタ風：検索ワードにマッチした行だけを表示し、直接編集できます"))

  (define-key-after menu [my-wgrep]
    `(menu-item "複数ファイル一括置換 (wgrep)"
                (lambda (_e) (interactive "e") (my/wgrep-replace))
                :keys "C-c F"
                :help "ripgrep で複数ファイルを検索し、結果を直接編集して一括保存します"))

  ;; ── Google 検索 ──
  (define-key-after menu [my-google-search]
    `(menu-item "Googleで検索"
                (lambda (e) (interactive "e") (my/ctx-google-search e))
                :help "選択範囲またはカーソル下の単語をGoogleで検索します"))

  ;; ── 変換サブメニュー ──
  (let ((conv-map (make-sparse-keymap "変換")))
    ;; 大文字/小文字
    (define-key conv-map [upcase]
      '(menu-item "大文字にする (ABC)" upcase-region
                  :help "選択範囲を大文字にします"
                  :enable (use-region-p)))
    (define-key conv-map [downcase]
      '(menu-item "小文字にする (abc)" downcase-region
                  :help "選択範囲を小文字にします"
                  :enable (use-region-p)))
    (define-key conv-map [capitalize]
      '(menu-item "先頭文字を大文字に (Abc)" capitalize-region
                  :help "各単語の先頭を大文字にします"
                  :enable (use-region-p)))
    (define-key conv-map [conv-sep1] menu-bar-separator)
    ;; エンコード
    (define-key conv-map [url-encode]
      '(menu-item "URLエンコード" my/ctx-url-encode-region
                  :help "選択範囲をURLエンコードします"
                  :enable (use-region-p)))
    (define-key conv-map [url-decode]
      '(menu-item "URLデコード" my/ctx-url-decode-region
                  :help "選択範囲をURLデコードします"
                  :enable (use-region-p)))
    (define-key conv-map [conv-sep2] menu-bar-separator)
    (define-key conv-map [base64-encode]
      '(menu-item "Base64エンコード" base64-encode-region
                  :help "選択範囲をBase64エンコードします"
                  :enable (use-region-p)))
    (define-key conv-map [base64-decode]
      '(menu-item "Base64デコード" base64-decode-region
                  :help "選択範囲をBase64デコードします"
                  :enable (use-region-p)))
    (define-key conv-map [conv-sep3] menu-bar-separator)
    ;; 全角・半角・ひらがな・カタカナ変換（japan-util.el 標準関数）
    (define-key conv-map [zenkaku-to-hankaku]
      '(menu-item "全角→半角" japanese-hankaku-region
                  :help "選択範囲の全角文字を半角に変換します"
                  :enable (use-region-p)))
    (define-key conv-map [hankaku-to-zenkaku]
      '(menu-item "半角→全角" japanese-zenkaku-region
                  :help "選択範囲の半角文字を全角に変換します"
                  :enable (use-region-p)))
    (define-key conv-map [conv-sep4] menu-bar-separator)
    (define-key conv-map [hira-to-kata]
      '(menu-item "ひらがな→カタカナ" japanese-katakana-region
                  :help "選択範囲のひらがなをカタカナに変換します"
                  :enable (use-region-p)))
    (define-key conv-map [kata-to-hira]
      '(menu-item "カタカナ→ひらがな" japanese-hiragana-region
                  :help "選択範囲のカタカナをひらがなに変換します"
                  :enable (use-region-p)))
    (define-key conv-map [conv-sep5] menu-bar-separator)
    ;; 数式計算（xyzzy の calc-onthespot 風：選択なしでもカーソル前を自動検出）
    (define-key conv-map [calc-spot]
      '(menu-item "数式をその場で計算" my/ctx-calc-onthespot
                  :keys "C-c ="
                  :help "選択範囲 or カーソル直前の数式を自動検出して計算・置換します"))
    (define-key conv-map [conv-sep6] menu-bar-separator)
    ;; TAB→スペース変換（選択範囲があれば選択内のみ、なければバッファ全体）
    (define-key conv-map [tab-to-space]
      '(menu-item "TAB→スペースに変換 (untabify)"
                  (lambda () (interactive)
                    (if (use-region-p)
                        (untabify (region-beginning) (region-end))
                      (untabify (point-min) (point-max)))
                    (message "TABをスペースに変換しました"))
                  :help "TAB文字をスペースに変換します（選択範囲 or バッファ全体）"))
    ;; スペース→TAB変換（逆変換）
    (define-key conv-map [space-to-tab]
      '(menu-item "スペース→TABに変換 (tabify)"
                  (lambda () (interactive)
                    (if (use-region-p)
                        (tabify (region-beginning) (region-end))
                      (tabify (point-min) (point-max)))
                    (message "スペースをTABに変換しました"))
                  :help "スペースをTAB文字に変換します（選択範囲 or バッファ全体）"))
    (define-key-after menu [my-conv-submenu]
      `(menu-item "変換" ,conv-map :help "大文字小文字やエンコードの変換")))

  ;; ── 行操作サブメニュー ──
  (let ((line-map (make-sparse-keymap "行操作")))
    (define-key line-map [sort-asc]
      '(menu-item "行を昇順でソート" sort-lines
                  :help "選択範囲の行を昇順にソートします"
                  :enable (use-region-p)))
    (define-key line-map [sort-desc]
      '(menu-item "行を降順でソート"
                  (lambda () (interactive)
                    (sort-lines t (region-beginning) (region-end)))
                  :help "選択範囲の行を降順にソートします"
                  :enable (use-region-p)))
    (define-key line-map [dedup]
      '(menu-item "重複行の削除" delete-duplicate-lines
                  :help "選択範囲内の重複した行を削除します"
                  :enable (use-region-p)))
    (define-key line-map [line-sep1] menu-bar-separator)
    (define-key line-map [add-quote]
      '(menu-item "行頭に引用記号 [> ] を挿入" my/ctx-add-quote
                  :help "選択範囲の各行、または現在の行の行頭に引用記号を追加します"))
    (define-key line-map [remove-quote]
      '(menu-item "行頭の引用記号 [>] を削除" my/ctx-remove-quote
                  :help "選択範囲の各行、または現在の行の行頭にある引用記号を削除します"))
    (define-key-after menu [my-line-submenu]
      `(menu-item "行操作" ,line-map :help "ソートや重複行削除")))

  ;; ── ファイル/フォルダサブメニュー ──
  (let ((file-map (make-sparse-keymap "ファイル/フォルダ")))
    (define-key file-map [copy-fullpath]
      '(menu-item "フルパスをコピー" my/ctx-copy-file-path
                  :help "ファイルの絶対パスをクリップボードにコピーします"
                  :enable buffer-file-name))
    (define-key file-map [copy-filename]
      '(menu-item "ファイル名のみコピー" my/ctx-copy-file-name
                  :help "ファイル名（拡張子付き）をコピーします"
                  :enable buffer-file-name))
    (define-key file-map [copy-dirpath]
      '(menu-item "フォルダパスをコピー" my/ctx-copy-dir-path
                  :help "ファイルが存在するフォルダのパスをコピーします"
                  :enable buffer-file-name))
    (define-key file-map [file-sep1] menu-bar-separator)
    (define-key file-map [open-explorer]
      '(menu-item "エクスプローラーで開く" my/ctx-open-folder
                  :help "ファイルの保存先フォルダをエクスプローラーで開きます"
                  :enable buffer-file-name))
    (define-key file-map [open-assoc]
      '(menu-item "関連付けアプリで開く" my-open-current-file-in-windows
                  :help "Windowsの関連付けプログラムでファイルを開きます"
                  :enable buffer-file-name))
    (define-key file-map [file-sep2] menu-bar-separator)
    (define-key file-map [winmerge]
      '(menu-item "WinMergeで差分比較" my-compare-with-winmerge
                  :help "WinMergeで現在のファイルを差分比較します"
                  :enable buffer-file-name))
    (define-key-after menu [my-file-submenu]
      `(menu-item "ファイル/フォルダ" ,file-map :help "パスのコピーやエクスプローラー起動")))

  ;; ── AI アシスタント サブメニュー（最下部に独立配置） ──
  (define-key-after menu [my-ai-sep] menu-bar-separator)
  (let ((ai-map (make-sparse-keymap "AI アシスタント")))
    (define-key ai-map [agy-send-dwim]
      '(menu-item "Antigravity CLI (PowerShell) に送信..."
                  (lambda (e) (interactive "e")
                    (unless (use-region-p) (mouse-set-point e))
                    (call-interactively #'my/agy-send-dwim))
                  :help "選択範囲（またはバッファ全体）を Antigravity CLI (PowerShell) に送信します"))
    (define-key ai-map [agy-menu]
      '(menu-item "AI & Antigravity メニュー (Hydra)"
                  (lambda () (interactive) (hydra-ai/body))
                  :keys "M-o A"
                  :help "AI アシスタントと Antigravity の全操作メニューを開きます"))
    (define-key ai-map [ai-sep0] menu-bar-separator)
    (define-key ai-map [ask-prompt]
      '(menu-item "質問・指示を入力して送信 (gptel)..."
                  (lambda (e) (interactive "e") (my/gptel-context-send e))
                  :help "選択範囲（またはバッファ全体）についてAIに自由に質問・指示します"))
    (define-key ai-map [ai-sep1] menu-bar-separator)
    (define-key ai-map [explain]
      '(menu-item "コード／文章を解説"
                  (lambda (e) (interactive "e")
                    (my/gptel-context-send e "以下のコード／文章を分かりやすく日本語で解説してください：\n\n"))
                  :help "選択範囲（またはバッファ）を分かりやすく解説させます"))
    (define-key ai-map [refactor]
      '(menu-item "リファクタリング・改善案"
                  (lambda (e) (interactive "e")
                    (my/gptel-context-send e "以下のコードの品質・可読性・パフォーマンスを改善したコードと理由を提示してください：\n\n"))
                  :help "コードの改善案と修正コードを提示させます"))
    (define-key ai-map [proofread]
      '(menu-item "文章を校正・推敲"
                  (lambda (e) (interactive "e")
                    (my/gptel-context-send e "以下の文章の誤字脱字を直し、より自然で分かりやすい文章に推敲してください：\n\n"))
                  :help "文章の校正と改善案を提示させます"))
    (define-key ai-map [send-to-chat]
      '(menu-item "チャットバッファに転送"
                  (lambda (e) (interactive "e") (my/gptel-send-to-chat e))
                  :help "選択範囲（またはバッファ）をチャットバッファに貼り付けて開きます"))
    (define-key ai-map [ai-sep2] menu-bar-separator)
    (define-key ai-map [open-chat]
      '(menu-item "チャットバッファを開く"
                  (lambda () (interactive) (gptel "*AI-Chat*"))
                  :keys "C-c g g"
                  :help "AI との対話バッファを開きます"))
    (define-key ai-map [add-context]
      '(menu-item "このバッファをコンテキストに追加"
                  (lambda () (interactive) (call-interactively #'gptel-add))
                  :help "現在のバッファ内容をチャットの前提情報として添付します"))
    (define-key ai-map [gptel-menu]
      '(menu-item "モデル切替・設定 (gptel メニュー)"
                  (lambda () (interactive) (call-interactively #'gptel-menu))
                  :keys "C-c g m"
                  :help "使用モデル(Qwen/OpenAI/Claude等)やパラメータを変更します"))
    (define-key-after menu [my-ai-submenu]
      `(menu-item "AI アシスタント" ,ai-map :help "LLM / Antigravity を使った質問・指示・対話")))

  menu)

;; フックに登録
;; t（末尾追加）を指定することで、標準の Cut/Copy/Paste が上に、
;; カスタム項目が下に来るようにする
(add-hook 'context-menu-functions #'my/emeditor-context-menu t)

;; *scratch* など「ファイルと紐付かないバッファ」が
;; tr-ime / set-language-environment の影響で SJIS (japanese-cp932)
;; になってしまう問題への最終対策。
;; 全初期化が終わった後に強制的に UTF-8 へ戻す。
(add-hook 'after-init-hook
          (lambda ()
            (setq-default buffer-file-coding-system 'utf-8)
            (with-current-buffer "*scratch*"
              (set-buffer-file-coding-system 'utf-8 t))))

;; =====================================================================
;; 24. リアルタイム置換 (visual-replace)
;; ─ 標準の M-% (通常置換) や C-M-% (正規表現置換) の挙動を置き換え、
;;   入力中にリアルタイムでバッファ上にプレビューを表示します
;; =====================================================================
(use-package visual-replace
  :ensure t
  :config
  (visual-replace-global-mode 1)
  ;; ※注意: ここでデフォルトを t にすると選択範囲が無視されるため、nilのままにします。
  ;; 選択範囲がない場合の「全体置換」はスマートコマンド側で制御します。
  (setq visual-replace-default-to-full-scope nil) 

  ;; スマート通常置換コマンド
  (defun my/visual-replace-smart ()
    "選択範囲があれば選択範囲、なければバッファ全体を対象にして通常置換を起動します。"
    (interactive)
    (let ((visual-replace-default-to-full-scope (not (use-region-p))))
      (call-interactively 'visual-replace)))

  ;; スマート正規表現置換コマンド
  (defun my/visual-replace-regexp-smart ()
    "選択範囲があれば選択範囲、なければバッファ全体を対象にして正規表現置換を起動します。"
    (interactive)
    (let ((visual-replace-default-to-full-scope (not (use-region-p)))
          (visual-replace-defaults-hook '(visual-replace-toggle-regexp)))
      (call-interactively 'visual-replace)))

  ;; ポップアップメニューを定義（選択範囲の有無で表示を切り替え）
  (defun my/visual-replace-menu ()
    "置換オプションのポップアップメニューを表示します。"
    (interactive)
    (let ((map (make-sparse-keymap "置換オプション")))
      (if (use-region-p)
          ;; 選択範囲がある場合（逆順に登録）
          (progn
            (define-key map [regexp-region]
              '(menu-item "正規表現置換 (選択範囲のみ)"
                          (lambda () (interactive)
                            (let ((visual-replace-defaults-hook '(visual-replace-toggle-regexp))
                                  (visual-replace-default-to-full-scope nil))
                              (call-interactively 'visual-replace)))
                          :keys "C-M-%"))
            (define-key map [normal-region]
              '(menu-item "通常置換 (選択範囲のみ)"
                          (lambda () (interactive)
                            (let ((visual-replace-defaults-hook nil)
                                  (visual-replace-default-to-full-scope nil))
                              (call-interactively 'visual-replace)))
                          :keys "M-%"))
            (define-key map [normal-full-forced]
              '(menu-item "通常置換 (バッファ全体に強制)"
                          (lambda () (interactive)
                            (let ((visual-replace-defaults-hook nil)
                                  (visual-replace-default-to-full-scope t))
                              (deactivate-mark)
                              (call-interactively 'visual-replace))))))
        ;; 選択範囲がない場合（逆順に登録）
        (progn
          (define-key map [regexp-from]
            '(menu-item "正規表現置換 (カーソル位置から)"
                        (lambda () (interactive)
                          (let ((visual-replace-defaults-hook '(visual-replace-toggle-regexp))
                                (visual-replace-default-to-full-scope nil))
                            (call-interactively 'visual-replace)))))
          (define-key map [regexp-full]
            '(menu-item "正規表現置換 (バッファ全体)"
                        (lambda () (interactive)
                          (let ((visual-replace-defaults-hook '(visual-replace-toggle-regexp))
                                (visual-replace-default-to-full-scope t))
                            (call-interactively 'visual-replace)))
                        :keys "C-M-%"))
          (define-key map [normal-from]
            '(menu-item "通常置換 (カーソル位置から)"
                        (lambda () (interactive)
                          (let ((visual-replace-defaults-hook nil)
                                (visual-replace-default-to-full-scope nil))
                            (call-interactively 'visual-replace)))))
          (define-key map [normal-full]
            '(menu-item "通常置換 (バッファ全体)"
                        (lambda () (interactive)
                          (let ((visual-replace-defaults-hook nil)
                                (visual-replace-default-to-full-scope t))
                            (call-interactively 'visual-replace)))
                        :keys "M-%"))))
      (popup-menu map)))

  ;; C-h をヘルプから解放して置換に割り当てる（Windows的な"Ctrl+H=置換"の
  ;; 感覚に合わせる）。ヘルプ機能自体はEmacs標準でF1にも同じ
  ;; help-command が既定で割り当たっているため、F1に一本化する形で残る。
  (global-set-key (kbd "C-h") #'my/visual-replace-menu)

  ;; キーバインドの設定
  (global-set-key (kbd "M-%") 'my/visual-replace-smart)
  (global-set-key (kbd "C-M-%") 'my/visual-replace-regexp-smart)

  ;; 置換入力中に C-r または M-r で正規表現の ON/OFF をトグル可能にする
  (define-key visual-replace-mode-map (kbd "C-r") 'visual-replace-toggle-regexp)
  (define-key visual-replace-mode-map (kbd "M-r") 'visual-replace-toggle-regexp)

  ;; Isearch中から文字列を引き継いで起動するキーバインド
  (define-key isearch-mode-map (kbd "M-%") 'visual-replace-from-isearch)

  ;; ミニバッファ（consult-line等）に入力された文字列を引き継いで起動するコマンド
  (defun my/visual-replace-from-minibuffer ()
    "ミニバッファに入力されている文字列を検索パターンとして、元のバッファで `visual-replace` を起動します。"
    (interactive)
    (let ((query (minibuffer-contents-no-properties)))
      (abort-recursive-edit)
      (run-at-time 0 nil
                   (lambda (q)
                     (let ((visual-replace-defaults-hook nil))
                       (visual-replace q)))
                   query)))

  ;; ミニバッファ入力中に M-% で置換へ移行
  (define-key minibuffer-local-map (kbd "M-%") 'my/visual-replace-from-minibuffer))

;; =====================================================================
;; 25. 範囲外のグレーアウト（ソフトナローイング：部分編集）
;; ─ 選択範囲に限定（Narrow）した際、範囲外を非表示にするのではなく、
;;   グレーアウト（影付き）で表示したまま編集・移動制限をかけます
;; =====================================================================
(defvar-local my/narrow-overlays nil
  "ナローイング範囲外をグレーアウトするためのオーバーレイリスト。")

(defvar-local my/narrow-bounds nil
  "現在のナローイング範囲 (start . end)")

(defun my/fancy-narrow-keep-inside ()
  "カーソルがナローイング範囲外に出た場合、範囲内に戻します。"
  (when my/narrow-bounds
    (let ((l (car my/narrow-bounds))
          (r (cdr my/narrow-bounds)))
      (cond
       ((< (point) l) (goto-char l))
       ((> (point) r) (goto-char r))))))

;; マイナーモードとして定義（モードラインに Narrow と表示させるため）
(define-minor-mode my/fancy-narrow-mode
  "範囲外をグレーアウトして編集制限をかける部分編集（ソフトナローイング）モード。"
  :init-value nil
  :lighter " Narrow"
  :keymap nil
  (if my/fancy-narrow-mode
      (add-hook 'post-command-hook 'my/fancy-narrow-keep-inside nil t)
    (remove-hook 'post-command-hook 'my/fancy-narrow-keep-inside t)
    (my/fancy-widen-overlays)))

(defun my/fancy-widen-overlays ()
  "グレーアウトオーバーレイと範囲設定をクリアします。"
  (mapc #'delete-overlay my/narrow-overlays)
  (setq my/narrow-overlays nil)
  (setq my/narrow-bounds nil))

(defun my/fancy-narrow-to-region (start end)
  "選択範囲を限定し、範囲外をグレーアウトして読み取り専用にします。"
  (interactive "r")
  (my/fancy-widen) ; すでにアクティブなら一度解除
  (let ((l (min start end))
        (r (max start end)))
    ;; 範囲外（上）のオーバーレイを作成
    (when (> l (point-min))
      (let ((ov (make-overlay (point-min) l)))
        (overlay-put ov 'face 'shadow)
        (overlay-put ov 'read-only t)
        (overlay-put ov 'evaporate t)
        (push ov my/narrow-overlays)))
    ;; 範囲外（下）のオーバーレイを作成
    (when (< r (point-max))
      (let ((ov (make-overlay r (point-max))))
        (overlay-put ov 'face 'shadow)
        (overlay-put ov 'read-only t)
        (overlay-put ov 'evaporate t)
        (push ov my/narrow-overlays)))
    (setq-local my/narrow-bounds (cons l r))
    (my/fancy-narrow-mode 1)
    (message "部分編集モード: %d 行〜 %d 行 (解除は M-o T w)" 
             (line-number-at-pos l) (line-number-at-pos r))))

(defun my/fancy-widen ()
  "グレーアウトと編集制限を解除し、全体表示に戻します。"
  (interactive)
  (my/fancy-narrow-mode 0)
  (message "部分編集モードを解除しました。"))


;; =====================================================================
;; 26. dmacro (Dynamic Macro) — 繰り返しの自動マクロ実行
;; =====================================================================

(use-package dmacro
  :ensure t
  :init
  ;; 繰り返しを再現するキーを C-t に設定
  (setq dmacro-key (kbd "C-t"))
  :config
  (global-dmacro-mode 1))

;; =====================================================================
;; 27. Meow（モーダル編集）
;; ─ 8節で設定済みのCUA/Windows風ショートカット(C-a/C-e/C-s/C-o/C-w/C-z等)は
;;   すべてControl修飾のため、Meowのnormal-state内の無修飾キーとは
;;   キー階層が異なり、互いを上書きしない。そのため両者は共存できる。
;;   （経緯：CUAとMeowの共存可否、および導入直後にカーソル移動キーが
;;    何も割り当たっていない問題について検討済み）
;; =====================================================================

(use-package meow
  :ensure t
  :custom
  (meow-use-dynamic-face-color nil) ; 勝手なフェイスの自動ブレンド・文字色黒化を抑止
  :config
  ;; Beaconのフェイク選択オーバーレイがセカンダリセレクションに埋もれないよう最優先表示（priority 100）
  (advice-add 'meow--beacon-add-overlay-at-region :around
              (lambda (orig-fun type p1 p2 backward)
                (funcall orig-fun type p1 p2 backward)
                (when (and meow--beacon-overlays (overlayp (car meow--beacon-overlays)))
                  (overlay-put (car meow--beacon-overlays) 'priority 100))))

  ;; スマートケース用正規表現生成関数
  (defun my/meow--smart-case-regexp (pattern)
    "PATTERNが大文字を含まない小文字のみの場合、大文字小文字無視の正規表現に展開する。"
    (if (isearch-no-upper-case-p pattern t)
        (let ((chars (mapcar (lambda (c)
                               (if (and (>= c ?a) (<= c ?z))
                                   (format "[%c%c]" c (upcase c))
                                 (regexp-quote (char-to-string c))))
                             (string-to-list pattern))))
          (apply #'concat chars))
      (regexp-quote pattern)))

  ;; Helix / Kakoune風の選択内マッチ（Meow公式 Beacon連携・Smart Case対応）
  (defun my/meow-select-matches-in-region (pattern)
    "選択範囲内（未選択時はバッファ全体）のPATTERNにマッチする箇所すべてをBeacon（マルチ選択）にする。
スマートケース対応: 小文字のみなら大文字小文字を無視し、大文字を含めば厳密一致。"
    (interactive "sMatch pattern: ")
    (let ((in-region (use-region-p)))
      (unless in-region
        ;; 選択範囲がない場合はバッファ全体を対象にする
        (set-mark (point-min))
        (goto-char (point-max))
        (activate-mark))
      (when (and (use-region-p) (not (string-empty-p pattern)))
      (let* ((case-fold (isearch-no-upper-case-p pattern t))
             (smart-re (my/meow--smart-case-regexp pattern)))
        ;; 1. 選択範囲をセカンダリセレクション(Grab)にする
        (secondary-selection-from-region)
        (meow--cancel-selection)
        ;; 2. セカンダリセレクションの開始位置へ移動
        (goto-char (overlay-start mouse-secondary-overlay))
        ;; 3. 検索文字列（smart-re）をMeowの検索履歴に登録
        (meow--push-search smart-re)
        ;; 4. セカンダリセレクション内で最初のマッチを検索
        (if (re-search-forward smart-re (overlay-end mouse-secondary-overlay) t)
            (let ((m-beg (match-beginning 0))
                  (m-end (match-end 0)))
              ;; 最初のマッチを選択（type: visit）
              (thread-first
                (meow--make-selection '(select . visit) m-beg m-end)
                (meow--select t))
              ;; 5. BEACON stateに切り替えて、残りのマッチ箇所にオーバーレイを展開
              (meow--switch-state 'beacon)
              (meow--beacon-remove-overlays)
              (save-restriction
                (meow--narrow-secondary-selection)
                (save-mark-and-excursion
                  (goto-char (point-min))
                  (while (re-search-forward smart-re nil t)
                    (unless (and (= (match-beginning 0) m-beg)
                                 (= (match-end 0) m-end))
                      (meow--beacon-add-overlay-at-region
                       '(select . visit)
                       (match-beginning 0)
                       (match-end 0)
                       nil)))))
              (setq meow--beacon-overlays (reverse meow--beacon-overlays))
              (message "Beacon: %d 箇所マッチ [%s] (r: ミニバッファ置換, c: 手動入力, d: 削除, i: 挿入)"
                       (1+ (length meow--beacon-overlays))
                       (if case-fold "大文字小文字無視" "厳密一致")))
          ;; マッチしなかった場合はGrabを解除
          (meow--cancel-second-selection)
          (message "No match for \"%s\" in selection" pattern))))))

  ;; Helix風: ミニバッファ対話式の一括置換 (r)
  (defun my/meow-replace (replacement)
    "選択範囲（またはBeacon全マッチ箇所）をミニバッファ入力した文字列で置換する。初期入力は直前のコピー内容。そのまま Enter でコピー内容、全部消して Enter で空文字列（削除）。"
    (interactive
     (let* ((clip (or (ignore-errors (current-kill 0 t)) ""))
            (prompt (if (string-empty-p clip)
                        "Replace with: "
                      "Replace with (初期値=コピー内容 / 全消しで削除): ")))
       ;; クリップボードが空でない場合はミニバッファを全選択状態で開く
       ;; （そのまま入力で上書き、Delete で消去して空文字列置換が可能）
       (list (if (string-empty-p clip)
                 (read-string prompt)
               (minibuffer-with-setup-hook
                   (lambda ()
                     (set-mark (minibuffer-prompt-end))
                     (goto-char (point-max))
                     (activate-mark))
                 (read-string prompt clip))))))
    (let ((rep replacement))   ; ← 空文字列もそのまま使う
      (cond
       ;; ケース1: Beacon状態（s でマッチした複数箇所）
       ((bound-and-true-p meow-beacon-mode)
        (meow--with-selection-fallback
         (meow--wrap-collapse-undo
          (let ((orig-beg (region-beginning))
                (orig-end (region-end)))
            (delete-region orig-beg orig-end)
            (insert rep)
            (save-mark-and-excursion
              (cl-loop for ov in meow--beacon-overlays do
                       (when (and (overlayp ov)
                                  (not (eq 'cursor (overlay-get ov 'meow-beacon-type))))
                         (goto-char (overlay-start ov))
                         (delete-region (overlay-start ov) (overlay-end ov))
                         (insert rep)
                         (delete-overlay ov))))
            (meow--beacon-remove-overlays)
            (meow--cancel-second-selection)
            (meow--switch-state 'normal)
            (message "Replaced all matches with \"%s\"" rep)))))
       ;; ケース2: 通常の選択範囲がある場合（x や w などで選択中）
       ((use-region-p)
        (let ((beg (region-beginning))
              (end (region-end)))
          (delete-region beg end)
          (insert rep)
          (meow--cancel-selection)
          (message "Replaced with \"%s\"" rep)))
       ;; ケース3: 選択がない場合（カーソル下の単語を自動選択して置換）
       (t
        (if-let* ((bounds (bounds-of-thing-at-point 'word)))
            (progn
              (delete-region (car bounds) (cdr bounds))
              (insert rep)
              (message "Replaced word with \"%s\"" rep))
          (message "[meow-replace] No word at point"))))))

  ;; 万能脱出: 選択解除およびBeacon（マルチカーソル）完全解除 (ESC)
  (defun my/meow-cancel-selection ()
    "選択を解除する。Beaconモード中であればBeaconも完全解除してNORMALに戻る。"
    (interactive)
    (if (bound-and-true-p meow-beacon-mode)
        (progn
          (meow--beacon-remove-overlays)
          (meow--cancel-second-selection)
          (meow--switch-state 'normal)
          (message "Quit Beacon"))
      (meow--cancel-second-selection)
      (meow-cancel-selection)))

  ;; Helix / Kakoune風: バッファ全体選択 (%)
  (defun my/meow-select-whole-buffer ()
    "バッファ全体を選択する（Helix / Kakoune の % 相当）。"
    (interactive)
    (thread-first
      (meow--make-selection '(select . buffer) (point-min) (point-max))
      (meow--select t)))

  ;; Helix風: 選択行の各行カーソル分割 (C)
  (defun my/meow-split-lines ()
    "選択範囲を各行ごとのBeaconカーソルに分割する（Helixの C 相当）。"
    (interactive)
    (if (use-region-p)
        (progn
          (secondary-selection-from-region)
          (meow--cancel-selection)
          (meow--switch-state 'beacon)
          (meow--add-beacons-for-char)
          (message "Lines split: %d 行にカーソル配置 (i: 挿入, a: 追加, c: 置換, d: 削除)"
                   (1+ (length meow--beacon-overlays))))
      (message "複数行を選択してから C を押してください")))

  ;; Helix / Kakoune風: 大文字・小文字トグル反転 (~)
  (defun my/meow-toggle-case ()
    "選択範囲（または1文字）の大文字・小文字を反転する（Helix / Kakoune の ~ 相当）。"
    (interactive)
    (if (use-region-p)
        (let* ((beg (region-beginning))
               (end (region-end))
               (str (buffer-substring-no-properties beg end))
               (toggled (mapconcat
                         (lambda (c)
                           (char-to-string
                            (cond
                             ((<= ?a c ?z) (upcase c))
                             ((<= ?A c ?Z) (downcase c))
                             (t c))))
                         str "")))
          (delete-region beg end)
          (insert toggled)
          (thread-first
            (meow--make-selection '(select . transient) beg (point))
            (meow--select t)))
      (let ((c (char-after)))
        (when c
          (delete-char 1)
          (insert-char
           (cond
            ((<= ?a c ?z) (upcase c))
            ((<= ?A c ?Z) (downcase c))
            (t c)))))))

  ;; Helix風 Goto キーマップ (g プレフィックス)
  (defvar my/meow-goto-keymap
    (let ((map (make-sparse-keymap)))
      (define-key map (kbd "g") (lambda () (interactive) (beginning-of-buffer)))
      (define-key map (kbd "e") (lambda () (interactive) (end-of-buffer)))
      (define-key map (kbd "h") (lambda () (interactive) (beginning-of-line)))
      (define-key map (kbd "l") (lambda () (interactive) (end-of-line)))
      (define-key map (kbd "i") (lambda () (interactive) (back-to-indentation)))
      (define-key map (kbd "RET") #'goto-line)
      (define-key map (kbd "<return>") #'goto-line)
      map)
    "Helix風 Goto キーマップ")

  (defun my/meow-goto-dispatch (arg)
    "Helix / Vim風のGotoディスパッチャ。
- 数値前置時 (例: 50g): 50行目へ即座にダイレクトジャンプ
- 単押し時: Helix風Gotoプレフィックス (gh:行頭, gl:行末, gg:先頭, ge:末尾, RET:指定行)"
    (interactive "P")
    (if arg
        (goto-line (prefix-numeric-value arg))
      (set-transient-map
       my/meow-goto-keymap
       nil
       nil
       "Goto: [g]先頭  [e]末尾  [h]行頭  [l]行末  [i]インデント  [RET]指定行")))

  (defun my/meow--register-p (register)
    "REGISTERが0-9のレジスタ指定として妥当な数値か判定する。"
    (and register (integerp register) (<= 0 register 9)))

  (defun my/meow-cut (&optional register)
    "選択中はkill-regionで直接切り取る（CUAのC-x遅延判定は経由しない）。
M-0〜M-9を前置した場合はそのレジスタへコピーしてから削除する。
選択が無ければ通常のmeow-kill（内部でmeow-C-kにフォールバック）。"
    (interactive "P")
    (if (use-region-p)
        (if (my/meow--register-p register)
            (copy-to-register (+ ?0 register) (region-beginning) (region-end) t)
          (kill-region (region-beginning) (region-end)))
      (meow-kill)))

  (defun my/meow-copy (&optional register)
    "選択中はkill-ring-saveで直接コピーする。
M-0〜M-9を前置した場合はそのレジスタへコピーする（削除はしない）。
選択が無ければ通常のmeow-save。"
    (interactive "P")
    (if (use-region-p)
        (if (my/meow--register-p register)
            (copy-to-register (+ ?0 register) (region-beginning) (region-end))
          (kill-ring-save (region-beginning) (region-end)))
      (meow-save)))

  (defun my/meow-paste (&optional register)
    "M-0〜M-9を前置した場合はそのレジスタの内容をinsert-registerで貼り付ける。
指定が無ければ通常のmeow-yank（内部でC-v=CUAペーストをシミュレート）。"
    (interactive "P")
    (if (my/meow--register-p register)
        (insert-register (+ ?0 register))
      (meow-yank)))

  (defun my/ime-off ()
    "Windows IME (OS側) と Emacs内部日本語入力 (Mozc) の両方を確実に OFF にする。"
    (interactive)
    ;; 1. Windows OS 側の IME を明示的に OFF（半角英数に強制）
    (when (fboundp 'w32-set-ime-open-status)
      (ignore-errors (w32-set-ime-open-status nil)))
    ;; 2. Emacs 内部の input method (Mozc 等) を確実に OFF（自動復活を防止）
    (when (boundp 'my/mozc-manual-off)
      (setq my/mozc-manual-off t))
    (when current-input-method
      (ignore-errors (deactivate-input-method))))

  (defun my/meow-insert-exit ()
    "IMEを確実にOFFにしてから、無条件でNORMALに復帰する。"
    (interactive)
    (my/ime-off)
    (meow-insert-exit))

  ;; Meow 日本語キーバインドガイド (INSERT / 編集モード)
  (defhydra hydra-meow-insert-help (:color blue :hint nil)
    "
  === EMACS 編集操作ガイド (INSERT時も有効) ===  [Tab] NORMALガイドへ
  [モード切替 / 日本語]     [Windows / CUA 基本]      [カーソル移動・選択]
  ESC : NORMAL復帰 (IME OFF)  C-c / C-x : コピー / 切取 (M-0〜9可)  C-e : 行末/インデント/行頭
  C-\\ : Mozc ON/OFF (日本語) C-v / C-z : 貼付 (M-0〜9可) / Undo    Shift+矢印 : 範囲選択
  [削除・編集]                C-y : やり直し (Redo)     Alt+ドラッグ : 矩形選択
  C-d : 1文字削除 (右削除)    M-z : Undo履歴ツリー      C-RET : 矩形選択開始
  C-k : 行末まで削除 (キル)   C-s : 上書き保存
  C-t : 自動繰返し (dmacro)   C-a : 全選択/解除トグル   [補完・検索]
  C-h : リアルタイム置換      C-w : バッファ閉じる      Tab : 補完決定 (Corfu)
  M-％ : スマート置換         C-q / Alt+F4: 終了        C-f : 検索 (Migemo)
  C-> / C-< : 同単語ジャンプ  F1 / C-c ? : このガイド   F3 / S-F3 : 次/前を検索
  Alt+←/→ : バッファ履歴(戻る/進む)                     C-'/C-S-' : ピン留め / クリア
  M-g m   : 足跡一覧 (consult-mark)                     M-g M     : 全ファイル足跡一覧
  ----------------------------------------------------------------------
  [ファンクションキー早見表]
  F1: ガイド (S-F1:標準ヘルプ)  F2: バッファ切替   F3: 検索 (S-F3:前へ)
  F4: 目次サイドバー   F5: 更新 (確認)   F6: 電卓 (Calc)
  F7: howm (S-F7:検索) F8: カレンダー (S-F8:天気) F9: メール (auximap)
  ----------------------------------------------------------------------
  [Tab / n] NORMALへ   [s] Consultメニュー   [m / M] 足跡一覧   [H] 標準ヘルプ   [q / ESC / F1] 閉じる
"
    ("<tab>" (if (fboundp 'hydra-meow-help/body) (hydra-meow-help/body)) :color blue)
    ("TAB" (if (fboundp 'hydra-meow-help/body) (hydra-meow-help/body)) :color blue)
    ("n" (if (fboundp 'hydra-meow-help/body) (hydra-meow-help/body)) :color blue)
    ("s" (if (fboundp 'hydra-consult/body) (hydra-consult/body)) :color blue)
    ("m" (call-interactively #'consult-mark) :color blue)
    ("M" (call-interactively #'consult-global-mark) :color blue)
    ("H" (call-interactively #'help-command) :color blue)
    ("q" nil :color blue)
    ("<escape>" nil :color blue)
    ("<f1>" nil :color blue)
    ("<F1>" nil :color blue))

  ;; Meow 日本語キーバインドガイド (NORMAL モード)
  (defhydra hydra-meow-help (:color blue :hint nil)
    "
  === MEOW 操作ガイド: NORMAL モード ===  [Tab] INSERTガイドへ
  [移動 / Goto (Helix)]      [選択 (マーク)]           [編集 / 挿入]
  h / j / k / l : 左 下 上 右  w / W : 単語 / 変数全体  i / a : 入力 (カーソル / 直後)
  b / e         : 単語移動    x / X : 行選択 / 上へ    A / I : 下 / 上に行を開いて入力
  g g / g e     : 先頭 / 末尾 ％    : バッファ全体選択  c     : 選択を消して入力
  g h / g l     : 行頭 / 行末 s     : 選択内マッチ     r     : ミニバッファ置換 (Helix風)
  50g / g RET   : 指定行移動  C     : 選択を行分割     m     : 複数行を1行に結合 (Join)
  f / t <文字>  : 文字へ移動  ESC   : 選択解除         ~     : 大文字/小文字反転 (Helix)
  ----------------------------------------------------------------------
  [おすすめ編集フロー (必修)]
  ① x (行選択) または ％ (全選択) → s (検索語) → r (置換後入力してEnterで一括置換！)
  ② x (行選択) → C (行分割) → i または a で各行に一括入力 → ESC
  ③ ) (括弧内) → c で中身書換 / ( (括弧込) → d で丸ごと削除
  ----------------------------------------------------------------------
  [検索 / 移動]             [括弧 / Puni 構造編集]   [コピー / 貼付 / レジスタ]
  / / ?   : 検索 / 逆方向   ( : 式全体を選択(括弧込)   y : コピー (M-0〜9でレジスタ可)
  n / N   : 次 / 前の一致   ) : 式の中身だけを選択     d : 切り取り (C-x / M-0〜9可)
  - n     : 逆検索 (Meow)   o : ブロック(連打で親へ)   p : 貼り付け (C-v互換)
  ;       : 選択方向を反転  SPC p ( : 選択を( )で包む  u : 元に戻す (Undo)
  Alt+←/→ : 履歴(戻る/進む) SPC p s : 囲み括弧を外す   C-d: 1文字削除  C-k: 行末削除
  C-'/C-S': ピン留め/クリア SPC b : ブックマーク一覧 C-\\ : Mozc ON/OFF (日本語)
                            SPC m   : 足跡一覧(マーク) SPC M : 全ファイル足跡一覧
                            SPC s   : Consult 探索メニュー (各種探索ツール)
  ----------------------------------------------------------------------
  [ファンクションキー早見表]
  F1: ガイド (S-F1:標準ヘルプ)  F2: バッファ切替   F3: 検索 (S-F3:前へ)
  F4: 目次サイドバー   F5: 更新 (確認)   F6: 電卓 (Calc)
  F7: howm (S-F7:検索) F8: カレンダー (S-F8:天気) F9: メール (auximap)
  ----------------------------------------------------------------------
  [Grab: テキスト入替の神機能]
  G : 選択をキープ (Grab)  → 別の場所を選択して R で瞬時に入替え！ (Y: 上書き)
  ----------------------------------------------------------------------
  [大文字(Shift)の法則]
  H/J/K/L : 選択を伸ばす (拡張)  W/E/B : 変数全体 (シンボル)  N / X : 逆方向 (- と同じ)
  ----------------------------------------------------------------------
  [Tab / i] INSERTへ   [s] Consultメニュー   [m / M] 足跡一覧   [C-q / Alt+F4] 終了   [q / ESC / F1] 閉じる
"
    ("<tab>" hydra-meow-insert-help/body :color blue)
    ("TAB" hydra-meow-insert-help/body :color blue)
    ("i" hydra-meow-insert-help/body :color blue)
    ("s" (if (fboundp 'hydra-consult/body) (hydra-consult/body)) :color blue)
    ("m" (call-interactively #'consult-mark) :color blue)
    ("M" (call-interactively #'consult-global-mark) :color blue)
    ("H" (call-interactively #'help-command) :color blue)
    ("q" nil :color blue)
    ("<escape>" nil :color blue)
    ("<f1>" nil :color blue)
    ("<F1>" nil :color blue))

  ;; F1 スマートヘルプ：現在のバッファ・モードに応じて最適なガイドを自動表示
  (defun my/smart-help ()
    "現在のモード（AI / カレンダー / EWW / nov.el / Meow INSERT / Meow NORMAL）に応じて最適な操作ガイドを表示する。
特殊モード以外でもガイドを確実に優先表示し、S-F1 で標準ヘルプを開く。"
    (interactive)
    (cond
     ((and (or (derived-mode-p 'howm-mode 'howm-menu-mode 'howm-view-summary-mode 'howm-view-contents-mode)
               (memq major-mode '(howm-mode howm-menu-mode howm-view-summary-mode howm-view-contents-mode))
               (string-match-p "\\*howm" (buffer-name)))
           (fboundp 'hydra-howm-help/body))
      (hydra-howm-help/body))
     ((and (or (bound-and-true-p gptel-mode)
               (derived-mode-p 'gptel-mode)
               (string-match-p "\\*.*\\(Chat\\|AI-Response\\|gptel\\).*" (buffer-name)))
           (fboundp 'hydra-gptel-help/body))
      (hydra-gptel-help/body))
     ((and (derived-mode-p 'calfw-calendar-mode 'cfw:calendar-mode) (fboundp 'hydra-calfw-help/body))
      (hydra-calfw-help/body))
     ((and (derived-mode-p 'eww-mode) (fboundp 'hydra-eww-help/body))
      (hydra-eww-help/body))
     ((and (derived-mode-p 'nov-mode) (fboundp 'hydra-nov-help/body))
      (hydra-nov-help/body))
     ((and (derived-mode-p 'auximap-mode) (fboundp 'hydra-auximap-help/body))
      (hydra-auximap-help/body))
     ((and (derived-mode-p 'auximap-view-mode) (fboundp 'hydra-auximap-view-help/body))
      (hydra-auximap-view-help/body))
     ((and (bound-and-true-p meow-mode) (not (bound-and-true-p meow-insert-mode)))
      (hydra-meow-help/body))
     ((fboundp 'hydra-meow-insert-help/body)
      (hydra-meow-insert-help/body))
     (t
      (call-interactively #'help-command))))

  ;; F1 でスマート操作ガイドを起動、S-F1 で Emacs 標準ヘルプ
  (global-set-key (kbd "<f1>") #'my/smart-help)
  (global-set-key (kbd "S-<f1>") #'help-command)

  (defun my/meow-backward-line (n)
    "上の行を選択・拡張します（x の逆方向）。"
    (interactive "p")
    (meow-line (- n)))

  (defun my/meow-search-backward ()
    "現在の選択文字列を上方向（逆方向）に向かって検索します（Vim の N 相当）。"
    (interactive)
    (let ((current-prefix-arg -1))
      (call-interactively #'meow-search)))

  (defun my/meow-setup ()
    "Meow公式のQWERTY向け推奨キーバインド。"
    (setq meow-cheatsheet-layout meow-cheatsheet-layout-qwerty)

    ;; MOTION state（dired等の特殊バッファ用）：j/kで上下移動
    ;; 元のコマンドは SPC j / SPC k から呼び出せる
    (meow-motion-overwrite-define-key
     '("h" . meow-left)
     '("j" . meow-next)
     '("k" . meow-prev)
     '("l" . meow-right)
     '("<escape>" . ignore))

    ;; リーダーキー（SPC）経由のコマンド
    (meow-leader-define-key
     '("s" . hydra-consult/body)
     '("b" . consult-bookmark)
     '("m" . consult-mark)
     '("M" . consult-global-mark)
     '("j" . "H-j")
     '("k" . "H-k")
     '("1" . meow-digit-argument)
     '("2" . meow-digit-argument)
     '("3" . meow-digit-argument)
     '("4" . meow-digit-argument)
     '("5" . meow-digit-argument)
     '("6" . meow-digit-argument)
     '("7" . meow-digit-argument)
     '("8" . meow-digit-argument)
     '("9" . meow-digit-argument)
     '("0" . meow-digit-argument)
     '("/" . meow-keypad-describe-key)
     '("?" . hydra-meow-help/body))

    ;; NORMAL state（通常の編集コマンド）
    (meow-normal-define-key
     '("0" . meow-expand-0)
     '("9" . meow-expand-9)
     '("8" . meow-expand-8)
     '("7" . meow-expand-7)
     '("6" . meow-expand-6)
     '("5" . meow-expand-5)
     '("4" . meow-expand-4)
     '("3" . meow-expand-3)
     '("2" . meow-expand-2)
     '("1" . meow-expand-1)
     '("-" . negative-argument)
     '(";" . meow-reverse)
     '("," . meow-inner-of-thing)
     '("." . meow-bounds-of-thing)
     '("[" . meow-beginning-of-thing)
     '("]" . meow-end-of-thing)
     '("<" . beginning-of-buffer)
     '(">" . end-of-buffer)
     '("%" . my/meow-select-whole-buffer)
     '("~" . my/meow-toggle-case)
     '("a" . meow-append)
     '("A" . meow-open-below)
     '("b" . meow-back-word)
     '("B" . meow-back-symbol)
     '("c" . meow-change)
     '("C" . my/meow-split-lines)
     '("d" . my/meow-cut)
     '("D" . meow-backward-delete)
     '("e" . meow-next-word)
     '("E" . meow-next-symbol)
     '("f" . meow-find)
     '("g" . my/meow-goto-dispatch)
     '("G" . meow-grab)
     '("h" . meow-left)
     '("H" . meow-left-expand)
     '("i" . meow-insert)
     '("I" . meow-open-above)
     '("j" . meow-next)
     '("J" . meow-next-expand)
     '("k" . meow-prev)
     '("K" . meow-prev-expand)
     '("l" . meow-right)
     '("L" . meow-right-expand)
     '("m" . meow-join)
     '("n" . meow-search)
     '("N" . my/meow-search-backward)    ; Vim風: 逆方向検索
     '("o" . meow-block)
     '("O" . meow-to-block)
     '("p" . my/meow-paste)
     '("q" . meow-quit)
     '("Q" . meow-quit)             ; 誤爆防止: Shift+q でも安全にキャンセル
     '("r" . my/meow-replace)
     '("R" . meow-swap-grab)
     '("s" . my/meow-select-matches-in-region)
     '("t" . meow-till)
     '("u" . meow-undo)
     '("U" . meow-undo-in-selection)
     '("v" . meow-visit)
     ;; Vim風の検索。isearch-forward/backwardはMigemo対応済み(6節)。
     '("/" . isearch-forward)
     '("?" . isearch-backward)
     '("w" . meow-mark-word)
     '("W" . meow-mark-symbol)
     '("x" . meow-line)
     '("X" . my/meow-backward-line)     ; 誤爆防止: 上の行を選択 (x の逆方向)
     '("y" . my/meow-copy)
     '("Y" . meow-sync-grab)
     '("z" . meow-pop-selection)
     '("'" . repeat)
     ;; 既定は選択キャンセルが "g" だが、CUA/Windows的にESCで
     ;; 選択解除できる方が直感的なため上書きする
     '("<escape>" . my/meow-cancel-selection)))

  (my/meow-setup)

  ;; --- Meow モードラインインジケータ（文字のみ・立体バッジ表示） ---
  (setq meow-replace-state-name-list
        '((normal . " NORMAL ")
          (insert . " INSERT ")
          (beacon . " BEACON ")
          (motion . " MOTION ")
          (keypad . " KEYPAD ")))

  (defun my/apply-meow-indicator-faces ()
    "Meowのモードラインインジケータのバッジ配色を設定する。"
    (when (facep 'meow-normal-indicator)
      ;; NORMAL: エメラルドグリーン背景 ＋ 白文字太字 ＋ 枠線
      (set-face-attribute 'meow-normal-indicator nil
                          :background "#10b981" :foreground "#ffffff"
                          :weight 'bold :box '(:line-width (1 . 1) :color "#059669"))
      ;; INSERT: オレンジ背景 ＋ 白文字太字 ＋ 枠線
      (set-face-attribute 'meow-insert-indicator nil
                          :background "#d97706" :foreground "#ffffff"
                          :weight 'bold :box '(:line-width (1 . 1) :color "#b45309"))
      ;; BEACON: パープル背景 ＋ 白文字太字 ＋ 枠線
      (set-face-attribute 'meow-beacon-indicator nil
                          :background "#8b5cf6" :foreground "#ffffff"
                          :weight 'bold :box '(:line-width (1 . 1) :color "#7c3aed"))
      ;; MOTION: ブルー背景 ＋ 白文字太字 ＋ 枠線
      (set-face-attribute 'meow-motion-indicator nil
                          :background "#0284c7" :foreground "#ffffff"
                          :weight 'bold :box '(:line-width (1 . 1) :color "#0369a1"))
      ;; KEYPAD: ティール背景 ＋ 白文字太字 ＋ 枠線
      (set-face-attribute 'meow-keypad-indicator nil
                          :background "#0d9488" :foreground "#ffffff"
                          :weight 'bold :box '(:line-width (1 . 1) :color "#0f766e"))))

  (my/apply-meow-indicator-faces)

  ;; --- NORMAL復帰時にIMEを自動OFF ---
  ;; meow-normal-mode に直接フックすると、日本語入力を確定した直後に
  ;; 誤ってIMEまでOFFになってしまう不具合があるため、フックではなく
  ;; INSERT stateの<escape>キー自体を専用関数(my/meow-insert-exit)に
  ;; 差し替える。実行順序(IME確認→OFF→NORMAL復帰)を関数内で保証できる。
  ;; macOS記事の mac-ime-deactivate に相当するのは、この環境(tr-ime)
  ;; では標準の deactivate-input-method（11b節のisearch/ミニバッファ
  ;; 抑制と同じ関数）。
  (with-eval-after-load 'meow
    (meow-define-keys 'insert
      '("<escape>" . my/meow-insert-exit)
      '("C-c ?" . hydra-meow-insert-help/body))
    ;; INSERT脱出時およびNORMAL復帰時に確実にIMEをOFF（タイマーで安全に非同期実行）
    (add-hook 'meow-insert-exit-hook
              (lambda () (run-at-time 0 nil #'my/ime-off)))
    (add-hook 'meow-switch-state-hook
              (lambda (&rest _)
                (when (bound-and-true-p meow-normal-mode)
                  (run-at-time 0 nil #'my/ime-off))))
    (with-eval-after-load 'meow-beacon
      (define-key meow-beacon-state-keymap (kbd "r") #'my/meow-replace)
      (define-key meow-beacon-state-keymap (kbd "<escape>") #'my/meow-cancel-selection)
      (define-key meow-beacon-state-keymap (kbd "q") #'my/meow-cancel-selection))

  ;; --- kbdシミュレーション対象キーの補正 ---
  ;; Meowの一部コマンド(移動・貼り付け等)は「指定したキーを押した体で
  ;; 実行する」方式のため、そのキーを他の用途に上書きしている場合は、
  ;; Meow側の変数を実際の割り当てに合わせて修正する必要がある
  ;; (Meow公式ドキュメントにも明記されている既知の注意点)。
  ;;
  ;; 8節/11節でCUA/Windows風に上書き済みのキーがここに該当する:
  ;;   C-f → my/consult-line-migemo に上書き済み(本来は forward-char)
  ;;   C-y → undo-redo に上書き済み(本来は yank)
  ;; そのため、移動は矢印キーへ、貼り付けはCUAの C-v(CUAペースト)へ
  ;; 向け直す。
  ;;
  ;; 切り取り(旧: C-w → kill-current-buffer に上書き済みで meow-kill が
  ;; 壊れていた問題)は、kbdシミュレーションではなく "s" キーを
  ;; my/meow-cut に直接差し替える方式に変更した。CUAの C-x は
  ;; 「プレフィックスキーか切り取りか」をタイマー付きの実キー入力待ちで
  ;; 判定する特殊な仕組み(cua--prefix-override-handler)のため、
  ;; kbdシミュレーション越しに呼ぶと待機状態に入りwhich-key風の
  ;; ポップアップが出てしまう。kill-regionを直接呼ぶことでこれを回避。
  (setq meow--kbd-forward-char "<right>")
  (setq meow--kbd-yank "C-v")

  ;; Meowのコピー・キル操作をWindowsクリップボードと完全同期
  ;; （Alt+0〜9 のレジスタ操作は独立したまま安全に保持されます）
  (setq meow-use-clipboard t)

  ;; NORMALモードでの選択範囲をさらに分かりやすくする設定
  ;; 選択方向（カーソル側3文字）にグラデーションをかけて端点と方向を明示
  (setq meow-use-enhanced-selection-effect t)
  ;; 選択中カーソルを太くして視認性を確保
  (setq meow-cursor-type-region-cursor '(bar . 3))

  ;; --- 通常バッファ・ターミナルの初期状態を INSERT に設定 ---
  ;; 通常のテキストエディタ同様に開いてすぐ入力（INSERT）できるようにし、
  ;; 高度な編集・選択（x→s→r やマルチカーソル等）を行いたい時だけ ESC で NORMAL に切り替える。
  ;; （※ Dired や Help 等の閲覧専用バッファは自動判定で motion が維持されます）
  (setq meow-mode-state-list
        '((conf-mode . insert)
          (fundamental-mode . insert)
          (help-mode . motion)
          (prog-mode . insert)
          (text-mode . insert)
          (conpty-mode . insert)
          (term-mode . insert)
          (auximap-mode . motion)
          (auximap-view-mode . motion)))

  ;; 通常ファイルを新規・既存で開いた時は、確実に INSERT モードで開始する
  ;; （※ Dired、Help、特殊バッファなどの閲覧専用画面は除く）
  (add-hook 'find-file-hook
            (lambda ()
              (unless (or (derived-mode-p 'dired-mode 'help-mode 'special-mode)
                          buffer-read-only)
                (when (fboundp 'meow--switch-state)
                  (meow--switch-state 'insert)))))

  ;; モードラインにMeowの状態表示（<N>/<I>/<M>等）を追加する。
  ;; 5節で mode-line-format を独自リストに差し替えているため、
  ;; この呼び出しをしないとインジケーターは一切表示されない。
  (meow-setup-indicator)

  ;; --- CUAとの共存に関する補足 ---
  ;; ・normal-state中でも C-x/C-c/C-v/C-z/C-a/C-e/C-s/C-o/C-w は
  ;;   Control修飾キーであるため、8節のCUA/Windows風バインドが
  ;;   そのまま機能する（Meow標準コマンドと衝突しない）。
  ;; ・矩形選択の C-RET はMeow標準キーマップで未使用のため衝突しない。
  ;; ・"u"（meow-undo）はnormal-state限定の別ルートとして残しているが、
  ;;   8節の C-z(undo) / M-z(vundo) が主系統であることに変わりはない。
  ;;
  ;; もし試した結果「今は要らない」となった場合は、下の行をコメントアウト
  ;; すればMeowは常駐するがnormal-state化はされず、通常のEmacsと同じ挙動に戻る。
  (meow-global-mode 1))

;; =====================================================================
;; 28. Puni（構造編集）とMeow/CUAの連携
;; ─ 括弧やリストなどの構文構造(sexp/list)を意識した編集をMeowに追加する。
;;   参考: Apribase「Emacs Meow を Evil Alternative として使えるようにする」
;;   ・delete-selection-mode（8節で有効化済み）と衝突しない設計のため、
;;     選択中にBackspaceを押した場合はまず選択範囲の削除が優先される。
;;   ・electric-pair-mode（既存の自動括弧補完）とも役割が異なるだけで
;;     競合しない(挿入時の自動閉じ括弧 vs 編集時の構造認識削除)。
;; =====================================================================

(use-package puni
  :ensure t
  :config
  ;; 全バッファでpuni-modeを有効化(公式README推奨)。
  ;; 括弧の対応が壊れるような中途半端な削除を防ぐBackspace/Deleteが
  ;; 有効になる。
  (puni-global-mode)

  ;; --- INSERT state: Backspaceを構造を壊さない削除に差し替え ---
  ;; conpty / term-mode 等の端末バッファでは、バッファ直接編集ではなく
  ;; 端末プロセスへ Backspace (\C-?) を送信する必要があるため切り分ける。
  (defun my/meow-backward-delete-char ()
    "conpty/term等の端末バッファではプロセスへBackspaceを送信し、
通常バッファではpuniによる構造認識削除を行う。"
    (interactive)
    (if (derived-mode-p 'conpty-mode 'term-mode)
        (if (fboundp 'term-send-backspace)
            (term-send-backspace)
          (term-send-raw-string "\C-?"))
      (puni-backward-delete-char)))

  (with-eval-after-load 'meow
    (meow-define-keys 'insert
    '("<backspace>" . my/meow-backward-delete-char))

  ;; --- NORMAL state: 括弧キーで囲み構造をそのまま選択 ---
  ;; Meow標準の meow-inner-of-thing/meow-bounds-of-thing（","/"."）は
  ;; 直後に "(" 等の対象指定が要るが、puniの以下2つはその指定なしで
  ;; 「今いる場所を囲むS式」を直接掴めるため、キー自体を括弧にして
  ;; 直感的に対応させる。
  ;;   "(" → 式全体を選択（括弧を含む。Vimの da( 相当）
  ;;   ")" → 式の中身だけを選択（括弧を含まない。Vimの di( 相当）
  (meow-normal-define-key
   '("(" . puni-mark-sexp-around-point)
   '(")" . puni-mark-list-around-point))

  ;; --- リーダーキー(SPC p ...)経由：囲み構造の変形操作 ---
  ;; 頻度が低い操作なのでSPC経由にまとめる。
  (meow-leader-define-key
   '("p (" . puni-wrap-round)    ; 選択範囲を ( ) で包む
     '("p [" . puni-wrap-square)   ; 選択範囲を [ ] で包む
     '("p {" . puni-wrap-curly)    ; 選択範囲を { } で包む
     '("p <" . puni-wrap-angle)    ; 選択範囲を < > で包む
     '("p s" . puni-splice)        ; 囲んでいる括弧だけを外す
     '("p l" . puni-slurp-forward) ; 次の要素を括弧の中に取り込む
     '("p b" . puni-barf-forward)))))


;; =====================================================================
;; U-NEXT 検索・再生連携 (Vertico補完 + Chrome Appモード)
;; =====================================================================

(require 'cl-lib)

(defun my/unext-search (query)
  "U-NEXT の動画を検索し、ミニバッファ（Vertico）で作品を選択して専用ウィンドウで開く。"
  (interactive "sU-NEXT 検索キーワード: ")
  (let* ((script-candidates
          (list (expand-file-name "unext_search.py" user-emacs-directory)
                (expand-file-name "unext_search.py" (file-name-directory (or load-file-name buffer-file-name default-directory)))
                (expand-file-name "unext_search.py" default-directory)))
         (script (cl-find-if #'file-exists-p script-candidates)))
    (unless script
      (user-error "unext_search.py が見つかりませんでした"))
    (message "U-NEXT: 「%s」を検索中..." query)
    (let* ((coding-system-for-read 'utf-8)
           ;; Windows環境では引数エンコードに UTF-8 を使うと CP932 誤変換で文字化けするため locale-coding-system を指定
           (coding-system-for-write (if (eq system-type 'windows-nt) locale-coding-system 'utf-8))
           (output (with-output-to-string
                     (call-process "python" nil standard-output nil script query)))
           (items (condition-case nil
                      (json-parse-string output :array-type 'list :object-type 'alist)
                    (error nil))))
      (if (null items)
          (message "U-NEXT: 「%s」に一致する作品が見つかりませんでした" query)
        (let* ((candidates
                (mapcar
                 (lambda (item)
                   (let* ((id (cdr (assq 'id item)))
                          (title (cdr (assq 'title item)))
                          (svod (cdr (assq 'svod item)))
                          (catch (cdr (assq 'catchphrase item)))
                          (badge (if svod "【見放題】" "【ポイント】"))
                          (label (if (and catch (not (string-empty-p catch)))
                                     (format "%-10s %s  ── %s" badge title catch)
                                   (format "%-10s %s" badge title))))
                     (cons label (cons id title))))
                 items))
               (chosen-label (completing-read "U-NEXT 作品を選択: " (mapcar #'car candidates) nil t))
               (chosen-info (cdr (assoc chosen-label candidates)))
               (chosen-id (car chosen-info))
               (chosen-title (cdr chosen-info))
               (url (format "https://video.unext.jp/title/%s" chosen-id))
               (chrome-path
                (cl-find-if #'file-exists-p
                            '("C:/Program Files/Google/Chrome/Application/chrome.exe"
                              "C:/Program Files (x86)/Google/Chrome/Application/chrome.exe"))))
          (message "U-NEXT: 「%s」を開きます..." chosen-title)
          (if chrome-path
              (start-process "unext-app" nil chrome-path (format "--app=%s" url))
            (browse-url url)))))))

(defalias 'unext-search #'my/unext-search)


;; =====================================================================
;; EWW (Emacs内蔵Webブラウザ) 最適化 ＆ ダークテーマ視認性向上
;; =====================================================================
;; 1. CA証明書の設定 (Emacs組み込みTLS・画像読み込み用)
(with-eval-after-load 'gnutls
  (let ((cert (expand-file-name "mcp-servers/tradingview-mcp/.venv/Lib/site-packages/certifi/cacert.pem"
                                (getenv "USERPROFILE"))))
    (when (file-exists-p cert)
      (add-to-list 'gnutls-trustfiles cert))))

;; 2. Web上の大容量ページ対応 ＆ HTTPS接続の堅牢化 (Windows curl使用)
(let ((curl-bin (if (file-executable-p "C:/Windows/System32/curl.exe")
                    "C:/Windows/System32/curl.exe"
                  (executable-find "curl"))))
  (when curl-bin
    ;; Windows標準curlの場合、証明書失効検証ブロック対策として--ssl-no-revokeを追加
    (setq eww-retrieve-command
          (if (string-match-p "System32" curl-bin)
              (list curl-bin "--ssl-no-revoke" "-s" "-L")
            (list curl-bin "-s" "-L")))))

;; 日本語など非ASCII文字を含むURLを自動的にパーセントエンコードしてcurlに渡す
(with-eval-after-load 'eww
  (advice-add 'eww-retrieve :filter-args
              (lambda (args)
                (cons (url-encode-url (car args)) (cdr args)))))

;; 2. 不正な <comment> タグによる以降のページ消滅バグの防止 ＆ 見出しサイズの統一
(with-eval-after-load 'shr
  (defalias 'shr-tag-comment #'shr-generic)
  ;; 本文は通常サイズを維持し、見出しだけ程よく拡大してメリハリをつける (案1)
  (set-face-attribute 'shr-h1 nil :height 1.3  :weight 'bold)
  (set-face-attribute 'shr-h2 nil :height 1.15 :weight 'bold)
  (set-face-attribute 'shr-h3 nil :height 1.05 :weight 'bold))

;; 3. 文字サイズ・配色の統一 ＆ ウィンドウ幅折り返し
(setq shr-width nil)                         ; ウィンドウ幅に合わせて表示
(setq shr-max-width nil)                     ; 最大幅制限を解除
(add-hook 'eww-mode-hook #'visual-line-mode) ; 画面端で自然に折り返し
;; 通常のバッファと全く同じ等幅フォント・文字サイズで統一描画
(setq shr-use-fonts nil)
;; Web独自色を無効化し、Emacsのダークテーマ色を統一適用（'C' キーで切り替え可能）
(setq shr-use-colors nil)
;; 初期状態では画像を読み込まず、文字だけを超爆速でレンダリング（'i' または 'I' キーで後から画像表示切替）
(setq shr-inhibit-images t)
(with-eval-after-load 'eww
  (define-key eww-mode-map (kbd "i") #'eww-toggle-images))

;; 4. EWW デフォルト検索エンジン ＆ ミニバッファ検索
;;    Yahoo! JAPAN (Google検索インデックス採用・No-JS対応) を使用
(setq eww-search-prefix "https://search.yahoo.co.jp/search?p=")

(defun my/consult-web-search (&optional initial)
  "ミニバッファでキーワードを入力し、Web検索（Yahoo! JAPAN / Google系）をEWWで開きます。"
  (interactive)
  (let ((query (read-string "Web検索 (EWW): " initial)))
    (when (and query (not (string-blank-p query)))
      (eww (format "%s%s" eww-search-prefix (url-hexify-string query))))))

(defalias 'web-search #'my/consult-web-search)
(defalias 'eww-search #'my/consult-web-search)

;; エディタ連携: カーソル下の単語または選択範囲で即座に EWW 検索
(defun my/eww-search-at-point ()
  "カーソル下の単語（または選択範囲）を初期値にして EWW で Web 検索する。"
  (interactive)
  (let* ((initial (if (use-region-p)
                      (buffer-substring-no-properties (region-beginning) (region-end))
                    (thing-at-point 'symbol t)))
         (query (read-string (format "Web検索 (EWW)%s: "
                                     (if initial (format " [既定: %s]" initial) ""))
                             nil nil initial)))
    (when (and query (not (string-blank-p query)))
      (eww (format "%s%s" eww-search-prefix (url-hexify-string query))))))

;; Markdownリンクコピー (w / y)
(defun my/eww-copy-markdown-link (&optional raw-url)
  "現在のページのタイトルとURLを [タイトル](URL) 形式でクリップボードにコピーする。
C-u を前置した場合は URL のみをコピーする。"
  (interactive "P")
  (let* ((url (eww-current-url))
         (title (or (plist-get eww-data :title) (buffer-name)))
         (clean-title (string-trim (replace-regexp-in-string "[\r\n]+" " " title)))
         (text (if raw-url url (format "[%s](%s)" clean-title url))))
    (when url
      (kill-new text)
      (message "Copied: %s" text))))

;; ページごとの自動タブ化 (Centaur Tabs連携)
(defun my/eww-rename-buffer-by-title ()
  "EWWのレンダリング完了後、バッファ名をページタイトルに合わせて自動リネームする。"
  (let ((title (plist-get eww-data :title)))
    (when (and title (not (string-blank-p title)))
      (let* ((clean (string-trim (replace-regexp-in-string "[\r\n]+" " " title)))
             (short (if (> (length clean) 25) (concat (substring clean 0 25) "…") clean)))
        (rename-buffer (format "*eww: %s*" short) t)))))
(add-hook 'eww-after-render-hook #'my/eww-rename-buffer-by-title)

;; リンクを新しいタブ（別バッファ）で開く (M-Enter)
(defun my/eww-open-in-new-tab ()
  "カーソル下のリンクを新しいEWWバッファ（タブ）で開く。"
  (interactive)
  (let ((url (get-text-property (point) 'shr-url)))
    (if url
        (let ((eww-buffer (generate-new-buffer "*eww*")))
          (with-current-buffer eww-buffer
            (eww-mode)
            (eww url))
          (pop-to-buffer eww-buffer))
      (message "カーソル位置にリンクがありません"))))

;; 外部ブラウザ（Windows既定ブラウザ: Chrome/Edge）への確実な連携 (&)
(setq browse-url-browser-function #'browse-url-default-windows-browser)

;; 5. EWW 見出し目次機能 (imenu / consult-imenu 連携)
;;    'o' キーまたは M-g i で記事内の全目次をミニバッファから一覧・ジャンプ
(defun my/eww-imenu-index ()
  "EWWバッファの見出し (shr-h1〜shr-h6) から imenu 用インデックスを作成します。"
  (save-excursion
    (goto-char (point-min))
    (let ((index nil))
      (while (not (eobp))
        (let ((face (get-text-property (point) 'face)))
          (when (and face (symbolp face) (string-match-p "\\`shr-h[1-6]" (symbol-name face)))
            (let* ((start (point))
                   (end (line-end-position))
                   (title (string-trim (buffer-substring-no-properties start end))))
              (when (> (length title) 0)
                (push (cons title (copy-marker start)) index))
              (goto-char end))))
        (forward-line 1))
      (nreverse index))))

(add-hook 'eww-mode-hook
          (lambda ()
            (setq-local imenu-create-index-function #'my/eww-imenu-index)))

(defun my/eww-jump-to-heading ()
  "EWWバッファの見出し目次をミニバッファに一覧表示し、即座にジャンプします。"
  (interactive)
  (if (fboundp 'consult-imenu)
      (consult-imenu)
    (call-interactively #'imenu)))

;; EWW 閲覧履歴の Consult 検索 (H)
(defun my/consult-eww-history ()
  "現在のEWWタブの閲覧履歴を Consult / Vertico でインクリメンタル検索してジャンプ。"
  (interactive)
  (let* ((history (if (bound-and-true-p eww-history) eww-history nil))
         (candidates
          (cl-loop for item in history
                   for title = (or (plist-get item :title) (plist-get item :url) "No title")
                   for url = (or (plist-get item :url) "")
                   collect (cons (format "%-45s  %s"
                                         (if (> (length title) 43)
                                             (concat (substring title 0 43) "…")
                                           title)
                                         url)
                                 item))))
    (if (null candidates)
        (message "EWW の閲覧履歴はありません")
      (let ((selected (consult--read candidates
                                     :prompt "EWW 閲覧履歴: "
                                     :sort nil
                                     :require-match t)))
        (when selected
          (eww-restore-history selected))))))

;; EWW ブックマークの Consult 検索 (B)
(defun my/consult-eww-bookmarks ()
  "EWW ブックマークを Consult / Vertico でインクリメンタル検索して開く。"
  (interactive)
  (eww-read-bookmarks)
  (if (null eww-bookmarks)
      (message "EWW ブックマークはありません (b で現在のページを追加)")
    (let* ((candidates
            (cl-loop for item in eww-bookmarks
                     for title = (or (plist-get item :title) (plist-get item :url) "No title")
                     for url = (or (plist-get item :url) "")
                     collect (cons (format "%-45s  %s"
                                           (if (> (length title) 43)
                                               (concat (substring title 0 43) "…")
                                             title)
                                           url)
                                   url)))
           (selected (consult--read candidates
                                    :prompt "EWW ブックマーク: "
                                    :sort nil
                                    :require-match t)))
      (when selected
        (eww selected)))))

;; EWW 操作ガイド (F1 / ?)
(defhydra hydra-eww-help (:color blue :hint nil)
  "
  === EWW Webブラウザ 操作ガイド ===  [F1 / q] 閉じる
  [ページ移動]              [リンク操作]              [表示・読書モード]
  l / Backspace : 戻る      Tab / S-Tab : 次 / 前のリンク R     : 本文だけ抽出 (リーダー)
  r             : 進む      Enter       : リンクを開く    i     : 画像表示 ON/OFF
  g             : 再読込み  M-Enter     : 新しいタブで開く C     : 配色 (Web色/テーマ色)
  [検索・履歴・ブックマーク] [コピー・外部連携]        [タブ・ファイル]
  o   : 目次 (Consult)      w / y : Markdownリンクコピー  S   : EWWバッファ一覧
  H   : 閲覧履歴 (Consult)  &     : 外部ブラウザで開く    C-w : タブを閉じる
  B   : ブックマーク一覧    b     : 現在ページを保存      d   : ダウンロード
  F4  : 目次サイドバー      f     : ページ内検索
  ----------------------------------------------------------------------
"
  ("l" eww-back-url :color blue)
  ("<backspace>" eww-back-url :color blue)
  ("r" eww-forward-url :color blue)
  ("g" eww-reload :color blue)
  ("R" eww-readable :color blue)
  ("i" eww-toggle-images :color blue)
  ("C" eww-toggle-colors :color blue)
  ("o" my/eww-jump-to-heading :color blue)
  ("H" my/consult-eww-history :color blue)
  ("B" my/consult-eww-bookmarks :color blue)
  ("b" eww-add-bookmark :color blue)
  ("<f4>" (lambda () (interactive) (if (fboundp 'imenu-list-smart-toggle) (imenu-list-smart-toggle) (speedbar-get-focus))) :color blue)
  ("f" isearch-forward :color blue)
  ("w" my/eww-copy-markdown-link :color blue)
  ("y" my/eww-copy-markdown-link :color blue)
  ("&" eww-browse-with-external-browser :color blue)
  ("d" eww-download :color blue)
  ("S" eww-list-buffers :color blue)
  ("q" nil :color blue)
  ("<escape>" nil :color blue)
  ("<f1>" nil :color blue)
  ("<F1>" nil :color blue))

(with-eval-after-load 'eww
  (define-key eww-mode-map (kbd "o") #'my/eww-jump-to-heading)
  (define-key eww-mode-map (kbd "w") #'my/eww-copy-markdown-link)
  (define-key eww-mode-map (kbd "y") #'my/eww-copy-markdown-link)
  (define-key eww-mode-map (kbd "H") #'my/consult-eww-history)
  (define-key eww-mode-map (kbd "B") #'my/consult-eww-bookmarks)
  (define-key eww-mode-map (kbd "b") #'eww-add-bookmark)
  (define-key eww-mode-map (kbd "M-RET") #'my/eww-open-in-new-tab)
  (define-key eww-mode-map (kbd "M-<return>") #'my/eww-open-in-new-tab)
  (define-key eww-mode-map (kbd "?") (lambda () (interactive) (if (fboundp 'hydra-eww-help/body) (hydra-eww-help/body) (describe-mode)))))


;; =====================================================================
;; 最終処理: GUIカスタマイズ設定 (custom.el) のロード
;; ─ パッケージの読み込みがすべて完了した後にロードすることで、
;;   外部パッケージテーマ（ef-themes 等）の適用失敗を防ぎます。
;; =====================================================================
(when (and custom-file (file-exists-p custom-file))
  (load custom-file nil t))
;; custom.el 内の過去ハッシュ値による上書きを防ぎ、テーマ確認プロンプトを完全に抑止
(setq custom-safe-themes t)
(advice-add 'custom-theme-load-confirm :override (lambda (&rest _) t))

;; どの配色・テーマでも選択範囲とカーソルを確実に見やすくする動的設定
(defun my/apply-cursor-region-faces (&rest _)
  "テーマの明暗を自動判定し、どの配色でも文字が埋もれない選択色を設定する。"
  (require 'color)
  (let* ((bg (face-background 'default nil t))
         (dark-p (or (eq (frame-parameter nil 'background-mode) 'dark)
                     (if (and bg (color-defined-p bg))
                         (let ((rgb (color-name-to-rgb bg)))
                           (< (+ (* (nth 0 rgb) 0.299)
                                 (* (nth 1 rgb) 0.587)
                                 (* (nth 2 rgb) 0.114))
                              0.5))
                       t))))
    (if dark-p
        ;; ダークテーマ: 視認性の高いネイビー背景 ＋ 白文字統一（どんな文字色でも確実に読める）
        (progn
          (set-face-attribute 'region nil
                              :background "#264f78"
                              :foreground "#ffffff"
                              :distant-foreground "#ffffff"
                              :extend t)
          ;; 複数マッチのBeacon選択（カレント以外の全マッチ箇所）を白文字＋鮮やかな青＋枠線でくっきり表示
          (set-face-attribute 'meow-beacon-fake-selection nil
                              :background "#3d59a1"
                              :foreground "#ffffff"
                              :distant-foreground "#ffffff"
                              :box '(:line-width (1 . 1) :color "#7aa2f7")
                              :extend nil)
          ;; 元の選択範囲全体（セカンダリセレクション）は控えめにしてマッチ箇所を邪魔しない
          (set-face-attribute 'secondary-selection nil
                              :background "#1a1e2e"
                              :foreground nil
                              :extend t)
          (set-face-attribute 'cursor nil :background "#e0af68"))
      ;; ライトテーマ: スカイブルー背景 ＋ 濃紺文字統一
      (progn
        (set-face-attribute 'region nil
                            :background "#b4d8fd"
                            :foreground "#002b55"
                            :distant-foreground "#000000"
                            :extend t)
        ;; 複数マッチのBeacon選択（ライトテーマ用）
        (set-face-attribute 'meow-beacon-fake-selection nil
                            :background "#a4cbfd"
                            :foreground "#002b55"
                            :distant-foreground "#000000"
                            :box '(:line-width (1 . 1) :color "#005fb8")
                            :extend nil)
        ;; 元の選択範囲全体（ライトテーマ用）
        (set-face-attribute 'secondary-selection nil
                            :background "#f0f4fc"
                            :foreground nil
                            :extend t)
        (set-face-attribute 'cursor nil :background "#005fb8"))))
  (when (fboundp 'my/apply-meow-indicator-faces)
    (my/apply-meow-indicator-faces)))
(my/apply-cursor-region-faces)
(if (boundp 'enable-theme-functions)
    (add-hook 'enable-theme-functions #'my/apply-cursor-region-faces)
  (advice-add 'load-theme :after #'my/apply-cursor-region-faces))


;; =====================================================================
;; 日本の祝日設定 (japanese-holidays)
;; =====================================================================
(with-eval-after-load 'calendar
  (when (require 'japanese-holidays nil t)
    (setq calendar-holidays
          (append japanese-holidays
                  holiday-local-holidays
                  holiday-other-holidays))
    (setq calendar-mark-holidays-flag t)
    ;; 土日・祝日の色分け表示（土曜:水色 / 日曜・祝日:赤色）
    (setq japanese-holiday-weekend '(0 6)
          japanese-holiday-weekend-marker
          '(holiday nil nil nil nil nil japanese-holiday-saturday))
    (add-hook 'calendar-today-visible-hook #'japanese-holiday-mark-weekend)
    (add-hook 'calendar-today-invisible-hook #'japanese-holiday-mark-weekend)
    (add-hook 'calendar-today-visible-hook #'calendar-mark-today)))


;; =====================================================================
;; プロジェクト管理の拡張 (project.el) ＆ キーヘルプ
;; =====================================================================
;; 1. .git がないフォルダでも「.project」を置くだけでプロジェクトルートとして自動認識
(with-eval-after-load 'project
  (setq project-vc-extra-root-markers '(".project" ".git")))

;; 2. プロジェクト操作専用キーバインド (C-c C-p)
;; ※ C-c p は Meow のリーダーキー SPC p と衝突するため C-c C-p に割り当て
(define-key mode-specific-map (kbd "p") nil)
(global-set-key (kbd "C-c C-p") #'hydra-project/body)

;; 3. which-key に標準の C-x p の日本語ガイドを追加
(with-eval-after-load 'which-key
  (which-key-add-key-based-replacements
    "C-x p"   "プロジェクト操作"
    "C-x p f" "プロジェクト内ファイル検索"
    "C-x p p" "別プロジェクト切り替え"
    "C-x p d" "ルートフォルダを開く (Dired)"
    "C-x p b" "プロジェクト内バッファ切り替え"
    "C-x p k" "プロジェクトの全バッファを閉じる"))


;; =====================================================================
;; 軽量株式チャートブラウザ (stock-charts.el)
;; =====================================================================
;; meigaralist.txt の銘柄・テーマ別リアルタイムチャートを表示
(let ((stock-charts-dir (expand-file-name "lisp/stock-charts" user-emacs-directory)))
  (when (file-directory-p stock-charts-dir)
    (add-to-list 'load-path stock-charts-dir))
  (when (or (require 'stock-charts nil t)
            (require 'my-stock-chart nil t))
    (defalias 'stock-charts #'my/stock-chart-open)
    (defalias 'consult-stock-chart-all #'my/stock-chart-search-all)))

;; =====================================================================
;; gptel（Qwen / LLM チャットクライアント）
;; =====================================================================
(use-package gptel
  :ensure t
  :bind (("C-c g g" . gptel)        ; チャットバッファを開く
         ("C-c g m" . gptel-menu)   ; モデル・パラメータ切り替えメニュー
         ("C-c RET" . gptel-send))  ; 選択範囲／プロンプトを送信
  :config
  ;; Windows ポータブル同梱 curl.exe を優先＆UTF-8固定
  (let ((portable-curl (expand-file-name "../bin/curl.exe" user-emacs-directory)))
    (when (file-executable-p portable-curl)
      (setq gptel-use-curl portable-curl
            gptel-curl-extra-args '("--insecure"))))
  (add-to-list 'process-coding-system-alist '("curl" . (utf-8 . utf-8)))

  ;; Qwen (Alibaba DashScope) バックエンド登録
  (gptel-make-openai "Qwen"
    :host "dashscope-intl.aliyuncs.com" ; ※国際版（中国国内リージョンは "dashscope.aliyuncs.com"）
    :endpoint "/compatible-mode/v1/chat/completions"
    :stream t
    :key (lambda () (getenv "DASHSCOPE_API_KEY"))
    :models '(qwen-plus
              qwen-max
              qwen-turbo
              qwen-coder-plus
              qwen2.5-coder-32b-instruct))

  ;; デフォルトモデル設定
  (setq gptel-backend (gptel-get-backend "Qwen")
        gptel-model   'qwen-plus)

  ;; gptel チャットバッファでの F1 操作ガイドバインド
  (with-eval-after-load 'gptel
    (define-key gptel-mode-map (kbd "<f1>")
      (lambda () (interactive)
        (if (fboundp 'hydra-gptel-help/body)
            (hydra-gptel-help/body)
          (describe-mode))))))

;; =====================================================================
;; auximap (IMAP メール一覧・閲覧・管理)
;; =====================================================================
(autoload 'auximap "auximap" "Browse IMAP email in Emacs." t)
(autoload 'auximap-reload "auximap" "Reload IMAP email list." t)
(autoload 'auximap-toggle "auximap" "Toggle auximap email reader." t)
(global-set-key (kbd "<f9>") #'auximap-toggle)
(global-set-key [f9] #'auximap-toggle)

;; =====================================================================
;; auxbookmark (Consult Web ブックマーク横断検索)
;; =====================================================================
(autoload 'consult-auxbookmark "auxbookmark" "Search all Web Bookmarks with Consult." t)
(autoload 'auxbookmark-consult "auxbookmark" "Search all Web Bookmarks with Consult." t)
(global-set-key (kbd "C-c b") #'consult-auxbookmark)

