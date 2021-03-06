;;;; base16.lisp -- The base16 encoding, formalized in RFC 3548 and RFC 4648.

(cl:in-package :binascii)

(defvar *hex-encode-table*
  #.(coerce "0123456789abcdef" 'simple-base-string))
(defvar *base16-encode-table*
  #.(coerce "0123456789ABCDEF" 'simple-base-string))

(defvar *base16-decode-table*
  (make-decode-table *base16-encode-table*))
(declaim (type decode-table *base16-decode-table*))

(defstruct (base16-encode-state
             (:include encode-state)
             (:copier nil)
             (:predicate nil)
             (:constructor make-base16-encode-state
                           (&aux (descriptor (base16-format-descriptor))
                                 (table *base16-encode-table*)))
             (:constructor make-hex-encode-state
                           (&aux (descriptor (base16-format-descriptor))
                                 (table *hex-encode-table*))))
  (bits 0 :type (unsigned-byte 8))
  (n-bits 0 :type fixnum)
  (table *base16-encode-table* :read-only t
         :type (simple-array base-char (16))))

(declaim (inline base16-encoder))
(defun base16-encoder (state output input
                       output-index output-end
                       input-index input-end lastp converter)
  (declare (type base16-encode-state state))
  (declare (type simple-octet-vector input))
  (declare (type index output-index output-end input-index input-end))
  (declare (type function converter))
  (let ((bits (base16-encode-state-bits state))
        (n-bits (base16-encode-state-n-bits state))
        (table (base16-encode-state-table state)))
    (declare (type index input-index output-index))
    (declare (type (unsigned-byte 8) bits))
    (declare (type fixnum n-bits))
    (tagbody
     PAD-CHECK
       (when (base16-encode-state-finished-input-p state)
         (go FLUSH-BITS))
     INPUT-CHECK
       (when (>= input-index input-end)
         (go DONE))
     DO-INPUT
       (when (zerop n-bits)
         (setf bits (aref input input-index))
         (incf input-index)
         (setf n-bits 8))
     OUTPUT-CHECK
       (when (>= output-index output-end)
         (go DONE))
     DO-OUTPUT
       (decf n-bits 4)
       (setf (aref output output-index)
             (funcall converter (aref table (ldb (byte 4 n-bits) bits))))
       (incf output-index)
       (if (>= n-bits 4)
           (go OUTPUT-CHECK)
           (go INPUT-CHECK))
     DONE
       (unless lastp
         (go RESTORE-STATE))
       (setf (base16-encode-state-finished-input-p state) t)
     FLUSH-BITS
       (when (zerop n-bits)
         (go RESTORE-STATE))
     FLUSH-OUTPUT-CHECK
       (when (>= output-index output-end)
         (go RESTORE-STATE))
     DO-FLUSH-OUTPUT
       (decf n-bits 4)
       (setf (aref output output-index)
             (funcall converter (aref table (ldb (byte 4 n-bits) bits))))
       (incf output-index)
       (when (= n-bits 4)
         (go FLUSH-OUTPUT-CHECK))
     RESTORE-STATE
       (setf (base16-encode-state-bits state) bits
             (base16-encode-state-n-bits state) n-bits))
    (values input-index output-index)))

(defun encoded-length-base16 (count)
  "Return the number of characters required to encode COUNT octets in Base16."
  (* count 2))

(defun base16-decode-table (case-fold)
  (if case-fold
      (case-fold-decode-table *base16-decode-table*
                              *base16-encode-table*)
      *base16-decode-table*))

(defstruct (base16-decode-state
             (:include decode-state)
             (:copier nil)
             (:predicate nil)
             (:constructor %make-base16-decode-state
                           (table
                            &aux (descriptor (base16-format-descriptor)))))
  (bits 0 :type (unsigned-byte 8))
  (n-bits 0 :type fixnum)
  (table *base16-decode-table* :read-only t :type decode-table))

(defun make-base16-decode-state (case-fold map01)
  (declare (ignore map01))
  (%make-base16-decode-state (base16-decode-table case-fold)))

(defun make-hex-decode-state (case-fold map01)
  (declare (ignore case-fold map01))
  (%make-base16-decode-state (base16-decode-table t)))

(defun base16-decoder (state output input
                       output-index output-end
                       input-index input-end lastp converter)
  (declare (type base16-decode-state state))
  (declare (type simple-octet-vector output))
  (declare (type index output-index output-end input-index input-end))
  (declare (type function converter))
  (let ((bits (base16-decode-state-bits state))
        (n-bits (base16-decode-state-n-bits state))
        (table (base16-decode-state-table state)))
    (declare (type (unsigned-byte 8) bits))
    (tagbody
     START
       (when (base16-decode-state-finished-input-p state)
         (go FLUSH-BITS))
     OUTPUT-AVAILABLE-CHECK
       (when (< n-bits 8)
         (go INPUT-AVAILABLE-CHECK))
     OUTPUT-SPACE-CHECK
       (when (>= output-index output-end)
         (go DONE))
     DO-OUTPUT
       (setf (aref output output-index) bits
             bits 0
             n-bits 0)
       (incf output-index)
       (go INPUT-AVAILABLE-CHECK)
     INPUT-AVAILABLE-CHECK
       (when (>= input-index input-end)
         (go DONE))
     DO-INPUT
       (assert (< n-bits 8))
       (let* ((v (aref input input-index))
              (c (dtref table (funcall converter v))))
         (when (= c +dt-invalid+)
           (error "invalid hex digit ~A at position ~D" v input-index))
         (incf input-index)
         (cond
           ((= n-bits 0)
            (setf bits (* (logand c #xf) 16)
                  n-bits 4)
            (go INPUT-AVAILABLE-CHECK))
           ((= n-bits 4)
            (setf bits (+ bits (logand c #xf))
                  n-bits 8)
            (go OUTPUT-SPACE-CHECk))))
     DONE
       (unless lastp
         (go RESTORE-STATE))
       (setf (base16-decode-state-finished-input-p state) t)
     FLUSH-BITS
       (when (zerop n-bits)
         (go RESTORE-STATE))
     FLUSH-OUTPUT-CHECK
       (when (>= output-index output-end)
         (go RESTORE-STATE))
     DO-FLUSH-OUTPUT
       (when (= n-bits 4)
         (error "attempting to decode an odd number of hex digits"))
       (setf (aref output output-index) bits
             bits 0
             n-bits 0)
     RESTORE-STATE
       (setf (base16-decode-state-n-bits state) n-bits
             (base16-decode-state-bits state) bits))
    (values input-index output-index)))

(defun decoded-length-base16 (length)
  (unless (evenp length)
    (error "cannot decode an odd number of base16 characters"))
  (truncate length 2))

(define-format :base16
  :encode-state-maker make-base16-encode-state
  :decode-state-maker make-base16-decode-state
  :encode-length-fun encoded-length-base16
  :decode-length-fun decoded-length-base16
  :encoder-fun base16-encoder
  :decoder-fun base16-decoder)
(define-format :hex
  :encode-state-maker make-hex-encode-state
  :decode-state-maker make-hex-decode-state
  :encode-length-fun encoded-length-base16
  :decode-length-fun decoded-length-base16
  :encoder-fun base16-encoder
  :decoder-fun base16-decoder)
