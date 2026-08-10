;; modules/evil.el --- Evil mode and leader keybindings configuration

;; Keep the system clipboard away from the kill ring - so yank and paste
;; don't go to the system clipboard (ie make this more vim like)
;; Use the + register to copy/paste from the system clipboard
(setq select-enable-clipboard nil)

;; Add evil mode
(use-package evil
  ;; Load this plugin straight away
  :demand t
  :init
  ;; Mandatory settings for evil-collection compatibility
  (setq evil-want-integration t)
  (setq evil-want-keybinding nil)
  
  ;; Doom-like split behaviors (new splits go right and below)
  (setq evil-vsplit-window-right t)
  (setq evil-split-window-below t)
  
  ;; Use C-i for jump forward (standard vim C-i / C-o)
  (setq evil-want-C-i-jump t)
  (setq evil-want-C-u-scroll t)
  :config
  (evil-mode 1)

  ;; Use 'visual' line movement for gj/gk (navigates wrapped long lines naturally)
  (evil-global-set-key 'normal "j" 'evil-next-visual-line)
  (evil-global-set-key 'normal "k" 'evil-previous-visual-line))

;; Add evil-collection (vim bindings across all built-in/package modes)
(use-package evil-collection
  :after evil
  :demand t
  :config
  (evil-collection-init))

(use-package evil-cleverparens
  :after evil
  :hook (emacs-lisp-mode . evil-cleverparens-mode)
  :config
  ;; Give curly bracket keys back to evil, and rebind the cleverparens
  ;; versions using the Meta key as a modifier
  (evil-define-key 'normal evil-cleverparens-mode-map
    "}" 'evil-forward-paragraph
    "{" 'evil-backward-paragraph
    (kbd "M-}") 'evil-cp-next-closing
    (kbd "M-{") 'evil-cp-previous-closing))

;; general.el (leader key framework)
(use-package general
  :after evil
  :demand t
  :config
  ;; Define a reusable leader definer for SPC (Normal/Visual) and C-SPC (Insert/Emacs)
  (general-create-definer my/leader-keys
    :states '(normal insert visual emacs)
    :keymaps 'override
    :prefix me-leader-key
    :global-prefix "C-SPC")

  ;; Root-level Quick Bindings & Group Definitions
  (my/leader-keys
   ;; Top-level quick actions
   "u"   '(universal-argument :which-key "Universal argument")
   
   ;; Buffer commands ("b")
   "b"   '(:ignore t :which-key "buffer")
   "bb"  '(switch-to-buffer :which-key "Switch buffer")
   "bk"  '(kill-current-buffer :which-key "Kill current buffer")
   "br"  '(revert-buffer :which-key "Revert buffer")
   "bn"  '(next-buffer :which-key "Next buffer")
   "bp"  '(previous-buffer :which-key "Previous buffer")

   ;; File commands ("f")
   "f"   '(:ignore t :which-key "file")
   "ff"  '(find-file :which-key "Find file")
   "fs"  '(save-buffer :which-key "Save file")
   "fp"  '((lambda () (interactive) (find-file (expand-file-name "init.el" user-emacs-directory)))
           :which-key "Open init.el")

   ;; Git commands ("g")
   "g"   '(:ignore t :which-key "git")
   "gs"  '(magit-status :which-key "Magit status")

   ;; Window navigation/management ("w")
   "w"   '(evil-write :which-key "Save file")))

(defun me-highlight-region-before-apply (function start end &rest args)
  "Highlight yanked text in region starting at START and ending at END before applying FUNCTION with ARGS"
  (pulse-momentary-highlight-region start end)
  (apply function start end args))

(with-eval-after-load 'evil
  (advice-add 'evil-yank :around #'me-highlight-region-before-apply))

(provide 'modules/evil)
