;;; globals.el --- Global variables -*- lexical-binding: t; -*-

;;; Commentary:
;; 

;;; Code:

(defcustom me-local-cache-directory
  (expand-file-name ".local/cache" user-emacs-directory)
  "Directory to store cached things in")

(defcustom me-local-backup-directory
  (expand-file-name "backups" me-local-cache-directory)
  "Directory to put backups in")

(unless (file-exists-p me-local-backup-directory)
  (make-directory me-local-backup-directory t))

(defcustom me-leader-key "SPC" "Leader key for evil/general")

(provide 'modules/globals)
;;; globals.el ends here
