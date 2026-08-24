;;; terraform.el --- Terraform -*- lexical-binding: t; -*-

;;; Commentary:
;; 

;;; Code:

(use-package terraform-mode
  :ensure t
  :custom
  (terraform-command "tofu")
  (terraform-format-on-save t))

(provide 'modules/languages/terraform)
;;; terraform.el ends here
