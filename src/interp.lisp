(in-package :lem)

(define-condition editor-abort-handler (signal-handler) ())

(defvar *exit-editor-hook* '())

(defun bailout (condition)
  (signal 'exit-editor
          :report (with-output-to-string (stream)
                    (princ condition stream)
                    (uiop:print-backtrace
                     :stream stream
                     :condition condition))))

(defun pop-up-backtrace (condition)
  (let ((o (with-output-to-string (stream)
             (princ condition stream)
             (fresh-line stream)
             (uiop:print-backtrace
              :stream stream
              :count 100))))
    (funcall 'pop-up-typeout-window
             (make-buffer "*EDITOR ERROR*")
             (lambda (stream)
               (format stream "~A" o))
             :focus t
             :erase t)))

(defmacro with-error-handler (() &body body)
  `(handler-case
       (handler-bind ((error
                        (lambda (condition)
                          (handler-bind ((error #'bailout))
                            (pop-up-backtrace condition)
                            (redraw-display)))))
         ,@body)
     (error ())))

(defvar *interactive-p* nil)
(defun interactive-p () *interactive-p*)

(defvar *last-flags* nil)
(defvar *curr-flags* nil)

(defmacro save-continue-flags (&body body)
  `(let ((*last-flags* *last-flags*)
         (*curr-flags* *curr-flags*))
     ,@body))

(defun continue-flag (flag)
  (prog1 (cdr (assoc flag *last-flags*))
    (push (cons flag t) *last-flags*)
    (push (cons flag t) *curr-flags*)))

(defmacro do-command-loop ((&key interactive) &body body)
  (alexandria:once-only (interactive)
    `(loop :for *last-flags* := nil :then *curr-flags*
           :for *curr-flags* := nil
           :do (let ((*interactive-p* ,interactive)) ,@body))))

(defun fix-current-buffer-if-broken ()
  (unless (eq (window-buffer (current-window))
              (current-buffer))
    (setf (current-buffer) (window-buffer (current-window)))))

(defun command-loop-body ()
  (flet ((redraw ()
           (when (= 0 (event-queue-length))
             (without-interrupts
               (handler-bind ((error #'bailout))
                 (redraw-display)))))

         (read-command-and-call ()
           (let ((cmd (progn
                        (start-idle-timers)
                        (prog1 (read-command)
                          (stop-idle-timers)))))
             (message nil)
             (call-command cmd nil)))

         (editor-abort-handler (c)
           (declare (ignore c))
           (signal-subconditions 'editor-abort-handler)
           (buffer-mark-cancel (current-buffer)) ; TODO: define handler
           )

         (editor-condition-handler (c)
           (declare (ignore c))
           (stop-record-key) ; TODO: define handler
           ))

    (redraw)

    (handler-case
        (handler-bind ((editor-abort
                         #'editor-abort-handler)
                       (editor-condition
                         #'editor-condition-handler))
          (read-command-and-call))
      (editor-condition (c)
        (restart-case (error c)
          (lem-restart:message ()
            (typecase c
              (editor-abort
               (let ((message (princ-to-string c)))
                 (unless (string= "" message)
                   (message "~A" message))))
              (otherwise
               (message "~A" c))))
          (lem-restart:call-function (fn)
            (funcall fn)))))))

(defvar *toplevel-command-loop-p* t)

(defun toplevel-command-loop-p ()
  *toplevel-command-loop-p*)

(defun command-loop ()
  (do-command-loop (:interactive t)
    (if (toplevel-command-loop-p)
        (handler-bind ((signal-handler #'handle-signal))
          (with-error-handler ()
            (let ((*toplevel-command-loop-p* nil))
              (handler-bind ((editor-condition
                               (lambda (c)
                                 (declare (ignore c))
                                 (invoke-restart 'lem-restart:message))))
                (command-loop-body)))))
        (command-loop-body))
    (fix-current-buffer-if-broken)))

(defun toplevel-command-loop (initialize-function)
  (handler-bind ((exit-editor
                   (lambda (c)
                     (return-from toplevel-command-loop
                       (exit-editor-report c)))))
    (with-error-handler ()
      (funcall initialize-function))
    (with-editor-stream ()
      (command-loop))))

(defun exit-editor (&optional report)
  (run-hooks *exit-editor-hook*)
  (mapc #'disable-minor-mode (active-global-minor-modes))
  (signal 'exit-editor :report report))

(defun call-background-job (function cont)
  (bt:make-thread
   (lambda ()
     (let ((error-text))
       (handler-case
           (handler-bind ((error (lambda (c)
                                   (setf error-text
                                         (with-output-to-string (stream)
                                           (princ c stream)
                                           (fresh-line stream)
                                           (uiop:print-backtrace
                                            :stream stream
                                            :count 100))))))
             (let ((result (funcall function)))
               (send-event (lambda () (funcall cont result)))))
         (error ()
           (send-event (lambda ()
                         (let ((buffer (make-buffer "*BACKGROUND JOB ERROR*")))
                           (erase-buffer buffer)
                           (insert-string (buffer-point buffer)
                                          error-text)
                           (display-buffer buffer)
                           (buffer-start (buffer-point buffer)))))))))))
