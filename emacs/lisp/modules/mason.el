;;; mason.el ---  -*- lexical-binding: t; -*-

;;; Commentary:
;; 

;;; Code:

(use-package mason
  :ensure t
  :config
  (mason-setup))

(defun me/configure-mason-for-mode (mode server)
  "Ensure mason has SERVER installed when MODE is activated.
Also adds `eglot-ensure' to MODE's hook."
  (let ((hook (intern (format "%s-hook" mode))))
    (add-hook hook #'eglot-ensure)
    (add-hook hook (lambda ()
                     (unless (mason-installed-p server)
                       (mason-install server))))))

(provide 'modules/mason)
;;; mason.el ends here
