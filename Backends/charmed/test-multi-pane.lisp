;;; test-multi-pane.lisp — Multi-pane test for charmed McCLIM backend
;;; Tests that multiple panes render in correct screen regions
;;; and that per-pane repaint works (bottom pane updates on keypress).

(defpackage #:clim-charmed-test-mp
  (:use #:clim #:clim-lisp)
  (:export #:run))

(in-package #:clim-charmed-test-mp)

(defun display-top (frame pane)
  (declare (ignore frame))
  (format pane "  TOP PANE: Hello from McCLIM charmed terminal!~%")
  (format pane "  This pane should appear in the upper half.~%")
  (format pane "  Press any key to increment counter in bottom pane.~%")
  (format pane "  Press Ctrl-Q to exit.~%"))

(defun display-bottom (frame pane)
  (let ((count (slot-value frame 'key-count)))
    (format pane "  BOTTOM PANE: Key presses: ~D~%" count)
    (format pane "  This pane repaints independently.~%")))

(define-application-frame multi-pane-test ()
  ((key-count :initform 0))
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

;;; On any keypress, increment the counter and mark bottom pane for redisplay.
(defmethod clim-charmed:charmed-handle-key-event
    ((frame multi-pane-test) key)
  (declare (ignore key))
  (incf (slot-value frame 'key-count))
  (let ((bp (find-pane-named frame 'bottom-pane)))
    (when bp
      (setf (pane-needs-redisplay bp) t))))

(defun run ()
  (let* ((port (make-instance 'clim-charmed::charmed-port
                              :server-path '(:charmed)))
         (fm (first (slot-value port 'climi::frame-managers))))
    (unwind-protect
         (let ((frame (make-application-frame 'multi-pane-test
                                              :frame-manager fm)))
           (run-frame-top-level frame))
      (climi::destroy-port port))))
