;;; -*- Mode: Lisp; Syntax: Common-Lisp; -*-
;;;
;;; key-translation-tests.lisp — Tests for terminal key event translation

(in-package #:clim-charmed-tests)

(in-suite key-translation-tests)

;;; Test modifier state bits
;;; The charmed backend uses McCLIM's modifier constants for key events

(test modifier-state-bits
  "Modifier state bits should be defined correctly"
  ;; Verify the modifier constants exist
  (is (integerp clim:+shift-key+))
  (is (integerp clim:+control-key+))
  (is (integerp clim:+meta-key+))
  ;; They should be distinct bits
  (is (zerop (logand clim:+shift-key+ clim:+control-key+)))
  (is (zerop (logand clim:+shift-key+ clim:+meta-key+)))
  (is (zerop (logand clim:+control-key+ clim:+meta-key+))))

(test translate-charmed-event-exists
  "The translate-charmed-event function should be defined"
  (is (fboundp 'clim-charmed::translate-charmed-event)))

(test find-event-sheet-exists
  "The find-event-sheet function should be defined"
  (is (fboundp 'clim-charmed::find-event-sheet)))

(test translate-key-name-exists
  "The translate-key-name function should be defined"
  (is (fboundp 'clim-charmed::translate-key-name)))

(test translate-key-name-special-keys
  "Special keys should translate to correct McCLIM key names"
  ;; Arrow keys
  (is (eq :up (clim-charmed::translate-key-name charmed:+key-up+ nil)))
  (is (eq :down (clim-charmed::translate-key-name charmed:+key-down+ nil)))
  (is (eq :left (clim-charmed::translate-key-name charmed:+key-left+ nil)))
  (is (eq :right (clim-charmed::translate-key-name charmed:+key-right+ nil)))
  ;; Page keys (McCLIM uses :prior/:next)
  (is (eq :prior (clim-charmed::translate-key-name charmed:+key-page-up+ nil)))
  (is (eq :next (clim-charmed::translate-key-name charmed:+key-page-down+ nil)))
  ;; Home/End
  (is (eq :home (clim-charmed::translate-key-name charmed:+key-home+ nil)))
  (is (eq :end (clim-charmed::translate-key-name charmed:+key-end+ nil)))
  ;; Control keys
  (is (eq :newline (clim-charmed::translate-key-name charmed:+key-enter+ nil)))
  (is (eq :tab (clim-charmed::translate-key-name charmed:+key-tab+ nil)))
  (is (eq :backspace (clim-charmed::translate-key-name charmed:+key-backspace+ nil)))
  (is (eq :escape (clim-charmed::translate-key-name charmed:+key-escape+ nil))))

(test translate-key-name-character-keys
  "Character keys should translate to uppercase keyword symbols"
  ;; Alpha characters become uppercase keywords
  (is (eq :|A| (clim-charmed::translate-key-name 0 #\a)))
  (is (eq :|A| (clim-charmed::translate-key-name 0 #\A)))
  (is (eq :|Z| (clim-charmed::translate-key-name 0 #\z)))
  ;; Digits become keyword symbols
  (is (eq :|0| (clim-charmed::translate-key-name 0 #\0)))
  (is (eq :|9| (clim-charmed::translate-key-name 0 #\9))))
