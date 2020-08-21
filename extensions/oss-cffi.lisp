#|
 This file is a part of cl-mixed
 (c) 2017 Shirakumo http://tymoon.eu (shinmera@tymoon.eu)
 Author: Nicolas Hafner <shinmera@tymoon.eu>
|#

(in-package #:cl-user)
(defpackage #:org.shirakumo.fraf.mixed.oss.cffi
  (:use #:cl #:cffi)
  (:export
   #:encoding
   #:open-flag
   #:ioctl
   #:fd-open
   #:fd-close
   #:fd-write))
(in-package #:org.shirakumo.fraf.mixed.oss.cffi)

(defctype size_t #+x86-64 :uint64 #+x86 :uint32)
(defctype ssize_t #+x86-64 :int64 #+x86 :int32)

(cffi:defcenum encoding
  (:int8   #x00000040)
  (:uint8  #x00000008)
  (:int16  #x00000010)
  (:uint16 #x00000080)
  (:int24  #x00008000)
  (:uint24 #x00008000) ; doesn't exist (?)
  (:int32  #x00001000)
  (:uint32 #x00001000) ; doesn't exist (?)
  (:float  #x00004000)
  (:double  #x00004000)) ; doesn't exist (?)

(cffi:defcfenum open-flag
  (:write-only 1))

(cffi:defcenum ioctl
  (:sndctl-dsp-setfmt   #xC0045005)
  (:sndctl-dsp-channels #xC0045006)
  (:sndctl-dsp-speed    #xC0045002))

(cffi:defcfun (ioctl "ioctl") :int
  (fd :int)
  (request ioctl)
  &rest)

(cffi:defcfun (fd-open "open") :int
  (path :string)
  (flags open-flag)
  &rest)

(cffi:defcfun (fd-close "close") :int
  (fd :int))

(cffi:defcfun (fd-write "write") ssize_t
  (fd :int)
  (buf :pointer)
  (bytes size_t))