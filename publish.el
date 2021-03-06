#!/usr/bin/env sh
":"; exec emacs --quick --script "$0" -- "$@" # -*- mode: emacs-lisp; lexical-binding: t; -*-

(message "Publising")

(pop argv) ; $0
(setq force (string= "-f" (pop argv)))

;;; Doom initialisation

(unless (bound-and-true-p doom-init-p)
  (setq gc-cons-threshold 16777216
        gcmh-high-cons-threshold 16777216)
  (setq doom-disabled-packages '(doom-themes))
  (load (expand-file-name "core/core.el" user-emacs-directory) nil t)
  (require 'core-cli)
  (doom-initialize))

(advice-add 'undo-tree-mode :override #'ignore) ; Undo tree is a pain

;;; General publishing setup

(section! "Initialising")

(require 'ox-publish)

(setq site-root "https://blog.tecosaur.com/tmio/")

(let ((css-src (expand-file-name "misc/org-css/main.css" doom-private-dir))
      (css-dest (expand-file-name "assets/org-style.css" (file-name-directory load-file-name)))
      (js-src (expand-file-name "misc/org-css/main.js" doom-private-dir))
      (js-dest (expand-file-name "assets/org-style.js" (file-name-directory load-file-name))))
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
      org-id-locations-file (expand-file-name ".orgids")
      org-babel-default-inline-header-args '((:eval . "no") (:exports . "code")))

;;; For some reason emoji detection doesn't seem to work, so let's just turn it on

(setcar (rassoc 'emoji org-latex-conditional-features) t)

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
    (if rtn (message "Publishing file \033[0;34m%s\033[0m using \033[0;36m%s\033[0m" (file-name-nondirectory filename) pub-func)
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

;;; No recentf please

(recentf-mode -1)
(advice-add 'recentf-mode :override #'ignore)
(advice-add 'recentf-cleanup :override #'ignore)

;;; Htmlized file publishing

(defun org-publish-to-htmlized (_plist filename pub-dir)
  "Publish a file with no change other than maybe optimisation.

FILENAME is the filename of the Org file to be published.  PLIST
is the property list for the given project.  PUB-DIR is the
publishing directory.

Return output file name."
  (unless (file-directory-p pub-dir)
    (make-directory pub-dir t))
  (call-process (expand-file-name "./htmlize-file.el") nil nil nil filename (expand-file-name (concat (file-name-base filename) ".org.html") pub-dir)))

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

;; Headers 'n footers

(setq html-preamble (file-contents "assets/header.html")
      html-postamble (file-contents "assets/footer.html"))

;;; Some cache files are unwanted

(let ((index-cache-file (expand-file-name "This Month in Org - Index.cache" org-publish-timestamp-directory))
      (archive-cache-file (expand-file-name "This Month in Org - Archive,404.cache" org-publish-timestamp-directory))
      (rss-cache-file (expand-file-name "This Month in Org - RSS.cache" org-publish-timestamp-directory)))
  (when (file-exists-p index-cache-file)
    (warn! "Removing Index cache file to force regeneration")
    (delete-file index-cache-file))
  (when (file-exists-p archive-cache-file)
    (warn! "Removing Archive cache file to force regeneration")
    (delete-file archive-cache-file))
  (when (file-exists-p rss-cache-file)
    (warn! "Removing problematic RSS cache file")
    (delete-file rss-cache-file)))

;;; Putting it all together

(setq org-publish-project-alist
      `(("This Month in Org"
         :components ("This Month in Org - Pages"
                      "This Month in Org - Index"
                      "This Month in Org - Archive,404"
                      "This Month in Org - Assets"
                      "This Month in Org - RSS"))
        ("This Month in Org - Pages"
         :base-directory "./content"
         :base-extension "org"
         :publishing-directory "./html"
         :exclude "rss\\.org"
         :recursive t
         :publishing-function
         (org-html-publish-to-html
          org-org-publish-to-org
          org-publish-to-htmlized
          org-ascii-publish-to-utf8
          org-latex-publish-to-pdf)
         :headline-levels 4
         :section-numbers nil
         :with-toc nil
         :html-preamble t
         :html-preamble-format (("en" ,html-preamble))
         :html-postamble t
         :html-postamble-format (("en" ,html-postamble)))
        ("This Month in Org - Index"
         :base-directory "./assets"
         :base-extension "org"
         :publishing-directory "./html"
         :exclude ".*"
         :include ("index.org")
         :recursive nil
         :publishing-function org-html-publish-to-html
         :headline-levels 4
         :section-numbers nil
         :with-toc nil
         :html-head-extra ,(file-contents "assets/index-head-extra.html")
         :html-preamble nil
         :html-postamble t
         :html-postamble-format (("en" ,html-postamble)))
        ("This Month in Org - Archive,404"
         :base-directory "./assets"
         :base-extension "org"
         :publishing-directory "./html"
         :exclude ".*"
         :include ("archive.org" "404.org")
         :recursive nil
         :publishing-function org-html-publish-to-html
         :headline-levels 4
         :section-numbers nil
         :with-toc nil
         :html-preamble t
         :html-preamble-format (("en" ,html-preamble))
         :html-postamble t
         :html-postamble-format (("en" ,html-postamble)))
        ("This Month in Org - Assets"
         :base-directory "./assets"
         :base-extension any
         :exclude "\\.html$" ; template files
         :publishing-directory "./html"
         :recursive t
         :publishing-function org-publish-attachment-optimised)
        ("This Month in Org - RSS"
         :base-directory "./content"
         :base-extension "org"
         :recursive nil
         :exclude ,(rx (or "rss.org" (regexp "DRAFT.*\\.org")))
         :publishing-function org-rss-publish-to-rss-only
         :publishing-directory "./html"
         :rss-extension "xml"
         :html-link-home ,site-root
         :html-link-use-abs-url t
         :html-link-org-files-as-html t
         :auto-sitemap t
         :sitemap-filename "rss.org"
         :sitemap-title "This Month in Org"
         :sitemap-style list
         :sitemap-sort-files anti-chronologically
         :sitemap-function format-rss-feed
         :sitemap-format-entry format-rss-feed-entry)
        ))

(section! "Publishing files")
(when force
  (warn! "Force flag set"))

(when force
  (delete-directory "./html" t))

(org-publish "This Month in Org" force)

(section! "Uploading")
(let ((rsync-status
       (with-temp-buffer
         (cons (call-process "rsync" nil t nil "-avzL" "--delete"
                             (expand-file-name "html/" (file-name-directory load-file-name))
                             "imh:/home/thedia18/public_html/tecosaur.com/blog/tmio/")
               (message "\033[0;33m%s\033[0m" (buffer-string))))))
  (if (= (car rsync-status) 0)
      (success! "Content uploaded")
    (error! "Content failed to upload, rsync exited with code %d" rsync-code)))
