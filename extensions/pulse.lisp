#|
 This file is a part of cl-mixed
 (c) 2017 Shirakumo http://tymoon.eu (shinmera@tymoon.eu)
 Author: Nicolas Hafner <shinmera@tymoon.eu>
|#

(defpackage #:org.shirakumo.fraf.mixed.pulse
  (:use #:cl)
  (:local-nicknames
   (#:mixed #:org.shirakumo.fraf.mixed)
   (#:mixed-cffi #:org.shirakumo.fraf.mixed.cffi)
   (#:pulse #:org.shirakumo.fraf.mixed.pulse.cffi))
  (:export
   #:pulse-error
   #:code
   #:pulse-present-p
   #:drain))
(in-package #:org.shirakumo.fraf.mixed.pulse)

(define-condition pulse-error (error)
  ((code :initarg :code :accessor code))
  (:report (lambda (c s) (format s "Pulse error ~d: ~a"
                                 (code c) (pulse:strerror (code c))))))

(defmacro with-error ((errorvar) &body body)
  `(cffi:with-foreign-object (,errorvar :int)
     (when (< (progn ,@body) 0)
       (error 'pulse-error :code (cffi:mem-ref ,errorvar :int)))))

(defun pulse-present-p ()
  (handler-case (cffi:use-foreign-library pulse:libpulse)
    (error () (return-from pulse-present-p NIL)))
  (cffi:with-foreign-object (err :int)
    (let ((drain (pulse:simple-new
                  (cffi:null-pointer) (cffi:null-pointer)
                  :playback (cffi:null-pointer) (cffi:null-pointer)
                  (cffi:null-pointer) (cffi:null-pointer) (cffi:null-pointer)
                  err)))
      (cond ((cffi:null-pointer-p drain)
             NIL)
            (T
             (pulse:simple-free drain)
             T)))))

(defclass drain (mixed:drain)
  ((simple :initform NIL :accessor simple)
   (server :initform NIL :initarg :server :accessor server)))

(defmethod initialize-instance :after ((drain drain) &key)
  (cffi:use-foreign-library pulse:libpulse)
  (cffi:use-foreign-library pulse:libpulse-simple))

(defmethod mixed:start ((drain drain))
  (unless (simple drain)
    (let ((pack (mixed:pack drain)))
      (cffi:with-foreign-object (sample-spec '(:struct pulse:sample-spec))
        (setf (pulse:sample-spec-format sample-spec) :float)
        (setf (pulse:sample-spec-rate sample-spec) (mixed:samplerate pack))
        (setf (pulse:sample-spec-channels sample-spec) (mixed:channels pack))
        (with-error (error)
          (setf (simple drain) (pulse:simple-new
                                (or (server drain) (cffi:null-pointer)) (mixed:program-name drain)
                                :playback (cffi:null-pointer) (mixed:program-name drain)
                                sample-spec (cffi:null-pointer) (cffi:null-pointer)
                                error))
          (if (cffi:null-pointer-p (simple drain)) -1 1))
        (setf (mixed:samplerate pack) (pulse:sample-spec-rate sample-spec))
        (setf (mixed:encoding pack) (pulse:sample-spec-format sample-spec))
        (setf (mixed:channels pack) (pulse:sample-spec-channels sample-spec))))))

(defmethod mixed:mix ((drain drain))
  (mixed:with-buffer-tx (data start end (mixed:pack drain))
    (with-error (err)
      (pulse:simple-write (simple drain) (mixed:data-ptr) (- end start) err))
    (mixed:finish (- end start))))

(defmethod mixed:end ((drain drain))
  (when (simple drain)
    (with-error (err)
      (pulse:simple-drain (simple drain) err))
    (pulse:simple-free (simple drain))
    (setf (simple drain) NIL)))
