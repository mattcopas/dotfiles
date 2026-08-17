;;; markdown.el --- Markdown config -*- lexical-binding: t; -*-

;;; Commentary:
;; 

;;; Code:

;; TODO get the same functionality as neovim - ie keep markdown rendered, but on the current line, show the actual markdown
(use-package markdown-mode
  :ensure t
  :mode ("\\.md$" . markdown-mode)
  :config
  (setq markdown-hide-markup t
	markdown-hide-urls t
	markdown-fontify-code-blocks-natively t))

(provide 'modules/languages/markdown)
;;; markdown.el ends here
