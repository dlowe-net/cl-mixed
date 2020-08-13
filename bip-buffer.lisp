#|
This file is a part of cl-mixed
(c) 2017 Shirakumo http://tymoon.eu (shinmera@tymoon.eu)
Author: Nicolas Hafner <shinmera@tymoon.eu>
|#

(in-package #:org.shirakumo.fraf.mixed)

(defclass bip-buffer ()
  ())

(declaim (inline free-for-r2 free-after-r1))
(defun free-for-r2 (handle)
  (declare (optimize speed))
  (- (mixed:buffer-r1-start handle)
     (mixed:buffer-r2-start handle)
     (mixed:buffer-r2-size handle)))

(defun free-after-r1 (handle)
  (declare (optimize speed))
  (- (mixed:buffer-size handle)
     (mixed:buffer-r1-start handle)
     (mixed:buffer-r1-size handle)))

(defun available-read (buffer)
  (declare (optimize speed))
  (mixed:buffer-r1-size (handle buffer)))

(defun available-write (buffer)
  (declare (optimize speed))
  (let ((buffer (handle buffer)))
    (if (< 0 (mixed:buffer-r2-size buffer))
        (free-for-r2 buffer)
        (free-after-r1 buffer))))

(defun request-write (buffer size)
  (declare (optimize speed))
  (declare (type (unsigned-byte 32) size))
  (let ((buffer (handle buffer)))
    (cond ((< 0 (mixed:buffer-r2-size buffer))
           (let ((free (min size (free-for-r2 buffer)))
                 (start (+ (mixed:buffer-r2-start buffer) (mixed:buffer-r2-size buffer))))
             (setf (mixed:buffer-reserved-size buffer) free)
             (setf (mixed:buffer-reserved-start buffer) start)
             (values start (+ free start))))
          ((<= (mixed:buffer-r1-start buffer) (free-after-r1 buffer))
           (let ((free (min size (free-after-r1 buffer)))
                 (start (+ (mixed:buffer-r1-start buffer) (mixed:buffer-r1-size buffer))))
             (setf (mixed:buffer-reserved-size buffer) free)
             (setf (mixed:buffer-reserved-start buffer) start)
             (values start (+ start free))))
          (T
           (let ((free (min size (mixed:buffer-r1-start buffer))))
             (values (setf (mixed:buffer-reserved-start buffer) 0)
                     free))))))

(defun finish-write (buffer size)
  (declare (optimize speed))
  (declare (type (unsigned-byte 32) size))
  (let ((buffer (handle buffer)))
    (when (< size (mixed:buffer-reserved-size buffer))
      (error "Cannot commit more than was allocated."))
    (cond ((= 0 size))
          ((and (= 0 (mixed:buffer-r1-size buffer))
                (= 0 (mixed:buffer-r2-size buffer)))
           (setf (mixed:buffer-r1-start buffer) (mixed:buffer-r2-start buffer))
           (setf (mixed:buffer-r1-size buffer) size))
          ((= (mixed:buffer-reserved-start buffer) (+ (mixed:buffer-r1-start buffer) (mixed:buffer-r1-size buffer)))
           (incf (mixed:buffer-r1-size buffer) size))
          (T
           (incf (mixed:buffer-r2-size buffer) size)))
    (setf (mixed:buffer-reserved-size buffer) 0)
    (setf (mixed:buffer-reserved-start buffer) 0)))

(defun request-read (buffer size)
  (declare (optimize speed))
  (declare (type (unsigned-byte 32) size))
  (let ((buffer (handle buffer)))
    (values (mixed:buffer-r1-start buffer)
            (min size (mixed:buffer-r1-size buffer)))))

(defun finish-read (buffer size)
  (declare (optimize speed))
  (declare (type (unsigned-byte 32) size))
  (let ((buffer (handle buffer)))
    (when (< (mixed:buffer-r1-size buffer) size)
      (error "Cannot commit more than was available."))
    (cond ((= (mixed:buffer-r1-size buffer) size)
           (shiftf (mixed:buffer-r1-start buffer) (mixed:buffer-r2-start buffer) 0)
           (shiftf (mixed:buffer-r1-size buffer) (mixed:buffer-r2-size buffer) 0))
          (T
           (decf (mixed:buffer-r1-size buffer) size)
           (incf (mixed:buffer-r1-start buffer) size)))))

(declaim (inline data-ptr))
(defun data-ptr (data &optional (start 0))
  (static-vectors:static-vector-pointer data :offset start))

(defmacro with-buffer-tx ((data start end buffer &key (direction :input) (size #xFFFFFFFF)) &body body)
  (let ((bufferg (gensym "BUFFER"))
        (sizeg (gensym "SIZE"))
        (handle (gensym "HANDLE")))
    `(let* ((,bufferg ,buffer)
            (,data (data ,bufferg)))
       ,(ecase direction
          ((:input :read)
           `(multiple-value-bind (,start ,end) (request-read ,bufferg ,size)
              (declare (ignorable ,start ,end))
              (flet ((finish (,sizeg) (finish-read ,bufferg ,sizeg))
                     (data-ptr (&optional (,data ,data) (,start ,start)) (data-ptr ,data ,start)))
                (declare (ignorable #'finish #'data-ptr))
                ,@body)))
          ((:output :write)
           `(multiple-value-bind (,start ,end) (request-write ,bufferg ,size)
              (declare (ignorable ,start ,end))
              (flet ((finish (,sizeg) (finish-write ,bufferg ,sizeg))
                     (data-ptr (&optional (,data ,data) (,start ,start)) (data-ptr ,data ,start)))
                (declare (ignorable #'finish #'data-ptr))
                (unwind-protect
                     (progn ,@body)
                  (let ((,handle (handle ,buffer)))
                    (setf (mixed:buffer-reserved-size ,handle) 0)
                    (setf (mixed:buffer-reserved-start ,handle) 0))))))))))

(defmacro with-buffer-transfer ((fdata fstart from) (tdata tstart to) size &body body)
  (let ((fromg (gensym "FROM"))
        (tog (gensym "TO"))
        (tend (gensym "TEND"))
        (fend (gensym "FEND")))
    `(let* ((,fromg ,from)
            (,tog ,to))
       (if (eq ,fromg ,tog)
           (multiple-value-bind (,fstart ,fend) (request-read ,fromg #xFFFFFFFF)
             (let* ((,tstart ,fstart)
                    (,fdata (data ,fromg))
                    (,tdata ,fdata)
                    (,size (- ,fend ,fstart)))
               (flet ((finish (,size) (declare (ignore ,size))))
                 ,@body)))
           (with-buffer-tx (,fdata ,fstart ,fend ,fromg :direction :read)
             (let ((,size (- ,fend ,fstart)))
               (with-buffer-tx (,tdata ,tstart ,tend ,tog :direction :write :size ,size)
                 (setf ,size (- ,tend ,tstart))
                 (flet ((finish (,size)
                          (finish-read ,fromg ,size)
                          (finish-write ,tog ,size)))
                   (declare (ignorable #'finish))
                   ,@body))))))))
