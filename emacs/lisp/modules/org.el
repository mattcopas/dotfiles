;;; org.el --- Org Mode config -*- lexical-binding: t; -*-

;;; Commentary:
;; 

;;; Code:

(defun me/org-mode-setup ()
  "Custom hook executed when opening any .org file."
  (setq display-line-numbers-type 'relative)
  (display-line-numbers-mode 1)
  (visual-line-mode 1))

(defun me--configure-org ()
  "Configure core Org settings."
  (setq me-private-directory "~/git/private-personal"
        me-private-personal-directory "~/git/private-personal"
        me-private-work-directory "~/git/private-work"
        me-private-client-directory "~/git/private-client"
        me-org-capture-todo-file (concat me-private-directory "/" ".todo.org")
        me-org-capture-personal-todo-file (concat me-private-personal-directory "/" "todo.org")
        me-org-capture-work-todo-file (concat me-private-work-directory "/" "todo.org")
        me-org-capture-client-todo-file (concat me-private-client-directory "/" "notes.org")
        org-directory "~/git/"
        org-default-notes-file (expand-file-name "notes.org" org-directory)
        ;; Visual cosmetics & indentation
        org-ellipsis " [...] "
        org-hide-emphasis-markers t
        org-startup-indented t
        org-startup-folded 'overview
        org-src-fontify-natively t
        org-src-tab-acts-natively t
        org-edit-src-content-indentation 0
        ;; Define custom TODO keyword states & colors
        org-todo-keywords
        '((sequence "TODO(t)" "IN PROGRESS(p)" "IN REVIEW(r)" "LOOP" "STRT(s)" "WAIT(w)" "HOLD(h)" "IDEA(i)" "|" "DONE(d)" "KILL(k)")
          (sequence "[ ](T)" "[-](S)" "[?](W)" "|" "[X](D)")
          (sequence "|" "OKAY(o)" "YES(y)" "NO(n)"))
        ;; Don't log when habits are completed by default
        ;; This can be changed for a specific todo item by setting the PROPERTY LOGGING -- see docs for org-log-repeat
        org-log-repeat nil
        ;; Don't make tasks with subtasks a different colour in org agenda
        ;; Is there a nicer way to mark tasks with subtasks in org agenda?
        org-agenda-dim-blocked-tasks nil
        ;; Set this to t to get rid of the section lines
        org-agenda-compact-blocks nil
        ;; In org agenda, dont show subtasks by default. This can be overridden for individual agenda views/sections -
        ;; see the 'settings' section of the docs for org-agenda-custom-commands for details on overriding variables
        org-tags-match-list-sublevels nil
        org-refile-use-outline-path 'full-file-path
        org-agenda-custom-commands
        '(("c" "Simple agenda view"
           ((tags "PRIORITY=\"A\""
                  ((org-agenda-skip-function '(org-agenda-skip-entry-if 'todo 'done))
                   (org-agenda-overriding-header "High priority unfinished tasks")))
            (agenda "")
            (alltodo ""
                     ((org-agenda-skip-function
                       '(or (air-org-skip-subtree-if-priority ?A)
                            ; is the nil condition needed here?
                            (org-agenda-skip-if nil '(scheduled deadline))))))))

          ("w" "Work agenda view"
           ((tags "+work+PRIORITY=\"A\""
                  ((org-agenda-skip-function '(org-agenda-skip-entry-if
                                               'todo '("WAIT" "KILL" "DONE")))
                   (org-agenda-overriding-header "High priority unfinished tasks")))
            (tags-todo  "+work"
                        ((org-agenda-skip-function '(org-agenda-skip-entry-if
                                                     'todo '("TODO" "IN PROGRESS" "IN REVIEW" "KILL" "DONE")))
                         (org-agenda-overriding-header "Blocked tasks")))
            (tags "+SCHEDULED=\"<today>\""
                  ((org-agenda-skip-function '(org-agenda-skip-entry-if 'todo '("DONE" "KILL")))
                   (org-agenda-overriding-header "Today's tasks")))
            (tags "+SCHEDULED=\"<today>\""
                  ((org-agenda-skip-function '(org-agenda-skip-entry-if 'nottodo '("DONE")))
                   (org-agenda-overriding-header "Today's completed tasks")))
            (tags "+SCHEDULED=\"<tomorrow>\""
                  ((org-agenda-overriding-header "Tomorrow's tasks")))
            (tags-todo "+work"
                       ((org-agenda-skip-function
                         '(or (air-org-skip-subtree-if-priority ?A)
                              (org-agenda-skip-entry-if 'nottodo '("TODO" "IN PROGRESS"))))))))

          ("p" "Personal agenda view"
           ((tags "+personal+PRIORITY=\"A\""
                  ((org-agenda-skip-function '(org-agenda-skip-entry-if 'todo 'done))
                   (org-agenda-overriding-header "High priority unfinished tasks")))
            (tags-todo "+personal"
                       ((org-agenda-skip-function
                         '(or (air-org-skip-subtree-if-priority ?A)
                              (org-agenda-skip-entry-if 'todo 'done))))))))
        org-capture-templates
        '(("t" "Todo" entry (file+headline me-org-capture-todo-file "Todo list") (function me-basic-todo-format))
          ("p" "Personal Todo" entry (file+headline me-org-capture-personal-todo-file "Todo list") (function me-basic-todo-format) :prepend t)
          ("w" "Work Todo" entry (file+headline me-org-capture-work-todo-file "Todo list") (function me-basic-todo-format) :prepend t)
          ("W" "Work Todo - today" entry (file+headline me-org-capture-work-todo-file "Todo list")
           (function me-scheduled-todo-format-today) :prepend t)
          ("c" "Client Todo" entry (file+headline me-org-capture-client-todo-file "Stuff to do") (function me-basic-todo-format) :prepend t)))

  ;; Remove duplicates from the list - otherwise org agenda lists some tasks multiple times
  (setq org-agenda-files
        (cl-remove-duplicates
         (list me-private-directory
               me-private-personal-directory
               me-private-client-directory
               me-private-work-directory)
         :test #'string-equal)))

;; Core Org Configuration
(use-package org
  :ensure t ; Built-in to Emacs - BUT we want the latest version, so tell the package manager to download it anyway
  :defer t
  :hook (org-mode . me/org-mode-setup)
  :config
  (me--configure-org))

(use-package org-journal
  ;; We don't need to bind variables in :config here because that's already done in the org block above.
  :config
  (setq org-journal-dir "~/git/journal"
    org-journal-file-format "%b-%Y.org"
    org-journal-file-type 'monthly
    org-journal-date-format "%a %e %b %Y" ; Mon 1 Jan 2023
    org-journal-find-file-fn #'find-file)
  (setq org-journal-carryover-items  "TODO=\"TODO\"|TODO=\"PROJ\"|TODO=\"STRT\"|TODO=\"WAIT\"|TODO=\"HOLD\"")
  :commands (org-journal-new-entry)) ; Tell emacs this is an interactive command. The alternative here is to wrap the call in a lambda that starts with (interactiv

;; Modern UI Enhancements (org-modern)
(use-package org-modern
  ; Don't demand this as we need to wait for org mode. It doesn't need loading immediately anyway
  :after org
  :hook (org-mode . org-modern-mode)
  :config
  (setq org-modern-star '("◉" "○" "✸" "✿" "✤" "✜")
        org-modern-table-vertical 1
        org-modern-table-horizontal 0.2
        org-modern-list '((?- . "•") (?+ . "➤"))))

;; Auto-reveal markup on cursor hover (org-appear)
(use-package org-appear
  :after org
  :hook (org-mode . org-appear-mode)
  :config
  (setq org-appear-autoemphasis t
        org-appear-autolinks t
        org-appear-autosubmarkers t))

;; Evil Keybindings for Org Mode (evil-org)
(use-package evil-org
  :after org
  :hook (org-mode . evil-org-mode)
  :config
  (require 'evil-org-agenda)
  (evil-org-agenda-set-keys))

;; Leader Keybindings (via General.el)
(with-eval-after-load 'general
  (general-define-key
   :states '(normal visual emacs)
   :keymaps 'override
   :prefix me-leader-key
   "o"  '(:ignore t :which-key "org")
   "oA" '(org-agenda :which-key "agenda")
   "X" '(org-capture :which-key "Org capture")
   "ol" '(org-insert-link :which-key "insert link")
   "njj" '(org-journal-new-entry :which-key "New journal entry"))

  ;; Local keys inside Org buffers
  (general-define-key
   :states '(normal visual)
   :keymaps 'org-mode-map
   "TAB"   'org-cycle
   "S-TAB" 'org-shifttab
   "M-j"   'org-metadown
   "M-k"   'org-metaup
   "M-h"   'org-metaleft
   "M-l"   'org-metaright))

(with-eval-after-load 'org
  ;; Local leader keys inside Org buffers
  (general-define-key
   :states '(normal visual)
   :keymaps 'org-mode-map
   :prefix me-leader-key
   "m" '(:ignore t :which-key "localleader/org")
   "mt" '(:ignore t :which-key "todo")
   "mtt" '((lambda ()
	     (interactive) (org-todo "TODO")) :which-key "Todo")
   "mtp" '((lambda ()
	     (interactive) (org-todo "IN PROGRESS")) :which-key "In Progress")
   "mtw" '((lambda ()
	     (interactive) (org-todo "WAIT")) :which-key "Wait")
   "mtw" '((lambda ()
	     (interactive) (org-todo "IN REVIEW")) :which-key "In Review")
   "mtd" '((lambda ()
	     (interactive) (org-todo "DONE")) :which-key "Done")))

;; Enable Habits - see https://orgmode.org/manual/Tracking-your-habits.html
;(add-to-list 'org-modules 'habit)

;; This and the below custom commands come from Aaron Beiber's blog post -
;; https://blog.aaronbieber.com/2016/09/24/an-agenda-for-life-with-org-mode.html
;; TODO is it worth replacing this with the package 'org-super-agenda'?
(defun air-org-skip-subtree-if-priority (priority)
"Skip an agenda subtree if it has a priority of PRIORITY.

PRIORITY may be one of the characters ?A, ?B, or ?C."
  (let ((subtree-end (save-excursion (org-end-of-subtree t)))
      (pri-value (* 1000 (- org-lowest-priority priority)))
      (pri-current (org-get-priority (thing-at-point 'line t))))
  (if (= pri-value pri-current)
      subtree-end
    nil)))

(defun me/schedule-task-for (delta)
  "Schedule a task for a given DELTA, for example \"+1d\" or \"-2d\"."
  (cond ((equal major-mode 'org-mode) (org-schedule nil delta))
        ((equal major-mode 'org-agenda-mode)
         (org-agenda-schedule nil delta)
         (org-agenda-redo))
        ;; This is essentially the final else statement in an if/else-if block
        (t (message (format "Invalid major-mode %s" major-mode)))))

(defun me/schedule-task-for-today ()
  "Schedule the task at point for today."
  (interactive)
  (me/schedule-task-for "+0d"))

(defun me/schedule-task-for-tomorrow ()
  "Schedule the task at point for tomorrow."
  (interactive)
  (me/schedule-task-for "+1d"))


(defun me-basic-todo-format ()
  "Function returning a basic todo format. Note that the docs for org-capture-templates requirse the template parameter to be literal or a function returning a template"
  "* TODO %?")

(defun me-scheduled-todo-format-today ()
  "Function returning a scheduled todo format (scheduled for today). Note that the docs for org-capture-templates requirse the template parameter to be literal or a function returning a template"
  "* TODO %? \n SCHEDULED: %(org-insert-time-stamp (org-read-date nil t))")


(provide 'modules/org)
;;; org.el ends here
