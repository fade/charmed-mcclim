;;;; object-inspector.lisp - An Interactive Object Inspector/Editor
;;;; Demonstrates charmed-mcclim presentations with drill-down navigation,
;;;; inline editing, and type-aware display of arbitrary Lisp objects.

(in-package #:cl-user)

(defpackage #:charmed-mcclim/object-inspector
  (:use #:cl #:charmed #:charmed-mcclim)
  (:export #:run #:inspect-object))

(in-package #:charmed-mcclim/object-inspector)

;;; ============================================================
;;; Inspection Protocol
;;; ============================================================

(defstruct slot-entry
  "A displayable slot/field in the inspector."
  (label "" :type string)
  (value nil)
  (value-string "" :type string)
  (type-string "" :type string)
  (editable-p nil :type boolean)
  (setter nil :type (or null function)))

(defgeneric inspect-slots (object)
  (:documentation "Return a list of SLOT-ENTRY structs describing the inspectable parts of OBJECT."))

(defgeneric object-title (object)
  (:documentation "Return a short title string for OBJECT."))

(defgeneric object-summary (object)
  (:documentation "Return detail lines (list of strings) describing OBJECT."))

;;; ============================================================
;;; Printing Helpers
;;; ============================================================

(defun safe-print (object &optional (max-length 80))
  "Print OBJECT to a string, truncating if needed. Never errors."
  (handler-case
      (let* ((raw (with-output-to-string (s)
                    (let ((*print-length* 10)
                          (*print-level* 3)
                          (*print-circle* t)
                          (*print-pretty* nil))
                      (prin1 object s))))
             (len (length raw)))
        (if (> len max-length)
            (concatenate 'string (subseq raw 0 (- max-length 3)) "...")
            raw))
    (error (e)
      (format nil "#<error printing: ~A>" e))))

(defun type-label (object)
  "Return a short type description string for OBJECT."
  (typecase object
    (null "NULL")
    (keyword "KEYWORD")
    (symbol "SYMBOL")
    (string (format nil "STRING[~D]" (length object)))
    (integer "INTEGER")
    (float "FLOAT")
    (ratio "RATIO")
    (complex "COMPLEX")
    (character "CHARACTER")
    (cons "CONS")
    (vector (format nil "VECTOR[~D]" (length object)))
    (array (format nil "ARRAY~A" (array-dimensions object)))
    (hash-table (format nil "HASH-TABLE[~D]" (hash-table-count object)))
    (package "PACKAGE")
    (function "FUNCTION")
    (pathname "PATHNAME")
    (stream "STREAM")
    (t (let ((class (class-of object)))
         (format nil "~A" (class-name class))))))

;;; ============================================================
;;; object-title methods
;;; ============================================================

(defmethod object-title (object)
  (format nil "~A: ~A" (type-label object) (safe-print object 60)))

(defmethod object-title ((object symbol))
  (format nil "Symbol: ~A" object))

(defmethod object-title ((object package))
  (format nil "Package: ~A" (package-name object)))

(defmethod object-title ((object string))
  (format nil "String[~D]: ~S" (length object) (safe-print object 50)))

(defmethod object-title ((object cons))
  (let ((len (ignore-errors (length object))))
    (if len
        (format nil "List[~D]" len)
        "Dotted pair")))

(defmethod object-title ((object hash-table))
  (format nil "Hash-table[~D/~D]" (hash-table-count object) (hash-table-size object)))

(defmethod object-title ((object function))
  (format nil "Function: ~A" (or (ignore-errors
                                    #+sbcl (sb-impl::%fun-name object)
                                    #-sbcl nil)
                                  "#<function>")))

(defmethod object-title ((object standard-object))
  (format nil "~A instance" (class-name (class-of object))))

;;; ============================================================
;;; inspect-slots methods
;;; ============================================================

(defmethod inspect-slots (object)
  "Default: show type and printed representation."
  (list (make-slot-entry :label "Type" :value (type-of object)
                         :value-string (format nil "~A" (type-of object))
                         :type-string "TYPE")
        (make-slot-entry :label "Value" :value object
                         :value-string (safe-print object 200)
                         :type-string (type-label object))))

(defmethod inspect-slots ((object symbol))
  (let ((slots nil))
    (push (make-slot-entry :label "Name" :value (symbol-name object)
                           :value-string (symbol-name object)
                           :type-string "STRING") slots)
    (push (make-slot-entry :label "Package" :value (symbol-package object)
                           :value-string (if (symbol-package object)
                                             (package-name (symbol-package object))
                                             "(uninterned)")
                           :type-string "PACKAGE") slots)
    (when (boundp object)
      (push (make-slot-entry :label "Value" :value (symbol-value object)
                             :value-string (safe-print (symbol-value object))
                             :type-string (type-label (symbol-value object))
                             :editable-p t
                             :setter (lambda (new-val)
                                       (setf (symbol-value object) new-val)))
            slots))
    (when (fboundp object)
      (push (make-slot-entry :label "Function" :value (symbol-function object)
                             :value-string (safe-print (symbol-function object))
                             :type-string "FUNCTION") slots))
    (when (macro-function object)
      (push (make-slot-entry :label "Macro" :value (macro-function object)
                             :value-string (safe-print (macro-function object))
                             :type-string "FUNCTION") slots))
    (when (symbol-plist object)
      (push (make-slot-entry :label "Plist" :value (symbol-plist object)
                             :value-string (safe-print (symbol-plist object))
                             :type-string "PLIST") slots))
    (let ((class (find-class object nil)))
      (when class
        (push (make-slot-entry :label "Class" :value class
                               :value-string (format nil "~A" (class-name class))
                               :type-string "CLASS") slots)))
    (nreverse slots)))

(defmethod inspect-slots ((object package))
  (let ((ext-count 0) (total-count 0))
    (do-external-symbols (s object) (declare (ignore s)) (incf ext-count))
    (do-symbols (s object) (declare (ignore s)) (incf total-count))
    (list
     (make-slot-entry :label "Name" :value (package-name object)
                      :value-string (package-name object)
                      :type-string "STRING")
     (make-slot-entry :label "Nicknames"
                      :value (package-nicknames object)
                      :value-string (format nil "~{~A~^, ~}" (or (package-nicknames object) '("(none)")))
                      :type-string "LIST")
     (make-slot-entry :label "Uses"
                      :value (package-use-list object)
                      :value-string (format nil "~{~A~^, ~}" (or (mapcar #'package-name (package-use-list object)) '("(none)")))
                      :type-string "LIST")
     (make-slot-entry :label "Used by"
                      :value (package-used-by-list object)
                      :value-string (format nil "~{~A~^, ~}" (or (mapcar #'package-name (package-used-by-list object)) '("(none)")))
                      :type-string "LIST")
     (make-slot-entry :label "External symbols" :value ext-count
                      :value-string (format nil "~D" ext-count)
                      :type-string "INTEGER")
     (make-slot-entry :label "Total symbols" :value total-count
                      :value-string (format nil "~D" total-count)
                      :type-string "INTEGER"))))

(defmethod inspect-slots ((object cons))
  (if (ignore-errors (listp (cdr object)))
      ;; Proper list
      (let ((len (ignore-errors (length object))))
        (if (and len (<= len 50))
            (loop for item in object
                  for i from 0
                  collect (make-slot-entry
                           :label (format nil "[~D]" i)
                           :value item
                           :value-string (safe-print item)
                           :type-string (type-label item)
                           :editable-p t
                           :setter (let ((idx i))
                                     (lambda (new-val)
                                       (setf (nth idx object) new-val)))))
            ;; Very long list — show first 50
            (loop for item in object
                  for i from 0 below 50
                  collect (make-slot-entry
                           :label (format nil "[~D]" i)
                           :value item
                           :value-string (safe-print item)
                           :type-string (type-label item)))))
      ;; Dotted pair
      (list (make-slot-entry :label "CAR" :value (car object)
                             :value-string (safe-print (car object))
                             :type-string (type-label (car object))
                             :editable-p t
                             :setter (lambda (v) (setf (car object) v)))
            (make-slot-entry :label "CDR" :value (cdr object)
                             :value-string (safe-print (cdr object))
                             :type-string (type-label (cdr object))
                             :editable-p t
                             :setter (lambda (v) (setf (cdr object) v))))))

(defmethod inspect-slots ((object vector))
  (let ((len (min (length object) 50)))
    (loop for i from 0 below len
          collect (make-slot-entry
                   :label (format nil "[~D]" i)
                   :value (aref object i)
                   :value-string (safe-print (aref object i))
                   :type-string (type-label (aref object i))
                   :editable-p (not (typep object 'simple-string))
                   :setter (let ((idx i))
                             (lambda (v) (setf (aref object idx) v)))))))

(defmethod inspect-slots ((object hash-table))
  (let ((entries nil))
    (push (make-slot-entry :label "Test" :value (hash-table-test object)
                           :value-string (format nil "~A" (hash-table-test object))
                           :type-string "SYMBOL") entries)
    (push (make-slot-entry :label "Count" :value (hash-table-count object)
                           :value-string (format nil "~D" (hash-table-count object))
                           :type-string "INTEGER") entries)
    (push (make-slot-entry :label "Size" :value (hash-table-size object)
                           :value-string (format nil "~D" (hash-table-size object))
                           :type-string "INTEGER") entries)
    (let ((count 0))
      (maphash (lambda (k v)
                 (when (< count 50)
                   (push (make-slot-entry
                          :label (safe-print k 30)
                          :value v
                          :value-string (safe-print v)
                          :type-string (type-label v)
                          :editable-p t
                          :setter (let ((key k))
                                    (lambda (new-val)
                                      (setf (gethash key object) new-val))))
                         entries)
                   (incf count)))
               object))
    (nreverse entries)))

(defmethod inspect-slots ((object standard-object))
  (let ((class (class-of object)))
    ;; Ensure finalized for slot access
    #+sbcl (sb-mop:finalize-inheritance class)
    (let ((slots #+sbcl (sb-mop:class-slots class)
                 #-sbcl nil))
      (if slots
          (loop for slot in slots
                for name = #+sbcl (sb-mop:slot-definition-name slot) #-sbcl nil
                when name
                collect (let ((sname name))
                          (make-slot-entry
                           :label (string sname)
                           :value (if (slot-boundp object sname)
                                      (slot-value object sname)
                                      :unbound)
                           :value-string (if (slot-boundp object sname)
                                             (safe-print (slot-value object sname))
                                             "#<unbound>")
                           :type-string (if (slot-boundp object sname)
                                            (type-label (slot-value object sname))
                                            "UNBOUND")
                           :editable-p (slot-boundp object sname)
                           :setter (lambda (v) (setf (slot-value object sname) v)))))
          ;; Fallback for non-SBCL or non-MOP
          (call-next-method)))))

(defmethod inspect-slots ((object function))
  (let ((slots nil))
    (push (make-slot-entry :label "Type" :value (type-of object)
                           :value-string (format nil "~A" (type-of object))
                           :type-string "TYPE") slots)
    #+sbcl
    (let ((name (ignore-errors (sb-impl::%fun-name object))))
      (when name
        (push (make-slot-entry :label "Name" :value name
                               :value-string (safe-print name)
                               :type-string (type-label name)) slots)))
    #+sbcl
    (let ((arglist (ignore-errors (sb-introspect:function-arglist object))))
      (when arglist
        (push (make-slot-entry :label "Arglist"
                               :value arglist
                               :value-string (format nil "~A" arglist)
                               :type-string "LIST") slots)))
    (let ((doc (ignore-errors (documentation object t))))
      (when doc
        (push (make-slot-entry :label "Documentation"
                               :value doc
                               :value-string (safe-print doc 200)
                               :type-string "STRING") slots)))
    (nreverse slots)))

;;; ============================================================
;;; object-summary methods
;;; ============================================================

(defmethod object-summary (object)
  "Default summary: type info and documentation if any."
  (let ((lines nil))
    (push (format nil "Type: ~A" (type-of object)) lines)
    (push (format nil "Class: ~A" (class-name (class-of object))) lines)
    (push "" lines)
    (push (format nil "Printed: ~A" (safe-print object 500)) lines)
    (nreverse lines)))

(defmethod object-summary ((object symbol))
  (let ((lines nil))
    (push (format nil "~A::~A" (if (symbol-package object)
                                    (package-name (symbol-package object))
                                    "#")
                  (symbol-name object))
          lines)
    (push "" lines)
    (when (boundp object)
      (push (format nil "Value: ~A" (safe-print (symbol-value object) 200)) lines))
    (when (fboundp object)
      (push (format nil "Function: ~A" (safe-print (symbol-function object) 200)) lines)
      #+sbcl
      (let ((arglist (ignore-errors (sb-introspect:function-arglist object))))
        (when arglist
          (push (format nil "Arglist: ~A" arglist) lines))))
    (let ((doc (or (documentation object 'function)
                   (documentation object 'variable)
                   (documentation object 'type))))
      (when doc
        (push "" lines)
        (push "── Documentation ──" lines)
        ;; Split multi-line docs
        (dolist (line (split-doc-string doc))
          (push line lines))))
    (let ((class (find-class object nil)))
      (when class
        (push "" lines)
        (push "── Class Info ──" lines)
        (push (format nil "Class: ~A" (class-name class)) lines)
        #+sbcl
        (let ((supers (mapcar #'class-name (sb-mop:class-direct-superclasses class))))
          (when supers
            (push (format nil "Superclasses: ~{~A~^, ~}" supers) lines)))
        #+sbcl
        (let ((subs (mapcar #'class-name (sb-mop:class-direct-subclasses class))))
          (when subs
            (push (format nil "Subclasses: ~{~A~^, ~}" subs) lines)))))
    (nreverse lines)))

(defmethod object-summary ((object standard-object))
  (let ((lines nil)
        (class (class-of object)))
    (push (format nil "Instance of ~A" (class-name class)) lines)
    (push "" lines)
    #+sbcl
    (let ((supers (mapcar #'class-name (sb-mop:class-direct-superclasses class))))
      (push (format nil "Superclasses: ~{~A~^, ~}" supers) lines))
    #+sbcl
    (let ((precedence (mapcar #'class-name (sb-mop:class-precedence-list class))))
      (push (format nil "Precedence: ~{~A~^, ~}" precedence) lines))
    (let ((doc (documentation (class-name class) 'type)))
      (when doc
        (push "" lines)
        (push "── Documentation ──" lines)
        (dolist (line (split-doc-string doc))
          (push line lines))))
    (nreverse lines)))

(defun split-doc-string (doc)
  "Split a documentation string into lines."
  (loop for start = 0 then (1+ end)
        for end = (position #\Newline doc :start start)
        collect (subseq doc start (or end (length doc)))
        while end))

;;; ============================================================
;;; Inspector State
;;; ============================================================

(defvar *history* nil "Stack of (object . scroll-offset) for back navigation.")
(defvar *current-object* nil "The object being inspected.")
(defvar *current-slots* nil "List of slot-entry for current object.")
(defvar *selected-slot* 0 "Index of selected slot in slots pane.")
(defvar *slots-scroll* 0 "Scroll offset for slots pane.")
(defvar *detail-scroll* 0 "Scroll offset for detail pane.")
(defvar *detail-lines* nil "Cached detail/summary lines.")
(defvar *editing-p* nil "Whether we are in inline edit mode.")
(defvar *edit-buffer* "" "Current edit text.")
(defvar *edit-cursor* 0 "Cursor position in edit buffer.")

;;; Panes
(defvar *history-pane* nil)
(defvar *slots-pane* nil)
(defvar *detail-pane* nil)
(defvar *interactor* nil)
(defvar *status* nil)

(defun push-object (object)
  "Push current object onto history and inspect a new object."
  (when *current-object*
    (push (cons *current-object* *slots-scroll*) *history*))
  (set-current-object object))

(defun pop-object ()
  "Go back to the previous object in history."
  (when *history*
    (let ((entry (pop *history*)))
      (set-current-object (car entry))
      (setf *slots-scroll* (cdr entry)))))

(defun set-current-object (object)
  "Set the current inspection target."
  (setf *current-object* object
        *current-slots* (ignore-errors (inspect-slots object))
        *selected-slot* 0
        *slots-scroll* 0
        *detail-scroll* 0
        *detail-lines* (ignore-errors (object-summary object))
        *editing-p* nil
        *edit-buffer* ""
        *edit-cursor* 0))

(defun selected-slot-entry ()
  "Return the currently selected slot-entry, or nil."
  (when (and *current-slots* (< *selected-slot* (length *current-slots*)))
    (nth *selected-slot* *current-slots*)))

(defun begin-edit ()
  "Begin inline editing of the selected slot."
  (let ((entry (selected-slot-entry)))
    (when (and entry (slot-entry-editable-p entry))
      (setf *editing-p* t
            *edit-buffer* (slot-entry-value-string entry)
            *edit-cursor* (length *edit-buffer*)))))

(defun commit-edit ()
  "Commit the current edit."
  (let ((entry (selected-slot-entry)))
    (when (and entry *editing-p* (slot-entry-setter entry))
      (handler-case
          (let ((new-val (read-from-string *edit-buffer*)))
            (funcall (slot-entry-setter entry) new-val)
            ;; Refresh slots
            (setf *current-slots* (ignore-errors (inspect-slots *current-object*))
                  *detail-lines* (ignore-errors (object-summary *current-object*))))
        (error (e)
          (setf (interactor-pane-message *interactor*)
                (format nil "Edit error: ~A" e)))))
    (setf *editing-p* nil
          *edit-buffer* ""
          *edit-cursor* 0)))

(defun cancel-edit ()
  "Cancel inline editing."
  (setf *editing-p* nil
        *edit-buffer* ""
        *edit-cursor* 0))

;;; ============================================================
;;; Display Functions
;;; ============================================================

(defun display-history (pane medium)
  "Display the inspection history as a breadcrumb stack."
  (let* ((cx (pane-content-x pane))
         (cy (pane-content-y pane))
         (cw (pane-content-width pane))
         (ch (pane-content-height pane)))
    (clear-presentations pane)
    ;; Show history items (most recent first, then current at bottom)
    (let* ((items (reverse *history*))
           (total (1+ (length items)))
           (start (max 0 (- total ch))))
      ;; History entries
      (loop for entry in (nthcdr start items)
            for i from 0
            for row = (+ cy i)
            for obj = (car entry)
            for title = (handler-case (object-title obj)
                          (error () "#<error>"))
            for display = (if (> (length title) (- cw 2))
                              (subseq title 0 (- cw 2))
                              title)
            when (< i ch)
            do (medium-write-string medium cx row
                                    (format nil "  ~A" display)
                                    :fg (lookup-color :white))
               (let ((pres (make-presentation obj 'history-entry
                                              cx row cw
                                              :pane pane
                                              :action (lambda (p)
                                                        (declare (ignore p))
                                                        (let ((pos (position entry *history*)))
                                                          (when pos
                                                            ;; Pop back to this point
                                                            (loop repeat pos do (pop *history*))
                                                            (pop-object)
                                                            (mark-all-dirty)))))))
                 (register-presentation pane pres)))
      ;; Current object at bottom
      (let* ((current-row (+ cy (min (- ch 1) (- total start 1))))
             (title (handler-case (object-title *current-object*)
                      (error () "#<error>")))
             (display (if (> (length title) (- cw 4))
                          (subseq title 0 (- cw 4))
                          title)))
        (medium-fill-rect medium cx current-row cw 1
                          :fg (lookup-color :green)
                          :style (make-style :bold t :inverse t))
        (medium-write-string medium cx current-row
                             (format nil "> ~A" display)
                             :fg (lookup-color :green)
                             :style (make-style :bold t :inverse t))))))

(defun display-slots (pane medium)
  "Display the slots/fields of the current object."
  (let* ((cx (pane-content-x pane))
         (cy (pane-content-y pane))
         (cw (pane-content-width pane))
         (ch (pane-content-height pane)))
    (clear-presentations pane)
    (unless *current-slots*
      (medium-write-string medium cx cy "(no slots)" :fg (lookup-color :white))
      (return-from display-slots))
    (let* ((visible-count (min ch (- (length *current-slots*) *slots-scroll*)))
           (label-width (min 20 (1+ (loop for s in *current-slots*
                                          maximize (length (slot-entry-label s)))))))
      (loop for i from 0 below visible-count
            for slot-idx = (+ i *slots-scroll*)
            for entry = (nth slot-idx *current-slots*)
            for row = (+ cy i)
            for selected = (= slot-idx *selected-slot*)
            do
               (let* ((label (slot-entry-label entry))
                      (truncated-label (if (> (length label) (1- label-width))
                                           (subseq label 0 (1- label-width))
                                           label))
                      (padded-label (format nil "~VA" label-width truncated-label))
                      (value-width (- cw label-width 3))
                      (value-str (if (and selected *editing-p*)
                                     *edit-buffer*
                                     (slot-entry-value-string entry)))
                      (display-value (if (> (length value-str) value-width)
                                         (subseq value-str 0 value-width)
                                         value-str))
                      (type-tag (slot-entry-type-string entry))
                      (editable (slot-entry-editable-p entry)))
                 ;; Selected row highlight
                 (when selected
                   (medium-fill-rect medium cx row cw 1
                                     :fg (lookup-color :green)
                                     :style (make-style :bold t :inverse t)))
                 ;; Label
                 (medium-write-string medium cx row padded-label
                                      :fg (if selected
                                              (lookup-color :green)
                                              (lookup-color :cyan))
                                      :style (when selected (make-style :bold t :inverse t)))
                 ;; Separator
                 (medium-write-string medium (+ cx label-width) row
                                      (if (and selected *editing-p*) "▸ " "= ")
                                      :fg (if selected
                                              (lookup-color :green)
                                              (lookup-color :white))
                                      :style (when selected (make-style :bold t :inverse t)))
                 ;; Value
                 (let ((value-fg (cond
                                   (selected (lookup-color :green))
                                   ((and selected *editing-p*) (lookup-color :yellow))
                                   ((string= type-tag "UNBOUND") (lookup-color :red))
                                   (editable (lookup-color :white))
                                   (t (lookup-color :white)))))
                   (medium-write-string medium (+ cx label-width 2) row display-value
                                        :fg value-fg
                                        :style (when selected (make-style :bold t :inverse t))))
                 ;; Edit cursor indicator
                 (when (and selected *editing-p*)
                   (let ((cursor-x (+ cx label-width 2 (min *edit-cursor* value-width))))
                     (when (< cursor-x (+ cx cw))
                       (let ((cursor-char (if (< *edit-cursor* (length *edit-buffer*))
                                              (char *edit-buffer* *edit-cursor*)
                                              #\Space)))
                         (medium-write-string medium cursor-x row
                                              (string cursor-char)
                                              :fg (lookup-color :black)
                                              :bg (lookup-color :green))))))
                 ;; Register presentation for the value (click to drill in)
                 (let ((pres (make-presentation (slot-entry-value entry)
                                                'slot-value
                                                (+ cx label-width 2) row
                                                (- cw label-width 2)
                                                :pane pane
                                                :action (lambda (p)
                                                          (let ((val (presentation-object p)))
                                                            (push-object val)
                                                            (mark-all-dirty))))))
                   (register-presentation pane pres)))))))

(defun display-detail (pane medium)
  "Display the detail/summary for the current object."
  (let* ((cx (pane-content-x pane))
         (cy (pane-content-y pane))
         (cw (pane-content-width pane))
         (ch (pane-content-height pane)))
    (when *detail-lines*
      (let ((visible-count (min ch (- (length *detail-lines*) *detail-scroll*))))
        (loop for i from 0 below visible-count
              for line-idx = (+ i *detail-scroll*)
              for line = (nth line-idx *detail-lines*)
              for row = (+ cy i)
              do (let ((display (if (> (length line) cw)
                                    (subseq line 0 cw)
                                    line))
                       (header-p (and (>= (length line) 2)
                                      (char= (char line 0) #\─))))
                   (medium-write-string medium cx row display
                                        :fg (if header-p
                                                (lookup-color :cyan)
                                                (lookup-color :white))
                                        :style (when header-p (make-style :bold t)))))))))

;;; ============================================================
;;; Utility
;;; ============================================================

(defun mark-all-dirty ()
  "Mark all panes as needing redraw."
  (when *history-pane* (setf (pane-dirty-p *history-pane*) t))
  (when *slots-pane* (setf (pane-dirty-p *slots-pane*) t))
  (when *detail-pane* (setf (pane-dirty-p *detail-pane*) t))
  (when *status* (setf (pane-dirty-p *status*) t)))

;;; ============================================================
;;; Layout
;;; ============================================================

(defun compute-layout (backend width height)
  "Compute pane positions for the given terminal size."
  (let* ((history-width (max 15 (floor width 5)))
         (remaining (- width history-width))
         (slots-width (max 30 (floor remaining 2)))
         (detail-width (- remaining slots-width))
         (content-height (- height 4)))
    ;; History pane (left)
    (setf (pane-x *history-pane*) 1
          (pane-y *history-pane*) 1
          (pane-width *history-pane*) history-width
          (pane-height *history-pane*) content-height
          (pane-dirty-p *history-pane*) t)
    ;; Slots pane (center)
    (setf (pane-x *slots-pane*) (1+ history-width)
          (pane-y *slots-pane*) 1
          (pane-width *slots-pane*) slots-width
          (pane-height *slots-pane*) content-height
          (pane-dirty-p *slots-pane*) t)
    ;; Detail pane (right)
    (setf (pane-x *detail-pane*) (+ 1 history-width slots-width)
          (pane-y *detail-pane*) 1
          (pane-width *detail-pane*) detail-width
          (pane-height *detail-pane*) content-height
          (pane-dirty-p *detail-pane*) t)
    ;; Interactor (bottom, 3 rows with border)
    (setf (pane-x *interactor*) 1
          (pane-y *interactor*) (- height 3)
          (pane-width *interactor*) width
          (pane-height *interactor*) 3
          (pane-dirty-p *interactor*) t)
    ;; Status bar (bottom)
    (setf (pane-x *status*) 1
          (pane-y *status*) height
          (pane-width *status*) width
          (pane-dirty-p *status*) t)
    ;; Update status
    (update-status)
    ;; Update backend pane list
    (setf (backend-panes backend)
          (list *history-pane* *slots-pane* *detail-pane* *interactor* *status*))))

;;; ============================================================
;;; Command Table
;;; ============================================================

(defvar *commands* (make-command-table "inspector"))

(define-command (*commands* "inspect" :documentation "Inspect a Lisp expression")
    ((expr string :prompt "expression"))
  "Evaluate and inspect the given expression."
  (handler-case
      (let ((object (eval (read-from-string expr))))
        (push-object object)
        (mark-all-dirty)
        (format nil "Inspecting: ~A" (safe-print object 60)))
    (error (e)
      (error "~A" e))))

(define-command (*commands* "back" :documentation "Go back to previous object")
    ()
  "Return to the previously inspected object."
  (if *history*
      (progn (pop-object) (mark-all-dirty) "OK")
      (error "No history")))

(define-command (*commands* "edit" :documentation "Edit the selected slot value")
    ()
  "Begin editing the currently selected slot."
  (let ((entry (selected-slot-entry)))
    (cond
      ((null entry) (error "No slot selected"))
      ((not (slot-entry-editable-p entry)) (error "Slot is not editable"))
      (t (begin-edit)
         (setf (pane-dirty-p *slots-pane*) t)
         "Editing... Enter to commit, Escape to cancel"))))

(define-command (*commands* "setf" :documentation "Set a slot to a new value")
    ((value string :prompt "value"))
  "Set the selected slot to a new value."
  (let ((entry (selected-slot-entry)))
    (cond
      ((null entry) (error "No slot selected"))
      ((not (slot-entry-setter entry)) (error "Slot is not settable"))
      (t (handler-case
             (let ((new-val (read-from-string value)))
               (funcall (slot-entry-setter entry) new-val)
               (setf *current-slots* (ignore-errors (inspect-slots *current-object*))
                     *detail-lines* (ignore-errors (object-summary *current-object*)))
               (mark-all-dirty)
               (format nil "Set ~A = ~A" (slot-entry-label entry) (safe-print new-val 60)))
           (error (e) (error "~A" e)))))))

(define-command (*commands* "describe" :documentation "Describe the current object")
    ()
  "Show CL:DESCRIBE output for the current object."
  (let ((desc (with-output-to-string (s)
                (describe *current-object* s))))
    (setf *detail-lines* (split-doc-string desc)
          *detail-scroll* 0
          (pane-dirty-p *detail-pane*) t)
    "Showing DESCRIBE output in detail pane"))

(define-command (*commands* "type" :documentation "Show type hierarchy for current object")
    ()
  "Display type information."
  (let ((lines nil))
    (push (format nil "Type: ~A" (type-of *current-object*)) lines)
    (push (format nil "Class: ~A" (class-name (class-of *current-object*))) lines)
    #+sbcl
    (let ((cpl (mapcar #'class-name
                       (sb-mop:class-precedence-list (class-of *current-object*)))))
      (push "" lines)
      (push "── Class Precedence List ──" lines)
      (dolist (c cpl) (push (format nil "  ~A" c) lines)))
    (setf *detail-lines* (nreverse lines)
          *detail-scroll* 0
          (pane-dirty-p *detail-pane*) t)
    "Showing type hierarchy"))

(define-command (*commands* "help" :documentation "Show available commands")
    ()
  "List all available commands."
  (let ((cmds (list-commands *commands*)))
    (format nil "Commands: ~{~A~^, ~}" cmds)))

(define-command (*commands* "quit" :documentation "Exit the inspector")
    ()
  "Quit the application."
  (setf (backend-running-p *current-backend*) nil))

;;; ============================================================
;;; Status
;;; ============================================================

(defun update-status ()
  "Update status bar."
  (setf (status-pane-sections *status*)
        `(("Object" . ,(handler-case (object-title *current-object*)
                         (error () "#<error>")))
          ("Slots" . ,(length *current-slots*))
          ("History" . ,(length *history*))
          ("Tab" . "complete/focus")
          ("q" . "quit"))
        (pane-dirty-p *status*) t))

;;; ============================================================
;;; Event Handling
;;; ============================================================

(defun slots-max-scroll ()
  "Maximum scroll offset for slots pane."
  (if *current-slots*
      (max 0 (- (length *current-slots*) (pane-content-height *slots-pane*)))
      0))

(defun detail-max-scroll ()
  "Maximum scroll offset for detail pane."
  (if *detail-lines*
      (max 0 (- (length *detail-lines*) (pane-content-height *detail-pane*)))
      0))

(defun update-detail-for-selection ()
  "Update detail pane to show info about the selected slot's value."
  (let ((entry (selected-slot-entry)))
    (when entry
      (setf *detail-lines* (ignore-errors (object-summary (slot-entry-value entry)))
            *detail-scroll* 0
            (pane-dirty-p *detail-pane*) t))))

(defmethod pane-handle-event ((pane application-pane) event)
  "Handle keyboard navigation in inspector panes."
  (when (typep event 'keyboard-event)
    (let* ((key (keyboard-event-key event))
           (code (key-event-code key))
           (char (key-event-char key)))
      (cond
        ;; ── Slots pane (with edit mode) ──
        ((eq pane *slots-pane*)
         (cond
           ;; Edit mode input handling
           (*editing-p*
            (cond
              ;; Enter - commit edit
              ((eql code +key-enter+)
               (commit-edit)
               (mark-all-dirty) t)
              ;; Escape - cancel edit
              ((eql code +key-escape+)
               (cancel-edit)
               (setf (pane-dirty-p *slots-pane*) t) t)
              ;; Backspace
              ((eql code +key-backspace+)
               (when (> *edit-cursor* 0)
                 (setf *edit-buffer*
                       (concatenate 'string
                                    (subseq *edit-buffer* 0 (1- *edit-cursor*))
                                    (subseq *edit-buffer* *edit-cursor*))
                       *edit-cursor* (1- *edit-cursor*))
                 (setf (pane-dirty-p *slots-pane*) t))
               t)
              ;; Delete
              ((eql code +key-delete+)
               (when (< *edit-cursor* (length *edit-buffer*))
                 (setf *edit-buffer*
                       (concatenate 'string
                                    (subseq *edit-buffer* 0 *edit-cursor*)
                                    (subseq *edit-buffer* (1+ *edit-cursor*))))
                 (setf (pane-dirty-p *slots-pane*) t))
               t)
              ;; Left arrow
              ((eql code +key-left+)
               (when (> *edit-cursor* 0)
                 (decf *edit-cursor*)
                 (setf (pane-dirty-p *slots-pane*) t))
               t)
              ;; Right arrow
              ((eql code +key-right+)
               (when (< *edit-cursor* (length *edit-buffer*))
                 (incf *edit-cursor*)
                 (setf (pane-dirty-p *slots-pane*) t))
               t)
              ;; Home
              ((eql code +key-home+)
               (setf *edit-cursor* 0
                     (pane-dirty-p *slots-pane*) t)
               t)
              ;; End
              ((eql code +key-end+)
               (setf *edit-cursor* (length *edit-buffer*)
                     (pane-dirty-p *slots-pane*) t)
               t)
              ;; Printable character
              ((and char (graphic-char-p char))
               (setf *edit-buffer*
                     (concatenate 'string
                                  (subseq *edit-buffer* 0 *edit-cursor*)
                                  (string char)
                                  (subseq *edit-buffer* *edit-cursor*))
                     *edit-cursor* (1+ *edit-cursor*)
                     (pane-dirty-p *slots-pane*) t)
               t)
              (t nil)))
           ;; Normal mode
           ;; Up - previous slot
           ((eql code +key-up+)
            (when (> *selected-slot* 0)
              (decf *selected-slot*)
              (when (< *selected-slot* *slots-scroll*)
                (setf *slots-scroll* *selected-slot*))
              (setf (pane-dirty-p *slots-pane*) t)
              (update-detail-for-selection)
              (update-status))
            t)
           ;; Down - next slot
           ((eql code +key-down+)
            (when (and *current-slots*
                       (< *selected-slot* (1- (length *current-slots*))))
              (incf *selected-slot*)
              (let ((visible (pane-content-height *slots-pane*)))
                (when (>= *selected-slot* (+ *slots-scroll* visible))
                  (setf *slots-scroll* (- *selected-slot* visible -1))))
              (setf (pane-dirty-p *slots-pane*) t)
              (update-detail-for-selection)
              (update-status))
            t)
           ;; Enter - drill into selected value
           ((eql code +key-enter+)
            (let ((entry (selected-slot-entry)))
              (when entry
                (push-object (slot-entry-value entry))
                (mark-all-dirty)
                (update-status)))
            t)
           ;; e - begin editing
           ((and char (char= char #\e))
            (let ((entry (selected-slot-entry)))
              (when (and entry (slot-entry-editable-p entry))
                (begin-edit)
                (setf (pane-dirty-p *slots-pane*) t)))
            t)
           ;; Backspace or b - go back
           ((or (eql code +key-backspace+)
                (and char (char= char #\b)))
            (when *history*
              (pop-object)
              (mark-all-dirty)
              (update-status))
            t)
           ;; q - quit
           ((and char (char= char #\q))
            (setf (backend-running-p *current-backend*) nil)
            t)
           (t nil)))

        ;; ── History pane ──
        ((eq pane *history-pane*)
         (cond
           ;; q - quit
           ((and char (char= char #\q))
            (setf (backend-running-p *current-backend*) nil) t)
           (t nil)))

        ;; ── Detail pane ──
        ((eq pane *detail-pane*)
         (cond
           ;; Up - scroll up
           ((eql code +key-up+)
            (when (> *detail-scroll* 0)
              (decf *detail-scroll*)
              (setf (pane-dirty-p *detail-pane*) t))
            t)
           ;; Down - scroll down
           ((eql code +key-down+)
            (when (< *detail-scroll* (detail-max-scroll))
              (incf *detail-scroll*)
              (setf (pane-dirty-p *detail-pane*) t))
            t)
           ;; Page Up
           ((eql code +key-page-up+)
            (setf *detail-scroll* (max 0 (- *detail-scroll* (pane-content-height *detail-pane*)))
                  (pane-dirty-p *detail-pane*) t)
            t)
           ;; Page Down
           ((eql code +key-page-down+)
            (setf *detail-scroll* (min (detail-max-scroll)
                                       (+ *detail-scroll* (pane-content-height *detail-pane*)))
                  (pane-dirty-p *detail-pane*) t)
            t)
           ;; q - quit
           ((and char (char= char #\q))
            (setf (backend-running-p *current-backend*) nil) t)
           (t nil)))

        ;; Other panes
        (t nil)))))

;;; ============================================================
;;; Entry Points
;;; ============================================================

(defun inspect-object (object)
  "Inspect an arbitrary Lisp object in the TUI inspector."
  ;; Initialize state
  (setf *history* nil)
  (set-current-object object)
  ;; Create panes
  (setf *history-pane* (make-instance 'application-pane
                                       :title "History"
                                       :display-fn #'display-history)
        *slots-pane* (make-instance 'application-pane
                                     :title "Slots"
                                     :display-fn #'display-slots)
        *detail-pane* (make-instance 'application-pane
                                      :title "Detail"
                                      :display-fn #'display-detail)
        *interactor* (make-instance 'interactor-pane
                                     :title "Command"
                                     :prompt "» "
                                     :command-table *commands*)
        *status* (make-instance 'status-pane))
  ;; Create and run frame
  (let ((frame (make-instance 'application-frame
                               :title "Object Inspector"
                               :layout #'compute-layout)))
    (run-frame frame))
  #+sbcl (sb-ext:exit)
  #+ccl (ccl:quit)
  #+ecl (ext:quit))

(defun run ()
  "Run the inspector on the CHARMED-MCCLIM package as a starting point."
  (inspect-object (find-package :charmed-mcclim)))
