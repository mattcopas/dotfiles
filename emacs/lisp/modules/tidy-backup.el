;;; tidy-backup.el --- A module stop emacs littering *~ files everywhere! -*- lexical-binding: t; -*-

;;; Commentary:
;; 

;;; Code:

;; Centralize Backup Files (*~)
;; Instead of dropping `file.el~` next to `file.el`, move ALL backups to cache/backups/
;; TODO make .local/cache a variable somewhere
(defvar my-backup-dir (expand-file-name "backups" me-local-cache-directory))
(setq backup-directory-alist `(("." . ,my-backup-dir))
      make-backup-files t
      vc-make-backup-files t
      version-control t
      kept-old-versions 2
      kept-new-versions 10
      delete-old-versions t)

;; Centralize Auto-Save Files (#file#)
(defvar my-autosave-dir (expand-file-name "auto-save" me-local-cache-directory))
(setq auto-save-file-name-transforms `((".*" ,my-autosave-dir t)))

(provide 'modules/tidy-backup)
;;; tidy-backup.el ends here
