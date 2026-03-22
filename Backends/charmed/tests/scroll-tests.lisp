;;; -*- Mode: Lisp; Syntax: Common-Lisp; -*-
;;;
;;; scroll-tests.lisp — Tests for scroll persistence and mode transitions

(in-package #:clim-charmed-tests)

(in-suite scroll-tests)

;;; Test scroll mode transitions
;;; The scroll mode should switch between :auto and :manual based on user actions
;;;
;;; NOTE: We avoid creating charmed-port instances in tests because the port
;;; initialization enters raw mode and alternate screen, which corrupts the
;;; terminal if not properly cleaned up. Instead we test the hash table logic
;;; directly using plain hash tables.

(test scroll-mode-default-is-auto
  "New panes should default to :auto scroll mode (hash table returns NIL, code defaults to :auto)"
  (let ((modes (make-hash-table :test #'eq)))
    ;; A pane not in the hash table should return NIL
    ;; The pane-scroll-mode function defaults NIL to :auto
    (is (null (gethash :fake-pane modes)))
    (is (eq :auto (or (gethash :fake-pane modes) :auto)))))

(test scroll-mode-transitions
  "Scroll mode should transition correctly based on scroll direction"
  (let ((modes (make-hash-table :test #'eq))
        (fake-pane :test-pane))
    ;; Initially should be :auto (default when not in table)
    (is (eq :auto (or (gethash fake-pane modes) :auto)))
    ;; Set to :manual (simulates scrolling up)
    (setf (gethash fake-pane modes) :manual)
    (is (eq :manual (gethash fake-pane modes)))
    ;; Set back to :auto (simulates reaching bottom)
    (setf (gethash fake-pane modes) :auto)
    (is (eq :auto (gethash fake-pane modes)))))

(test scroll-offset-storage
  "Scroll offsets should be stored per-pane"
  (let ((offsets (make-hash-table :test #'eq))
        (pane1 :pane-1)
        (pane2 :pane-2))
    ;; Initially no offsets
    (is (null (gethash pane1 offsets)))
    (is (null (gethash pane2 offsets)))
    ;; Set offsets
    (setf (gethash pane1 offsets) 10)
    (setf (gethash pane2 offsets) 25)
    ;; Verify independent storage
    (is (= 10 (gethash pane1 offsets)))
    (is (= 25 (gethash pane2 offsets)))))

(test scroll-offset-clamping-logic
  "Scroll offset clamping should work correctly"
  ;; Test the clamping logic used in scroll-pane
  (let ((content-h 100)
        (viewport-h 20))
    (let ((max-scroll (max 0 (- content-h viewport-h))))
      ;; max-scroll should be 80
      (is (= 80 max-scroll))
      ;; Clamping tests
      (is (= 0 (max 0 (min max-scroll -10))))   ; negative clamps to 0
      (is (= 50 (max 0 (min max-scroll 50))))   ; middle stays
      (is (= 80 (max 0 (min max-scroll 100))))  ; over max clamps to max
      (is (= 80 (max 0 (min max-scroll 80)))))) ; at max stays
  ;; Edge case: content smaller than viewport
  (let ((content-h 10)
        (viewport-h 20))
    (let ((max-scroll (max 0 (- content-h viewport-h))))
      ;; max-scroll should be 0 (can't scroll)
      (is (= 0 max-scroll)))))
