(in-package :lem)

(defvar *inactive-window-background-color* nil)

(defun overlay-attributes (under-attributes over-start over-end over-attribute)
  ;; under-attributes := ((start-charpos end-charpos attribute) ...)
  (let* ((over-attribute (ensure-attribute over-attribute))
         (under-part-attributes (lem-base::subseq-elements under-attributes
                                                           over-start
                                                           over-end))
         (merged-attributes (lem-base::remove-elements under-attributes
                                                       over-start
                                                       over-end)))
    (flet ((add-element (start end attribute)
             (when (< start end)
               (push (list start end (ensure-attribute attribute))
                     merged-attributes))))
      (if (null under-part-attributes)
          (add-element over-start over-end over-attribute)
          (loop :for prev-under := 0 :then under-end-offset
                :for (under-start-offset under-end-offset under-attribute)
                :in under-part-attributes
                :do (add-element (+ over-start prev-under)
                                 (+ over-start under-start-offset)
                                 over-attribute)
                    (add-element (+ over-start under-start-offset)
                                 (+ over-start under-end-offset)
                                 (alexandria:if-let (under-attribute
                                                     (ensure-attribute under-attribute nil))
                                   (merge-attribute under-attribute
                                                    over-attribute)
                                   over-attribute))
                :finally (add-element (+ over-start under-end-offset)
                                      over-end
                                      over-attribute))))
    (lem-base::normalization-elements merged-attributes)))

