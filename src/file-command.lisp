(in-package :lem)

(defun expand-files* (filename)
  (directory-files (expand-file-name filename (buffer-directory))))

(defun maybe-create-directory (directory)
  (when (prompt-for-y-or-n-p
         (format nil "Directory does not exist: ~A. Create" directory))
    (ensure-directories-exist directory)))

(defun directory-for-file-or-lose (filename)
  (let ((directory (directory-namestring filename)))
    (unless (or (uiop:directory-exists-p directory)
                (maybe-create-directory directory))
      (error 'editor-abort))
    directory))

(defgeneric execute-find-file (mode pathname))

(define-command find-file (arg) ("p")
  (let ((*default-external-format* *default-external-format*))
    (let ((filename
            (cond ((and (numberp arg) (= 1 arg))
                   (prompt-for-file
                    "Find File: "
                    :directory (buffer-directory)
                    :default nil
                    :existing nil))
                  ((numberp arg)
                   (setf *default-external-format*
                         (prompt-for-encodings
                          "Encodings: "
                          :history-symbol 'mh-read-file-encodings))
                   (prompt-for-file
                    "Find File: "
                    :directory (buffer-directory)
                    :default nil
                    :existing nil))
                  ((pathnamep arg)
                   (namestring arg)))))
      (dolist (pathname (expand-files* filename))
        (execute-find-file (get-file-mode pathname)
                           pathname)))))

(defmethod execute-find-file (mode pathname)
  (directory-for-file-or-lose pathname)
  (multiple-value-bind (buffer new-file-p)
      (find-file-buffer pathname)
    (switch-to-buffer buffer t nil)
    (values buffer new-file-p)))

(define-command read-file (filename) ("FRead File: ")
  (when (pathnamep filename)
    (setf filename (namestring filename)))
  (dolist (pathname (expand-files* filename))
    (let ((buffer (find-file-buffer (namestring pathname))))
      (setf (buffer-read-only-p buffer) t)
      (switch-to-buffer buffer t nil)))
  t)

(define-editor-variable Add-Newline-at-EOF-on-Writing-File nil)

(defun add-newline-at-eof (buffer)
  (when (variable-value 'Add-Newline-at-EOF-on-Writing-File :default buffer)
    (unless (start-line-p (buffer-end-point buffer))
      (with-point ((p (buffer-point buffer) :left-inserting))
        (save-excursion
          (insert-character p #\newline))))))

(defun save-buffer (buffer &optional force-p)
  (cond
    ((and (or force-p (buffer-modified-p buffer))
          (buffer-filename buffer))
     (add-newline-at-eof buffer)
     (write-to-file buffer (buffer-filename buffer))
     (buffer-unmark buffer)
     (buffer-filename buffer))
    ((null (buffer-filename buffer))
     (editor-error "No file name"))
    (t nil)))

(define-command save-current-buffer (&optional force-p) ("P")
  (let ((buffer (current-buffer)))
    (alexandria:when-let (filename (save-buffer buffer force-p))
      (message "Wrote ~A" filename))))

(define-command write-file (filename) ("FWrite File: ")
  (let* ((old (buffer-name))
         (new (file-namestring filename))
         (expand-file-name (expand-file-name filename)))
    (unless (and (find expand-file-name (mapcar #'buffer-filename
                                                (buffer-list))
                       :test #'equal)
                 (not (prompt-for-y-or-n-p (format nil
                                                   "~a is opend, overwrite it?"
                                                   expand-file-name))))
      (directory-for-file-or-lose filename)
      (unless (string= old new)
        (buffer-rename (current-buffer)
                       (if (get-buffer new)
                           (unique-buffer-name new)
                           new)))
      (setf (buffer-filename) expand-file-name)
      (add-newline-at-eof (current-buffer))
      (save-current-buffer t))))

(define-command write-region-file (start end filename)
    ("r" "FWrite Region To File: ")
  (setf filename (expand-file-name filename))
  (add-newline-at-eof (point-buffer start))
  (write-region-to-file start end filename)
  (message "Wrote ~A" filename))

(define-command insert-file (filename) ("fInsert file: ")
  (insert-file-contents (current-point)
                        (expand-file-name filename))
  t)

(define-command save-some-buffers (&optional save-silently-p) ("P")
  (let ((prev-buffer (current-buffer)))
    (dolist (buffer (buffer-list))
      (when (and (buffer-modified-p buffer)
                 (buffer-filename buffer))
        (switch-to-buffer buffer nil)
        (when (or save-silently-p
                  (prompt-for-y-or-n-p (format nil "Save file ~A" (buffer-filename buffer))))
          (save-current-buffer))))
    (switch-to-buffer prev-buffer nil)))

(defun revert-buffer-function (buffer)
  (buffer-value buffer 'revert-buffer-function))

(defun (setf revert-buffer-function) (function buffer)
  (setf (buffer-value buffer 'revert-buffer-function)
        function))

(defun revert-buffer-internal (buffer)
  (with-buffer-read-only buffer nil
    (let* ((point (buffer-point buffer))
           (line-number (line-number-at-point point))
           (column (point-column point)))
      (erase-buffer buffer)
      (insert-file-contents point (buffer-filename buffer))
      (buffer-unmark buffer)
      (update-changed-disk-date buffer)
      (move-to-line point line-number)
      (move-to-column point column)
      t)))

(define-command revert-buffer (does-not-ask-p) ("P")
  (let ((ask (not does-not-ask-p))
        (buffer (current-buffer)))
    (alexandria:if-let (fn (revert-buffer-function buffer))
      (funcall fn buffer)
      (when (and (or (buffer-modified-p buffer)
                     (changed-disk-p buffer))
                 (if ask
                     (prompt-for-y-or-n-p (format nil "Revert buffer from file ~A" (buffer-filename)))
                     t))
        (revert-buffer-internal buffer)))))

(define-condition ask-revert-buffer (before-executing-command)
  ((last-time :initform nil
              :allocation :class
              :accessor ask-revert-buffer-last-time)))
(defmethod handle-signal ((condition ask-revert-buffer))
  (when (or (null (ask-revert-buffer-last-time condition))
            (< (* 2 (/ internal-time-units-per-second 10))
               (- (get-internal-real-time) (ask-revert-buffer-last-time condition))))
    (setf (ask-revert-buffer-last-time condition) (get-internal-real-time))
    (when (changed-disk-p (current-buffer))
      (revert-buffer t)
      #+(or)
      (cond ((eql (buffer-value (current-buffer) 'no-revert-buffer)
                  (file-write-date (buffer-filename))))
            ((prompt-for-y-or-n-p (format nil "Revert buffer from file ~A" (buffer-filename)))
             (revert-buffer t))
            (t
             (setf (buffer-value (current-buffer) 'no-revert-buffer)
                   (file-write-date (buffer-filename))))))))

(define-command change-directory (directory)
    ((prompt-for-directory "change directory: " :directory (buffer-directory)))
  (let ((directory (expand-file-name directory (buffer-directory))))
    (setf (buffer-directory) directory)
    (uiop:chdir directory)
    (setf *default-pathname-defaults* (uiop:getcwd)))
  t)
