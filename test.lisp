(ql:quickload '(cl-mixed cl-out123 cl-mpg123))

;;; Shorthand stuff to set up the audio system
(defun call-with-out (function rate channels encoding)
  (let ((out  (cl-out123:connect (cl-out123:make-output NIL))))
    (format T "~&Playback device ~a / ~a" (cl-out123:driver out) (cl-out123:device out))
    (cl-out123:start out :rate rate :channels channels :encoding encoding)
    (unwind-protect
         (funcall function out)
      (cl-out123:stop out)
      (cl-out123:disconnect out))))

(defmacro with-out ((out &key (rate 44100) (channels 2) (encoding :float)) &body body)
  `(call-with-out (lambda (,out) ,@body) ,rate ,channels ,encoding))

(defun call-with-mp3 (function pathname samples)
  (let* ((file (cl-mpg123:connect (cl-mpg123:make-file pathname :buffer-size NIL))))
    (multiple-value-bind (rate channels encoding) (cl-mpg123:file-format file)
      (format T "~&Input format ~a Hz ~a channels ~a encoded." rate channels encoding)
      (setf (cl-mpg123:buffer-size file) (* samples channels (cl-mixed:samplesize encoding)))
      (setf (cl-mpg123:buffer file) (cffi:foreign-alloc :uchar :count (cl-mpg123:buffer-size file)))
      (unwind-protect
           (funcall function file rate channels encoding)
        (cl-mpg123:disconnect file)
        (cffi:foreign-free (cl-mpg123:buffer file))))))

(defmacro with-mp3 ((file rate channels encoding &key pathname samples) &body body)
  `(call-with-mp3 (lambda (,file ,rate ,channels ,encoding) ,@body) ,pathname ,samples))

(defmacro with-edge-setup ((file out rate &key pathname samples) &body body)
  (let ((channels (gensym "CHANNELS"))
        (encoding (gensym "ENCODING")))
    `(with-mp3 (,file ,rate ,channels ,encoding :pathname ,pathname :samples ,samples)
       (with-out (,out :rate ,rate :channels ,channels :encoding ,encoding)
         ,@body))))

(defun play (file out mixer samples)
  (let* ((buffer (cl-mpg123:buffer file))
         (buffersize (cl-mpg123:buffer-size file))
         (read (cl-mpg123:process file)))
    (loop for i from read below buffersize
          do (setf (cffi:mem-aref buffer :uchar i) 0))
    (cl-mixed:mix samples mixer)
    (let ((played (cl-out123:play out buffer buffersize)))
      (when (/= played read)
        (format T "~&Playback is not catching up with input by ~a bytes."
                (- read played))))
    (/= 0 read)))

;;; Test for the 3d audio space segment
(defun test-space (mp3 &key (samples 500) (width 100) (height 50) (speed 0.001))
  (with-edge-setup (file out samplerate :pathname mp3 :samples samples)
    (let* ((source (cl-mixed:make-source (cl-mpg123:buffer file)
                                         (cl-mpg123:buffer-size file)
                                         (cl-mpg123:encoding file)
                                         (cl-mpg123:channels file)
                                         :alternating
                                         samplerate))
           (drain (cl-mixed:make-drain (cl-mpg123:buffer file)
                                       (cl-mpg123:buffer-size file)
                                       (cl-out123:encoding out)
                                       (cl-out123:channels out)
                                       :alternating
                                       samplerate))
           (space (make-instance 'cl-mixed:space :samplerate samplerate))
           (mixer (cl-mixed:make-mixer source space drain)))
      (cl-mixed:with-buffers samples (li ri lo ro)
        (cl-mixed:connect source :left space 0 li)
        (setf (cl-mixed:output :right source) ri)
        (cl-mixed:connect space :left drain :left lo)
        (cl-mixed:connect space :right drain :right ro)
        (cl-mixed:start mixer)
        (unwind-protect
             (loop for tt = 0 then (+ tt speed)
                   for dx = 0 then (- (* width (sin tt)) x)
                   for dz = 0 then (- (* height (cos tt)) z)
                   for x = (* width (sin tt)) then (+ x dx)
                   for z = (* height (cos tt)) then (+ z dz)
                   do (setf (cl-mixed:input-field :location 0 space) (list x 0 z))
                      (setf (cl-mixed:input-field :velocity 0 space) (list dx 0 dz))
                   while (play file out mixer samples))
          (cl-mixed:end mixer))))))

;;; Test for a simple tone generator
(defun test-tone (tones &key (samples 50) (type :sine))
  (with-out (out)
    (multiple-value-bind (rate channels encoding) (cl-out123:playback-format out)
      (let* ((buffersize (* samples channels (cl-mixed:samplesize encoding)))
             (buffer (cffi:foreign-alloc :uint8 :count buffersize))
             (generator (cl-mixed:make-generator :type type))
             (drain (cl-mixed:make-drain buffer buffersize encoding channels :alternating rate))
             (mixer (cl-mixed:make-mixer generator drain)))
        (cl-mixed:with-buffers samples (mono)
          (dotimes (i channels)
            (cl-mixed:connect generator :mono drain i mono))
          (cl-mixed:start mixer)
          (unwind-protect
               (loop for time = 0.0 then (+ time (/ samples rate))
                     while tones
                     do (setf (cl-mixed:frequency generator)
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
                        (cl-mixed:mix samples mixer)
                        (cl-out123:play out buffer buffersize)
                        (when (<= (first tones) time)
                          (pop tones) (pop tones)))))))))

;;; Test for a custom audio filter
(defclass echo (cl-mixed:virtual)
  ((buffer :initform NIL :accessor buffer)
   (offset :initform 0 :accessor offset)
   (delay :initarg :delay :initform 0.2 :accessor delay)
   (falloff :initarg :falloff :initform 0.8 :accessor falloff)
   (samplerate :initarg :samplerate :initform 44100 :accessor samplerate)))

(defmethod cl-mixed:start ((echo echo))
  (setf (buffer echo) (make-array (ceiling (* (delay echo) (samplerate echo)))
                                  :element-type 'single-float
                                  :initial-element 0.0s0)))

(defmethod cl-mixed:mix (samples (echo echo))
  (let ((out (cl-mixed:data (aref (cl-mixed:outputs echo) 0)))
        (in (cl-mixed:data (aref (cl-mixed:inputs echo) 0)))
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
    (setf (offset echo) offset)))

(defun test-echo (mp3 &key (samples 500) (delay 0.2) (falloff 0.8))
  (with-edge-setup (file out samplerate :pathname mp3 :samples samples)
    (let* ((source (cl-mixed:make-source (cl-mpg123:buffer file)
                                         (cl-mpg123:buffer-size file)
                                         (cl-mpg123:encoding file)
                                         (cl-mpg123:channels file)
                                         :alternating
                                         samplerate))
           (drain (cl-mixed:make-drain (cl-mpg123:buffer file)
                                       (cl-mpg123:buffer-size file)
                                       (cl-out123:encoding out)
                                       (cl-out123:channels out)
                                       :alternating
                                       samplerate))
           (echo (make-instance 'echo :samplerate samplerate :falloff falloff :delay delay))
           (mixer (cl-mixed:make-mixer source echo drain)))
      (cl-mixed:with-buffers samples (li ri lo ro)
        (cl-mixed:connect source :left echo 0 li)
        (setf (cl-mixed:output :right source) ri)
        (cl-mixed:connect echo :left drain :left lo)
        (cl-mixed:connect echo :right drain :right ro)
        (cl-mixed:start mixer)
        (unwind-protect
             (loop while (play file out mixer samples))
          (cl-mixed:end mixer))))))