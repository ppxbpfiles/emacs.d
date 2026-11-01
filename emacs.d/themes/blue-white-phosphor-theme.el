;;; blue-white-phosphor-theme.el --- Eye-friendly MicroEMACS / X68000 style retro theme -*- lexical-binding: t; -*-

;; Author: Antigravity
;; Keywords: faces, themes
;; Package-Requires: ((emacs "24.1"))

;;; Commentary:

;; An eye-friendly retro computing color theme inspired by MicroEMACS (μEmacs 3.10)
;; on classic Japanese personal computers (Sharp X68000 / NEC PC-9801).
;; Softens harsh neon primaries into gentle, eye-comfortable tones while preserving
;; the unmistakable black & cyan retro aesthetic.
;;
;; Usage:
;;   (load-theme 'blue-white-phosphor t)

;;; Code:

(deftheme blue-white-phosphor
  "Eye-friendly MicroEMACS / X68000 style black & cyan retro theme.")

(let ((class '((class color) (min-colors 89)))
      ;; Eye-friendly retro palette (softened contrast)
      (bg          "#0a0e14") ; Soft deep dark background
      (fg-main     "#d8e2ec") ; Softened off-white body text
      (fg-cyan     "#4ec9b0") ; Gentle cyan / sea-green (line numbers & primary accents)
      (fg-yellow   "#e5c07b") ; Warm amber/cream yellow (accents & keywords)
      (fg-green    "#88c096") ; Gentle sage green (strings)
      (fg-dim      "#8aa2b4") ; Muted cyan-gray (comments / doc)
      (fg-subtle   "#264f64") ; Subtle borders & guides
      (bg-mode-act "#26c6da") ; Vivid yet comfortable true-cyan mode-line band
      (bg-mode-ina "#1a8fa0") ; Dimmed cyan mode-line band for inactive windows
      (bg-hl       "#131f28") ; Gentle line highlight
      (err         "#e06c75")) ; Mild error red

  (custom-theme-set-faces
   'blue-white-phosphor

   ;; Base faces
   `(default ((,class (:foreground ,fg-main :background ,bg))))
   `(fringe ((,class (:foreground ,fg-cyan :background ,bg))))
   `(cursor ((,class (:background ,fg-cyan :foreground ,bg))))
   `(highlight ((,class (:foreground ,bg :background ,fg-cyan))))
   `(region ((,class (:foreground ,bg :background ,fg-cyan :weight bold))))
   `(secondary-selection ((,class (:foreground ,bg :background ,fg-yellow))))
   `(shadow ((,class (:foreground ,fg-subtle))))
   `(minibuffer-prompt ((,class (:foreground ,fg-cyan :weight bold))))
   `(vertical-border ((,class (:foreground ,fg-subtle))))
   `(window-divider ((,class (:foreground ,fg-subtle))))

   ;; Line numbers (Gentle Cyan)
   `(line-number ((,class (:foreground ,fg-cyan :background ,bg :weight normal))))
   `(line-number-current-line ((,class (:foreground ,fg-yellow :background ,bg-hl :weight bold))))
   `(hl-line ((,class (:background ,bg-hl))))

   ;; Mode line (Soft Cyan band with dark text)
   `(mode-line ((,class (:foreground "#0a0e14" :background ,bg-mode-act :box nil :weight bold))))
   `(mode-line-inactive ((,class (:foreground "#0a0e14" :background ,bg-mode-ina :box nil))))
   `(mode-line-buffer-id ((,class (:foreground "#0a0e14" :weight bold))))
   `(header-line ((,class (:foreground ,fg-cyan :background ,bg-mode-ina))))

   ;; Search (reverse video, softened)
   `(isearch ((,class (:foreground ,bg :background ,fg-yellow :weight bold))))
   `(isearch-fail ((,class (:foreground ,bg :background ,err :weight bold))))
   `(lazy-highlight ((,class (:foreground ,bg :background ,fg-cyan :weight bold))))
   `(match ((,class (:foreground ,bg :background ,fg-yellow :weight bold))))

   ;; Whitespace / special characters (Warm yellow accents)
   `(whitespace-newline ((,class (:foreground ,fg-yellow))))
   `(whitespace-space ((,class (:foreground ,fg-subtle))))
   `(whitespace-tab ((,class (:foreground ,fg-yellow))))
   `(whitespace-trailing ((,class (:foreground ,bg :background ,fg-yellow))))

   ;; Paren matching
   `(show-paren-match ((,class (:foreground ,bg :background ,fg-yellow :weight bold))))
   `(show-paren-mismatch ((,class (:foreground ,bg :background ,err :weight bold))))

   ;; Links & Buttons
   `(link ((,class (:foreground ,fg-cyan :underline t))))
   `(link-visited ((,class (:foreground ,fg-dim :underline t))))
   `(button ((,class (:foreground ,fg-yellow :underline t :weight bold))))

   ;; Font-lock
   `(font-lock-builtin-face ((,class (:foreground ,fg-cyan :weight bold))))
   `(font-lock-comment-delimiter-face ((,class (:foreground ,fg-dim))))
   `(font-lock-comment-face ((,class (:foreground ,fg-dim :slant italic))))
   `(font-lock-doc-face ((,class (:foreground ,fg-dim))))
   `(font-lock-constant-face ((,class (:foreground ,fg-yellow :weight bold))))
   `(font-lock-function-name-face ((,class (:foreground ,fg-cyan :weight bold))))
   `(font-lock-keyword-face ((,class (:foreground ,fg-yellow :weight bold))))
   `(font-lock-negation-char-face ((,class (:foreground ,fg-yellow :weight bold))))
   `(font-lock-preprocessor-face ((,class (:foreground ,fg-cyan :weight bold))))
   `(font-lock-regexp-grouping-backslash ((,class (:foreground ,fg-yellow))))
   `(font-lock-regexp-grouping-construct ((,class (:foreground ,fg-yellow :weight bold))))
   `(font-lock-string-face ((,class (:foreground ,fg-green))))
   `(font-lock-type-face ((,class (:foreground ,fg-cyan :weight bold))))
   `(font-lock-variable-name-face ((,class (:foreground ,fg-main))))
   `(font-lock-warning-face ((,class (:foreground ,bg :background ,fg-yellow :weight bold))))

   ;; Terminal (ghostel / term / ansi-color)
   `(ansi-color-black ((,class (:foreground ,bg :background ,bg))))
   `(ansi-color-red ((,class (:foreground ,err :background ,err))))
   `(ansi-color-green ((,class (:foreground ,fg-green :background ,fg-green))))
   `(ansi-color-yellow ((,class (:foreground ,fg-yellow :background ,fg-yellow))))
   `(ansi-color-blue ((,class (:foreground ,fg-cyan :background ,fg-cyan))))
   `(ansi-color-magenta ((,class (:foreground ,fg-dim :background ,fg-dim))))
   `(ansi-color-cyan ((,class (:foreground ,fg-cyan :background ,fg-cyan))))
   `(ansi-color-white ((,class (:foreground ,fg-main :background ,fg-main))))

   ;; Dired
   `(dired-directory ((,class (:foreground ,fg-cyan :weight bold))))
   `(dired-symlink ((,class (:foreground ,fg-yellow :slant italic))))
   `(dired-ignored ((,class (:foreground ,fg-subtle))))
   `(dired-marked ((,class (:foreground ,bg :background ,fg-yellow :weight bold))))
   `(dired-header ((,class (:foreground ,fg-main :weight bold))))

   ;; Org Mode
   `(org-level-1 ((,class (:foreground ,fg-cyan :weight bold :height 1.1))))
   `(org-level-2 ((,class (:foreground ,fg-yellow :weight bold))))
   `(org-level-3 ((,class (:foreground ,fg-green :weight bold))))
   `(org-level-4 ((,class (:foreground ,fg-dim))))
   `(org-code ((,class (:foreground ,fg-cyan :background nil))))
   `(org-block ((,class (:foreground ,fg-main :background nil))))
   `(org-table ((,class (:foreground ,fg-cyan))))
   `(org-date ((,class (:foreground ,fg-yellow :underline t))))
   `(org-todo ((,class (:foreground ,bg :background ,fg-yellow :weight bold))))
   `(org-done ((,class (:foreground ,fg-subtle :strike-through t))))

   ;; Markdown
   `(markdown-header-face-1 ((,class (:foreground ,fg-cyan :weight bold :height 1.1))))
   `(markdown-header-face-2 ((,class (:foreground ,fg-yellow :weight bold))))
   `(markdown-header-face-3 ((,class (:foreground ,fg-green :weight bold))))
   `(markdown-code-face ((,class (:foreground ,fg-cyan :background nil))))
   `(markdown-inline-code-face ((,class (:foreground ,fg-cyan :background nil))))
   `(markdown-pre-face ((,class (:foreground ,fg-main :background nil))))
   `(markdown-link-face ((,class (:foreground ,fg-cyan :underline t))))
   `(markdown-url-face ((,class (:foreground ,fg-subtle))))
   `(markdown-list-face ((,class (:foreground ,fg-yellow))))))

;;;###autoload
(and load-file-name
     (boundp 'custom-theme-load-path)
     (add-to-list 'custom-theme-load-path
                  (file-name-as-directory
                   (file-name-directory load-file-name))))

(provide-theme 'blue-white-phosphor)

;;; blue-white-phosphor-theme.el ends here