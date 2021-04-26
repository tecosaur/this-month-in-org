#!/usr/bin/env sh
":"; exec script -eqfc "TERM=xterm-direct emacs --quick -nw --eval '(progn (setq file-to-htmlize \"$1\" output-file \"$2\") (load (expand-file-name \"$0\")))' && rm typescript" 1>/dev/null  # -*- mode: emacs-lisp; lexical-binding: t; -*-

(defvar htmlize-theme 'doom-opera-light)

;; Need output file
(when (string= "" output-file)
  (kill-emacs 2))
(setq output-file (expand-file-name output-file))

;;; Doom initialisation

(unless (bound-and-true-p doom-init-p)
  (setq gc-cons-threshold 16777216
        gcmh-high-cons-threshold 16777216)
  (setq doom-disabled-packages '(doom-themes))
  (load (expand-file-name "core/core.el" user-emacs-directory) nil t)
  (require 'core-cli)
  (doom-initialize))

(advice-add 'undo-tree-mode :override #'ignore) ; Undo tree is a pain

(load-theme htmlize-theme t)

;;; No recentf please

(recentf-mode -1)
(advice-add 'recentf-mode :override #'ignore)
(advice-add 'recentf-cleanup :override #'ignore)

;;; Writegood is not desired

(advice-add 'writegood-mode :override #'ignore)

;;; Quit without fuss

(setq kill-emacs-hook nil
      noninteractive t)

;;; Lighten org-mode

(when (string= "org" (file-name-extension file-to-htmlize))
  (setcdr (assoc 'org after-load-alist) nil)
  (setq org-load-hook nil)
  (require 'org)
  (setq org-mode-hook nil))

;; Start htmlizing

(require 'htmlize)

(ignore-errors
  (with-temp-buffer
    (insert-file-contents file-to-htmlize)
    (setq buffer-file-name file-to-htmlize)
    (ignore-errors
      (normal-mode)
      (if (eq major-mode 'org-mode)
          (org-show-all))
      (font-lock-ensure))
    (with-current-buffer (htmlize-buffer-1)
      (goto-char (point-min))
      (replace-string "</title>\n"
                      "</title>
  <style>
    body { background: #f0eeed !important; }
    body > pre {
      font-size: 1rem;
      max-width: min(100rem, 100%);
      width: max-content;
      white-space: pre-wrap;
      margin: auto;
    }
  </style>\n")
      (write-file output-file)
      (kill-emacs 0))))
(kill-emacs 1)
