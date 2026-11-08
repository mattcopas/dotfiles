;;; generate.el --- Capture real org behaviour as test expectations -*- lexical-binding: t; -*-
;; Run on the home machine only, through generate.sh. Never needed on the work machine:
;; the outputs in test/golden/expected are committed, and the tests only read those.
(require 'cl-lib)
(defvar gen-root (file-name-directory (or load-file-name buffer-file-name)))
(defvar gen-repo (expand-file-name "../../../../" gen-root))
(defvar gen-fix (expand-file-name "../fixtures/" gen-root))
(defvar gen-out (expand-file-name "expected/" gen-root))
(defvar gen-work (getenv "ORGFLOW_GOLDEN_WORK"))
(dolist (dir (list "org/lisp" "org-journal")) nil)
(add-to-list 'load-path (expand-file-name "emacs/elpaca/sources/org/lisp" gen-repo))
(add-to-list 'load-path (expand-file-name "emacs/elpaca/sources/org-journal" gen-repo))

;; A fixed clock, so outputs are stable. Wed 11 Nov 2026 10:30 local.
(defvar gen-now (encode-time 0 30 10 11 11 2026))
(defun gen-set-now (min hour day month year) (setq gen-now (encode-time 0 min hour day month year)))
(advice-add 'current-time :override (lambda () gen-now))
(advice-add 'format-time-string :filter-args
            (lambda (args) (if (cadr args) args (list (car args) gen-now (nth 2 args)))))
(advice-add 'decode-time :filter-args
            (lambda (args) (if (car args) args (cons gen-now (cdr args)))))
(advice-add 'float-time :filter-args
            (lambda (args) (if (car args) args (list gen-now))))
(advice-add 'time-to-days :filter-args
            (lambda (args) (if (car args) args (list gen-now))))

;; org-today goes through time-since, which reads the C clock directly.
(advice-add 'time-since :override
            (lambda (time) (time-subtract gen-now time)))
(advice-add 'time-less-p :filter-args
            (lambda (args) (list (or (car args) gen-now) (or (cadr args) gen-now))))
(advice-add 'calendar-current-date :override
            (lambda (&optional _offset)
              (let ((d (decode-time gen-now)))
                (list (nth 4 d) (nth 3 d) (nth 5 d)))))

(setenv "LC_ALL" "C")
(setq system-time-locale "C" make-backup-files nil auto-save-default nil create-lockfiles nil
      inhibit-message nil org-element-use-cache nil)
(require 'org)
(require 'org-agenda)
(require 'org-capture)
(require 'calendar)

;; Load the user's real config by evaluating only its defuns, so the fixtures
;; run against the same keywords, views and capture templates as Emacs itself.
(with-temp-buffer
  (insert-file-contents (expand-file-name "emacs/lisp/modules/org.el" gen-repo))
  (goto-char (point-min))
  (condition-case nil
      (while t
        (let ((form (read (current-buffer))))
          (when (eq (car-safe form) 'defun) (eval form t))))
    (end-of-file nil)))
(me--configure-org)
(defvar gen-agenda-dir (expand-file-name "agenda/" gen-fix))

(defun gen-write (name text)
  (let ((file (expand-file-name name gen-out)))
    (make-directory (file-name-directory file) t)
    (with-temp-file file (insert text))))

(defun gen-copy (from name)
  "Copy fixture FROM to a scratch file NAME and return the path."
  (let ((dest (expand-file-name name gen-work)))
    (make-directory (file-name-directory dest) t)
    (copy-file (expand-file-name from gen-fix) dest t)
    dest))

(defun gen-agenda ()
  (setq org-agenda-files
        (list (expand-file-name "personal" gen-agenda-dir)
              (expand-file-name "client" gen-agenda-dir)
              (expand-file-name "work" gen-agenda-dir))
        org-agenda-window-setup 'current-window
        org-agenda-sticky nil)
  (dolist (key '("c" "w" "p"))
    (org-agenda nil key)
    (gen-write (format "agenda-%s.txt" key)
               (buffer-substring-no-properties (point-min) (point-max)))))

(defun gen-each-heading (file fn)
  "Call FN at every heading in a fresh buffer on FILE, in reverse order, then save."
  (let ((buffer (find-file-noselect file)))
    (with-current-buffer buffer
      (org-mode)
      (goto-char (point-max))
      (while (re-search-backward "^\\*+ " nil t)
        (save-excursion (funcall fn)))
      (save-buffer))
    (kill-buffer buffer)))

(defun gen-edit (from name fn)
  (let ((file (gen-copy from name)))
    (let ((buffer (find-file-noselect file)))
      (with-current-buffer buffer
        (org-mode)
        (org-fold-show-all)
        (funcall fn)
        (save-buffer))
      (kill-buffer buffer))
    (gen-write name (with-temp-buffer (insert-file-contents file) (buffer-string)))))

(defun gen-goto (title)
  (goto-char (point-min))
  (re-search-forward (concat "^\\*+ .*" (regexp-quote title)))
  (org-back-to-heading t))

(defun gen-edits ()
  ;; Marking every repeater fixture DONE.
  (let ((file (gen-copy "edits/repeat.org" "edit-repeat.org")))
    (gen-each-heading file (lambda () (org-todo "DONE")))
    (gen-write "edit-repeat.org" (with-temp-buffer (insert-file-contents file) (buffer-string))))
  ;; Scheduling every heading, for today and then a fixed offset.
  (let ((file (gen-copy "edits/schedule.org" "edit-schedule-today.org")))
    (gen-each-heading file (lambda () (org-schedule nil "+0d")))
    (gen-write "edit-schedule-today.org" (with-temp-buffer (insert-file-contents file) (buffer-string))))
  (let ((file (gen-copy "edits/schedule.org" "edit-schedule-tomorrow.org")))
    (gen-each-heading file (lambda () (org-schedule nil "+1d")))
    (gen-write "edit-schedule-tomorrow.org" (with-temp-buffer (insert-file-contents file) (buffer-string))))
  ;; Structure editing.
  (gen-edit "edits/table.org" "edit-table-align.org"
            (lambda () (goto-char (point-min)) (search-forward "apple") (org-table-align)
              (search-forward "Second") (forward-line 1) (org-table-align)))
  (gen-edit "edits/structure.org" "edit-move-second-up.org" (lambda () (goto-char (point-min)) (re-search-forward "^\\* Second") (org-back-to-heading t) (org-metaup)))
  (gen-edit "edits/structure.org" "edit-move-down.org" (lambda () (gen-goto "First") (org-metadown)))
  (gen-edit "edits/structure.org" "edit-move-up.org" (lambda () (gen-goto "Second") (org-metaup)))
  (gen-edit "edits/structure.org" "edit-move-child-down.org" (lambda () (gen-goto "First child") (org-metadown)))
  (gen-edit "edits/structure.org" "edit-promote-subtree.org" (lambda () (gen-goto "First child") (org-shiftmetaleft)))
  (gen-edit "edits/structure.org" "edit-demote-subtree.org" (lambda () (gen-goto "Second") (org-shiftmetaright)))
  (gen-edit "edits/structure.org" "edit-promote.org" (lambda () (gen-goto "First child") (org-metaleft)))
  (gen-edit "edits/structure.org" "edit-demote.org" (lambda () (gen-goto "First") (org-metaright)))
  (gen-edit "edits/structure.org" "edit-demote-third.org" (lambda () (gen-goto "Third") (org-metaright))))

(defun gen-capture ()
  (dolist (spec '(("ww" "Work plain" "edit-capture-ww.org" "Todo list" work)
                  ("wt" "Work today" "edit-capture-wt.org" "Todo list" work)
                  ("wT" "Work tomorrow" "edit-capture-wT.org" "Todo list" work)
                  ("t" "Plain append" "edit-capture-t.org" "Todo list" plain)))
    (pcase-let ((`(,key ,title ,name ,_ ,_) spec))
      (let* ((file (expand-file-name name gen-work)))
        (make-directory gen-work t)
        (with-temp-file file
          (insert "#+TITLE: Capture\n\n* Before\n* Todo list\nIntro line.\n** TODO Existing one\n** TODO Existing two\nBody.\n* After\n"))
        (setq me-org-capture-work-todo-file file me-org-capture-todo-file file)
        (org-capture nil key)
        (insert title)
        (org-capture-finalize)
        (gen-write name (with-temp-buffer (insert-file-contents file) (buffer-string)))
        (let ((b (find-buffer-visiting file))) (when b (kill-buffer b))))))
  ;; A file with no matching headline yet.
  (let ((file (expand-file-name "edit-capture-new.org" gen-work)))
    (with-temp-file file (insert "* Other\n"))
    (setq me-org-capture-work-todo-file file)
    (org-capture nil "ww")
    (insert "Into new headline")
    (org-capture-finalize)
    (gen-write "edit-capture-new.org" (with-temp-buffer (insert-file-contents file) (buffer-string)))
    (let ((b (find-buffer-visiting file))) (when b (kill-buffer b)))))

(defun gen-journal-case (name files min hour day month year &optional times)
  "Run org-journal in a scratch dir holding FILES, writing every file to expected."
  (let* ((dir (expand-file-name (concat "journal-" name "/") gen-work)))
    (make-directory dir t)
    (dolist (f files) (copy-file (expand-file-name f gen-fix) (expand-file-name (file-name-nondirectory f) dir) t))
    (setq org-journal-dir dir)
    (gen-set-now min hour day month year)
    (org-journal--list-dates)
    (dotimes (_ (or times 1))
      (org-journal-new-entry nil)
      (save-buffer))
    (dolist (b (buffer-list))
      (when (and (buffer-file-name b) (string-prefix-p dir (buffer-file-name b)))
        (with-current-buffer b (save-buffer))
        (kill-buffer b)))
    (dolist (f (directory-files dir t "\\.org\\'"))
      (gen-write (format "journal-%s/%s" name (file-name-nondirectory f))
                 (with-temp-buffer (insert-file-contents f) (buffer-string))))))

(defun gen-journal ()
  (require 'org-journal)
  (setq org-journal-file-format "%b-%Y.org"
        org-journal-file-type 'monthly
        org-journal-date-format "%a %e %b %Y"
        org-journal-find-file-fn #'find-file
        org-journal-carryover-items "TODO=\"TODO\"|TODO=\"PROJ\"|TODO=\"STRT\"|TODO=\"WAIT\"|TODO=\"HOLD\"")
  (gen-journal-case "empty" nil 32 14 11 11 2026)
  (gen-journal-case "single-digit" nil 5 9 2 3 2027)
  (gen-journal-case "inmonth" '("journal/inmonth/Nov-2026.org") 32 14 11 11 2026)
  (gen-journal-case "nested" '("journal/nested/Nov-2026.org") 32 14 11 11 2026)
  (gen-journal-case "rollover" '("journal/rollover/Nov-2026.org") 15 9 1 12 2026)
  (gen-journal-case "sameday" '("journal/sameday/Nov-2026.org") 32 14 11 11 2026)
  (gen-journal-case "twice" '("journal/inmonth/Nov-2026.org") 32 14 11 11 2026 2))

;; Refuse to write expectations if any part of org still sees the real clock.
(unless (and (= (org-today) (calendar-absolute-from-gregorian '(11 11 2026)))
             (equal (format-time-string "%F") "2026-11-11"))
  (error "Fixed clock is not in effect: org-today=%S" (org-today)))

(make-directory gen-out t)
(gen-agenda)
(gen-edits)
(gen-capture)
(gen-journal)
(message "Org version: %s" (org-version))
(gen-write "org-version.txt" (concat (org-version) "\n"))
(kill-emacs 0)
