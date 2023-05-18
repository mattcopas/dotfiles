;;; $DOOMDIR/config.el -*- lexical-binding: t; -*-

;; Place your private configuration here! Remember, you do not need to run 'doom
;; sync' after modifying this file!


;; Some functionality uses this to identify you, e.g. GPG configuration, email
;; clients, file templates and snippets.
(setq user-full-name "John Doe"
      user-mail-address "john@doe.com")

;; Doom exposes five (optional) variables for controlling fonts in Doom. Here
;; are the three important ones:
;;
;; + `doom-font'
;; + `doom-variable-pitch-font'
;; + `doom-big-font' -- used for `doom-big-font-mode'; use this for
;;   presentations or streaming.
;;
;; They all accept either a font-spec, font string ("Input Mono-12"), or xlfd
;; font string. You generally only need these two:
;; (setq doom-font (font-spec :family "monospace" :size 12 :weight 'semi-light)
;;       doom-variable-pitch-font (font-spec :family "sans" :size 13))

;; If you use `org' and don't want your org files in the default location below,
;; change `org-directory'. It must be set before org loads!
(setq org-directory "~/org/")

;; This determines the style of line numbers in effect. If set to `nil', line
;; numbers are disabled. For relative line numbers, set this to `relative'.
(setq display-line-numbers-type t)


;; Here are some additional functions/macros that could help you configure Doom:
;;
;; - `load!' for loading external *.el files relative to this one - `use-package!' for configuring packages
;; - `after!' for running code after a package has loaded
;; - `add-load-path!' for adding directories to the `load-path', relative to
;;   this file. Emacs searches the `load-path' when you load packages with
;;   `require' or `use-package'.
;; - `map!' for binding new keys
;;
;; To get information about any of these functions/macros, move the cursor over
;; the highlighted symbol at press 'K' (non-evil users must press 'C-c c k').
;; This will open documentation for it, including demos of how they are used.
;;
;; You can also try 'gd' (or 'C-c c d') to jump to their definition and see how
;; they are implemented.


;;;;;;;;;;;;;;;;;;
;; My custom stuff
;;;;;;;;;;;;;;;;;;

;; Set fonts
(when  (eq system-type 'windows-nt)
        (setq font-to-use "Cascadia Code")
        (setq doom-font (font-spec :family font-to-use)
        doom-variable-pitch-font (font-spec :family font-to-use) ; inherits `doom-font''s :size
                doom-unicode-font (font-spec :family font-to-use)
                        doom-big-font (font-spec :family font-to-use))
  )

(setq doom-font (font-spec :size 18))

