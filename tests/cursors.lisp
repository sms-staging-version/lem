(defpackage :lem-tests/cursors
  (:use :cl
        :testif
        :lem-tests/utilities)
  (:import-from :lem/common/killring
                :make-killring
                :push-killring-item
                :peek-killring-item))
(in-package :lem-tests/cursors)

(defun make-testing-killring ()
  (let ((killring (lem/common/killring:make-killring 10)))
    (push-killring-item killring "aaa")
    (push-killring-item killring "bbb")
    (push-killring-item killring "ccc")
    killring))

(test simple-fake-cursor-test
  (with-testing-buffer (buffer (lem:make-buffer "cursor test"))
    (let* ((lem::*killring* (make-testing-killring))
           (cursor (lem::make-fake-cursor (lem:current-point))))
      (test "Test the fake-cursor created"
        (test "buffer-fake-cursors"
          (ok (alexandria:length= 1 (lem::buffer-fake-cursors buffer)))
          (ok (eq cursor (first (lem::buffer-fake-cursors buffer)))))
        (test "killring"
          (let ((killring (lem::fake-cursor-killring cursor)))
            (ok (not (eq (lem::current-killring) killring)))
            (ok (equal "aaa" (peek-killring-item killring 2)))
            (ok (equal "bbb" (peek-killring-item killring 1)))
            (ok (equal "ccc" (peek-killring-item killring 0)))))
        (test "point-kind"
          (ok (eq :left-inserting (lem:point-kind cursor)))))
      (test "Delete cursor"
        (lem::delete-fake-cursor cursor)
        (ok (null (lem::buffer-fake-cursors buffer)))))))

(defun make-testing-fake-cursors (point n)
  (lem:with-point ((p point))
    (loop :repeat n
          :do (assert (not (null (lem:line-offset p 1))))
              (lem::make-fake-cursor p))))

(test "Test to execute a series of commands"
  (lem-fake-interface:with-fake-interface ()
    (let ((lem::*killring* (lem/common/killring:make-killring 10)))
      (with-testing-buffer (buffer (make-text-buffer (lines "abcdefg" "hijklmn" "opqrstu")))
        (make-testing-fake-cursors (lem:buffer-point buffer) 2)
        (test "execute self-insert command"
          (lem:execute-key-sequence (list (lem:make-key :sym " ")))
          (ok (string= (lines " abcdefg" " hijklmn" " opqrstu")
                       (lem:buffer-text buffer))))
        (test "execute delete-previous-character command"
          (lem:execute-key-sequence (list (lem:make-key :ctrl t :sym "h")))
          (lem:buffer-text buffer)
          (ok (string= (lines "abcdefg" "hijklmn" "opqrstu")
                       (lem:buffer-text buffer))))
        (test "multiple cursor killring"
          (lem:execute (lem:buffer-major-mode buffer)
                       (make-instance 'lem::delete-next-char-with-multiple-cursors)
                       4)
          (ok (equal '("abcd"
                       "opqr"
                       "hijk")
                     (mapcar (lambda (killring)
                               (peek-killring-item killring 0))
                             (cons lem::*killring*
                                   (mapcar (lambda (cursor)
                                             (lem::fake-cursor-killring cursor))
                                           (lem::buffer-fake-cursors buffer)))))))))))

(defun linum-and-column (point)
  (list (lem:line-number-at-point point)
        (lem:point-column point)))

(defun all-positions (buffer)
  (mapcar #'linum-and-column (lem::buffer-cursors buffer)))

(defun positions-set-equal (positions1 positions2)
  (alexandria:set-equal positions1 positions2 :test #'equal))

(test "next-line/previous-line"
  (lem-fake-interface:with-fake-interface ()
    (lem::save-continue-flags
      (with-testing-buffer (buffer (make-text-buffer (lines "abcdefghijklmn"
                                                            "opqrstuvwxyz"
                                                            "0123456789"
                                                            "------------------")))
        (lem::set-window-buffer buffer (lem:current-window))
        (make-testing-fake-cursors (lem:buffer-point buffer) 2)
        (lem:execute (lem:buffer-major-mode buffer)
                     (make-instance 'lem:move-to-end-of-line)
                     nil)

        (lem:execute (lem:buffer-major-mode buffer)
                     (make-instance 'lem:next-line)
                     nil)
        (ok (positions-set-equal '((2 12) (3 10) (4 10))
                                 (all-positions buffer)))

        (lem:execute (lem:buffer-major-mode buffer)
                     (make-instance 'lem:previous-line)
                     nil)
        (ok (positions-set-equal '((1 14) (2 12) (3 10))
                                 (all-positions buffer)))

        (lem:execute (lem:buffer-major-mode buffer)
                     (make-instance 'lem:next-line)
                     nil)
        (ok (positions-set-equal '((2 12) (3 10) (4 10))
                                 (all-positions buffer)))))))
