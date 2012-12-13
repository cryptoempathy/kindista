(in-package :kindista)

(defun strcat (&rest items)
  (format nil "~{~A~}" items))

(defmacro s+ (&rest strings)
  `(concatenate 'string ,@strings))

(defmacro with-file-lock ((path &key interval) &body body)
  "Get an exclusive lock on a file. If lock cannot be obtained, keep
   trying after waiting a while"
  (let ((lock-path (gensym))
        (lock-file (gensym)))
    `(let ((,lock-path (format nil "~a.lock" (namestring ,path))))
       (unwind-protect
         (progn
           (loop
             :for ,lock-file = (open ,lock-path :direction :output
                                     :if-exists nil
                                     :if-does-not-exist :create)
             :until ,lock-file
             :do (sleep ,(or interval 0.1))
             :finally (close ,lock-file))
           ,@body)
         (ignore-errors
           (delete-file ,lock-path))))))

(defmacro html (&body body)
  (let ((sym (gensym)))
    `(with-html-output-to-string (,sym)
       ,@body)))

(defmacro asetf (place value)
  `(anaphora::symbolic setf ,place ,value))

(defun sublist (list &optional start length)
  (when start
    (dotimes (i start)
      (setf list (cdr list))))
  (if length
    (when list
      (iter (for i from 1 to length)
            (collect (car list))
            (if (cdr list)
              (setf list (cdr list))
              (finish))))
    (copy-list list)))

(defun intersection-fourth (list1 list2)
  (intersection list1 list2 :key #'fourth))

(defun string-intersection (list1 list2)
  (intersection list1 list2 :test #'string=))

(defun activity-rank (item)
  ; is it from a friend?
  ; how many people like it
  ; how recent
  ; how close is it?
  
  (let ((friends (getf *user* :following))
        (age (- (get-universal-time) (first item)))
        (distance (air-distance (getf *user* :lat) (getf *user* :long)
                                (second item) (third item))))
    (round (- age
             (/ 120000 (log (+ distance 4)))
             (if (intersection friends (fifth item)) 86400 0)
             (* (length (loves (fourth item))) 100000)))))

(defun resource-rank (item)
  (let ((age (- (get-universal-time) (first item)))
        (loves (max 1 (length (loves (fourth item))))))
    (* (/ 50 (log (+ (/ age 86400) 6)))
       (expt loves 0.3))))

(defun inline-timestamp (time &key type url)
  (let ((inner (html
                 (when type
                   (htm (str type) " "))
                 (str (humanize-universal-time time)))))
    (html
      (:span :class "timestamp" :data-time time :data-type type
        (if url
          (htm (:a :href url (str inner)))
          (str inner))))))
