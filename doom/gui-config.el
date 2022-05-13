;; provide is only needed if we use (require 'gui-config)
;; (provide 'gui-config)
;; Open in full screen mode

(add-hook 'window-setup-hook #'toggle-frame-fullscreen)
