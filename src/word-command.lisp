(in-package :lem)

(defun word-type (char)
  (when (characterp char)
    (cond ((char<= (code-char 12354) ;#\HIRAGANA_LETTER_A
                   char
                   (code-char 12435) ;#\HIRAGANA_LETTER_N
                   )
           :hiragana)
          ((char<= (code-char 12450) ;#\KATAKANA_LETTER_A
                   char
                   (code-char 12531) ;#\KATAKANA_LETTER_N
                   )
           :katakana)
          ((or (<= #x4E00
                   (char-code char)
                   #x9FFF)
               (find char "仝々〆〇ヶ"))
           :kanji)
          ((alphanumericp char)
           :alphanumeric))))

(defun word-offset (point n)
  (multiple-value-bind (skip-chars-forward
                        char-offset
                        end-buffer-p)
      (if (plusp n)
          (values #'skip-chars-forward
                  0
                  #'end-buffer-p)
          (values #'skip-chars-backward
                  -1
                  #'start-buffer-p))
    (loop :repeat (abs n)
          :do (funcall skip-chars-forward point (complement #'word-type))
              (when (funcall end-buffer-p point)
                (return))
              (let ((type (word-type (character-at point char-offset))))
                (if (null type)
                    (return nil)
                    (funcall skip-chars-forward
                             point
                             (lambda (c) (eql type (word-type c))))))
          :finally (return point))))

(define-command (forward-word (:advice-classes movable-advice)) (n) ("p")
  (word-offset (current-point) n))

(define-command (previous-word (:advice-classes movable-advice)) (n) ("p")
  (word-offset (current-point) (- n)))

(define-command delete-word (n) ("p")
  (do-each-cursors ()
    (with-point ((point (current-point) :right-inserting))
      (let ((start (current-point))
            (end (or (word-offset point n)
                     (if (plusp n)
                         (buffer-end point)
                         (buffer-start point)))))
        (cond ((point= start end))
              ((point< start end)
               (kill-region start end))
              (t
               (kill-region end start)))))))

(define-command backward-delete-word (n) ("p")
  (with-killring-context (:before-inserting t)
    (delete-word (- n))))

(defun case-region-aux (start end case-fun replace-char-p)
  (save-excursion
    (with-point ((point start :left-inserting))
      (loop :while (and (point< point end)
                        (not (end-buffer-p point)))
            :do (let ((c (character-at point 0)))
                  (cond ((char= c #\newline)
                         (character-offset point 1))
                        ((funcall replace-char-p c)
                         (delete-character point)
                         (insert-character point (funcall case-fun c)))
                        (t
                         (character-offset point 1))))))))

(define-command downcase-region (start end) ("r")
  (do-each-cursors ()
    (case-region-aux start end #'char-downcase #'identity)))

(define-command uppercase-region (start end) ("r")
  (do-each-cursors ()
    (case-region-aux start end #'char-upcase #'identity)))

(defun case-word-aux (point n replace-char-p first-case rest-case)
  (dotimes (_ n)
    (skip-chars-forward point (complement #'word-type))
    (when (end-buffer-p point)
      (return))
    (let ((c (character-at point)))
      (delete-character point)
      (insert-character point (funcall first-case c))
      (with-point ((end (or (word-offset (copy-point point :temporary) 1)
                            (buffer-end point))
                        :left-inserting))
        (case-region-aux point
                         end
                         rest-case
                         replace-char-p)
        (move-point point end)))))

(define-command (capitalize-word (:advice-classes movable-advice)) (&optional (n 1)) ("p")
  (case-word-aux (current-point) n #'alphanumericp #'char-upcase #'char-downcase))

(define-command (lowercase-word (:advice-classes movable-advice)) (&optional (n 1)) ("p")
  (case-word-aux (current-point) n #'alphanumericp #'char-downcase #'char-downcase))

(define-command (uppercase-word (:advice-classes movable-advice)) (&optional (n 1)) ("p")
  (case-word-aux (current-point) n #'alphanumericp #'char-upcase #'char-upcase))

(define-command (forward-paragraph (:advice-classes movable-advice)) (&optional (n 1)) ("p")
  (let ((point (current-point))
        (dir (if (plusp n) 1 -1)))
    (dotimes (_ (abs n))
      (loop :while (blank-line-p point)
            :do (unless (line-offset point dir)
                  (return-from forward-paragraph)))
      (loop :until (blank-line-p point)
            :do (unless (line-offset point dir)
                  (when (plusp dir) (buffer-end point))
                  (return-from forward-paragraph))))))

(define-command (backward-paragraph (:advice-classes movable-advice)) (&optional (n 1)) ("p")
  (forward-paragraph (- n)))

(define-command kill-paragraph (&optional (n 1)) ("p")
  (do-each-cursors ()
    (dotimes (_ n t)
      (with-point ((start (current-point) :right-inserting))
        (forward-paragraph)
        (kill-region start
                     (current-point))))))

(defun %count-words (start end)
  (save-excursion
    (let ((wnum 0))
      (loop :for point := (copy-point start :temporary) :then (word-offset point 1)
            :while (and point (point< point end))
            :do (incf wnum))
      wnum)))

(define-command count-words () ()
  (let ((buffer (current-buffer)))
    (multiple-value-bind (start end)
        (if (buffer-mark-p buffer)
            (values (region-beginning buffer)
                    (region-end buffer))
            (values (buffer-start-point buffer)
                    (buffer-end-point buffer)))
      (let ((chnum (count-characters start end))
            (wnum (%count-words start end))
            (linum (count-lines start end)))
        (show-message (format nil "~a has ~d lines, ~d words and ~d characters."
                              (if (buffer-mark-p buffer)
                                  "Region"
                                  "Buffer")
                              linum wnum chnum))))))
