;;; org.el --- Org Mode config -*- lexical-binding: t; -*-

;;; Commentary:
;; 

;;; Code:

;; Core Org Configuration
(use-package org
  :ensure t ; Built-in to Emacs - BUT we want the latest version, so tell the package manager to download it anyway
  :defer t
  :hook (org-mode . me/org-mode-setup)
  :config
  (setq org-directory "~/git/"
	org-journal-directory "~/git/journal"
	org-journal-file-format "%b-%Y.org"
	org-journal-file-type 'monthly
	org-journal-date-format "%a %e %b %Y" ; Mon 1 Jan 2023
        org-default-notes-file (expand-file-name "notes.org" org-directory)
        org-agenda-files (list org-directory)
        
        ;; Visual cosmetics & indentation
        org-ellipsis " [...] "
        org-hide-emphasis-markers t
        org-startup-indented t
        org-startup-folded 'overview
        org-src-fontify-natively t
        org-src-tab-acts-natively t
        org-edit-src-content-indentation 0)

  ;; Define custom TODO keyword states & colors
  (setq org-todo-keywords
        '((sequence "TODO(t)" "IN PROGRESS(p)" "IN REVIEW(r)" "LOOP" "STRT(s)" "WAIT(w)" "HOLD(h)" "IDEA(i)" "|" "DONE(d)" "KILL(k)")
	    (sequence "[ ](T)" "[-](S)" "[?](W)" "|" "[X](D)")
	    (sequence "|" "OKAY(o)" "YES(y)" "NO(n)")))

  (defun me/org-mode-setup ()
    "Custom hook executed when opening any .org file."
    (setq display-line-numbers-type 'relative)
    (display-line-numbers-mode 1)
    (visual-line-mode 1)))

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
   :prefix "SPC"
   "o"  '(:ignore t :which-key "org")
   "oa" '(org-agenda :which-key "agenda")
   "X" '(org-capture :which-key "Org capture")
   "ol" '(org-insert-link :which-key "insert link")
   "ot" '(org-todo :which-key "cycle todo state")
   "oA" '(org-archive-subtree :which-key "archive subtree"))

  ;; Local leader keys inside Org buffers
  (general-define-key
   :states '(normal visual)
   :keymaps 'org-mode-map
   "TAB"   'org-cycle
   "S-TAB" 'org-shifttab
   "M-j"   'org-metadown
   "M-k"   'org-metaup
   "M-h"   'org-metaleft
   "M-l"   'org-metaright))

(provide 'modules/org)
;;; org.el ends here
