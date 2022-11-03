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
       '((sequence "TODO(t)" "IN PROGRESS(p)" "LOOP(r)" "STRT(s)" "WAIT(w)" "HOLD(h)" "IDEA(i)" "|" "DONE(d)" "KILL(k)")
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

(defun me/backup-commit ()
  "Commit everything in the current repository in a commit called 'backup'."
  ;; We need to make this interactive to appear as part of M-x (evaluate-extended-command)
  ;; Otherwise it would only appear under M-: (eval-expression)
  ;; See https://stackoverflow.com/questions/29199807/why-are-some-emacs-functions-not-available-via-m-x for more detail
  (interactive)
  (let ((cwd default-directory))

    ;; Could prompt user for y/n ? See http://xahlee.info/emacs/emacs/elisp_idioms_prompting_input.html
    (message "Not implemented yet! cwd: %s" cwd)
    (if (y-or-n-p (format "Backup directory %s to git?" cwd))
        (progn
          (message "not implemented yet")
        )
        (progn
          (message "Ok - aborting")
        )
      )))
;;; config.el ends here
