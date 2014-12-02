;;; Copyright 2012-2014 CommonGoods Network, Inc.
;;;
;;; This file is part of Kindista.
;;;
;;; Kindista is free software: you can redistribute it and/or modify it
;;; under the terms of the GNU Affero General Public License as published
;;; by the Free Software Foundation, either version 3 of the License, or
;;; (at your option) any later version.
;;;
;;; Kindista is distributed in the hope that it will be useful, but WITHOUT
;;; ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
;;; FITNESS FOR A PARTICULAR PURPOSE.  See the GNU Affero General Public
;;; License for more details.
;;;
;;; You should have received a copy of the GNU Affero General Public License
;;; along with Kindista.  If not, see <http://www.gnu.org/licenses/>.

(in-package :kindista)

(defun broadcast-email-notice-handler ()
  (let ((notice (cddddr *notice*)))
    (send-broadcast-email (getf notice :broadcast-id)
                          (getf notice :user-id))))

(defun send-broadcast-email (broadcast-id user-id)
  (let ((data (db user-id)))
    (when (getf data :notify-kindista)
      (let* ((name (getf data :name))
             (email (first (getf data :emails)))
             (unsubscribe (getf data :unsubscribe-key))
             (broadcast (db broadcast-id))
             (author-email (car (db (getf broadcast :author) :emails)))
             (amazon-smile-p (getf broadcast :amazon-smile-p))
             (broadcast-path (s+ *broadcast-path* (getf broadcast :path)))
             (latest-broadcast-p (eql (getf *latest-broadcast* :id)
                                      broadcast-id))
             (text-broadcast (if latest-broadcast-p
                               (getf *latest-broadcast* :text)
                               (read-file-into-string broadcast-path)))
             (html-broadcast (if latest-broadcast-p
                               (getf *latest-broadcast* :html)
                               (markdown-file broadcast-path)))
             (html-message (html-email-base
                             (strcat html-broadcast
                                    (when amazon-smile-p
                                      (amazon-smile-reminder :html))
                                     (unsubscribe-notice-ps-html
                                       unsubscribe
                                       email
                                       "updates from Kindista"
                                       :detailed-notification-description "occasional updates like this from Kindista"))))
             (text-message (s+ text-broadcast
                               (when amazon-smile-p
                                 (amazon-smile-reminder))
                               (unsubscribe-notice-ps-text
                                 unsubscribe
                                 email
                                 "updates from Kindista"
                                 :detailed-notification-description "occasional updates like this from Kindista"))) )
        (when email
          (cl-smtp:send-email +mail-server+
                              (if latest-broadcast-p
                                (or (getf *latest-broadcast* :author-email)
                                    author-email)
                                author-email )
                              (format nil "\"~A\" <~A>" name email)
                              (getf broadcast :title)
                              text-message
                              :html-message html-message)))))

  )

(defun create-broadcast (&key path title author blog-p amazon-smile-p)
  (insert-db `(:type ,(if blog-p :blog :broadcast)
               :created ,(get-universal-time)
               :title ,title
               :author ,author
               :amazon-smile-p ,amazon-smile-p
               :path ,path
               )))

(defun index-blog
  (id
   data
   &aux (author-id (getf data :author))
        (author (db author-id))
        (created (universal-to-timestamp (getf data :created)))
        (local-dir (with-output-to-string (str)
                     (format-timestring
                       str
                       created
                       :format '((:year 4) #\/ (:month 2) #\/ (:day 2) #\/))))
        (hyphenated-title (hyphenate (getf data :title)))
        (blog-path (s+ *blog-path* local-dir hyphenated-title))
        (result (make-result :latitude (getf author :lat)
                             :longitude (getf author :long)
                             :id id
                             :type :blog
                             :people (list author-id)
                             :time (getf data :created)
                             :tags (getf data :tags))))

  (with-locked-hash-table (*db-results*)
    (setf (gethash id *db-results*) result))

  (with-mutex (*blog-mutex*)
    (setf *blog-index*
          (safe-sort (push result *blog-index*)
                     #'<
                     :key #'result-time)))

  (unless (file-exists-p blog-path)
    (let* ((data-path (s+ *broadcast-path* (getf data :path)))
           (dirname (s+ *blog-path* local-dir))
           (markdown (markdown-file data-path)))

       (ensure-directories-exist dirname)
       (with-open-file (file blog-path :direction :output
                                       :if-exists :supersede)
         (with-standard-io-syntax
           (let ((*print-pretty* t))
             (prin1 (list id markdown) file))
           (terpri))))))

(defun save-broadcast
  (text
   title
   &aux (now (local-time:now))
        (hyphenated-title (hyphenate title))
        (local-dir (with-output-to-string (str)
                     (format-timestring
                       str
                       now
                       :format '((:year 4) #\/ (:month 2) #\/ (:day 2) #\/))))
        (dirname (strcat *broadcast-path* local-dir))
        (filename (s+ hyphenated-title ".md"))
        (new-file-path (merge-pathnames dirname filename)))

  (ensure-directories-exist dirname)
  (with-open-file (file new-file-path :direction :output
                                      :if-exists :supersede)
    (with-standard-io-syntax
      (let ((*print-pretty* t))
        (princ text file))
      (terpri)))
 ;(copy-file file new-file-path)
  (s+ local-dir filename))

(defun get-blog-post
  (year
   month
   day
   title
   &aux (date-path (strcat *blog-path* year "/" month "/" day "/"))
        (path (merge-pathnames date-path title)))

  (with-open-file (file path :direction :input :if-does-not-exist nil)
    (if file
      (let* ((file-contents (read file))
             (id (car file-contents))
             (html (cadr file-contents))
             (data (db id)))
        (standard-page
          (getf data :title)
          (html
            (:div :class "blog item"
             (str html))
            )
          )
        )
      (not-found))))