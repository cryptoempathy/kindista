;;; Copyright 2012-2013 CommonGoods Network, Inc.
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

(defun card (&rest contents)
  (html
    (:div :class "card"
      (dolist (item contents)
        (str item)))))

(defun card-button (title url &key next-url (method "GET"))
  (html
    (:form :method method :action url
      (when next-url
        (htm (:input :type "hidden" :name "next" :value next-url)))
      (:input :type "submit" :value title))))

(defun id-button (id button-name &optional alias)
  (let* ((mutuals (mutual-connections id))
         (entity (db id))
         (name (getf entity :name))
         (groupid (when (eq (getf entity :type) :group) id)))
    (html
      (:button :class "card" :value id :name button-name
        (:img :src (get-avatar-thumbnail id 300 300))
        (:div :class "details"
          (:h3 (str name))
            (unless groupid
              (unless (string= name alias)
                (htm (:p "nickname: " (str alias))))) 
            (awhen (getf entity :city)
              (htm (:p (str (s+ (if groupid "Located" "Lives") " in ")) (str it)))) 
            (when mutuals
              (htm (:p (str (length mutuals))
                       (unless groupid
                         (htm " mutual"))
                       " connection"
                       (when (> (length mutuals) 1)
                         (htm "s"))))))))))

(defun feedback-card (id)
  (let* ((data (db id))
         (url (strcat "/feedback/" id))
         (by (getf data :by))
         (bydata (db by)))
    (card
      (html
        (str (h3-timestamp (getf data :created)))
        (:p (:a :href (s+ "/people/" (username-or-id by)) (str (getf bydata :name)))) 
        (:p (str (regex-replace-all "\\n" (getf data :text) "<br>")))
        (:div :class "actions"
          (str (activity-icons :hearts (length (loves id)) :url url))
          (:form :method "post" :action url
            (:input :type "hidden" :name "next" :value (script-name*))
            (if (member *userid* (gethash id *love-index*))
              (htm (:input :type "submit" :name "unlove" :value "Loved"))
              (htm (:input :type "submit" :name "love" :value "Love")))   
            (when (getf *user* :admin)
               (htm
                " &middot; "  
                (:input :type "submit" :name "reply" :value "Reply")))
            (when (eql *userid* by)
              (htm
                " &middot; "  
                (:input :type "submit" :name "delete" :value "Delete")))))

          (:div :class "comments"
            (dolist (comment-id (gethash id *comment-index*))
              (str (comment-card comment-id)))

            (when (getf *user* :admin)
              (htm
                (:div :class "item reply"
                  (:h4 "post a comment") 
                  (:form :method "post" :action (strcat "/feedback/" id)
                    (:table :class "post"
                      (:tr
                        (:td (:textarea :cols "150" :rows "4" :name "text"))
                        (:td
                          (:button :class "yes" :type "submit" :class "submit" "Reply")))))))))))))

(defun comment-card (comment-id)
  (let* ((data (db comment-id))
         (by (car (getf data :by)))
         (bydata (db by)))
    (card
      (html
        (str (h3-timestamp (getf data :created)))
        (:p (:a :href (s+ "/people/" (username-or-id by))
             (str (getf bydata :name)))
         " replied:")
        (:p (str (regex-replace-all "\\n" (db comment-id :text) "<br>")))
        (when (or (eql (getf data :by) *userid*)
                  (getf *user* :admin))
          (htm (:a :class "right" :href (strcat "/comments/" comment-id "/delete") "delete")))
        ))))
