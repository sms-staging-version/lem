(in-package :lem-capi)

(defclass capi-impl (lem:implementation)
  ()
  (:default-initargs
   :support-floating-window nil
   :native-scroll-support nil
   :redraw-after-modifying-floating-window nil))

(setf lem:*implementation* (make-instance 'capi-impl))

(defvar *lem-panel*)
(defvar *editor-thread*)

(defmethod lem-if:invoke ((implementation capi-impl) function)
  (with-error-handler ()
    (setf *lem-panel* (make-instance 'lem-panel))
    (capi:display
     (make-instance 'capi:interface
                    :auto-menus nil
                    :best-width 800
                    :best-height 600
                    :layout *lem-panel*))
    (setf *editor-thread*
          (funcall function
                   (lambda ())
                   (lambda (report)
                     (when report
                       (with-open-file (out "~/ERROR"
                                            :direction :output
                                            :if-exists :supersede
                                            :if-does-not-exist :create)
                         (write-string report out)))
                     (capi:quit-interface *lem-panel*))))))

(defmethod lem-if:set-first-view ((implementation capi-impl) view)
  (with-error-handler ()
    (set-first-window (lem-panel-window-panel *lem-panel*) view)))

(defmethod lem-if:display-background-mode ((implementation capi-impl))
  (let ((color (color:get-color-spec
                (capi:simple-pane-background
                 (first (all-window-panes (lem-panel-window-panel *lem-panel*)))))))
    (lem:rgb-to-background-mode (* (color:color-red color) 255)
                                (* (color:color-green color) 255)
                                (* (color:color-blue color) 255))))

(defmethod lem-if:update-foreground ((implementation capi-impl) color-name)
  (map-window-panes (lem-panel-window-panel *lem-panel*)
                    (lambda (window-pane)
                      (change-foreground window-pane color-name))))

(defmethod lem-if:update-background ((implementation capi-impl) color-name)
  (map-window-panes (lem-panel-window-panel *lem-panel*)
                    (lambda (window-pane)
                      (change-background window-pane color-name))))

(defmethod lem-if:display-width ((implementation capi-impl))
  (with-error-handler ()
    (window-panel-width (lem-panel-window-panel *lem-panel*))))

(defmethod lem-if:display-height ((implementation capi-impl))
  (with-error-handler ()
    (window-panel-height (lem-panel-window-panel *lem-panel*))))

(defmethod lem-if:make-view ((implementation capi-impl) window x y width height use-modeline)
  (with-error-handler ()
    (if (lem:minibuffer-window-p window)
        (window-panel-minibuffer (lem-panel-window-panel *lem-panel*))
        (make-instance 'window-pane
                       :window window
                       :window-panel (lem-panel-window-panel *lem-panel*)))))

(defmethod lem-if:delete-view ((implementation capi-impl) view)
  (with-error-handler ()
    (window-panel-delete-window (lem-panel-window-panel *lem-panel*) view)
    (destroy-window-pane view)))

(defmethod lem-if:clear ((implementation capi-impl) view)
  (with-error-handler ()
    (clear view)))

(defmethod lem-if:set-view-size ((implementation capi-impl) view width height)
  (setf (window-panel-modified-p (lem-panel-window-panel *lem-panel*)) t))

(defmethod lem-if:set-view-pos ((implementation capi-impl) view x y)
  (setf (window-panel-modified-p (lem-panel-window-panel *lem-panel*)) t))

(defmethod lem-if:print ((implementation capi-impl) view x y string attribute)
  (with-error-handler ()
    (draw-string view string x y (lem:ensure-attribute attribute nil))))

(defmethod lem-if:print-modeline ((implementation capi-impl) view x y string attribute)
  (with-error-handler ()
    (draw-string-in-modeline view string x y (lem:ensure-attribute attribute nil))))

(defmethod lem-if:clear-eol ((implementation capi-impl) view x y)
  (with-error-handler ()
    (clear-eol view x y)))

(defmethod lem-if:clear-eob ((implementation capi-impl) view x y)
  (with-error-handler ()
    (clear-eob view x y)))

;(defmethod lem-if:redraw-window ((implementation capi-impl) window force)
;  )

(defmethod lem-if:redraw-view-after ((implementation capi-impl) view focus-window-p)
  )

(defmethod lem-if:update-display ((implementation capi-impl))
  (with-error-handler ()
    (let ((window-panel (lem-panel-window-panel *lem-panel*)))
      (with-apply-in-pane-process-wait-single (window-panel)
        (when (window-panel-modified-p window-panel)
          (map-window-panes window-panel (lambda (window-pane)
                                          (when (window-pane-pixmap window-pane)
                                            (multiple-value-bind (w h)
                                                (capi:simple-pane-visible-size window-pane)
                                              (gp:clear-graphics-port (window-pane-pixmap window-pane))
                                              (gp:copy-pixels window-pane
                                                              (window-pane-pixmap window-pane)
                                                              0 0 w h 0 0)))))
          (update-window-ratios window-panel)
          (lem::adjust-windows (lem::window-topleft-x)
                               (lem::window-topleft-y)
                               (+ (lem::window-max-width) (lem::window-topleft-x))
                               (+ (lem::window-max-height) (lem::window-topleft-y)))
          (lem::minibuf-update-size)
          (setf (window-panel-modified-p window-panel) nil)
          (map-window-panes window-panel #'reinitialize-pixmap))
        (when (current-tab-is-main *lem-panel*)
          (map-window-panes window-panel #'update-window)
          (capi:set-pane-focus (window-panel-minibuffer window-panel)))))))

;(defmethod lem-if:scroll ((implementation capi-impl) view n)
;  )

(defmethod lem-if:split-window-horizontally ((implementation capi-impl) view new-view)
  (with-error-handler ()
    (let ((window-panel (lem-panel-window-panel *lem-panel*)))
      (setf (window-panel-modified-p window-panel) t)
      (split-horizontally window-panel view new-view))))

(defmethod lem-if:split-window-vertically ((implementation capi-impl) view new-view)
  (with-error-handler ()
    (let ((window-panel (lem-panel-window-panel *lem-panel*)))
      (setf (window-panel-modified-p window-panel) t)
      (split-vertically window-panel view new-view))))
