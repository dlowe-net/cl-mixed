#|
 This file is a part of cl-mixed
 (c) 2017 Shirakumo http://tymoon.eu (shinmera@tymoon.eu)
 Author: Nicolas Hafner <shinmera@tymoon.eu>
|#

(defpackage #:org.shirakumo.fraf.mixed.out123
  (:use #:cl)
  (:local-nicknames
   (#:mixed #:org.shirakumo.fraf.mixed)
   (#:mixed-cffi #:org.shirakumo.fraf.mixed.cffi)
   (#:out123 #:org.shirakumo.fraf.out123))
  (:export
   #:drain))
(in-package #:org.shirakumo.fraf.mixed.out123)

(defclass drain (mixed:drain)
  ((out :initform (out123:make-output NIL) :accessor out)))

(defmethod initialize-instance :after ((drain drain) &key)
  (setf (mixed-cffi:direct-segment-mix (mixed:handle drain)) (cffi:callback mix)))

(defmethod mixed:start ((drain drain))
  (let ((pack (mixed:pack drain)))
    (out123:connect (out drain))
    (out123:start (out drain) :rate (mixed:samplerate pack) :channels (mixed:channels pack) :encoding :float)
    (setf (mixed:samplerate pack) (out123:rate (out drain)))
    (setf (mixed:encoding pack) (out123:encoding (out drain)))
    (setf (mixed:channels pack) (out123:channels (out drain)))))

(cffi:defcallback mix :int ((segment :pointer))
  (let ((drain (mixed:pointer->object segment)))
    (mixed:with-buffer-tx (data start end (mixed:pack drain))
      (mixed:finish (out123:play-directly (out drain) (mixed:data-ptr) (- end start))))
    1))

(defmethod mixed:end ((drain drain))
  (out123:stop (out drain))
  (out123:disconnect (out drain)))
