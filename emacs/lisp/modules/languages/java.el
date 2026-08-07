;;; java.el --- Java config -*- lexical-binding: t; -*-

;;; Commentary:
;; Ideally we want eglot-java installed to run tests and stuff
;; However getting java versions working with that is a pain

;; So the current setup is just eglot, and it assumes java-21.0.10-amzn installed via sdkman, AND jdtls is installed as a external (brew etc) package

;;; Code:

;; Make sure to install jdtls outside emacs!
;; eg brew install jdtls
;; Easier than configuring jdtls in emacs becauae you then have to configura java versions (jdtls requires 21), which is a PITA
(use-package eglot
  ; Built into emacs
  :ensure nil
  :hook (java-mode . eglot-ensure)
  :config
  (add-to-list 'eglot-server-programs
	       `((java-mode java-ts-mode) . ("jdtls" "--java-executable" ,(file-truename "~/.sdkman/candidates/java/21.0.10-amzn/bin/java")))))

(provide 'modules/languages/java)
;;; java.el ends here
