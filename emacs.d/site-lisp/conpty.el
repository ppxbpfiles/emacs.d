;;; conpty.el --- ConPTY terminal support for Windows -*- lexical-binding: t; -*-

;; Copyright (C) 2024
;; Author: Emacs ConPTY
;; Version: 0.1.0
;; Package-Requires: ((emacs "26.1"))
;; Keywords: terminals, processes, windows
;; URL: https://github.com/user/emacs-conpty
;;
;; This is a modified version of v0.1.0 (not the original).

;;; Commentary:

;; This package provides ConPTY (Windows Pseudo Console) support for Emacs
;; on Windows, enabling proper terminal emulation with ANSI escape sequences.
;;
;; Usage:
;;   M-x conpty        - Start a terminal with the default shell
;;   M-x conpty-run    - Run a specific command in a terminal

;;; Code:

(require 'term)

(defgroup conpty nil
  "ConPTY terminal support for Windows."
  :group 'terminals
  :prefix "conpty-")

(defcustom conpty-program nil
  "Path to the emacs-conpty executable."
  :type '(choice (const nil) file)
  :group 'conpty)

(defcustom conpty-shell nil
  "Shell to run in the ConPTY terminal."
  :type '(choice (const nil) string)
  :group 'conpty)

(defcustom conpty-default-columns 80
  "Default number of columns for the terminal."
  :type 'integer
  :group 'conpty)

(defcustom conpty-default-rows 24
  "Default number of rows for the terminal."
  :type 'integer
  :group 'conpty)

(defcustom conpty-log-file nil
  "If non-nil, path to a file where emacs-conpty appends debug logs."
  :type '(choice (const nil) file)
  :group 'conpty)

(defcustom conpty-extra-args nil
  "Additional command-line arguments passed to emacs-conpty."
  :type '(repeat string)
  :group 'conpty)

(defvar-local conpty--process nil
  "The ConPTY process for this buffer.")

(defvar-local conpty--alt-screen-bumped nil
  "Non-nil after we have nudged the child with a resize on alt-screen entry.")

(defvar-local conpty--alt-screen-redraw-sent nil
  "Non-nil after we have sent one redraw keystroke in this alt-screen session.")

(defvar conpty--resize-timer nil
  "Timer for debouncing resize events.")

(defun conpty--find-program ()
  "Find the emacs-conpty executable."
  (or conpty-program
      (executable-find "emacs-conpty")
      (let ((dir (file-name-directory (or load-file-name buffer-file-name ""))))
        (when dir
          (let ((release (expand-file-name "target/release/emacs-conpty.exe" dir))
                (debug (expand-file-name "target/debug/emacs-conpty.exe" dir)))
            (cond ((file-executable-p release) release)
                  ((file-executable-p debug) debug)))))))

(defun conpty--get-shell ()
  "Get the shell to use."
  (or conpty-shell
      (getenv "COMSPEC")
      "cmd.exe"))

(defun conpty--send-resize (proc cols rows)
  "Send resize escape sequence to PROC with COLS and ROWS."
  (when (and proc (process-live-p proc))
    (process-send-string proc (format "\e[8;%d;%dt" rows cols))))

(defun conpty--window-cols (&optional win)
  "Estimate terminal columns that fit in WIN.
`window-body-width' can undercount for term buffers in some setups,
so prefer `window-max-chars-per-line' when available."
  (let* ((win (or win (selected-window)))
         (body-cols (window-body-width win))
         (max-cols (when (fboundp 'window-max-chars-per-line)
                     (floor (window-max-chars-per-line win)))))
    (max 2 (or (and max-cols (> max-cols 0) max-cols)
               body-cols
               conpty-default-columns))))

(defun conpty--window-rows (&optional win)
  "Return terminal rows that fit in WIN."
  (let ((win (or win (selected-window))))
    (max 2 (or (window-body-height win)
               conpty-default-rows))))

(defun conpty--sync-visible-size (proc)
  "Sync PROC to the currently visible window size for its buffer.
This is needed right after creating the terminal buffer: the process is
started before `switch-to-buffer' displays it, so the initial ConPTY size
often falls back to `conpty-default-columns' / `conpty-default-rows' even
when the actual window is much wider or taller."
  (when (and proc (process-live-p proc))
    (let* ((buf (process-buffer proc))
           (win (and buf (get-buffer-window buf t)))
           (cols (if win (conpty--window-cols win) conpty-default-columns))
           (rows (if win (conpty--window-rows win) conpty-default-rows)))
      (when (buffer-live-p buf)
        (with-current-buffer buf
          (term-reset-size rows cols)))
      (conpty--send-resize proc cols rows))))

(defun conpty--force-alt-screen-redraw (proc)
  "Ask PROC to redraw once with Ctrl-L.
This works around a startup case where the first alt-screen frame arrives
but Emacs does not visibly settle until the child performs one more redraw."
  (when (and proc (process-live-p proc))
    (process-send-string proc "\C-l")))

(defun conpty--bump-resize (proc)
  "Force the child to receive a fresh WINDOW_BUFFER_SIZE_EVENT.
Full-screen apps such as vim do not redraw their status line on the
initial frame because they never see a SIGWINCH equivalent. Sending
the same size is a no-op for ConPTY; toggling rows by one forces a
real resize event. We also call `term-reset-size' so Emacs's
term-mode updates its own screen representation, which is what makes
the bottom row actually appear (the missing piece compared with the
`window-size-change-functions' path)."
  (when (and proc (process-live-p proc))
    (let* ((buf (process-buffer proc))
           (win (and buf (get-buffer-window buf t)))
           (cols (if win (conpty--window-cols win) conpty-default-columns))
           (rows (if win (conpty--window-rows win) conpty-default-rows)))
      (when (buffer-live-p buf)
        (with-current-buffer buf
          (term-reset-size (1+ rows) cols)))
      (conpty--send-resize proc cols (1+ rows))
      (run-with-timer
       0.05 nil
       (lambda (p b c r)
         (when (and p (process-live-p p))
           (when (buffer-live-p b)
             (with-current-buffer b
               (term-reset-size r c)))
           (conpty--send-resize p c r)
           ;; Mimic what M-x / M-: do for free: poke the echo area so
           ;; Emacs schedules a full redisplay pass.
           (let ((message-log-max nil))
             (message " ")
             (message nil))
           (force-window-update b)
           (redisplay t)))
       proc buf cols rows))))

(defun conpty--filter (proc str)
  "Process filter wrapper around `term-emulate-terminal'.
Detects vim/less/etc. entering the alternate screen buffer and
schedules a one-shot dummy resize so the child gets SIGWINCH and
redraws its bottom line."
  (let ((buf (process-buffer proc)))
    (when (and buf (buffer-live-p buf))
      (cond
       ((and (string-match-p "\e\\[\\?1049h" str)
             (not (buffer-local-value 'conpty--alt-screen-bumped buf)))
        (with-current-buffer buf
          (setq conpty--alt-screen-bumped t)
          (setq conpty--alt-screen-redraw-sent nil))
        ;; Windows vim.exe often emits a few blanking frames before it paints
        ;; the real first screen, so one early bump can be too soon to make
        ;; Emacs redisplay the eventual status line. Nudge once immediately
        ;; after alt-screen entry and once more after the initial paint settles.
        (run-with-timer 0.15 nil #'conpty--bump-resize proc)
        (run-with-timer 0.45 nil #'conpty--bump-resize proc)
        ;; A manual C-l inside Windows vim makes the missing status line
        ;; appear reliably, so send the same redraw automatically after the
        ;; initial flurry of blanking frames and size sync has settled.
        (run-with-timer 0.80 nil #'conpty--force-alt-screen-redraw proc))
       ((string-match-p "\e\\[\\?1049l" str)
        (with-current-buffer buf
          (setq conpty--alt-screen-bumped nil)
          (setq conpty--alt-screen-redraw-sent nil)))))
    (when (and (buffer-local-value 'conpty--alt-screen-bumped buf)
               (not (buffer-local-value 'conpty--alt-screen-redraw-sent buf)))
      (with-current-buffer buf
        (setq conpty--alt-screen-redraw-sent t))))
  (term-emulate-terminal proc str))

(defun conpty--window-size-change (_frame)
  "Handle window size change."
  (when conpty--resize-timer
    (cancel-timer conpty--resize-timer))
  (setq conpty--resize-timer
        (run-with-timer
         0.1 nil
         (lambda ()
           ;; consult-buffer/vertico-posframe などの補完UIはポップアップの
           ;; 表示のたびにウィンドウ構成を何度も変更するため、ミニバッファが
           ;; 開いている間はここでの一括リサイズ処理(全conptyバッファへの
           ;; term-reset-size / conpty--send-resize / 再描画)を行わない。
           ;; 補完UIを閉じた後、実際のウィンドウサイズが変わっていれば
           ;; 次回の window-size-change-functions 発火で改めて追従する。
           (unless (active-minibuffer-window)
             (dolist (buf (buffer-list))
               (when (buffer-live-p buf)
                 (with-current-buffer buf
                   (when (and (derived-mode-p 'conpty-mode)
                              conpty--process
                              (process-live-p conpty--process))
                     (let* ((win (get-buffer-window buf t))
                            (cols (if win (conpty--window-cols win) conpty-default-columns))
                            (rows (if win (conpty--window-rows win) conpty-default-rows)))
                       (term-reset-size rows cols)
                       (conpty--send-resize conpty--process cols rows)))))))))))

(defun conpty--copy-or-sigint ()
  "選択範囲があればコピーし、なければ Ctrl-C を端末に送信します。"
  (interactive)
  (if (use-region-p)
      (progn
        (kill-ring-save (region-beginning) (region-end))
        (deactivate-mark)
        (message "Copied"))
    (term-send-raw-string "\C-c")))

(defun conpty-copy ()
  "選択範囲または表示中の端末出力をコピーします。"
  (interactive)
  (if (use-region-p)
      (conpty--copy-or-sigint)
    (kill-ring-save (point-min) (point-max))
    (message "Copied terminal buffer")))

(defun conpty--clipboard-text ()
  "Return text from the Windows/GUI clipboard or the kill ring."
  (or (when (fboundp 'gui-get-selection)
        (ignore-errors
          (gui-get-selection 'CLIPBOARD 'STRING)))
      (when (fboundp 'w32-get-clipboard-data)
        (ignore-errors
          (w32-get-clipboard-data)))
      (ignore-errors
        (current-kill 0 t))))

(defun conpty-paste ()
  "クリップボードまたはキルリングのテキストを、改行コードを適切に変換して送信します。
末尾の改行(CR/LF)は取り除いてから送るため、コピー元に付いていた末尾の
改行によって最後の行が意図せず実行されてしまうことはありません
(行の途中の改行は従来通りEnterとして送られます)。"
  (interactive)
  (let ((text (conpty--clipboard-text)))
    (when text
      ;; 末尾の改行を除去して、貼り付けだけで実行(Enter)されないようにする
      (let* ((trimmed (replace-regexp-in-string "[\r\n]+\\'" "" text))
             ;; 残った改行コード(CRLFやLF)を、端末がEnterキー入力として
             ;; 認識できる \r に変換します
             (converted (replace-regexp-in-string "\r?\n" "\r" trimmed)))
        (term-send-raw-string converted)))))

(defun conpty-switch-to-minibuffer ()
  "アクティブなミニバッファへ移動します。"
  (interactive)
  (let ((win (active-minibuffer-window)))
    (if (window-live-p win)
        (select-window win)
      (message "アクティブなミニバッファはありません"))))
(defvar conpty-override-map (make-sparse-keymap) "Keymap that takes precedence over CUA in ConPTY buffers.")
(defvar-local conpty-override-mode nil)
(define-key conpty-override-map (kbd "C-c") 'conpty--copy-or-sigint)
(define-key conpty-override-map (kbd "C-S-c") 'conpty-copy)
(define-key conpty-override-map (kbd "C-v") 'conpty-paste)
(define-key conpty-override-map (kbd "C-y") 'conpty-paste)

(defun conpty--redirect-paste (orig-fn &rest args)
  "conpty-mode バッファでは `cua-paste'/`yank' の代わりに `conpty-paste' を使う。
CUA や Emacs 標準の yank はキーマップの優先順位次第で `conpty-paste' より先に
実行されてしまうことがあり、その場合バッファへ直接挿入しようとして
char-mode の read-only なバッファに対して \"Buffer is read-only\" エラーに
なってしまう。
`overriding-local-map' 等でキーマップの優先順位そのものを操作する方法は、
char-mode 終了時・プロセス終了時・ミニバッファ移行時など解除すべき
タイミングをすべて正確に把握する必要があり壊れやすかった(右クリック
メニューが機能しなくなる・プロセス終了後に操作不能になる・ミニバッファでの
入力が飲み込まれる、等の副作用が実際に発生した)。
それよりも、実行されるコマンド自体をここで横取りする方が確実で副作用がない:
conpty-mode 以外のバッファ(ミニバッファ含む)には一切影響しない。"
  (if (derived-mode-p 'conpty-mode)
      (call-interactively #'conpty-paste)
    (apply orig-fn args)))

(advice-add 'yank :around #'conpty--redirect-paste)
(with-eval-after-load 'cua-base
  (advice-add 'cua-paste :around #'conpty--redirect-paste))

(defun conpty--enforce-raw-keymap (&rest _)
  "Kept only to clear a stale `overriding-local-map' if it was set by an
older version of this file before it gets byte-recompiled; new code never
sets `overriding-local-map' itself."
  (when (derived-mode-p 'conpty-mode)
    (kill-local-variable 'overriding-local-map)))

(advice-add 'term-char-mode :after #'conpty--enforce-raw-keymap)
(advice-add 'term-line-mode :after #'conpty--enforce-raw-keymap)

(defun conpty--sentinel (proc msg)
  "`term-sentinel' を呼んだ後、プロセスが終了していたら念のため
`overriding-local-map' を解除する(通常は元々 nil のはず)。"
  (term-sentinel proc msg)
  (let ((buf (process-buffer proc)))
    (when (and buf (buffer-live-p buf))
      (with-current-buffer buf
        (when (and (derived-mode-p 'conpty-mode)
                   (not (process-live-p proc)))
          (kill-local-variable 'overriding-local-map))))))

(define-derived-mode conpty-mode term-mode "ConPTY"
  "Major mode for ConPTY terminal."
  (setq-local term-suppress-hard-newline t)
  ;; CUA モードの C-c/C-v/C-x は emulation-mode-map-alists の登録順序に
  ;; 依存しており、cua-enable-cua-keys 環境では ConPTY 側の優先設定が
  ;; 効かず cua-paste 等が先に実行されてしまう（read-only バッファへの
  ;; yank でエラーになる）。CUA 専用のバッファローカル変数で確実に無効化する。
  (setq-local cua-inhibit-cua-keys t)
  ;; CUA のグローバルキーより先に ConPTY のキーを解決する。
  (setq-local conpty-override-mode t)
  (setq-local emulation-mode-map-alists
              (cons '((conpty-override-mode . conpty-override-map))
                    emulation-mode-map-alists))

  ;; 端末固有のキーマップをカスタマイズ
  (let ((old-map term-raw-map))
    (setq-local term-raw-map (copy-keymap old-map)))

  ;; Windows風の Ctrl-C / Ctrl-V / Ctrl-A 設定
  ;; line-mode では term-raw-map が使われないため、mode map にも登録する。
  (define-key conpty-mode-map (kbd "C-c") 'conpty--copy-or-sigint)
  (define-key conpty-mode-map (kbd "C-S-c") 'conpty-copy)
  (define-key conpty-mode-map (kbd "C-v") 'conpty-paste)
  (define-key conpty-mode-map (kbd "C-y") 'conpty-paste)
  (define-key term-raw-map (kbd "C-c") 'conpty--copy-or-sigint)
  (define-key term-raw-map (kbd "C-S-c") 'conpty-copy)
  (define-key term-raw-map (kbd "C-v") 'conpty-paste)
  (define-key term-raw-map (kbd "C-a") 'mark-whole-buffer)

  ;; Emacs標準のヤンクとコピーも raw-mode で使えるようにする
  (define-key term-raw-map (kbd "C-y") 'conpty-paste)

  ;; 保険: context-menu-mode が無効な環境でも右クリックでメニューを出す
  ;; (通常は context-menu-mode 自身のバインドで動くのでここには来ない)
  (define-key term-raw-map (kbd "<mouse-3>") 'context-menu-open)
  (define-key term-raw-map (kbd "M-w") 'kill-ring-save)

  ;; raw-mode でも Emacs 側の移動操作を使えるようにする
  (let ((conpty-c-x-map (make-sparse-keymap)))
    (define-key conpty-c-x-map (kbd "o") 'other-window)
    (define-key conpty-c-x-map (kbd "O") (lambda () (interactive) (other-window -1)))
    (define-key conpty-c-x-map (kbd "m") 'conpty-switch-to-minibuffer)
    (define-key conpty-c-x-map (kbd "k") 'kill-buffer)
    (define-key term-raw-map (kbd "C-x") conpty-c-x-map))
  ;; Ctrl-C をコピー等に割り当てたため、モード切り替え用のキーとして
  ;; Ctrl-Q を割り当てます（Ctrl-Q を押すとカーソル移動可能な line-mode になります）
  (define-key term-raw-map (kbd "C-q") 'term-line-mode)

  ;; 画面内容をテキストファイルに書き出す(後で検索/見返す用)
  (define-key conpty-mode-map (kbd "<f7>") 'conpty-write-buffer-to-file)
  (define-key term-raw-map (kbd "<f7>") 'conpty-write-buffer-to-file)

  ;; M-o (ランチャー) などのグローバルキーを端末内でも有効にする
  (let ((launcher (lookup-key (current-global-map) (kbd "M-o"))))
    (when (and launcher (not (integerp launcher)))
      (define-key term-raw-map (kbd "M-o") launcher))))

(defun conpty-write-buffer-to-file (file)
  "ConPTY バッファの内容(画面表示+スクロールバック全体)を
テキストファイル FILE に書き出します。後で検索したり見返したりする
ためのものなので、`write-region' そのままとは違い、リージョン選択の
有無に関係なくバッファ全体を対象にします。"
  (interactive
   (list (read-file-name "書き出し先のファイル: "
                          nil nil nil
                          (format-time-string "conpty-%Y%m%d-%H%M%S.txt"))))
  (write-region (point-min) (point-max) file)
  (message "ConPTY バッファの内容を %s に書き出しました" file))


(defun conpty--make-term (name shell)
  "Create a ConPTY terminal buffer NAME running SHELL."
  (let* ((conpty-exe (conpty--find-program))
         (buf (get-buffer-create name))
         (cols conpty-default-columns)
         (rows conpty-default-rows))
    (with-current-buffer buf
      (let ((win (get-buffer-window buf t)))
        (when win
          (setq cols (conpty--window-cols win))
          (setq rows (conpty--window-rows win))))

      (conpty-mode)
      (term-reset-size rows cols)

      (let* ((args (append (list "-c" (number-to-string cols)
                                 "-r" (number-to-string rows)
                                 "-s" shell)
                           (when conpty-log-file
                             (list "--log" (expand-file-name conpty-log-file)))
                           conpty-extra-args))
             (stderr-buf (get-buffer-create (format "%s<stderr>" name)))
             (process-adaptive-read-buffering nil)
             (proc (make-process
                    :name name
                    :buffer buf
                    :command (cons conpty-exe args)
                    :connection-type 'pipe
                    :coding 'utf-8-unix
                    :noquery t
                    :filter #'conpty--filter
                    :sentinel #'conpty--sentinel
                    :stderr stderr-buf)))
        (setq conpty--process proc)
        (set-process-query-on-exit-flag proc nil)
        (goto-char (point-max))
        (set-marker (process-mark proc) (point))
        (term-char-mode)
        ;; `make-process' starts ConPTY before this buffer is visible, so its
        ;; startup size is commonly the 80x24 default. Once the buffer is
        ;; actually displayed, push the real window size back to the child.
        (run-with-timer 0.05 nil #'conpty--sync-visible-size proc)))

    (add-hook 'window-size-change-functions #'conpty--window-size-change)
    buf))

;;;###autoload
(defun conpty ()
  "Start a ConPTY terminal with the default shell."
  (interactive)
  (unless (eq system-type 'windows-nt)
    (error "ConPTY is only available on Windows"))
  (let ((program (conpty--find-program)))
    (unless program
      (error "Cannot find emacs-conpty executable. Build with `cargo build --release'"))
    (switch-to-buffer (conpty--make-term "*conpty*" (conpty--get-shell)))))

;;;###autoload
(defun conpty-run (command)
  "Run COMMAND in a ConPTY terminal."
  (interactive "sCommand: ")
  (unless (eq system-type 'windows-nt)
    (error "ConPTY is only available on Windows"))
  (let ((program (conpty--find-program)))
    (unless program
      (error "Cannot find emacs-conpty executable. Build with `cargo build --release'"))
    (let ((name (format "*conpty: %s*" (car (split-string command)))))
      (switch-to-buffer (conpty--make-term name command)))))

;;;###autoload
(defun conpty-powershell ()
  "Start PowerShell in a ConPTY terminal."
  (interactive)
  (let ((conpty-shell "powershell.exe"))
    (conpty)))

;;;###autoload
(defun conpty-pwsh ()
  "Start PowerShell Core in a ConPTY terminal."
  (interactive)
  (let ((conpty-shell "pwsh.exe"))
    (conpty)))

;;;###autoload
(defun conpty-wsl ()
  "Start WSL in a ConPTY terminal."
  (interactive)
  (let ((conpty-shell "wsl.exe"))
    (conpty)))

(defun conpty--context-menu (menu click)
  "ConPTY 用の右クリックメニュー項目を追加します。
標準の `context-menu-region' は `buffer-read-only' なバッファでは
「貼り付け」項目自体を出さないため、char-mode で意図的に read-only
にしている ConPTY バッファでは通常の右クリックメニューに貼り付けが
出てこない。ここでは read-only かどうかに関係なく、常に
`conpty-paste' を呼ぶ「貼り付け」項目を追加する。"
  (when (derived-mode-p 'conpty-mode)
    (mouse-set-point click)
    (define-key menu [conpty-separator] menu-bar-separator)
    (when (use-region-p)
      (define-key menu [conpty-copy]
        '(menu-item "コピー" conpty--copy-or-sigint)))
    (define-key menu [conpty-paste]
      '(menu-item "貼り付け" conpty-paste)))
  menu)

(add-hook 'context-menu-functions #'conpty--context-menu t)

(provide 'conpty)
;;; conpty.el ends here