;; Set bullets for org-mode (requires unicode font, and (org +pretty) in .doom.d/init.el)
(setq
    org-superstar-headline-bullets-list '("⁖" "◉" "○" "✸" "✿"))

;; Fix meghanada (java) on Windows
(cond
   ((eq system-type 'windows-nt)
       (setq meghanada-java-path (expand-file-name "bin/java.exe" (getenv "JAVA_HOME")))
           (setq meghanada-maven-path "mvn.cmd"))
      (t
          (setq meghanada-java-path "java")
              (setq meghanada-maven-path "mvn")))

(after! org
  (map! :map org-mode-map
    ;; Remap M-k/j to move items up/down
    :n "M-j" #'org-metadown
    :n "M-k" #'org-metaup
  )
  ;; This fixes the leading stars being shown in org mode!
  ;; The second parameter (t) disables the prompt to load a theme
  (load-theme 'doom-one t)

  ; Org task statuses
  (setq org-todo-keywords
       '((sequence "TODO(t)" "IN PROGRESS(p)" "IN REVIEW(r)" "LOOP" "STRT(s)" "WAIT(w)" "HOLD(h)" "IDEA(i)" "|" "DONE(d)" "KILL(k)")
         (sequence "[ ](T)" "[-](S)" "[?](W)" "|" "[X](D)")
         (sequence "|" "OKAY(o)" "YES(y)" "NO(n)"))))

(when (window-system)
  (load "~/git/dotfiles/doom/gui-config.el"))

;; projectile
(setq
 projectile-project-search-path '("~/git")
)

; Add .ideavimrc to vimrc mode list
(after! vimrc-mode
        (add-to-list 'auto-mode-alist '(".ideavimrc" . vimrc-mode)))

; When selecting, deleting etc, don't copy to clipboard
; Use "+y to copy to clpboard
(setq x-select-enable-clipboard nil)

;; map Leader-w to save
(map!
 :desc "Save file"
 :leader
 :n "w" #'evil-write)

; Display time and battery in modeline
(display-time-mode 1)
(setq display-time-24hr-format 1)
(display-battery-mode 1)

(setq-default tab-width 2)

(defun me/backup-commit ()
  "Commit everything in the current repository in a commit called 'backup'."

  ;; We need to make this interactive to appear as part of M-x (evaluate-extended-command)
  ;; Otherwise it would only appear under M-: (eval-expression)
  ;; See https://stackoverflow.com/questions/29199807/why-are-some-emacs-functions-not-available-via-m-x for more detail
  (interactive)
  (if (y-or-n-p (format "Backup directory %s to git?" default-directory))
  (progn
    (shell-command "git add . && git commit -am 'backup' && git push origin")
    (message "Committed and pushed to origin!"))
  (progn
    (message "Ok - aborted"))))

(defun me/org-create-demoted ()
  "Create an item that is indented, relative to the current item."
  (interactive)
  (+org/insert-item-below 1)
  (evil-force-normal-state)
  (org-metaright)
  (evil-append-line 1))

(defun me/evil-insert-block (lang)
  (evil-open-below 1)
  (evil--self-insert-string (format"\#+BEGIN_SRC %s\n\#+END_SRC" lang))
  (evil-open-above 1))

(defun me/insert-block (lang)
    (insert (format "
        \#+BEGIN_SRC %s

        \#+END_SRC" lang)))

(defun me/insert-elisp-block ()
    "This function inserts a src block in org mode, in the language emacs lisp."
    (interactive)
    (if (eq major-mode 'org-mode)
        (with-current-buffer (current-buffer)
            (if (bound-and-true-p evil-org-mode) ;; bound-and-true-p is a macro - returns its value if set, or nil (which is sufficient for a conditional)
                (me/evil-insert-block "emacs-lisp")
                (me/insert-block "emacs-lisp")))
      (message "Not in org mode")))

; Modifications of this could be written for project specific stuff -eg search Jira, search gitlab etc
(defun me/lemme-google-that ()
  "Google for a user-input query.

   This uses the function add-to-history.
   If the variable history-delete-duplicates is nil, duplicates will NOT be deleted.
   The max history length is set by the variable history-length"
  (interactive)
  (defvar me/lemme-google-that-history '())
  (let ((input-query (completing-read "Search Google for: " me/lemme-google-that-history)))
    (add-to-history 'me/lemme-google-that-history input-query)
    (browse-url (format "https://google.com/search?q=%s" input-query))))

(map! :leader
      (:prefix "h"
       :desc "Google something" "g" #'me/lemme-google-that))

(defun me/evil-normalize-all-buffers ()
  "Force a drop to normal state.
Taken from https://emacs.stackexchange.com/questions/24563/evil-mode-switch-back-to-normal-mode-automatically-after-inaction"

  (unless (eq evil-state 'normal)
    (dolist (buffer (buffer-list))
      (set-buffer buffer)
      (unless (or (minibufferp)
                  (eq evil-state 'emacs))
        (evil-force-normal-state)))
    (message "Dropped back to normal state in all buffers")))

(defvar me/evil-normal-timer
  (run-with-idle-timer 10 t #'me/evil-normalize-all-buffers)
  "Drop back to normal state after idle for 10 seconds.")

(defun me/wsl-copy (start end)
  "Copy region to windows clipboard.
   Originally comes from an SO post - https://emacs.stackexchange.com/questions/39210/copy-paste-from-windows-clipboard-in-wsl-terminal/59607#59607"
  (interactive "r")
  (shell-command-on-region start end "clip.exe"))

;; Warn when using Esc instead of C-g
(defun me/warn-esc ()
  (interactive)
  "Warn me when I use Esc instead of C-g"

  (evil-force-normal-state)
  (message "Could you have used C-g ?"))

(map!
 :desc "Warn when using Esc instead of C-g"
 :i (kbd "<escape>") #'me/warn-esc)
;;
;; Load machine specific stuff, if present. Specify a non nil second arg to prevent an error if not found
(load "~/tools/emacs-local.el" t)
;;
;;; config.el ends here
