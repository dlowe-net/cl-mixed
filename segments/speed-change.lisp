#|
 This file is a part of cl-mixed
 (c) 2017 Shirakumo http://tymoon.eu (shinmera@tymoon.eu)
 Author: Nicolas Hafner <shinmera@tymoon.eu>
|#

(in-package #:org.shirakumo.fraf.mixed)

(defclass speed-change (segment)
  ()
  (:default-initargs
   :speed 1.0))

(defmethod initialize-instance :after ((segment speed-change) &key speed)
  (with-error-on-failure ()
    (mixed:make-segment-speed-change speed (handle segment))))

(defun make-speed-change (&rest args &key speed)
  (declare (ignore speed))
  (apply #'make-instance 'speed-change args))

(define-field-accessor speed speed-change float :speed-factor)
(define-field-accessor bypass speed-change :bool :bypass)
