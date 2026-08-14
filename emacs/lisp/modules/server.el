;;; server.el --- Emacs server config -*- lexical-binding: t; -*-

;;; Commentary:
;; 

;;; Code:

;; Required for server-running-p
(require 'server)
;; Start emacs in server mode so that emacsclient can be used
(unless (or noninteractive (daemonp) (server-running-p))
  (server-start))

(provide 'modules/server)
;;; server.el ends here
