;;; test-multi-pane.lisp — Multi-pane test for charmed McCLIM backend
;;; Tests that multiple panes render in correct screen regions.

(defpackage #:clim-charmed-test-mp
  (:use #:clim #:clim-lisp)
  (:export #:run))

(in-package #:clim-charmed-test-mp)

(defun display-top (frame pane)
  (declare (ignore frame))
  (format pane "  TOP PANE: Hello from McCLIM charmed terminal!~%")
  (format pane "  This pane should appear in the upper half.~%")
  (format pane "  Press Ctrl-Q to exit.~%"))

(defun display-bottom (frame pane)
  (declare (ignore frame))
  (format pane "  BOTTOM PANE: Status area~%")
  (format pane "  This pane should appear in the lower half.~%"))

(define-application-frame multi-pane-test ()
  ()
  (:panes
   (top-pane :application
             :display-function 'display-top
             :scroll-bars nil)
   (bottom-pane :application
                :display-function 'display-bottom
                :scroll-bars nil))
  (:layouts
   (default
    (vertically ()
      (3/4 top-pane)
      (1/4 bottom-pane))))
  (:top-level (clim-charmed:charmed-frame-top-level)))

(defun run ()
  (let* ((port (make-instance 'clim-charmed::charmed-port
                              :server-path '(:charmed)))
         (fm (first (slot-value port 'climi::frame-managers))))
    (unwind-protect
         (let ((frame (make-application-frame 'multi-pane-test
                                              :frame-manager fm)))
           (run-frame-top-level frame))
      (climi::destroy-port port))))
