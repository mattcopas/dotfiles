;;; ui.el --- General UI stuff -*- lexical-binding: t; -*-
;;
;;; Commentary:
;;
;;  Description
;;
;;; Code:

;; Nerd Icons
(use-package nerd-icons
  :demand t)
;; Icons for dired (lazy-loaded when opening a folder)
(use-package nerd-icons-dired
  :hook (dired-mode . nerd-icons-dired-mode))

;; Doom Themes
(use-package doom-themes
  :demand t
  :config
  (setq doom-themes-enable-bold t
        doom-themes-enable-italic t)
  (load-theme 'doom-one t)
  (doom-themes-visual-bell-config)
  (doom-themes-org-config))

;; Doom Modeline
(use-package doom-modeline
  :demand t
  :init
  (doom-modeline-mode 1)
  :config
  (setq doom-modeline-height 25
        doom-modeline-bar-width 4
        doom-modeline-icon t
        doom-modeline-major-mode-icon t
        doom-modeline-minor-modes nil))

(provide 'modules/ui)
;;; icons.el ends here
