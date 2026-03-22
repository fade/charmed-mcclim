;;; -*- Mode: Lisp; Syntax: Common-Lisp; -*-
;;;
;;; package.lisp — Test package for charmed backend tests

(defpackage #:clim-charmed-tests
  (:use #:cl #:fiveam)
  (:export #:charmed-backend-suite
           #:scroll-tests
           #:key-translation-tests
           #:viewport-tests))

(in-package #:clim-charmed-tests)

(def-suite charmed-backend-suite
  :description "Test suite for the McCLIM charmed terminal backend")

(def-suite scroll-tests
  :description "Tests for scroll persistence and mode transitions"
  :in charmed-backend-suite)

(def-suite key-translation-tests
  :description "Tests for terminal key event translation"
  :in charmed-backend-suite)

(def-suite viewport-tests
  :description "Tests for viewport capture and geometry"
  :in charmed-backend-suite)
