;;; ai.el --- AI Coding agents etc -*- lexical-binding: t; -*-

;;; Commentary:
;; 

;;; Code:

;; This used to be called pi-coding-agent but was renamed...
(use-package pilish
  :ensure (:host "github.com" :repo "dnouri/pilish")
  :config
  (defalias 'pi 'pilish "Pi Coding Agent"))

(provide 'modules/ai)
;;; ai.el ends here
