(defpackage :lem-lisp-mode.autodoc
  (:use :cl :lem :lem-lisp-mode))
(in-package :lem-lisp-mode.autodoc)

(define-key *lisp-mode-keymap* "C-c C-d C-a" 'lisp-autodoc)
(define-key *lisp-mode-keymap* "M-a" 'lisp-autodoc)

(let ((autodoc-symbol nil))
  (defun autodoc-symbol ()
    (or autodoc-symbol
        (setf autodoc-symbol (intern "AUTODOC" :swank)))))

(defun highlighting-marker (point)
  (let ((marker-start "===> ")
        (marker-end " <==="))
    (when (search-forward point marker-start)
      (with-point ((start point))
        (when (search-forward point marker-end)
          (let ((matched-string
                  (with-point ((start start)
                               (end point))
                    (character-offset end (- (length marker-end)))
                    (points-to-string start end))))
            (character-offset start (- (length marker-start)))
            (delete-between-points start point)
            (insert-string start matched-string :attribute 'region)))))))

(defun autodoc (function)
  (let ((context (lem-lisp-syntax:parse-for-swank-autodoc (current-point))))
    (lisp-eval-async
     `(,(autodoc-symbol) ',context)
     (lambda (doc)
       (trivia:match doc
         ((list doc _)
          (unless (eq doc :not-available)
            (let* ((buffer (make-buffer "*swank:autodoc-fontity*"
                                        :temporary t :enable-undo-p nil)))
              (with-point ((point (buffer-point buffer) :right-inserting))
                (erase-buffer buffer)
                (change-buffer-mode buffer 'lisp-mode)
                (insert-string point doc)
                (setf (variable-value 'line-wrap :buffer buffer) nil)
                (highlighting-marker point)
                (funcall function buffer))))))))))

(define-command lisp-autodoc () ()
  (autodoc #'message-buffer))

(defmethod execute :after ((mode lisp-mode) (command self-insert) argument)
  (when (eql #\space (lem::get-self-insert-char))
    (lisp-autodoc)))
