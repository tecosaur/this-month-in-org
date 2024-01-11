#!/usr/bin/env sh
":"; exec emacs --quick --script "$0" -- "$@" # -*- mode: emacs-lisp; lexical-binding: t; -*-

(unless load-file-name
  (error "This is designed to be run as a script file, not within Emacs"))

(defvar cli-mode-force nil)    ; -f, --force
(defvar cli-mode-draft nil)    ; -d, --draft
(defvar cli-mode-publish nil)  ; -p, --publish
(defvar cli-mode-nopush nil)   ; -n, --nopush
(defvar cli-mode-onlypush nil) ; -o, --onlypush

(pop argv) ; $0

(when (or (member "-h" argv) (member "--help" argv))
  (setq argv nil)
  (message "
    publish.el [switches]

Switches:
  -f, --force      Force publishing all files
  -d, --draft      Publish a draft update, including DRAFT-* files
  -p, --publish    Explicitly publish an update (default), negates --draft
  -n, --nopush     Skip the push step, perform a dry-run
  -o, --onlypush   Skip file generation, just push (intended for use after a dry-run)

When neither --draft or --publish are provided, the mode will be picked based on
the presence of unstaged files.  This primarily affects the publication commit.")
  (kill-emacs 0))

(while argv
  (pcase (pop argv)
    ((or "-f" "--force")
     (setq cli-mode-force t))
    ((or "-d" "--draft")
     (setq cli-mode-draft t))
    ((or "-p" "--publish")
     (setq cli-mode-publish t))
    ((or "-n" "--nopush")
     (setq cli-mode-nopush t))
    ((or "-o" "--onlypush")
     (setq cli-mode-onlypush t))))

(when (and cli-mode-draft cli-mode-publish)
  (error "--publish and --draft are mutually exclusive, pick one"))
(when (and cli-mode-draft cli-mode-onlypush)
  (error "--nopush and --onlypush are mutually exclusive, pick one"))

(setq gc-cons-threshold (* 4 1024 1024)
      gcmh-high-cons-threshold (* 4 1024 1024))

;;; Package initialisation

(unless (file-directory-p "~/.config/doom")
  (error "This publishing script currently assumes a Doom emacs install exists."))

;; Assumes that the doom install is already fully-functional.
(push "~/.config/emacs/lisp" load-path)
(push "~/.config/emacs/lisp/lib" load-path)
(require 'doom-lib)
(require 'doom)
(doom-require 'doom-lib 'files)
(require 'doom-modules)
(require 'doom-packages)
(doom-initialize-packages)

;;I don't like this, but it works.
(dolist (subdir (directory-files (file-name-concat straight-base-dir "straight" straight-build-dir) t))
  (push subdir load-path))

(require 'doom-cli)
(doom-require 'doom-cli 'doctor)

(doom-module-context-with '(:config . use-package)
  (doom-load (abbreviate-file-name
              (file-name-sans-extension
               (doom-module-locate-path :config 'use-package doom-module-init-file)))))

(defun doom-shut-up-a (fn &rest args)
  ;;`quiet!' is defined in doom-lib.el
  (quiet! (apply fn args)))

(push "~/.config/doom/subconf" load-path)

;;; General publishing setup

(section! "Initialising")

(require 'org)
(require 'ox-publish)
(require 'ox-html)
(require 'ox-latex)
(require 'ox-ascii)
(require 'ox-org) ; For the word count
(require 'org-persist)
(remove-hook 'kill-emacs-hook #'org-persist-gc)

(require 's) ; Needed for my config

(provide 'config-org-behaviour) ; We *don't* want this
(require 'config-org-exports)
(require 'config-ox-html)
(require 'config-ox-latex)
(require 'config-ox-ascii)

(require 'engrave-faces-html)
(load (expand-file-name "engraved-theme.el" (file-name-directory load-file-name)))
(engrave-faces-use-theme 'doom-opera-light)

;; For faces
(require 'highlight-quoted)
(require 'highlight-numbers)
(require 'rainbow-delimiters)

;; Setup

(setq blog-name "This Month in Org"
      site-root "https://blog.tecosaur.net/tmio/"
      user-full-name "TEC"
      user-mail-address "contact.tmio@tecosaur.net"
      publish-root (file-name-directory load-file-name)
      content-dir (file-name-concat publish-root "content")
      html-dir (file-name-concat publish-root "html")
      assets-dir (file-name-concat publish-root "assets")
      git-publish-branch "html")

(setq default-directory publish-root)

(let ((css-src (expand-file-name "misc/org-css/main.css" doom-user-dir))
      (css-dest (file-name-concat assets-dir "org-style.css"))
      (js-src (expand-file-name "misc/org-css/main.js" doom-user-dir))
      (js-dest (file-name-concat assets-dir "org-style.js")))
  (when (file-newer-than-file-p css-src css-dest)
    (copy-file css-src css-dest t))
  (when (file-newer-than-file-p js-src js-dest)
    (copy-file js-src js-dest t)))

(defun file-contents (file)
  (with-temp-buffer
    (insert-file-contents file)
    (buffer-string)))

(setq org-html-style-default (file-contents "assets/head.html")
      org-html-scripts ""
      org-html-meta-tags-opengraph-image
      `(:image ,(concat site-root "org-icon.png")
        :type "image/png"
        :width "464"
        :height "512"
        :alt "Org unicorn logo")
      org-export-with-broken-links t
      org-id-locations-file (file-name-concat html-dir ".orgids")
      org-babel-default-inline-header-args '((:eval . "no") (:exports . "code"))
      org-confirm-babel-evaluate nil
      org-resource-download-policy t
      org-publish-list-skipped-files nil)

(setf (alist-get :eval org-babel-default-header-args) "no")

;;; For some reason emoji detection doesn't seem to work, so let's just turn it on

;; (setcar (rassoc 'emoji org-latex-conditional-features) t)

;;; Remove generated .tex/.pdf files from the base directory

(defadvice! org-latex-publish-to-pdf-rm-a (_plist filename _pub-dir)
  :after #'org-latex-publish-to-pdf
  (let ((tex-file (concat (file-name-sans-extension filename) ".tex"))
        (pdf-file (concat (file-name-sans-extension filename) ".pdf")))
    (when (file-exists-p tex-file)
      (delete-file tex-file))
    (when (file-exists-p pdf-file)
      (delete-file pdf-file))))

;;; Compress certain files

(defun org-publish-attachment-optimised (_plist filename pub-dir)
  "Publish a file with no change other than maybe optimisation.

FILENAME is the filename of the Org file to be published.  PLIST
is the property list for the given project.  PUB-DIR is the
publishing directory.

Return output file name."
  (unless (file-directory-p pub-dir)
    (make-directory pub-dir t))
  (let ((ext (file-name-extension filename))
        (outfile (expand-file-name (file-name-nondirectory filename) pub-dir))
        (figure? (string= "figure" (file-name-nondirectory (directory-file-name (file-name-directory filename))))))
    (unless (file-equal-p (expand-file-name (file-name-directory filename))
                          (file-name-as-directory (expand-file-name pub-dir)))
      (cond
       ((and figure? (string= "png" ext)
             (executable-find "pngquant"))
        (message "optimising %s with pngquant" (file-name-nondirectory filename))
        (call-process "pngquant" nil nil nil "--output" outfile filename))
       ((and figure? (string= "svg" ext)
             (executable-find "svgo"))
        (message "optimising %s with svgo" (file-name-nondirectory filename))
        (call-process "svgo" nil nil nil "-o" outfile filename))
       ((and (string= "css" ext)
             (executable-find "csso"))
        (message "optimising %s with csso" (file-name-nondirectory filename))
        (call-process "csso" nil nil nil "-i" filename "-o" outfile))
       ((and (string= "scss" ext)
             (executable-find "sassc"))
        (message "converting %s to css with sassc" (file-name-nondirectory filename))
        (setq outfile (replace-regexp-in-string "\\.scss$" ".css" outfile))
        (call-process "sassc" nil nil nil "--style" "compressed" filename outfile))
       (t (copy-file filename outfile t)))
      outfile)))

;;; Use ascii colours to make output more informative

(defadvice! org-publish-needed-p-cleaner
  (filename &optional pub-dir pub-func _true-pub-dir base-dir)
  :override #'org-publish-needed-p
  (let ((rtn (if (not org-publish-use-timestamps-flag) t
               (org-publish-cache-file-needs-publishing
                filename pub-dir pub-func base-dir))))
    (if rtn
        (message "Publishing file (\033[0;36m%s\033[0m) \033[0;34m%s\033[0m"
                 (replace-regexp-in-string
                  "\\`org-\\(.+?\\)-publish.*\\'" "\\1"
                  (symbol-name pub-func))
                 (file-name-nondirectory filename)
                 pub-func)
      (when org-publish-list-skipped-files
        (message "\033[0;90mSkipping unmodified file %s\033[0m" filename)))
    rtn))

(defadvice! org-publish-initialize-cache-message-a (project-name)
  :before #'org-publish-initialize-cache
  (message "\033[0;35m%s\033[0m" project-name))

;;; Silence uninformative noise

(advice-add 'org-toggle-pretty-entities :around #'doom-shut-up-a)
(advice-add 'indent-region :around #'doom-shut-up-a)
(advice-add 'rng-what-schema :around #'doom-shut-up-a)
(advice-add 'ispell-init-process :around #'doom-shut-up-a)
(advice-add 'org-babel-check-evaluate :around #'doom-shut-up-a)
(advice-add 'org-babel-exp-results :around #'doom-shut-up-a)

;;; No recentf please

(recentf-mode -1)
(advice-add 'recentf-mode :override #'ignore)
(advice-add 'recentf-cleanup :override #'ignore)

;;; Htmlized file publishing

(defun org-publish-to-engraved (_plist filename pub-dir)
  "Publish a file with no change other than maybe optimisation.

FILENAME is the filename of the Org file to be published.  PLIST
is the property list for the given project.  PUB-DIR is the
publishing directory.

Return output file name."
  (unless (file-directory-p pub-dir)
    (make-directory pub-dir t))
  (engrave-faces-html-file filename (expand-file-name (concat (file-name-base filename) ".org.html") pub-dir)))

;;; RSS

(defun org-rss-publish-to-rss-only (plist filename pub-dir)
  "Publish RSS with PLIST, only when FILENAME is 'rss.org'.
PUB-DIR is when the output will be placed."
  (when (equal "rss.org" (file-name-nondirectory filename))
    (let ((org-fancy-html-export-mode nil))
      (org-rss-publish-to-rss plist filename pub-dir))
    (org-fix-rss (concat pub-dir (file-name-base filename) ".xml"))))

(defun format-rss-feed (title list)
  "Generate RSS feed, as a string.
TITLE is the title of the RSS feed.  LIST is an internal
representation for the files to include, as returned by
`org-list-to-lisp'.  PROJECT is the current project."
  (concat "#+title: " title "\n\n"
          (org-list-to-subtree list 1 '(:icount "" :istart ""))))

(defun format-rss-feed-entry (entry style project)
  "Format ENTRY for the RSS feed.
ENTRY is a file name.  STYLE is either 'list' or 'tree'.
PROJECT is the current project."
  (cond ((not (directory-name-p entry))
         (let* ((file (org-publish--expand-file-name entry project))
                (title (org-publish-find-title entry project))
                (date (format-time-string "%Y-%m-%d" (org-publish-find-date entry project)))
                (link (concat (file-name-sans-extension entry) ".html")))
           (with-temp-buffer
             (org-mode)
             (insert (format "* [[file:%s][%s]]\n" file title))
             (org-set-property "RSS_TITLE" title)
             (org-set-property "RSS_PERMALINK" link)
             (org-set-property "PUBDATE" date)
             (insert-file-contents file)
             (goto-char (point-min))
             (while (re-search-forward "\\[fn:\\([^]]+\\)\\]" nil t)
               (replace-match "[fn\\1]")) ; footnotes are problematic
             (goto-char (point-min))
             (while (re-search-forward "\\[\\[file:\\(figures/.+?\\)\\]\\]" nil t)
               (replace-match (concat "[[" site-root "\\1]]")))
             (buffer-string))))
        ((eq style 'tree)
         ;; Return only last subdir.
         (file-name-nondirectory (directory-file-name entry)))
        (t entry)))

(defun org-fix-rss (file)
  (with-temp-buffer
    (insert-file-contents file)
    (goto-char (point-min))
    (when (search-forward "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n<?xml version=\"1.0\" encoding=\"utf-8\"?>" nil t)
      (replace-match "<?xml version=\"1.0\" encoding=\"utf-8\"?>"))
    (while (re-search-forward "<span class='acr'>\\(.+?\\)</span>" nil t)
      (replace-match "\\1"))
    (write-file file)))

;;; Putting it all together

(defun do-publish ()
  "Publish the blog into `html-dir'."
  (let ((blog-component-pages       (format "%s - Pages" blog-name))
        (blog-component-index       (format "%s - Index" blog-name))
        (blog-component-archive&404 (format "%s - Archive,404" blog-name))
        (blog-component-assets      (format "%s - Assets" blog-name))
        (blog-component-rss         (format "%s - RSS" blog-name))
        (html-header (file-contents "assets/header.html"))
        (html-footer (file-contents "assets/footer.html")))
    ;; Get rid of unwanted cache files
    (let ((index-cache-file
           (file-name-concat org-publish-timestamp-directory (concat blog-component-index ".cache")))
          (archive-cache-file
           (file-name-concat org-publish-timestamp-directory (concat blog-component-archive&404 ".cache")))
          (rss-cache-file
           (file-name-concat org-publish-timestamp-directory (concat blog-component-rss ".cache"))))
      (when (file-exists-p index-cache-file)
        (warn! "Removing Index cache file to force regeneration")
        (delete-file index-cache-file))
      (when (file-exists-p archive-cache-file)
        (warn! "Removing Archive cache file to force regeneration")
        (delete-file archive-cache-file))
      (when (file-exists-p rss-cache-file)
        (warn! "Removing problematic RSS cache file")
        (delete-file rss-cache-file)))
    ;;Set up the publish alist
    (setq org-publish-project-alist
          `((,blog-name
             :components (,blog-component-pages
                          ,blog-component-index
                          ,blog-component-archive&404
                          ,blog-component-assets
                          ,blog-component-rss))
            (,blog-component-pages
             :base-directory ,content-dir
             :base-extension "org"
             :publishing-directory ,html-dir
             :exclude "rss\\.org"
             :recursive t
             :publishing-function
             (org-html-publish-to-html
              org-org-publish-to-org
              org-publish-to-engraved
              org-ascii-publish-to-utf8
              ;; org-latex-publish-to-pdf
              )
             :headline-levels 4
             :section-numbers nil
             :with-toc nil
             :html-preamble t
             :html-preamble-format (("en" ,html-header))
             :html-postamble t
             :html-postamble-format (("en" ,html-footer)))
            (,blog-component-index
             :base-directory ,assets-dir
             :base-extension "org"
             :publishing-directory ,html-dir
             :exclude ".*"
             :include ("index.org")
             :recursive nil
             :publishing-function org-html-publish-to-html
             :time-stamp-file nil
             :headline-levels 4
             :section-numbers nil
             :with-toc nil
             :html-head-extra ,(file-contents (file-name-concat assets-dir "index-head-extra.html"))
             :html-preamble nil
             :html-postamble t
             :html-postamble-format (("en" ,html-footer)))
            (,blog-component-archive&404
             :base-directory ,assets-dir
             :base-extension "org"
             :publishing-directory ,html-dir
             :exclude ".*"
             :include ("archive.org" "404.org")
             :recursive nil
             :publishing-function org-html-publish-to-html
             :time-stamp-file nil
             :headline-levels 4
             :section-numbers nil
             :with-toc nil
             :html-preamble t
             :html-preamble-format (("en" ,html-header))
             :html-postamble t
             :html-postamble-format (("en" ,html-footer)))
            (,blog-component-assets
             :base-directory ,assets-dir
             :base-extension any
             :exclude "\\.html$" ; template files
             :publishing-directory ,html-dir
             :recursive t
             :publishing-function org-publish-attachment-optimised)
            (,blog-component-rss
             :base-directory ,content-dir
             :base-extension "org"
             :recursive nil
             :exclude ,(rx (or "rss.org" (regexp "DRAFT.*\\.org")))
             :publishing-function org-rss-publish-to-rss-only
             :publishing-directory ,html-dir
             :rss-extension "xml"
             :html-link-home ,site-root
             :html-link-use-abs-url t
             :html-link-org-files-as-html t
             :auto-sitemap t
             :sitemap-filename "rss.org"
             :sitemap-title ,blog-name
             :sitemap-style list
             :sitemap-sort-files anti-chronologically
             :sitemap-function format-rss-feed
             :sitemap-format-entry format-rss-feed-entry)))

    (section! "Publishing files")

    (when cli-mode-force
      (warn! "Force flag set"))

    (when (and cli-mode-force (file-directory-p html-dir))
      (call-process "git" nil nil nil "worktree" "remove" "-f" git-publish-branch)
      (call-process "git" nil nil nil "worktree" "prune")
      (delete-directory html-dir t)
      (call-process "git" nil nil nil "worktree" "add" html-dir git-publish-branch)
      (if (file-directory-p html-dir)
          (dolist (child (directory-files html-dir))
            (unless (member child '("." ".." ".git"))
              (if (file-directory-p child)
                  (delete-directory child t)
                (delete-file child))))
        (warn! "Failed to create html worktree")))

    (unless (file-directory-p html-dir)
      (call-process "git" nil nil nil "worktree" "add" html-dir git-publish-branch)
      (unless (file-directory-p html-dir)
        (warn! "Failed to create html worktree")))

    (org-publish blog-name cli-mode-force)))

;; To make somewhat nice git history in the HTML branch, we'll want to collect
;; information on the current state off affairs and commit accordingly.
;;
;; We start by checking to see if we should make a "publish" style commit or a
;; "draft" style commit. This is determied by seeing if there are any
;; =content/...= lines in the git status, the assumption being that at each
;; publish point everything under =content/= has been comitted.
;;
;; Then we check to see if the last commit in the html branch is a "publish"
;; style commit or a "draft" style commit. We make this easy for ourselves by
;; prepending draft commits messages with the keyword "DRAFT". Should the last
;; commit be a draft, we replace it. Otherwise, a new commit is created.
;;
;; Lastly, we actually push the HTML branch.

(defun last-commit-log (fmt &optional branch)
  "Get the log line for the last commit in FMT (optionally for BRANCH)."
  (with-temp-buffer
    (apply #'call-process "git" nil t nil "log"
           (delq nil (list (and branch (format "refs/heads/%s" branch)) "-1"
                           (format "--pretty=format:%s" fmt))))
    (buffer-string)))

(defun last-commit-subject (&optional branch)
  "Get the commit subject line."
  (last-commit-log "%s" branch))

(defun last-commit-hash (&optional branch)
  "Get the commit subject line."
  (last-commit-log "%h" branch))

(defun get-unstaged-changes ()
  "List all unstaged changes in the form ((status . filepath)...)."
  (with-temp-buffer
    (call-process "git" nil t nil "status" "--porcelain=v1")
    (goto-char (point-min))
    (let (changes)
      (while (re-search-forward "^\\(..\\) +" nil t)
        (push (cons (match-string 1)
                    (and (re-search-forward "[^\n]+" nil t)
                         (match-string 0)))
              changes))
      changes)))

(defun git-try-command (&rest args)
  "Try to run git with ARGS, returning t on success, nil on error.
Should an error occur, an informative message is printed."
  (with-temp-buffer
    (setq args (delq nil args))
    (let ((exit-code (apply #'call-process "git" nil t nil args)))
      (or (eq exit-code 0)
          (progn
            (error! "Failed to %s" (car args))
            (message "  Git command: git %s" (mapconcat #'shell-quote-argument args " "))
            (message "  Error: %s" (mapconcat #'identity (split-string (buffer-string) "\n") "\n         "))
            nil)))))

(defun do-push ()
  "Perform the push step."
  (let* ((draft-mode-p
          (or cli-mode-draft
              (and (not cli-mode-publish)
                   (member (file-name-base content-dir)
                           (mapcar
                            (lambda (change) (car (file-name-split (cdr change))))
                            (get-unstaged-changes))))))
         (html-draft-p (string-prefix-p "DRAFT " (last-commit-subject git-publish-branch)))
         (html-changed-files (length (let ((default-directory html-dir)) (get-unstaged-changes))))
         (commit-message
          (if draft-mode-p
              (format "DRAFT update (%s files changed)\nLast source commit: %s\nLocal time: %s"
                      html-changed-files
                      (last-commit-hash)
                      (format-time-string "%F %T (UTC%z)"))
            (format "Publish update based on %s" (last-commit-hash)))))
    (if draft-mode-p
        (section! "Pushing (draft)")
      (section! "Pushing"))
    (if (= html-changed-files 0)
        (warn! "No changes to push")
      (let ((default-directory html-dir))
        (and (prog1 (or (not html-draft-p)
                        (git-try-command "reset" "--soft" "HEAD~1"))
               (unless draft-mode-p
                 (dolist (file (mapcar #'cdr (get-unstaged-changes)))
                   (when (and (file-exists-p file)
                              (string-prefix-p "DRAFT-" (file-name-base file)))
                     (warn! "Skipping draft file %s" file)
                     (delete-file file)))))
             (git-try-command "add" "-A")
             (git-try-command "commit" "--message" commit-message)
             (git-try-command "push" (and html-draft-p "--force-with-lease")))))))

(cond
 (cli-mode-nopush
  (do-publish)
  (warn! "Skipping push step"))
 (cli-mode-onlypush
  (warn! "Skipping publish step")
  (do-push))
 (t ; Default behaviour
  (do-publish)
  (do-push)))

(section! "Finished")
