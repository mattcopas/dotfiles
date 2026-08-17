;;; yaml.el --- Yaml config and packages -*- lexical-binding: t; -*-

;;; Commentary:
;; 

;;; Code:

;; Requires Emacs 29+
(use-package yaml-ts-mode
  :ensure nil
  :init
  ;; If yaml-mode is used, change to yaml-ts-mode instead
  (add-to-list 'major-mode-remap-alist '(yaml-mode . yaml-ts-mode))
  :config
  (setq yaml-indent-offset 2)
  :hook
  (yaml-ts-mode . (lambda ()
		    (setq-local tab-width 2)
		    (setq-local indent-tabs-mode nil)
		    (setq yaml-indent-offset 2))))

;; We can have multuiple (use-package eglot) blocks because use-package appends stuff, instead of overwriting it
(use-package eglot
  :after mason
  :ensure nil
  :hook (yaml-ts-mode . (lambda ()
			  (unless (mason-installed-p "yaml-language-server")
			    (mason-install "yaml-language-server"))))
  :hook (yaml-ts-mode . eglot-ensure)
  :hook (yaml-ts-mode . (lambda ()
                          (setq-local eglot-workspace-configuration
                                      '((:yaml
                                         :schemas
                                         ((https://raw.githubusercontent.com/compose-spec/compose-spec/master/schema/compose-spec.json
                                           . ["*docker-compose*.yml" "*docker-compose*.yaml" "compose.yml" "compose.yaml"]))
                                         :schemaStore (:enable t)
                                         :completion t
                                         :hover t
                                         :validate t))))))

(provide 'modules/languages/yaml)
;;; yaml.el ends here