(defun draw-attribute-to-screen-line (screen attribute screen-row start-charpos end-charpos
                                      &key (transparency t))
  ;; transparencyがTのとき、オーバーレイがその下のテキストの属性を消さずに
  ;; 下のattributeを上のattributeとマージします。(透過する)
  ;; NILのとき、オーバーレイの下のテキスト属性はオーバーレイの色で置き換えられます。
  ;;
  ;; 常に透過せず真偽値で切り替えているのはカーソルもオーバーレイとして扱うため、マージすると
  ;; シンボルのcursorという値でattributeを保持できなくなってしまいeqで判別できなくなるためです。
  ;; cursorというシンボルのattributeには特別な意味があり、画面描画フェーズでカーソルに
  ;; 対応する箇所を表示するときcursorとeqならその(x, y)座標にカーソルがあることがわかります。
  ;; たとえばncursesでは、カーソル位置を物理的なカーソルにセットするためにCのwmove関数を呼びます。
  (when (and (<= 0 screen-row)
             (< screen-row (screen-height screen))
             (not (null (aref (screen-lines screen) screen-row)))
             (or (null end-charpos)
                 (< start-charpos end-charpos)))
    (destructuring-bind (string . attributes)
        (aref (screen-lines screen) screen-row)
      (when (and end-charpos (<= (length string) end-charpos))
        (setf (car (aref (screen-lines screen) screen-row))
              (concatenate 'string
                           string
                           (make-string (- end-charpos (length string))
                                        :initial-element #\space))))
      (setf (cdr (aref (screen-lines screen) screen-row))
            (if transparency
                (overlay-attributes attributes
                                    start-charpos
                                    (or end-charpos (length string))
                                    attribute)
                (lem-base::put-elements attributes
                                        start-charpos
                                        (or end-charpos (length string))
                                        attribute))))))

(defun draw-attribute-to-screen-region (screen attribute screen-row start end)
  (flet ((draw-line (row start-charpos &optional end-charpos)
           (draw-attribute-to-screen-line screen attribute row start-charpos end-charpos)))
    (with-point ((point start))
      (loop :for start-charpos := (point-charpos start) :then 0
            :for row :from screen-row
            :do (cond ((same-line-p point end)
                       (draw-line row start-charpos (point-charpos end))
                       (return))
                      (t
                       (draw-line row start-charpos)))
            :while (line-offset point 1)))))

(defun make-temporary-region-overlay-from-cursor (cursor)
  (let ((mark (cursor-mark cursor)))
    (when (mark-active-p mark)
      (make-temporary-overlay cursor (mark-point mark) 'region))))

(defun get-window-overlays (window)
  (let* ((buffer (window-buffer window))
         (overlays (overlays buffer)))
    (when (eq (current-window) window)
      (dolist (cursor (buffer-cursors buffer))
        (if-push (make-temporary-region-overlay-from-cursor cursor)
                 overlays)))
    overlays))

(defun draw-window-overlays-to-screen (window)
  (let ((screen (window-screen window))
        (view-point (window-view-point window)))
    (flet ((calc-row (curr-point) (count-lines view-point curr-point)))
      (let ((left-width 0)
            (view-end-point (with-point ((view-point view-point))
                              (or (line-offset view-point (screen-height screen))
                                  (buffer-end view-point)))))
        (loop :for overlay :in (get-window-overlays window)
              :for start := (overlay-start overlay)
              :for end := (overlay-end overlay)
              :do (cond
                    ((overlay-get overlay :display-left)
                     (when (and (point<= view-point start)
                                (point<= end view-end-point))
                       (let ((i (calc-row start)))
                         (when (< i (screen-height screen))
                           (let ((str (overlay-get overlay :text)))
                             (setf left-width (max left-width (length str)))
                             (setf (aref (screen-left-lines screen) i)
                                   (cons str (overlay-attribute overlay))))))))
                    ((and (same-line-p start end)
                          (point<= view-point start)
                          (point< start view-end-point))
                     (draw-attribute-to-screen-line screen
                                                    (overlay-attribute overlay)
                                                    (calc-row start)
                                                    (point-charpos start)
                                                    (point-charpos end)))
                    ((and (point<= view-point start)
                          (point< end view-end-point))
                     (draw-attribute-to-screen-region screen
                                                      (overlay-attribute overlay)
                                                      (calc-row start)
                                                      start
                                                      end))
                    ((and (point<= start view-point)
                          (point<= view-point end)
                          (point<= end view-end-point))
                     (draw-attribute-to-screen-region screen
                                                      (overlay-attribute overlay)
                                                      0
                                                      view-point
                                                      end))
                    ((point<= view-point start)
                     (draw-attribute-to-screen-region screen
                                                      (overlay-attribute overlay)
                                                      (calc-row start)
                                                      start
                                                      view-end-point))))
        (setf (screen-left-width screen) left-width)))))

(defun draw-point-to-screen (screen view-point cursor-point attribute)
  (let ((charpos (point-charpos cursor-point)))
    (draw-attribute-to-screen-line screen
                                   attribute
                                   (count-lines view-point cursor-point)
                                   charpos
                                   (1+ charpos)
                                   :transparency nil)))

(defun draw-cursor-to-screen (window)
  (when (eq (current-window) window)
    (let ((buffer (window-buffer window)))
      (dolist (point (buffer-fake-cursors buffer))
        (draw-point-to-screen (window-screen window)
                              (window-view-point window)
                              point
                              'fake-cursor))
      (draw-point-to-screen (window-screen window)
                            (window-view-point window)
                            (buffer-point buffer)
                            'cursor))))

(defun reset-screen-lines (screen view-point)
  (with-point ((point view-point))
    (loop :for row :from 0 :below (screen-height screen)
          :do (let* ((line (lem-base::point-line point))
                     (str/attributes (lem-base::line-string/attributes line)))
                (setf (aref (screen-lines screen) row) str/attributes))
              (unless (line-offset point 1)
                (fill (screen-lines screen) nil :start (1+ row))
                (return)))))

(defun reset-screen-left-lines (screen)
  (fill (screen-left-lines screen) nil))

(defun reset-screen-lines-and-left-lines (window)
  (reset-screen-lines (window-screen window)
                      (window-view-point window))
  (reset-screen-left-lines (window-screen window)))

(defun draw-window-to-screen (window)
  (reset-screen-lines-and-left-lines window)
  (draw-window-overlays-to-screen window)
  (draw-cursor-to-screen window))


(defvar *printing-tab-size*)

(defun screen-margin-left (screen)
  (screen-left-width screen))

(defun screen-print-string (screen x y string attribute)
  (when (and (eq attribute 'cursor) (< 0 (length string)))
    (setf (screen-last-print-cursor-x screen) x
          (screen-last-print-cursor-y screen) y))
  (let ((view (screen-view screen))
        (x0 x)
        (i -1)
        (pool-string (make-string (screen-width screen) :initial-element #\space)))
    (loop :for char :across string
          :do (cond
                ((char= char #\tab)
                 (loop :with size :=
                          (+ (screen-margin-left screen)
                             (* *printing-tab-size*
                                (floor (+ *printing-tab-size* x) *printing-tab-size*)))
                       :while (< x size)
                       :do (setf (aref pool-string (incf i)) #\space)
                           (incf x)))
                ((alexandria:when-let ((control-char (control-char char)))
                   (loop :for c :across control-char
                         :do (setf (aref pool-string (incf i)) c
                                   x (char-width c x)))
                   t))
                (t
                 (setf (aref pool-string (incf i)) char)
                 (setf x (char-width char x)))))
    (unless (= i -1)
      (lem-if:print (implementation) view x0 y
                    (subseq pool-string 0 (1+ i))
                    attribute))
    x))

(defvar *redraw-start-y*)
(defvar *redraw-end-y*)

(defun redraw-line-p (y)
  (or (not *redraw-start-y*)
      (<= *redraw-start-y* y *redraw-end-y*)))

(defun disp-print-line (screen y str/attributes do-clrtoeol
                        &key (start-x 0) (string-start 0) string-end)
  (unless (redraw-line-p y)
    (return-from disp-print-line nil))
  (destructuring-bind (str . attributes)
      str/attributes
    (when (null string-end)
      (setf string-end (length str)))
    (unless (and (= 0 string-start)
                 (= (length str) string-end))
      (setf str (subseq str
                        string-start
                        (if (null string-end)
                            nil
                            (min (length str) string-end))))
      (setf attributes (lem-base::subseq-elements attributes string-start string-end)))
    (let ((prev-end 0)
          (x start-x))
      (loop :for (start end attr) :in attributes
            :do (setf end (min (length str) end))
                (setf x (screen-print-string screen x y (subseq str prev-end start) nil))
                (setf x (screen-print-string screen x y (subseq str start end) attr))
                (setf prev-end end))
      (setf x (screen-print-string screen x y
                                   (if (= prev-end 0)
                                       str
                                       (subseq str prev-end))
                                   nil))
      (when do-clrtoeol
        (lem-if:clear-eol (implementation) (screen-view screen) x y)))))

(define-editor-variable truncate-character #\\)
(defvar *truncate-character*)

(defun screen-display-line-wrapping (screen screen-width view-charpos cursor-y point-y
                                     str/attributes)
  (declare (ignore cursor-y))
  (when (and (< 0 view-charpos) (= point-y 0))
    (setf str/attributes
          (cons (subseq (car str/attributes) view-charpos)
                (lem-base::subseq-elements (cdr str/attributes)
                                           view-charpos
                                           (length (car str/attributes))))))
  (let ((start 0)
        (start-x (screen-left-width screen))
        (truncate-str/attributes
          (cons (string *truncate-character*)
                (list (list 0 1 'lem:truncate-attribute)))))
    (loop :for i := (wide-index (car str/attributes)
                                (1- screen-width)
                                :start start)
          :while (< point-y (screen-height screen))
          :do (cond ((null i)
                     (disp-print-line screen point-y str/attributes t
                                      :string-start start :start-x start-x)
                     (return))
                    (t
                     (disp-print-line screen point-y str/attributes t
                                      :string-start start :string-end i
                                      :start-x start-x)
                     (disp-print-line screen point-y
                                      truncate-str/attributes
                                      t
                                      :start-x (+ start-x (1- screen-width)))
                     (incf point-y)
                     (setf start i))))
    point-y))

(defun screen-display-line (screen screen-width view-charpos cursor-y point-y str/attributes)
  (declare (ignore view-charpos))
  (let ((start-x (screen-left-width screen))
        start
        end)
    (cond ((= cursor-y point-y)
           (setf start (or (wide-index (car str/attributes)
                                       (screen-horizontal-scroll-start screen))
                           0))
           (setf end (wide-index (car str/attributes)
                                 (+ (screen-horizontal-scroll-start screen)
                                    screen-width))))
          (t
           (setf start 0)
           (setf end (wide-index (car str/attributes) screen-width))))
    (when (redraw-line-p point-y)
      (lem-if:clear-eol (implementation) (screen-view screen) start-x point-y))
    (disp-print-line screen point-y str/attributes nil
                     :start-x start-x
                     :string-start start
                     :string-end end))
  point-y)

(defun screen-display-lines (screen redraw-flag buffer view-charpos cursor-y)
  (let* ((*printing-tab-size* (variable-value 'tab-width :default buffer))
         (line-wrap (variable-value 'line-wrap :default buffer))
         (disp-line-function
           (if line-wrap
               #'screen-display-line-wrapping
               #'screen-display-line))
         (wrap-lines (screen-wrap-lines screen))
         (screen-width (- (screen-width screen)
                          (screen-left-width screen))))
    (setf (screen-wrap-lines screen) nil)
    (loop :for y :from 0
          :for i :from 0
          :for str/attributes :across (screen-lines screen)
          :for left-str/attr :across (screen-left-lines screen)
          :while (< y (screen-height screen))
          :do (cond
                ((and (null left-str/attr)
                      (not redraw-flag)
                      (not (null str/attributes))
                      #1=(aref (screen-old-lines screen) i)
                      (equal str/attributes #1#)
                      #+(or)(/= cursor-y i))
                 (let ((n (count i wrap-lines)))
                   (incf y n)
                   (dotimes (_ n)
                     (push i (screen-wrap-lines screen)))))
                (str/attributes
                 (setf (aref (screen-old-lines screen) i) str/attributes)
                 (when (zerop (length (car str/attributes)))
                   (lem-if:clear-eol (implementation) (screen-view screen) 0 y))
                 (let (y2)
                   (when left-str/attr
                     (screen-print-string screen
                                          0
                                          y
                                          (car left-str/attr)
                                          (cdr left-str/attr)))
                   (setq y2
                         (funcall disp-line-function
                                  screen
                                  screen-width
                                  view-charpos
                                  cursor-y
                                  y
                                  str/attributes))
                   (cond
                     (line-wrap
                      (let ((offset (- y2 y)))
                        (cond ((< 0 offset)
                               (setf redraw-flag t)
                               (dotimes (_ offset)
                                 (push i (screen-wrap-lines screen))))
                              ((and (= offset 0) (find i wrap-lines))
                               (setf redraw-flag t))))
                      (setf y y2))
                     (t
                      (setf (aref (screen-lines screen) i) nil)))))
                (t
                 (fill (screen-old-lines screen) nil :start i)
                 (lem-if:clear-eob (implementation) (screen-view screen) 0 y)
                 (return))))))

(defun screen-redraw-modeline (window force)
  (let* ((screen (window-screen window))
         (view (screen-view screen))
         (default-attribute (if (eq window (current-window))
                                'modeline
                                'modeline-inactive))
         (elements '())
         (left-x 0)
         (right-x (window-width window)))
    (modeline-apply window
                    (lambda (string attribute alignment)
                      (case alignment
                        ((:right)
                         (decf right-x (length string))
                         (push (list right-x string attribute) elements))
                        (otherwise
                         (push (list left-x string attribute) elements)
                         (incf left-x (length string)))))
                    default-attribute)
    (setf elements (nreverse elements))
    (when (or force (not (equal elements (screen-modeline-elements screen))))
      (setf (screen-modeline-elements screen) elements)
      (lem-if:print-modeline (implementation) view 0 0
                             (make-string (window-width window) :initial-element #\space)
                             default-attribute)
      (loop :for (x string attribute) :in elements
            :do (lem-if:print-modeline (implementation) view x 0 string attribute)))))

(defun adjust-horizontal-scroll (window)
  (let ((screen (window-screen window))
        (buffer (window-buffer window)))
    (unless (variable-value 'line-wrap :default buffer)
      (let ((point-column (point-column (buffer-point buffer)))
            (width (- (screen-width screen) (screen-left-width screen))))
        (cond ((<= (+ (screen-horizontal-scroll-start screen) width)
                   (1+ point-column))
               (setf (screen-horizontal-scroll-start screen)
                     (- (1+ point-column) width)))
              ((< point-column (screen-horizontal-scroll-start screen))
               (setf (screen-horizontal-scroll-start screen) point-column)))))))

(defun redraw-display-window (window force)
  (let ((lem-if:*background-color-of-drawing-window*
          (cond ((typep window 'floating-window)
                 (floating-window-background-color window))
                ((and *inactive-window-background-color*
                      (not (eq window (current-window)))
                      (eq 'window (type-of window)))
                 *inactive-window-background-color*)
                (t nil)))
        (focus-window-p (eq window (current-window)))
        (buffer (window-buffer window))
        (screen (window-screen window)))
    (let ((scroll-n (when focus-window-p
                      (window-see window))))
      (when (or (not (native-scroll-support (implementation)))
                (not (equal (screen-last-buffer-name screen) (buffer-name buffer)))
                (not (eql (screen-last-buffer-modified-tick screen)
                          (buffer-modified-tick buffer)))
                (and scroll-n (>= scroll-n (screen-height screen))))
        (setf scroll-n nil))
      (when scroll-n
        (lem-if:scroll (implementation) (screen-view screen) scroll-n))
      (multiple-value-bind (*redraw-start-y* *redraw-end-y*)
          (when scroll-n
            (if (plusp scroll-n)
                (values (- (screen-height screen) scroll-n) (screen-height screen))
                (values 0 (- scroll-n))))
        (run-show-buffer-hooks window)
        (draw-window-to-screen window)
        (adjust-horizontal-scroll window)
        (let ((*truncate-character*
                (variable-value 'truncate-character :default buffer)))
          (screen-display-lines screen
                                (or force
                                    (screen-modified-p screen)
                                    (not (eql (screen-left-width screen)
                                              (screen-old-left-width screen))))
                                buffer
                                (point-charpos (window-view-point window))
                                (if focus-window-p
                                    (count-lines (window-view-point window)
                                                 (window-point window))
                                    -1)))
        (setf (screen-old-left-width screen)
              (screen-left-width screen))
        (setf (screen-last-buffer-name screen)
              (buffer-name buffer))
        (setf (screen-last-buffer-modified-tick screen)
              (buffer-modified-tick buffer))
        (when (window-use-modeline-p window)
          (screen-redraw-modeline window (or (screen-modified-p screen) force)))
        (lem-if:redraw-view-after (implementation) (screen-view screen))
        (setf (screen-modified-p screen) nil)))))
