(in-package :lem-lisp-mode)

(define-editor-variable load-file-functions '())
(define-editor-variable before-compile-functions '())
(define-editor-variable before-eval-functions '())

(define-attribute compilation-region-highlight
  (t :background "orange"))

(define-attribute evaluation-region-highlight
  (t :background "green"))

(defparameter *default-port* 4005)
(defparameter *localhost* "127.0.0.1")
(defparameter *enable-feature-highlight* t)
(defparameter *write-string-function* 'write-string-to-repl)

(defvar *connection-list* '())
(defvar *connection* nil)
(defvar *event-hooks* '())
(defvar *last-compilation-result* nil)
(defvar *indent-table* (make-hash-table :test 'equal))

(define-major-mode lisp-mode language-mode
    (:name "lisp"
     :description "Contains necessary functions to handle lisp code."
     :keymap *lisp-mode-keymap*
     :syntax-table lem-lisp-syntax:*syntax-table*
     :mode-hook *lisp-mode-hook*)
  (modeline-add-status-list 'lisp-mode (current-buffer))
  (setf (variable-value 'beginning-of-defun-function) 'lisp-beginning-of-defun)
  (setf (variable-value 'end-of-defun-function) 'lisp-end-of-defun)
  (setf (variable-value 'indent-tabs-mode) nil)
  (setf (variable-value 'enable-syntax-highlight) t)
  (setf (variable-value 'calc-indent-function) 'calc-indent)
  (setf (variable-value 'line-comment) ";")
  (setf (variable-value 'insertion-line-comment) ";; ")
  (setf (variable-value 'xref-mode-tag) 'lisp-mode)
  (setf (variable-value 'find-definitions-function) 'find-definitions)
  (setf (variable-value 'find-references-function) 'find-references)
  (setf (variable-value 'completion-spec) 'completion-symbol)
  (setf (variable-value 'idle-function) 'lisp-idle-function)
  (set-syntax-parser lem-lisp-syntax:*syntax-table*
                     (make-tmlanguage-lisp :enable-feature-support *enable-feature-highlight*))
  (unless (connected-p) (self-connect)))

(define-key *lisp-mode-keymap* "C-M-q" 'lisp-indent-sexp)
(define-key *lisp-mode-keymap* "C-c M-p" 'lisp-set-package)
(define-key *global-keymap* "M-:" 'self-lisp-eval-string)
(define-key *lisp-mode-keymap* "C-c M-:" 'lisp-eval-string)
(define-key *global-keymap* "C-x C-e" 'self-lisp-eval-last-expression)
(define-key *lisp-mode-keymap* "C-c C-e" 'lisp-eval-last-expression)
(define-key *lisp-mode-keymap* "C-M-x" 'lisp-eval-defun)
(define-key *lisp-mode-keymap* "C-c C-r" 'lisp-eval-region)
(define-key *lisp-mode-keymap* "C-c C-l" 'lisp-load-file)
(define-key *lisp-mode-keymap* "C-c M-c" 'lisp-remove-notes)
(define-key *lisp-mode-keymap* "C-c C-k" 'lisp-compile-and-load-file)
(define-key *lisp-mode-keymap* "C-c C-c" 'lisp-compile-defun)
(define-key *lisp-mode-keymap* "C-c Return" 'lisp-macroexpand)
(define-key *lisp-mode-keymap* "C-c M-m" 'lisp-macroexpand-all)
(define-key *lisp-mode-keymap* "C-c C-d d" 'lisp-describe-symbol)
(define-key *lisp-mode-keymap* "C-c C-z" 'lisp-switch-to-repl-buffer)
(define-key *lisp-mode-keymap* "C-c z" 'lisp-switch-to-repl-buffer)
(define-key *lisp-mode-keymap* "C-c C-b" 'lisp-connection-list)
(define-key *lisp-mode-keymap* "C-c g" 'lisp-interrupt)
(define-key *lisp-mode-keymap* "C-c C-q" 'lisp-quickload)

(defmethod convert-modeline-element ((element (eql 'lisp-mode)) window)
  (format nil " [~A~A]" (buffer-package (window-buffer window) "CL-USER")
          (if *connection*
              (format nil " ~A:~A"
                      (connection-implementation-name *connection*)
                      (or (self-connection-p *connection*)
                          (connection-pid *connection*)))
              "")))

(defun change-current-connection (conn)
  (when *connection*
    (abort-all *connection* "change connection")
    (notify-change-connection-to-wait-message-thread))
  (setf *connection* conn))

(defun connected-p ()
  (not (null *connection*)))

(defun add-connection (conn)
  (push conn *connection-list*)
  (change-current-connection conn))

(defun remove-connection (conn)
  (setf *connection-list* (delete conn *connection-list*))
  ;(change-current-connection (car *connection-list*))
  (setf *connection* (car *connection-list*))
  *connection*)

(define-command lisp-connection-list () ()
  (lem.menu-mode:display-menu
   (make-instance 'lem.menu-mode:menu
                  :columns '(" " "hostname" "port" "pid" "name" "version" "command")
                  :items *connection-list*
                  :column-function (lambda (c)
                                     (list (if (eq c *connection*) "*" "")
                                           (connection-hostname c)
                                           (connection-port c)
                                           (or (self-connection-p c) (connection-pid c))
                                           (connection-implementation-name c)
                                           (connection-implementation-version c)
                                           (connection-command c)))
                  :select-callback (lambda (menu c)
                                     (change-current-connection c)
                                     (lem.menu-mode:update-menu menu *connection-list*)
                                     :close)
                  :update-items-function (lambda () *connection-list*))
   :name "Lisp Connections"))

(defvar *self-connected-port* nil)

(defun self-connected-p ()
  (not (null *self-connected-port*)))

(defun self-connected-port ()
  *self-connected-port*)

;; DO NOT USE THIS VARIABLE, this is for unit-test
(defvar *disable-self-connect* nil)

(defun self-connect ()
  (unless *disable-self-connect*
    (let ((port (lem-socket-utils:random-available-port)))
      (log:debug "Starting internal SWANK and connecting to it" swank:*communication-style*)
      (let ((swank::*swank-debug-p* nil))
        (swank:create-server :port port :style :spawn))
      (%slime-connect *localhost* port)
      (update-buffer-package)
      (setf *self-connected-port* port))))

(defun self-connection-p (c)
  (and (typep c 'connection)
       (integerp *self-connected-port*)
       (member (connection-hostname c) '("127.0.0.1" "localhost") :test 'equal)
       (ignore-errors (equal (connection-pid c) (swank/backend:getpid)))
       (= (connection-port c) *self-connected-port*)
       :self))

(defun check-connection ()
  (unless (connected-p)
    (self-connect)))

(defun buffer-package (buffer &optional default)
  (let ((package-name (buffer-value buffer "package" default)))
    (typecase package-name
      (null default)
      ((or symbol string)
       (string-upcase package-name))
      ((cons (or symbol string))
       (string-upcase (car package-name))))))

(defun (setf buffer-package) (package buffer)
  (setf (buffer-value buffer "package") package))

(defvar *current-package* nil)

(defun current-package ()
  (or *current-package*
      (buffer-package (current-buffer))
      (connection-package *connection*)))

(defun current-swank-thread ()
  (or (buffer-value (current-buffer) 'thread)
      t))

(defun features ()
  (when (connected-p)
    (connection-features *connection*)))

(defun indentation-update (info)
  (push (list :indentation-update info) lem-lisp-syntax.indent::*indent-log*)
  (loop :for (name indent packages) :in info
        :do (lem-lisp-syntax:update-system-indentation name indent packages))
  #+(or)
  (loop :for (name indent packages) :in info
        :do (dolist (package packages)
              (unless (gethash package *indent-table*)
                (setf (gethash package *indent-table*)
                      (make-hash-table :test 'equal)))
              (setf (gethash name (gethash package *indent-table*)) indent))))

(defun indent-spec (string)
  (when (connected-p)
    (let* ((parts (uiop:split-string string :separator ":"))
           (length (length parts))
           (package))
      (cond ((= length 1)
             (setq package (current-package)))
            ((or (= length 2)
                 (and (= length 3)
                      (string= "" (second parts))))
             (setq package (first parts))))
      (let ((table (gethash package *indent-table*)))
        (when table
          (values (gethash (first (last parts)) table)))))))

(defun calc-indent (point)
  (let ((lem-lisp-syntax:*get-method-function* #'indent-spec))
    (lem-lisp-syntax:calc-indent point)))

(defun lisp-rex (form &key
                      continuation
                      (thread (current-swank-thread))
                      (package (current-package)))
  (emacs-rex *connection*
             form
             :continuation continuation
             :thread thread
             :package package))

(defun lisp-eval-internal (emacs-rex-fun rex-arg package)
  (let ((tag (gensym))
        (thread-id (current-swank-thread)))
    (catch tag
      (funcall emacs-rex-fun
               *connection*
               rex-arg
               :continuation (lambda (result)
                               (alexandria:destructuring-ecase result
                                 ((:ok value)
                                  (throw tag value))
                                 ((:abort condition)
                                  (declare (ignore condition))
                                  (editor-error "Synchronous Lisp Evaluation aborted"))))
               :package package
               :thread thread-id)
      (handler-case (loop (sit-for 10 nil))
        (editor-abort ()
          (send-message-string *connection* (format nil "(:emacs-interrupt ~D)" thread-id))
          (keyboard-quit))))))

(defun lisp-eval-from-string (string &optional (package (current-package)))
  (lisp-eval-internal 'emacs-rex-string string package))

(defun lisp-eval (sexp &optional (package (current-package)))
  (lisp-eval-internal 'emacs-rex sexp package))

(defun lisp-eval-async (form &optional cont (package (current-package)))
  (let ((buffer (current-buffer)))
    (lisp-rex form
              :continuation (lambda (value)
                              (alexandria:destructuring-ecase value
                                ((:ok result)
                                 (when cont
                                   (let ((prev (current-buffer)))
                                     (setf (current-buffer) buffer)
                                     (funcall cont result)
                                     (unless (eq (current-buffer)
                                                 (window-buffer (current-window)))
                                       (setf (current-buffer) prev)))))
                                ((:abort condition)
                                 (display-message "Evaluation aborted on ~A." condition))))
              :thread (current-swank-thread)
              :package package)))

(defun eval-with-transcript (form)
  (lisp-rex form
            :continuation (lambda (value)
                            (alexandria:destructuring-ecase value
                              ((:ok x)
                               (display-message "~A" x))
                              ((:abort condition)
                               (display-message "Evaluation aborted on ~A." condition))))
            :package (current-package)))

(defun re-eval-defvar (string)
  (eval-with-transcript `(swank:re-evaluate-defvar ,string)))

(defun interactive-eval (string)
  (eval-with-transcript `(swank:interactive-eval ,string)))

(defun eval-print (string &optional print-right-margin)
  (let ((value (lisp-eval (if print-right-margin
                              `(let ((*print-right-margin* ,print-right-margin))
                                 (swank:eval-and-grab-output ,string))
                              `(swank:eval-and-grab-output ,string)))))
    (insert-string (current-point) (first value))
    (insert-character (current-point) #\newline)
    (insert-string (current-point) (second value))))

(defun new-package (name prompt-string)
  (setf (connection-package *connection*) name)
  (setf (connection-prompt-string *connection*) prompt-string)
  t)

(defun read-package-name ()
  (check-connection)
  (let ((package-names (mapcar #'string-downcase
                               (lisp-eval
                                '(swank:list-all-package-names t)))))
    (string-upcase (prompt-for-string
                    "Package: "
                    :completion-function (lambda (str)
                                           (completion str package-names))
                    :test-function (lambda (str)
                                     (find str package-names :test #'string=))
                    :history-symbol 'mh-lisp-package))))

(defun lisp-beginning-of-defun (point n)
  (lem-lisp-syntax:beginning-of-defun point (- n)))

(defun lisp-end-of-defun (point n)
  (if (minusp n)
      (lisp-beginning-of-defun point (- n))
      (dotimes (_ n)
        (with-point ((p point))
          (cond ((and (lem-lisp-syntax:beginning-of-defun p -1)
                      (point<= p point)
                      (or (form-offset p 1)
                          (progn
                            (move-point point p)
                            (return)))
                      (point< point p))
                 (move-point point p)
                 (skip-whitespace-forward point t)
                 (when (end-line-p point)
                   (character-offset point 1)))
                (t
                 (form-offset point 1)
                 (skip-whitespace-forward point t)
                 (when (end-line-p point)
                   (character-offset point 1))))))))

(define-command lisp-indent-sexp () ()
  (with-point ((end (current-point) :right-inserting))
    (when (form-offset end 1)
      (indent-region (current-point) end))))

(define-command lisp-set-package (package-name) ((read-package-name))
  (check-connection)
  (cond ((string= package-name ""))
        ((eq (current-buffer) (repl-buffer))
         (destructuring-bind (name prompt-string)
             (lisp-eval `(swank:set-package ,package-name))
           (new-package name prompt-string)
           (lem.listener-mode:refresh-prompt (repl-buffer))))
        (t
         (setf (buffer-value (current-buffer) "package") package-name))))

(define-command lisp-listen-in-current-package () ()
  (check-connection)
  (alexandria:when-let ((repl-buffer (repl-buffer))
                        (package (buffer-package (current-buffer))))
    (save-excursion
      (setf (current-buffer) repl-buffer)
      (destructuring-bind (name prompt-string)
          (lisp-eval `(swank:set-package ,package))
        (new-package name prompt-string)))
    (start-lisp-repl)
    (buffer-end (buffer-point repl-buffer))))

(define-command lisp-interrupt () ()
  (send-message-string
   *connection*
   (format nil "(:emacs-interrupt ~A)" (current-swank-thread))))

(defun prompt-for-sexp (string &optional initial)
  (prompt-for-string string
                     :initial-value initial
                     :completion-function (lambda (str)
                                            (declare (ignore str))
                                            (completion-symbol (current-point)))
                     :history-symbol 'mh-sexp))

(define-command lisp-eval-string (string)
    ((prompt-for-sexp "Lisp Eval: "))
  (check-connection)
  (interactive-eval string))

(define-command lisp-eval-last-expression (p) ("P")
  (check-connection)
  (with-point ((start (current-point))
               (end (current-point)))
    (form-offset start -1)
    (run-hooks (variable-value 'before-eval-functions) start end)
    (let ((string (points-to-string start end)))
      (if p
          (eval-print string (- (window-width (current-window)) 2))
          (interactive-eval string)))))

(defun self-current-package ()
  (or (find (or *current-package*
                (buffer-package (current-buffer))
                (scan-current-package (current-point)))
            (list-all-packages)
            :test 'equalp
            :key 'package-name)
      *package*))

(defmacro with-eval ((&key (values (gensym) values-p)
                           (stream (error ":stream missing")))
                     &body body)
  (alexandria:with-gensyms (io)
    `(with-open-stream (,io ,stream)
       (let* ((*package* (self-current-package))
              (*terminal-io* ,io)
              (*standard-output* ,io)
              (*standard-input* ,io)
              (*error-output* ,io)
              (*query-io* ,io)
              (*debug-io* ,io)
              (*trace-output* ,io)
              (*terminal-io* ,io)
              (,values (multiple-value-list (eval (read-from-string string)))))
         ,@(if (not values-p) `((declare (ignorable ,values))))
         ,@body))))

(defun self-interactive-eval (string)
  (with-eval (:values values :stream (make-editor-io-stream))
    (display-message "=> ~{~S~^, ~}" values)))

(defun self-eval-print (string &optional print-right-margin)
  (declare (ignore print-right-margin))
  (with-eval (:values values :stream (make-buffer-output-stream (current-point)))
    (insert-string (current-point) (format nil "~{~S~^~%~}" values))))

(define-command self-lisp-eval-string (string)
    ((prompt-for-sexp "Lisp Eval: "))
  (self-interactive-eval string))

(define-command self-lisp-eval-last-expression (p) ("P")
  (with-point ((start (current-point))
               (end (current-point)))
    (form-offset start -1)
    (run-hooks (variable-value 'before-eval-functions) start end)
    (let ((string (points-to-string start end)))
      (if p
          (self-eval-print string (- (window-width (current-window)) 2))
          (self-interactive-eval string)))))

(define-command lisp-eval-defun () ()
  (check-connection)
  (with-point ((point (current-point)))
    (lem-lisp-syntax:top-of-defun point)
    (with-point ((start point)
                 (end point))
      (scan-lists end 1 0)
      (run-hooks (variable-value 'before-eval-functions) start end)
      (let ((string (points-to-string start end)))
        (if (ppcre:scan "^\\(defvar(?:\\s|$)" string)
            (re-eval-defvar string)
            (interactive-eval string))))))

(define-command lisp-eval-region (start end) ("r")
  (check-connection)
  (eval-with-transcript
   `(swank:interactive-eval-region
     ,(points-to-string start end))))

(define-command lisp-load-file (filename)
    ((prompt-for-file "Load File: "
                      :directory (or (buffer-filename) (buffer-directory))
                      :default nil
                      :existing t))
  (check-connection)
  (when (and (probe-file filename)
             (not (uiop:directory-pathname-p filename)))
    (run-hooks (variable-value 'load-file-functions) filename)
    (interactive-eval
     (prin1-to-string
      `(if (and (find-package :roswell)
                (find-symbol (string :load) :roswell))
           (uiop:symbol-call :roswell :load ,filename)
           (swank:load-file ,filename))))))

(defun get-operator-name ()
  (with-point ((point (current-point)))
    (scan-lists point -1 1)
    (character-offset point 1)
    (symbol-string-at-point point)))

(define-command lisp-echo-arglist () ()
  (check-connection)
  (let ((name (get-operator-name))
        (package (current-package)))
    (when name
      (lisp-eval-async `(swank:operator-arglist ,name ,package)
                       (lambda (arglist)
                         (when arglist
                           (display-message "~A" (ppcre:regex-replace-all "\\s+" arglist " "))))))))

(defun check-parens ()
  (with-point ((point (current-point)))
    (buffer-start point)
    (loop :while (form-offset point 1))
    (skip-space-and-comment-forward point)
    (end-buffer-p point)))

(defun compilation-finished (result)
  (setf *last-compilation-result* result)
  (destructuring-bind (notes successp duration loadp fastfile)
      (rest result)
    (show-compile-result notes duration
                         (if (not loadp)
                             successp
                             (and fastfile successp)))
    (highlight-notes notes)
    (when (and loadp fastfile successp)
      (lisp-eval-async `(swank:load-file ,fastfile)))))

(defun show-compile-result (notes secs successp)
  (display-message (format nil "~{~A~^ ~}"
                           (remove-if #'null
                                      (list (if successp
                                                "Compilation finished"
                                                "Compilation failed")
                                            (unless notes
                                              "(No warnings)")
                                            (when secs
                                              (format nil "[~,2f secs]" secs)))))))

(defun make-highlight-overlay (pos buffer)
  (with-point ((point (buffer-point buffer)))
    (move-to-position point pos)
    (skip-chars-backward point #'syntax-symbol-char-p)
    (make-overlay point
                  (or (form-offset (copy-point point :temporary) 1)
                      (buffer-end-point buffer))
                  'compiler-note-attribute)))

(defvar *note-overlays* nil)

(defun convert-notes (notes)
  (loop :for note :in notes
        :when (destructuring-bind (&key location message source-context &allow-other-keys) note
                (when location
                  (alexandria:when-let ((xref-location
                                         (source-location-to-xref-location location nil t)))
                    (list xref-location
                          message
                          source-context))))
        :collect :it))

(defun highlight-notes (notes)
  (lisp-remove-notes)
  (when (or notes (get-buffer-windows (get-buffer "*lisp-compilations*")))
    (lem.sourcelist:with-sourcelist (sourcelist "*lisp-compilations*")
      (loop :for (xref-location message source-context) :in (convert-notes notes)
            :do (let* ((name (xref-filespec-to-filename (xref-location-filespec xref-location)))
                       (pos (xref-location-position xref-location))
                       (buffer (xref-filespec-to-buffer (xref-location-filespec xref-location))))
                  (lem.sourcelist:append-sourcelist
                   sourcelist
                   (lambda (cur-point)
                     (insert-string cur-point name :attribute 'lem.sourcelist:title-attribute)
                     (insert-string cur-point ":")
                     (insert-string cur-point (princ-to-string pos)
                                    :attribute 'lem.sourcelist:position-attribute)
                     (insert-string cur-point ":")
                     (insert-character cur-point #\newline 1)
                     (insert-string cur-point message)
                     (insert-character cur-point #\newline)
                     (insert-string cur-point source-context))
                   (alexandria:curry #'go-to-location xref-location))
                  (push (make-highlight-overlay pos buffer)
                        *note-overlays*))))))

(define-command lisp-remove-notes () ()
  (mapc #'delete-overlay *note-overlays*)
  (setf *note-overlays* '()))

(define-command lisp-compile-and-load-file () ()
  (check-connection)
  (when (buffer-modified-p (current-buffer))
    (when (prompt-for-y-or-n-p "Save file")
      (save-current-buffer)))
  (let ((file (buffer-filename (current-buffer))))
    (run-hooks (variable-value 'load-file-functions) file)
    (lisp-eval-async `(swank:compile-file-for-emacs ,file t)
                     #'compilation-finished)))

(define-command lisp-compile-region (start end) ("r")
  (check-connection)
  (let ((string (points-to-string start end))
        (position `((:position ,(position-at-point start))
                    (:line
                     ,(line-number-at-point (current-point))
                     ,(point-charpos (current-point))))))
    (run-hooks (variable-value 'before-compile-functions) start end)
    (lisp-eval-async `(swank:compile-string-for-emacs ,string
                                                      ,(buffer-name (current-buffer))
                                                      ',position
                                                      ,(buffer-filename (current-buffer))
                                                      nil)
                     #'compilation-finished)))

(define-command lisp-compile-defun () ()
  (check-connection)
  (with-point ((point (current-point)))
    (lem-lisp-syntax:top-of-defun point)
    (with-point ((start point)
                 (end point))
      (scan-lists end 1 0)
      (lisp-compile-region start end))))

(defun form-string-at-point ()
  (with-point ((point (current-point)))
    (skip-chars-backward point #'syntax-symbol-char-p)
    (with-point ((start point)
                 (end point))
      (form-offset end 1)
      (points-to-string start end))))

(defun macroexpand-internal (expander)
  (let* ((self (eq (current-buffer) (get-buffer "*lisp-macroexpand*")))
         (orig-package-name (buffer-package (current-buffer) "CL-USER"))
         (p (and self (copy-point (current-point) :temporary))))
    (lisp-eval-async `(,expander ,(form-string-at-point))
                     (lambda (string)
                       (let ((buffer (make-buffer "*lisp-macroexpand*")))
                         (with-buffer-read-only buffer nil
                           (unless self (erase-buffer buffer))
                           (change-buffer-mode buffer 'lisp-mode)
                           (setf (buffer-package buffer) orig-package-name)
                           (when self
                             (move-point (current-point) p)
                             (kill-sexp))
                           (insert-string (buffer-point buffer)
                                          string)
                           (indent-region (buffer-start-point buffer)
                                          (buffer-end-point buffer))
                           (with-pop-up-typeout-window (s buffer)
                             (declare (ignore s)))
                           (when self
                             (move-point (buffer-point buffer) p))))))))

(define-command lisp-macroexpand () ()
  (check-connection)
  (macroexpand-internal 'swank:swank-macroexpand-1))

(define-command lisp-macroexpand-all () ()
  (check-connection)
  (macroexpand-internal 'swank:swank-macroexpand-all))

(define-command lisp-quickload (system-name)
    ((prompt-for-symbol-name "System: " (lem-lisp-mode::buffer-package (current-buffer))))
  (check-connection)
  (eval-with-transcript `(,(uiop:find-symbol* :quickload :quicklisp) ,(string system-name))))

(defvar *completion-symbol-with-fuzzy* t)

(defun symbol-completion (str &optional (package (current-package)))
  (let* ((fuzzy *completion-symbol-with-fuzzy*)
         (result (lisp-eval-from-string
                  (format nil "(~A ~S ~S)"
                          (if fuzzy
                              "swank:fuzzy-completions"
                              "swank:completions")
                          str
                          package)
                  "COMMON-LISP")))
    (when result
      (destructuring-bind (completions timeout-p) result
        (declare (ignore timeout-p))
        (completion-hypheen str (mapcar (if fuzzy #'first #'identity) completions))))))

(defun prompt-for-symbol-name (prompt &optional (initial ""))
  (let ((package (current-package)))
    (prompt-for-string prompt
                       :initial-value initial
                       :completion-function (lambda (str)
                                              (symbol-completion str package))
                       :history-symbol 'mh-read-symbol)))

(defun definition-to-location (definition)
  (destructuring-bind (title location) definition
    (source-location-to-xref-location location title t)))

(defun definitions-to-locations (definitions)
  (loop :for def :in definitions
        :for xref := (definition-to-location def)
        :when xref
        :collect xref))

(defun find-local-definition (point name)
  (alexandria:when-let (point (lem-lisp-syntax:search-local-definition point name))
    (list (make-xref-location :filespec (point-buffer point)
                              :position (position-at-point point)))))

(defun find-definitions-default (point)
  (let ((name (or (symbol-string-at-point point)
                  (prompt-for-symbol-name "Edit Definition of: "))))
    (alexandria:when-let (result (find-local-definition point name))
      (return-from find-definitions-default result))
    (let ((definitions (lisp-eval `(swank:find-definitions-for-emacs ,name))))
      (definitions-to-locations definitions))))

(defparameter *find-definitions* '(find-definitions-default))

(defun find-definitions (point)
  (check-connection)
  (display-xref-locations (some (alexandria:rcurry #'funcall point) *find-definitions*)))

(defun find-references (point)
  (check-connection)
  (let* ((name (or (symbol-string-at-point point)
                   (prompt-for-symbol-name "Edit uses of: ")))
         (data (lisp-eval `(swank:xrefs '(:calls :macroexpands :binds
                                          :references :sets :specializes)
                                        ,name))))
    (display-xref-references
     (loop
       :for (type . definitions) :in data
       :for defs := (definitions-to-locations definitions)
       :collect (make-xref-references :type type
                                      :locations defs)))))

(defun completion-symbol (point)
  (check-connection)
  (with-point ((start point)
               (end point))
    (skip-chars-backward start #'syntax-symbol-char-p)
    (skip-chars-forward end #'syntax-symbol-char-p)
    (when (point< start end)
      (let* ((fuzzy *completion-symbol-with-fuzzy*)
             (result
               (lisp-eval-from-string (format nil "(~A ~S ~S)"
                                              (if fuzzy
                                                  "swank:fuzzy-completions"
                                                  "swank:completions")
                                              (points-to-string start end)
                                              (current-package)))))
        (when result
          (destructuring-bind (completions timeout-p) result
            (declare (ignore timeout-p))
            (mapcar (lambda (completion)
                      (make-completion-item
                       :label (if fuzzy
                                  (first completion)
                                  completion)
                       :detail (if fuzzy
                                   (fourth completion)
                                   "")
                       :start start
                       :end end))
                    completions)))))))

(defun show-description (string)
  (let ((buffer (make-buffer "*lisp-description*")))
    (change-buffer-mode buffer 'lisp-mode)
    (with-pop-up-typeout-window (stream buffer :erase t)
      (princ string stream))))

(defun lisp-eval-describe (form)
  (lisp-eval-async form #'show-description))

(define-command lisp-describe-symbol () ()
  (check-connection)
  (let ((symbol-name
          (prompt-for-symbol-name "Describe symbol: "
                            (or (symbol-string-at-point (current-point)) ""))))
    (when (string= "" symbol-name)
      (editor-error "No symbol given"))
    (lisp-eval-describe `(swank:describe-symbol ,symbol-name))))

(defvar *wait-message-thread* nil)

(defun notify-change-connection-to-wait-message-thread ()
  (bt:interrupt-thread *wait-message-thread*
                       (lambda () (error 'change-connection))))

(defun start-thread ()
  (unless *wait-message-thread*
    (setf *wait-message-thread*
          (bt:make-thread
           (lambda () (loop
                        :named exit
                        :do
                        (handler-case
                            (loop

                              ;; workaround for windows
                              ;;  (sleep seems to be necessary to receive
                              ;;   change-connection event immediately)
                              #+(and sbcl win32)
                              (sleep 0.001)

                              (unless (connected-p)
                                (setf *wait-message-thread* nil)
                                (return-from exit))
                              (when (message-waiting-p *connection* :timeout 1)
                                (let ((barrior t))
                                  (send-event (lambda ()
                                                (unwind-protect (progn (pull-events)
                                                                       (redraw-display))
                                                  (setq barrior nil))))
                                  (loop
                                    (unless (connected-p)
                                      (return))
                                    (unless barrior
                                      (return))
                                    (sleep 0.1)))))
                          (change-connection ()))))
           :name "lisp-wait-message"))))

(defun connected-slime-message (connection)
  (display-popup-message
   (format nil "Swank server running on ~A ~A"
           (connection-implementation-name connection)
           (connection-implementation-version connection))
   :timeout 1
   :style '(:gravity :center)))

(defun %slime-connect (hostname port)
  (let ((connection
          (handler-case (if (eq hostname *localhost*)
                            (or (ignore-errors (new-connection "127.0.0.1" port))
                                (new-connection "localhost" port))
                            (new-connection hostname port))
            (error (c)
              (editor-error "~A" c)))))
    (add-connection connection)
    (start-thread)
    connection))

(define-command slime-connect (hostname port &optional (start-repl t))
    ((:splice
      (list (prompt-for-string "Hostname: " :initial-value *localhost*)
            (parse-integer
             (prompt-for-string "Port: "
                                :initial-value (princ-to-string *default-port*))))))
  (let ((connection (%slime-connect hostname port)))
    (when start-repl (start-lisp-repl))
    (connected-slime-message connection)))

(defvar *unknown-keywords* nil)
(defun pull-events ()
  (when (and (boundp '*connection*)
             (not (null *connection*)))
    (handler-case (loop :while (message-waiting-p *connection*)
                        :do (dispatch-message (read-message *connection*)))
      (disconnected ()
        (remove-connection *connection*)))))

(defun dispatch-message (message)
  (log-message (prin1-to-string message))
  (dolist (e *event-hooks*)
    (when (funcall e message)
      (return-from dispatch-message)))
  (alexandria:destructuring-case message
    ((:write-string string &rest rest)
     (declare (ignore rest))
     (funcall *write-string-function* string))
    ((:read-string thread tag)
     (repl-read-string thread tag))
    ((:read-aborted thread tag)
     (repl-abort-read thread tag))
    ;; ((:open-dedicated-output-stream port coding-system)
    ;;  )
    ((:new-package name prompt-string)
     (new-package name prompt-string))
    ((:return value id)
     (finish-evaluated *connection* value id))
    ;; ((:channel-send id msg)
    ;;  )
    ;; ((:emacs-channel-send id msg)
    ;;  )
    ((:read-from-minibuffer thread tag prompt initial-value)
     (read-from-minibuffer thread tag prompt initial-value))
    ((:y-or-n-p thread tag question)
     (dispatch-message `(:emacs-return ,thread ,tag ,(prompt-for-y-or-n-p question))))
    ((:emacs-return-string thread tag string)
     (send-message-string
      *connection*
      (format nil "(:emacs-return-string ~A ~A ~S)"
              thread
              tag
              string)))
    ((:new-features features)
     (setf (connection-features *connection*)
           features))
    ((:indentation-update info)
     (indentation-update info))
    ((:eval-no-wait form)
     (eval (read-from-string form)))
    ((:eval thread tag form-string)
     (let ((result (handler-case (eval (read-from-string form-string))
                     (error (c)
                       `(:error ,(type-of c) ,(princ-to-string c)))
                     (:no-error (&rest values)
                       `(:ok ,(first values))))))
       (dispatch-message `(:emacs-return ,thread ,tag ,result))))
    ((:emacs-return thread tag value)
     (send-message-string
      *connection*
      (format nil "(:emacs-return ~A ~A ~S)" thread tag value)))
    ;; ((:ed what)
    ;;  )
    ;; ((:inspect what thread tag)
    ;;  )
    ;; ((:background-message message)
    ;;  )
    ((:debug-condition thread message)
     (assert thread)
     (display-message "~A" message))
    ((:ping thread tag)
     (send-message-string
      *connection*
      (format nil "(:emacs-pong ~A ~A)" thread tag)))
    ;; ((:reader-error packet condition)
    ;;  )
    ;; ((:invalid-rpc id message)
    ;;  )
    ;; ((:emacs-skipped-packet _pkg))
    ;; ((:test-delay seconds)
    ;;  )
    ((t &rest args)
     (declare (ignore args))
     (pushnew (car message) *unknown-keywords*))))

(defun read-from-minibuffer (thread tag prompt initial-value)
  (let ((input (prompt-for-sexp prompt initial-value)))
    (dispatch-message `(:emacs-return ,thread ,tag ,input))))

(defun show-source-location (source-location)
  (alexandria:destructuring-case source-location
    ((:error message)
     (display-message "~A" message))
    ((t &rest _)
     (declare (ignore _))
     (let ((xref-location (source-location-to-xref-location source-location)))
       (go-to-location xref-location
                       (lambda (buffer)
                         (setf (current-window)
                               (pop-to-buffer buffer))))))))

(defun source-location-to-xref-location (location &optional content no-errors)
  (alexandria:destructuring-ecase location
    ((:location location-buffer position _hints)
     (declare (ignore _hints))
     (let ((buffer (location-buffer-to-buffer location-buffer)))
       (with-point ((point (buffer-point buffer)))
         (move-to-location-position point position)
         (make-xref-location :content (or content "")
                             :filespec buffer
                             :position (position-at-point point)))))
    ((:error message)
     (unless no-errors
       (editor-error "~A" message)))))

(defun location-buffer-to-buffer (location-buffer)
  (alexandria:destructuring-ecase location-buffer
    ((:file filename)
     (find-file-buffer filename))
    ((:buffer buffer-name)
     (let ((buffer (get-buffer buffer-name)))
       (unless buffer (editor-error "~A is already deleted buffer" buffer-name))
       buffer))
    ((:buffer-and-file buffer filename)
     (or (get-buffer buffer)
         (find-file-buffer filename)))
    ((:source-form string)
     (let ((buffer (make-buffer "*lisp-source*")))
       (erase-buffer buffer)
       (change-buffer-mode buffer 'lisp-mode)
       (insert-string (buffer-point buffer) string)
       (buffer-start (buffer-point buffer))
       buffer))
    #+(or)((:zip file entry))
    ))

(defun move-to-bytes (point bytes)
  (buffer-start point)
  (loop
    (let ((size (1+ (babel:string-size-in-octets (line-string point)))))
      (when (<= bytes size)
        (loop :for i :from 0
              :do
                 (decf bytes (babel:string-size-in-octets (string (character-at point i))))
                 (when (<= bytes 0)
                   (character-offset point i)
                   (return-from move-to-bytes point))))
      (decf bytes size)
      (unless (line-offset point 1) (return)))))

(defun move-to-location-position (point location-position)
  (alexandria:destructuring-ecase location-position
    ((:position pos)
     (move-to-bytes point (1+ pos)))
    ((:offset start offset)
     (move-to-position point (1+ start))
     (character-offset point offset))
    ((:line line-number &optional column)
     (move-to-line point line-number)
     (if column
         (line-offset point 0 column)
         (back-to-indentation point)))
    ((:function-name name)
     (buffer-start point)
     (search-forward-regexp point (ppcre:create-scanner
                                   `(:sequence
                                     "(def"
                                     (:greedy-repetition 1 nil (:char-class :word-char-class #\-))
                                     (:greedy-repetition 1 nil :whitespace-char-class)
                                     (:greedy-repetition 0 nil #\()
                                     ,name
                                     (:char-class :whitespace-char-class #\( #\)))
                                   :case-insensitive-mode t))
     (line-start point))
    ;; ((:method name specializers &rest qualifiers)
    ;;  )
    ;; ((:source-path source-path start-position)
    ;;  )
    ((:eof)
     (buffer-end point))))


(defparameter *impl-name* nil)
(defvar *slime-command-impls* '(roswell-impls-candidates
                                qlot-impls-candidates))
(defun get-lisp-command (&key impl (prefix ""))
  (format nil "~Aros ~{~A~^ ~}" prefix
          `(,@(if impl `("-L" ,impl))
            "-s" "swank" "run")))

(let (cache)
  (defun roswell-impls-candidates (&optional impl)
    (if impl
        (cond ((string= "" impl)
               (get-lisp-command :impl nil))
              ((find impl (or (first cache) (roswell-impls-candidates)) :test #'equal)
               (get-lisp-command :impl impl)))
        (progn
          (unless (and cache
                       (< (get-universal-time) (+ 3600 (cdr cache))))
            (setf cache
                  (cons (nreverse
                         (uiop:split-string (string-right-trim
                                             (format nil "~%")
                                             (with-output-to-string (out)
                                               (uiop:run-program '("ros" "list" "installed")
                                                                 :output out)))
                                            :separator '(#\Newline)))
                        (get-universal-time))))
          (first cache)))))

(defun qlot-impls-candidates (&optional impl)
  (if impl
      (ignore-errors
       (when (string= "qlot/" impl :end2 5)
         (get-lisp-command :prefix "qlot exec "
                           :impl (let ((impl (subseq impl 5)))
                                   (unless (zerop (length impl))
                                     impl)))))
      (when (ignore-errors
             (string-right-trim
              '(#\newline)
              (uiop:run-program '("ros" "roswell-internal-use" "which" "qlot")
                                :output :string)))
        (mapcar (lambda (x) (format nil "qlot/~A" x))
                (roswell-impls-candidates)))))

(defun get-slime-command-list ()
  (cons ""
        (loop :for f :in *slime-command-impls*
              :append (funcall f))))

(defun completion-impls (str &optional (command-list (get-slime-command-list)))
  (completion-strings str command-list))

(defun prompt-for-impl (&key (existing t))
  (let* ((default-impl (config :slime-lisp-implementation ""))
         (command-list (get-slime-command-list))
         (impl (prompt-for-string
                (format nil "lisp implementation (~A): " default-impl)
                :completion-function 'completion-impls
                :test-function (and existing
                                    (lambda (name)
                                      (member name command-list :test #'string=)))
                :history-symbol 'mh-read-impl))
         (impl (if (string= impl "")
                   default-impl
                   impl))
         (command (loop :for f :in *slime-command-impls*
                        :for command := (funcall f impl)
                        :when command
                        :do (return command))))
    (setf (config :slime-lisp-implementation) impl)
    command))

(defun lisp-process-buffer-name (port)
  (format nil "*Run Lisp swank/~D*" port))

(defun get-lisp-process-buffer (port)
  (get-buffer (lisp-process-buffer-name port)))

(defun make-lisp-process-buffer (port)
  (make-buffer (lisp-process-buffer-name port)))

(defun run-lisp (&key command port directory)
  (labels ((output-callback (string)
             (let* ((buffer (make-lisp-process-buffer port))
                    (point (buffer-point buffer)))
               (buffer-end point)
               (insert-escape-sequence-string point string))))
    (let ((process
            (lem-process:run-process (uiop:split-string command)
                                     :directory directory
                                     :output-callback #'output-callback)))
      process)))

(defun send-swank-create-server (process port)
  (lem-process:process-send-input
   process
   (format nil "(swank:create-server :port ~D :dont-close t)~%" port)))

(defun run-slime (command &key (directory (buffer-directory)))
  (unless command
    (setf command (get-lisp-command :impl *impl-name*)))
  (let* ((port (lem-socket-utils:random-available-port))
         (process (run-lisp :command command :directory directory :port port)))
    (send-swank-create-server process port)
    (start-lisp-repl)
    (let ((spinner
            (start-loading-spinner :modeline
                                   :buffer (repl-buffer)
                                   :loading-message "Slime is starting up")))
      (let (timer
            (retry-count 0))
        (labels ((interval ()
                   (handler-case
                       (let ((conn (%slime-connect *localhost* port)))
                         (setf (connection-command conn) command)
                         (setf (connection-process conn) process)
                         (setf (connection-process-directory conn) directory)
                         conn)
                     (editor-error (c)
                       (cond ((or (not (lem-process:process-alive-p process))
                                  (< 30 retry-count))
                              (failure c))
                             (t
                              (incf retry-count))))
                     (:no-error (conn)
                       (connected-slime-message conn)
                       ;; replのプロンプトの表示とカーソル位置の変更をしたいが
                       ;; 他のファイルの作業中にバッファ/ウィンドウが切り替わると作業の邪魔なので
                       ;; with-current-windowで元に戻す
                       (unless (repl-buffer)
                         (with-current-window (current-window) (start-lisp-repl)))
                       (success))))
                 (success ()
                   (finalize)
                   #-win32
                   (add-hook *exit-editor-hook* 'slime-quit-all))
                 (failure (c)
                   (finalize)
                   (pop-up-typeout-window (make-lisp-process-buffer port)
                                          nil)
                   (error c))
                 (finalize ()
                   (stop-timer timer)
                   (stop-loading-spinner spinner)))
          (setf timer (start-timer 500 t #'interval)))))))

(define-command slime (&optional ask-impl) ("P")
  (let ((command (if ask-impl (prompt-for-impl))))
    (run-slime command)))

(defun delete-lisp-connection (connection)
  (prog1 (when (connection-process connection)
           (alexandria:when-let (buffer (get-lisp-process-buffer (connection-port connection)))
             (kill-buffer buffer))
           (lem-process:delete-process (connection-process connection))
           t)
    (remove-connection connection)))

(define-command slime-quit () ()
  (when (self-connection-p *connection*)
    (editor-error "The current connection is myself"))
  (when *connection*
    (delete-lisp-connection *connection*)))

(defun slime-quit* ()
  (ignore-errors (slime-quit)))

(defun slime-quit-all ()
  (flet ((find-connection ()
           (dolist (c *connection-list*)
             (when (connection-process c)
               (return c)))))
    (loop
      (let ((*connection* (find-connection)))
        (unless *connection* (return))
        (delete-lisp-connection *connection*)))))

(defun sit-for* (second)
  (loop :with end-time := (+ (get-internal-real-time)
                             (* second internal-time-units-per-second))
        :for e := (read-event (float
                               (/ (- end-time (get-internal-real-time))
                                  internal-time-units-per-second)))
        :while (key-p e)))

(define-command slime-restart () ()
  (when *connection*
    (alexandria:when-let ((last-command (connection-command *connection*))
                          (directory (connection-process-directory *connection*)))
      (when (slime-quit)
        (sit-for* 3)
        (run-slime last-command :directory directory)))))

(define-command slime-self-connect (&optional (start-repl t)) ()
  (unless (self-connected-p)
    (self-connect))
  (when start-repl (start-lisp-repl)))


(defun scan-current-package (point)
  (with-point ((p point))
    (loop
      (ppcre:register-groups-bind (package-name)
          ("^\\s*\\(\\s*(?:cl:)?in-package (?:#?:|')?([^\)\\s]*)\\s*\\)"
           (string-downcase (line-string p)))
        (return package-name))
      (unless (line-offset p -1)
        (return)))))

(defun update-buffer-package ()
  (let ((package (scan-current-package (current-point))))
    (when package
      (lisp-set-package package))))

(defun lisp-idle-function ()
  (when (connected-p)
    (let ((major-mode (buffer-major-mode (current-buffer))))
      (when (eq major-mode 'lisp-mode)
        (update-buffer-package)))))

(define-command lisp-scratch () ()
  (let ((buffer (primordial-buffer)))
    (change-buffer-mode buffer 'lisp-mode)
    (switch-to-buffer buffer)))

(defun highlight-region (start end attribute name)
  (let ((overlay (make-overlay start end attribute)))
    (start-timer 100
                 nil
                 (lambda ()
                   (delete-overlay overlay))
                 (lambda (err)
                   (declare (ignore err))
                   (ignore-errors
                    (delete-overlay overlay)))
                 name)))

(defun highlight-compilation-region (start end)
  (highlight-region start
                    end
                    'compilation-region-highlight
                    "delete-compilation-region-overlay"))

(defun highlight-evaluation-region (start end)
  (highlight-region start
                    end
                    'evaluation-region-highlight
                    "delete-evaluation-region-overlay"))

(add-hook (variable-value 'before-compile-functions :global)
          'highlight-compilation-region)

(add-hook (variable-value 'before-eval-functions :global)
          'highlight-evaluation-region)

;; workaround for windows
#+win32
(progn
  (defun slime-quit-all-for-win32 ()
    "quit slime and remove connection to exit lem normally on windows (incomplete)"
    (let ((conn-list (copy-list *connection-list*)))
      (slime-quit-all)
      (loop :while *connection*
            :do (remove-connection *connection*))
      #+sbcl
      (progn
        (sleep 0.5)
        (dolist (c conn-list)
          (let* ((s  (lem-lisp-mode.swank-protocol::connection-socket c))
                 (fd (sb-bsd-sockets::socket-file-descriptor (usocket:socket s))))
            (ignore-errors
              ;;(usocket:socket-shutdown s :IO)
              ;;(usocket:socket-close s)
              (sockint::shutdown fd sockint::SHUT_RDWR)
              (sockint::close fd)))))))
  (add-hook *exit-editor-hook* 'slime-quit-all-for-win32))

(define-file-type ("lisp" "asd" "cl" "lsp" "ros") lisp-mode)
