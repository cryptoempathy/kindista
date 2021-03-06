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

(defun requests-help-text ()
  (welcome-bar
    (html
      (:h2 "Getting started with requests")
      (:p "Here are some things you can do to get started:")
      (:ul
        (:li (:a :href "/requests/new" "Post a request") " to the community for something you need.")
        (:li "Browse recently posted requests listed below.")
        (:li "Find specific requests by selecting keywords from the " (:strong "browse by keyword") " menu.")
        (:li "Search for requests using the search "
          (:span :class "menu-button" "button")
          (:span :class "menu-showing" "bar")
          " at the top of the screen.")))))

(defun get-requests-new ()
  (require-user
    (enter-inventory-tags :page-title "Post a request"
                          :action "/requests/new"
                          :button-text "Post request"
                          :selected "requests")))

(defun post-requests-new ()
  (post-new-inventory-item "request" :url "/requests/new"))

(defun get-request
  (id
   &key all-terms
        any-terms
        without-terms
        distance
        notify-matches
   &aux (k (get-parameter-string "k"))
        (unverified-email (get-parameter-string "email")))

  (unless (integerp id)
    (setf id (parse-integer id)))

  (let* ((request (db id))
         (by (getf request :by))
         (unverified-userid (gethash unverified-email *email-index*))
         (unverified-user (db unverified-userid))
         (verified-user (when (string= (getf unverified-user
                                             :unsubscribe-key)
                                       k)
                            unverified-user))
         (userid (or (when verified-user unverified-userid)
                     *userid*))
         (self (eql userid by))
         (matchmaker-admin (matchmaker-admin-p))
         (result (gethash id *db-results*)))
    (cond
     ((or (not request)
          (not (eql (getf request :type) :request)))
      (not-found))

     ((and (getf request :violates-terms)
           (not self)
           (not (getf *user* :admin)))
        (item-violates-terms))

     ((and (not self)
           (item-view-denied (result-privacy result)))
       (permission-denied))

     (t
      (with-location
        (standard-page
          "Requests"
          (html
            (:div :class "inventory-item-page"
              (when (and *userid*
                         (or matchmaker-admin self))
                (str (menu-horiz
                       (when self
                         (html (:a :href (s+ "/people/"
                                             (username-or-id)
                                             "/requests")
                                "show my requests")))
                       (html (:a :href "/admin/matchmaker"
                              "show requests without matchmakers")))))

              (str (inventory-activity-item result :show-distance t :show-tags t))
              (when (or self (group-admin-p by) matchmaker-admin)
                (str (item-matches-html id :data request
                                           :self self
                                           :all-terms all-terms
                                           :any-terms any-terms
                                           :without-terms without-terms
                                           :distance distance
                                           :notify-matches notify-matches)))))
          :selected "requests"))))))

(defun get-request-reply (id)
  (require-user
    (let* ((id (parse-integer id))
           (data (db id)))
      (if (eql (getf data :type) :request)
        (inventory-item-reply "request" id data)
        (not-found)))))

(defun post-request (id)
  (post-existing-inventory-item "request" :id id :url (script-name*)))

(defun get-requests ()
  (when *userid*
    (send-metric* :got-requests *userid*))
  (with-location
    (let* ((page (if (scan +number-scanner+ (get-parameter "p"))
                   (parse-integer (get-parameter "p"))
                   0))
           (q (get-parameter "q"))
           (base (iter (for tag in (split " " (get-parameter "kw")))
                       (when (scan *tag-scanner* tag)
                         (collect tag))))
           (start (* page 20)))
      (when (string= q "") (setf q nil))
      (multiple-value-bind (tags items)
          (nearby-inventory-top-tags :request :base base :q q)
        (standard-page
          "Requests"
          (inventory-body-html "a"
                               "request"
                               :base base
                               :q q
                               :items items
                               :start start
                               :page page)
          :top (when (getf *user* :help)
                 (requests-help-text))
          :search q
          :search-scope (if q "requests" "all")
          :right (html
                   (str (donate-sidebar))
                   (str (browse-inventory-tags "request" :q q :base base :tags tags)))
          :selected "requests")))))


(defun get-requests-all ()
  (with-user
    (with-location
      (let ((base (iter (for tag in (split " " (get-parameter "kw")))
                        (when (scan *tag-scanner* tag)
                          (collect tag)))))
        (multiple-value-bind (tags items)
            (nearby-inventory-top-tags :request :count 10000 :subtag-count 10)
          (declare (ignore items))
          (standard-page
           "Requests"
             (browse-all-inventory-tags "a" "request" :base base :tags tags)
             :top (when (getf *user* :help)
                   (requests-help-text))
             :selected "requests"))))))
