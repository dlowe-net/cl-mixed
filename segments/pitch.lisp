#|
 This file is a part of cl-mixed
 (c) 2017 Shirakumo http://tymoon.eu (shinmera@tymoon.eu)
 Author: Nicolas Hafner <shinmera@tymoon.eu>
|#

(in-package #:org.shirakumo.fraf.mixed)

(defclass pitch (segment)
  ()
  (:default-initargs
   :pitch 1.0
   :samplerate *default-samplerate*))

(defmethod initialize-instance :after ((segment pitch) &key pitch samplerate bypass wet)
  (with-error-on-failure ()
    (mixed:make-segment-pitch pitch samplerate (handle segment)))
  (when wet (setf (wet segment) wet))
  (setf (bypass segment) bypass))

(defun make-pitch (&rest args &key pitch samplerate)
  (declare (ignore pitch samplerate))
  (apply #'make-instance 'pitch args))

(define-field-accessor pitch pitch :float :pitch-shift)
(define-field-accessor samplerate pitch :float :samplerate)
(define-field-accessor bypass pitch :bool :bypass)
(define-field-accessor wet pitch :float :mix)
