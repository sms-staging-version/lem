(in-package :lem)

(defvar *implementation*)

(defclass implementation ()
  ((name
    :initform (alexandria:required-argument :name)
    :initarg :name
    :reader implementation-name)
   (native-scroll-support
    :initform nil
    :initarg :native-scroll-support
    :reader native-scroll-support)
   (redraw-after-modifying-floating-window
    :initform nil
    :initarg :redraw-after-modifying-floating-window
    :reader redraw-after-modifying-floating-window)
   (support-floating-window
    :initform t
    :initarg :support-floating-window
    :reader support-floating-window)))

(defun get-default-implementation (&key (errorp t))
  (let* ((classes (c2mop:class-direct-subclasses (find-class 'implementation)))
         (class (case (length classes)
                  (0
                   (when errorp
                     (error "Implementation does not exist.~
                             (probably because you didn't quickload lem-ncurses)")))
                  (1
                   (first classes))
                  (otherwise
                   (dolist (class classes (first classes))
                     (when (string= :ncurses (class-name class))
                       (return class)))))))
    (when class
      (make-instance class))))

(defvar lem-if:*background-color-of-drawing-window* nil)

(defgeneric lem-if:invoke (implementation function))
(defgeneric lem-if:get-background-color (implementation))
(defgeneric lem-if:update-foreground (implementation color-name))
(defgeneric lem-if:update-background (implementation color-name))
(defgeneric lem-if:display-width (implementation))
(defgeneric lem-if:display-height (implementation))
(defgeneric lem-if:make-view (implementation window x y width height use-modeline))
(defgeneric lem-if:delete-view (implementation view))
(defgeneric lem-if:clear (implementation view))
(defgeneric lem-if:set-view-size (implementation view width height))
(defgeneric lem-if:set-view-pos (implementation view x y))
(defgeneric lem-if:print (implementation view x y string attribute))
(defgeneric lem-if:print-modeline (implementation view x y string attribute))
(defgeneric lem-if:clear-eol (implementation view x y))
(defgeneric lem-if:clear-eob (implementation view x y))
(defgeneric lem-if:redraw-view-after (implementation view)
  (:method (implementation view)))
(defgeneric lem-if:update-display (implementation))
(defgeneric lem-if:scroll (implementation view n))

(defgeneric lem-if:set-first-view (implementation view)
  (:method (implementation view)))
(defgeneric lem-if:split-window-horizontally (implementation view new-view)
  (:method (implementation view new-view)))
(defgeneric lem-if:split-window-vertically (implementation view new-view)
  (:method (implementation view new-view)))

(defgeneric lem-if:display-popup-menu (implementation items
                                       &key action-callback
                                            print-spec
                                            focus-attribute
                                            non-focus-attribute
                                            style))
(defgeneric lem-if:popup-menu-update (implementation items))
(defgeneric lem-if:popup-menu-quit (implementation))
(defgeneric lem-if:popup-menu-down (implementation))
(defgeneric lem-if:popup-menu-up (implementation))
(defgeneric lem-if:popup-menu-first (implementation))
(defgeneric lem-if:popup-menu-last (implementation))
(defgeneric lem-if:popup-menu-select (implementation))
(defgeneric lem-if:display-popup-message (implementation buffer-or-string &key timeout
                                                                               destination-window
                                                                               style))
(defgeneric lem-if:delete-popup-message (implementation popup-message))

(defgeneric lem-if:display-menu (implementation menu name))
(defgeneric lem-if:update-menu (implementation menu items))

(defgeneric lem-if:clipboard-paste (implementation)
  (:method (implementation)))
(defgeneric lem-if:clipboard-copy (implementation text)
  (:method (implementation text)))

(defvar *display-background-mode* nil)

(defun implementation ()
  *implementation*)

(defmacro with-implementation (implementation &body body)
  `(let ((*implementation* ,implementation))
     ,@body))

(defun display-background-mode ()
  (or *display-background-mode*
      (if (light-color-p (lem-if:get-background-color (implementation)))
          :light
          :dark)))

(defun set-display-background-mode (mode)
  (check-type mode (member :light :dark nil))
  (setf *display-background-mode* mode))

(defun set-foreground (name)
  (lem-if:update-foreground (implementation) name))

(defun set-background (name)
  (lem-if:update-background (implementation) name))

(defun display-width () (lem-if:display-width (implementation)))
(defun display-height () (lem-if:display-height (implementation)))

(defun invoke-frontend (function &key (implementation
                                       (get-default-implementation)))
  (let ((bt:*default-special-bindings*
          `((*implementation* . ,implementation)
            ,@bt:*default-special-bindings*)))
    (lem-if:invoke implementation function)))
