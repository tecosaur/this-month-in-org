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

(defadvice! undo-tree-no-err (orig-fn &rest args)
  :around #'undo-tree-load-history
  (ignore-errors (apply orig-fn args)))

(section! "Initialising")

;;; General publishing setup

(require 'ox-publish)

(setq site-root "https://blog.tecosaur.com/tmio/")

(copy-file (expand-file-name "misc/org-css/main.min.css" doom-private-dir)
           (expand-file-name "assets/org-style.css" (file-name-directory load-file-name)) t)
(copy-file (expand-file-name "misc/org-css/main.js" doom-private-dir)
           (expand-file-name "assets/org-style.js" (file-name-directory load-file-name)) t)

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
      org-id-locations-file (expand-file-name ".orgids"))

;;; RSS

(defun org-rss-publish-to-rss-only (plist filename pub-dir)
  "Publish RSS with PLIST, only when FILENAME is 'rss.org'.
PUB-DIR is when the output will be placed."
  (when (equal "rss.org" (file-name-nondirectory filename))
    (org-rss-publish-to-rss plist filename pub-dir)
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

;;; Putting it all together

(let ((index-cache-file (expand-file-name "This Month in Org - Index.cache" org-publish-timestamp-directory))
      (archive-cache-file (expand-file-name "This Month in Org - Archive.cache" org-publish-timestamp-directory))
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

(setq org-publish-project-alist
      `(("This Month in Org"
         :components ("This Month in Org - Pages"
                      "This Month in Org - Index"
                      "This Month in Org - Archive"
                      "This Month in Org - Assets"
                      "This Month in Org - RSS"))
        ("This Month in Org - Pages"
         :base-directory "./content"
         :base-extension "org"
         :publishing-directory "./html"
         :exclude ,(rx (or "rss.org" "index.org" "archive.org" "404.org"))
         :recursive t
         :publishing-function
         (org-html-publish-to-html
          org-org-publish-to-org
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
         :base-directory "./content"
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
        ("This Month in Org - Archive"
         :base-directory "./content"
         :base-extension "org"
         :publishing-directory "./html"
         :exclude ".*"
         :include ("archive.org")
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
         :publishing-function org-publish-attachment)
        ("This Month in Org - RSS"
         :base-directory "./content"
         :base-extension "org"
         :recursive nil
         :exclude ,(rx (or "rss.org" "index.org" "archive.org" "404.org" (regexp "DRAFT.*\\.org")))
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

(org-publish "This Month in Org" force)

(section! "Uploading")
(let ((rsync-status
       (with-temp-buffer
         (cons (call-process "rsync" nil t nil "-avzL" "--delete"
                             (expand-file-name "html/" (file-name-directory load-file-name))
                             "imh:/home/thedia18/public_html/tecosaur.com/blog/tmio/")
               (message (buffer-string))))))
  (if (= (car rsync-status) 0)
      (success! "Content uploaded")
    (error! "Content failed to upload, rsync exited with code %d" rsync-code)))
