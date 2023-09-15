;; provide is only needed if we use (require 'gui-config)
;; (provide 'gui-config)
;; Open in full screen mode

;; Note the use of string= here - (eq x y) will return false here
(if (string= system-type "darwin")
    ;; if macos, use maximised window (because dekstop notifications don't seem to work on fullscreen)
    (add-hook 'window-setup-hook #'toggle-frame-maximized)
  ;; otherwise use the standard frame-fullscreen
  (add-hook 'window-setup-hook #'toggle-frame-fullscreen))
