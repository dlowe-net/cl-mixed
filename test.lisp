(ql:quickload '(cl-mixed clout123 cl-mpg123))

(defpackage #:org.shirakumo.fraf.mixed.examples
  (:use #:cl)
  (:local-nicknames
   (#:mixed #:org.shirakumo.fraf.mixed)
   (#:out123 #:org.shirakumo.fraf.out123)
   (#:mpg123 #:org.shirakumo.fraf.mpg123)))

(in-package #:org.shirakumo.fraf.mixed.examples)

;;; Shorthand stuff to set up the audio system
(defun call-with-out (function rate channels encoding)
  (let ((out  (out123:connect (out123:make-output NIL))))
    (format T "~&Playback device ~a / ~a" (out123:driver out) (out123:device out))
    (out123:start out :rate rate :channels channels :encoding encoding)
    (unwind-protect
         (funcall function out)
      (out123:stop out)
      (out123:disconnect out))))

(defmacro with-out ((out &key (rate 44100) (channels 2) (encoding :float)) &body body)
  `(call-with-out (lambda (,out) ,@body) ,rate ,channels ,encoding))

(defun call-with-mp3 (function pathname samples)
  (let* ((file (mpg123:connect (mpg123:make-file pathname :buffer-size NIL))))
    (multiple-value-bind (rate channels encoding) (mpg123:file-format file)
      (format T "~&Input format ~a Hz ~a channels ~a encoded." rate channels encoding)
      (setf (mpg123:buffer-size file) (* samples channels (mixed:samplesize encoding)))
      (setf (mpg123:buffer file) (cffi:foreign-alloc :uchar :count (mpg123:buffer-size file)))
      (unwind-protect
           (funcall function file rate channels encoding)
        (mpg123:disconnect file)
        (cffi:foreign-free (mpg123:buffer file))))))

(defmacro with-mp3 ((file rate channels encoding &key pathname samples) &body body)
  `(call-with-mp3 (lambda (,file ,rate ,channels ,encoding) ,@body) ,pathname ,samples))

(defmacro with-edge-setup ((file out rate &key pathname samples) &body body)
  (let ((channels (gensym "CHANNELS"))
        (encoding (gensym "ENCODING")))
    `(with-mp3 (,file ,rate ,channels ,encoding :pathname ,pathname :samples ,samples)
       (with-out (,out :rate ,rate :channels ,channels :encoding ,encoding)
         ,@body))))

(defun play (file out sequence samples)
  (let* ((buffer (mpg123:buffer file))
         (buffersize (mpg123:buffer-size file))
         (read (mpg123:process file)))
    (loop for i from read below buffersize
          do (setf (cffi:mem-aref buffer :uchar i) 0))
    (mixed:mix samples sequence)
    (let ((played (out123:play out buffer buffersize)))
      (when (/= played read)
        (format T "~&Playback is not catching up with input by ~a bytes."
                (- read played))))
    (/= 0 read)))

;;; Test for the 3d audio space segment
(defun test-space (mp3 &key (samples 500) (width 100) (height 50) (speed 0.001))
  (with-edge-setup (file out samplerate :pathname mp3 :samples samples)
    (let* ((source (mixed:make-unpacker (mpg123:buffer file)
                                           (mpg123:buffer-size file)
                                           (mpg123:encoding file)
                                           (mpg123:channels file)
                                           :alternating
                                           samplerate))
           (drain (mixed:make-packer (mpg123:buffer file)
                                        (mpg123:buffer-size file)
                                        (out123:encoding out)
                                        (out123:channels out)
                                        :alternating
                                        samplerate))
           (space (mixed:make-space-mixer :samplerate samplerate))
           (sequence (mixed:make-segment-sequence source space drain)))
      (mixed:with-buffers samples (li ri lo ro)
        (mixed:connect source :left space 0 li)
        (setf (mixed:output :right source) ri)
        (mixed:connect space :left drain :left lo)
        (mixed:connect space :right drain :right ro)
        (mixed:start sequence)
        (unwind-protect
             (loop for tt = 0 then (+ tt speed)
                   for dx = 0 then (- (* width (sin tt)) x)
                   for dz = 0 then (- (* height (cos tt)) z)
                   for x = (* width (sin tt)) then (+ x dx)
                   for z = (* height (cos tt)) then (+ z dz)
                   do (setf (mixed:input-field :location 0 space) (list x 0 z))
                      (setf (mixed:input-field :velocity 0 space) (list dx 0 dz))
                   while (play file out sequence samples))
          (mixed:end sequence))))))

;;; Test for a simple tone generator
(defun test-tone (tones &key (type :sine))
  (with-out (out)
    (multiple-value-bind (rate channels encoding) (out123:playback-format out)
      (let* ((generator (mixed:make-generator :type type))
             (drain (mixed:make-packer 100 encoding channels rate))
             (sequence (mixed:make-segment-sequence generator drain)))
        (mixed:with-buffers 100 (mono)
          (dotimes (i channels)
            (mixed:connect generator :mono drain i mono))
          (mixed:start sequence)
          (unwind-protect
               (loop with samples = 0
                     for time = 0.0 then (+ time (/ samples rate))
                     while tones
                     do (setf (mixed:frequency generator)
                              (ecase (second tones)
                                (_    0.0)
                                (C4   261.63)
                                ( C#4 277.18)
                                (D4   293.66)
                                ( D#4 311.13)
                                (E4   329.63)
                                (F4   349.23)
                                ( F#4 369.99)
                                (G4   392.00)
                                ( G#4 415.30)
                                (A4   440.00)
                                ( A#4 466.16)
                                (B4   493.88)
                                (C5   523.25)
                                ( C#5 554.37)
                                (D5   587.33)
                                ( D#5 622.25)
                                (E5   659.25)
                                (F5   698.46)))
                        (mixed:mix sequence)
                        (mixed:with-buffer-tx (data start end (pack drain))
                          (setf samples (out123:play out (mixed:data-ptr) (- end start)))
                          (mixed:finish samples))
                        (when (<= (first tones) time)
                          (pop tones) (pop tones)))
            (mixed:end sequence)))))))

;;; Test for a custom audio filter
(defclass echo (mixed:virtual)
  ((buffer :initform NIL :accessor buffer)
   (offset :initform 0 :accessor offset)
   (delay :initarg :delay :initform 0.2 :accessor delay)
   (falloff :initarg :falloff :initform 0.8 :accessor falloff)
   (samplerate :initarg :samplerate :initform 44100 :accessor samplerate)))

(defmethod mixed:start ((echo echo))
  (setf (buffer echo) (make-array (ceiling (* (delay echo) (samplerate echo)))
                                  :element-type 'single-float
                                  :initial-element 0.0f0)))

(defmethod mixed:mix (samples (echo echo))
  (let ((out (mixed:data (aref (mixed:outputs echo) 0)))
        (in (mixed:data (aref (mixed:inputs echo) 0)))
        (buf (buffer echo))
        (offset (offset echo))
        (falloff (falloff echo)))
    (declare (type cffi:foreign-pointer in out))
    ;; Mix
    (loop for i from 0 below samples
          for sample = (cffi:mem-aref in :float i)
          for echo = (aref buf offset)
          do (setf (cffi:mem-aref out :float i) (+ sample echo))
             (setf (aref buf offset) (* (+ sample echo) falloff))
             (setf offset (mod (1+ offset) (length buf))))
    (setf (offset echo) offset)
    T))

(defun test-echo (mp3 &key (samples 500) (delay 0.2) (falloff 0.8))
  (with-edge-setup (file out samplerate :pathname mp3 :samples samples)
    (let* ((source (mixed:make-unpacker (mpg123:buffer file)
                                           (mpg123:buffer-size file)
                                           (mpg123:encoding file)
                                           (mpg123:channels file)
                                           :alternating
                                           samplerate))
           (drain (mixed:make-packer (mpg123:buffer file)
                                        (mpg123:buffer-size file)
                                        (out123:encoding out)
                                        (out123:channels out)
                                        :alternating
                                        samplerate))
           (echo (make-instance 'echo :samplerate samplerate :falloff falloff :delay delay))
           (sequence (mixed:make-segment-sequence source echo drain)))
      (mixed:with-buffers samples (li ri lo ro)
        (mixed:connect source :left echo 0 li)
        (setf (mixed:output :right source) ri)
        (mixed:connect echo :left drain :left lo)
        (mixed:connect echo :right drain :right ro)
        (mixed:start sequence)
        (unwind-protect
             (loop while (play file out sequence samples))
          (mixed:end sequence))))))
