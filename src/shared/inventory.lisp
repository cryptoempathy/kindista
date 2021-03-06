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

(defun mark-recent-inventory-active ()
"To fix a bug introduced in commit f24b715bd4bb893f8bc6fc037910ee677b3e59dd in which new inventory items were not being marked as active"
  (dolist (id (hash-table-keys *db*))
    (let* ((item (db id))
           (type (getf item :type)))
      (when (and (or (eql type :event)
                     (eql type :request)
                     (eql type :offer))
                 (> (getf item :created) 3610734290))
         (modify-db id :active t)))))

(defun new-pending-offer-notice-handler ()
  (send-pending-offer-notification-email (getf (cddddr *notice*) :id)))

(defun create-inventory-item (&key type (by *userid*) title details tags privacy)
  (insert-db (list :type type
                   :active t
                   :by by
                   :privacy privacy ;a list of groups who can see the item
                   :title title
                   :details details
                   :tags tags
                   :created (get-universal-time))))

(defun inventory-item-result (id &key data by-id by)
  (or (gethash id *db-results*)
      (let* ((item (or data (db id)))
             (by-id (or by-id (getf data :by)))
             (by (or by (db by-id))))
        (when item
          (make-result :latitude (or (getf item :lat) (getf by :lat))
                       :longitude (or (getf item :long) (getf by :long))
                       :id id
                       :type (getf item :type)
                       :people (list by-id)
                       :privacy (getf item :privacy)
                       :time (or (getf item :edited) (getf item :created))
                       :tags (getf item :tags))))))

(defun index-inventory-item (id data)
  (let* ((by-id (getf data :by))
         (by (db by-id))
         (type (getf data :type))
         (pending (getf by :pending))
         (result (inventory-item-result id
                                        :data data
                                        :by-id by-id
                                        :by by))
         (locationp (and (result-latitude result)
                        (result-longitude result))))

    ;; other code (e.g. index transaction) requires results for inactive items
    (with-locked-hash-table (*db-results*)
      (setf (gethash id *db-results*) result))

    (cond
      (pending
       (with-locked-hash-table (*pending-person-items-index*)
         (push id (gethash by-id *pending-person-items-index*))))

      ((getf data :active)
       (with-locked-hash-table (*profile-activity-index*)
         (asetf (gethash by-id *profile-activity-index*)
                (safe-sort (push result it) #'> :key #'result-time)))

       (if (eq type :offer)
         (with-locked-hash-table (*offer-index*)
           (push id (gethash by-id *offer-index*)))
         (with-locked-hash-table (*request-index*)
           (push id (gethash by-id *request-index*))))

       (when locationp
         (let ((title-stems (stem-text (getf data :title)))
               (details-stems (stem-text (getf data :details)))
               (tag-stems (stem-text (separate-with-spaces
                                       (getf data :tags)))))
           (if (eq type :offer)
             (with-locked-hash-table (*offer-stem-index*)
               (dolist (stem title-stems)
                 (push result (getf (gethash stem *offer-stem-index*) :title)))
               (dolist (stem details-stems)
                 (push result (getf (gethash stem *offer-stem-index*) :details)))
               (dolist (stem tag-stems)
                 (push result (getf (gethash stem *offer-stem-index*) :tags))))

             (with-locked-hash-table (*request-stem-index*)
               (dolist (stem title-stems)
                 (push result (getf (gethash stem *request-stem-index*) :title)))
               (dolist (stem details-stems)
                 (push result (getf (gethash stem *request-stem-index*) :details)))
               (dolist (stem tag-stems)
                 (push result (getf (gethash stem *request-stem-index*) :tags))))))

         (if (eq type :offer)
           (geo-index-insert *offer-geo-index* result)
           (geo-index-insert *request-geo-index* result))

         ;; unless item is older than 180 days
         (unless (< (result-time result) (- (get-universal-time) 15552000))
           ;; unless item is older than 30 days
           (unless (< (result-time result) (- (get-universal-time) 2592000))
             (with-mutex (*recent-activity-mutex*)
               (push result *recent-activity-index*)))
           (geo-index-insert *activity-geo-index* result)))

       (when (eq type :request)
         (if (or (getf data :match-all-terms)
                 (getf data :match-any-terms))
           (index-matchmaker id data)
           (with-mutex (*requests-without-matchmakers-mutex*)
             (safe-sort (push result
                              *requests-without-matchmakers-index*)
                        #'>
                        :key #'result-time)))))
      (t
       (if (eq type :offer)
         (with-locked-hash-table (*account-inactive-offer-index*)
           (push id (gethash by-id *account-inactive-offer-index*)))
         (with-locked-hash-table (*account-inactive-request-index*)
           (push id (gethash by-id *account-inactive-request-index*))))))))

(defun modify-inventory-item (id &key title details tags privacy)
  (let* ((result (gethash id *db-results*))
         (type (result-type result))
         (data (db id))
         (by (getf data :by))
         (now (get-universal-time)))

    (flet
      ((reindex-stems (new-text old-text data-type)
         (let* ((oldstems (stem-text old-text))
                (newstems (stem-text new-text))
                (common (intersection oldstems newstems :test #'string=)))

           (flet ((commonp (stem)
                    (member stem common :test #'string=)))

             (setf oldstems (delete-if #'commonp oldstems))
             (setf newstems (delete-if #'commonp newstems))

             (when (eq type :offer)
               (with-locked-hash-table (*offer-stem-index*)
                 (dolist (stem oldstems)
                   (asetf (getf (gethash stem *offer-stem-index*) data-type)
                          (remove result it))))
                 (dolist (stem newstems)
                   (push result (getf (gethash stem *offer-stem-index*)
                                      data-type))))

             (when (eq type :request)
               (with-locked-hash-table (*request-stem-index*)
                 (dolist (stem oldstems)
                   (asetf (getf (gethash stem *request-stem-index*) data-type)
                          (remove result it))))
                 (dolist (stem newstems)
                   (push result (getf (gethash stem *request-stem-index*)
                                      data-type))))))))

      (reindex-stems title (getf data :title) :title)
      (reindex-stems details (getf data :details) :details)
      (reindex-stems (separate-with-spaces tags)
                     (separate-with-spaces (getf data :tags))
                     :tags))

    (unless (equal tags (getf data :tags))
      (setf (result-tags result) tags))

    (setf (result-privacy result) privacy)

    (let ((data (list :title title
                      :details details
                      :tags tags
                      :privacy privacy)))

      (unless (and (getf *user* :admin)
                   (not (group-admin-p by))
                   (not (eql *userid* by)))
        (refresh-item-time-in-indexes id :time now)
        (append data (list :edited now)))

      (apply #'modify-db id data))

    (case (result-type result)
      (:offer (update-matchmaker-offer-data id))
      (:request (when (or (getf data :match-all-terms)
                          (getf data :match-any-terms))
                  (modify-matchmaker id)
                  (update-matchmaker-request-data id))))))

(defun deactivate-inventory-item (id &key violates-terms)
  (let* ((result (gethash id *db-results*))
         (type (result-type result))
         (data (db id))
         (by (getf data :by))
         (type-index (case type
                       (:offer *offer-index*)
                       (:request *request-index*)))
         (stem-index (case type
                       (:offer *offer-stem-index*)
                       (:request *request-stem-index*)
                       (:event *event-stem-index*)))
         (geo-index (case type
                      (:offer *offer-geo-index*)
                      (:request *request-geo-index*)
                      (:event *event-geo-index*)))
         (stems (stem-text (s+ (getf data :title) " " (getf data :details)))))

    (when result
      (with-locked-hash-table (stem-index)
        (dolist (stem stems)
          (asetf (gethash stem stem-index)
                 (remove result it))))

      ;; delete matchmakers
      (case type
        (:offer
          (unmatch-offer-matches id
                                 by
                                 (copy-list
                                   (gethash id
                                           *offers-with-matching-requests-index*)))
          (with-locked-hash-table (*offers-with-matching-requests-index*)
            (remhash id *offers-with-matching-requests-index*)))

        (:request
          (when (or (getf data :match-all-terms)
                    (getf data :match-any-terms))
            (unmatch-request-matches id
                                   by
                                   (append (getf data :matching-offers)
                                           (getf data :hidden-matching-offers)))
            (remove-matchmaker-from-indexes id))))

      (geo-index-remove geo-index result)

      (if (eq type :event)
        (with-mutex (*event-mutex*)
          (asetf *event-index* (remove result it)))
        (with-locked-hash-table (type-index)
          (asetf (gethash by type-index)
                 (remove id it))))
      (case type
        (:request
          (with-locked-hash-table (*account-inactive-request-index*)
            (push id (gethash by *account-inactive-request-index*))))
        (:offer
          (with-locked-hash-table (*account-inactive-offer-index*)
            (push id (gethash by *account-inactive-offer-index*)))))

      (unless (eq type :event)
        (with-locked-hash-table (*profile-activity-index*)
          (asetf (gethash by *profile-activity-index*)
                 (remove result it)))
        (geo-index-remove *activity-geo-index* result)
        (with-mutex (*recent-activity-mutex*)
          (asetf *recent-activity-index* (remove id it :key #'result-id)))))

    (modify-db id :active nil :violates-terms violates-terms)))

(defun delete-pending-inventory-item (id)
  (let ((data (db id)))
    (with-locked-hash-table (*pending-person-items-index*)
      (asetf (gethash (getf data :by) *pending-person-items-index*)
             (remove id it)))
    (remove-from-db id)))

(defun deleted-invalid-item-reply-text (to-name from-name type &optional explanation)
  (strcat "Greetings " to-name ","
        #\linefeed
        #\linefeed
        "Your " type
        " violated Kindista's Terms of Use and we had to remove it. "
        "Please list multiple offers and requests separately (not in the same item). "
        "Kindista is for giving and receiving freely; please avoid any language which implies that you are expecting barter or money in exchange for your offer or request. "
        #\linefeed
        (aif explanation
          (strcat #\linefeed it #\linefeed)
          "")
        #\linefeed
        "To ensure that this doesn't happen again, please review Kindista's Sharing Guidelines before posting any additional offers or requests:"
        #\linefeed
        "https://kindista.org/faq#sharing-guidelines"
        #\linefeed
        #\linefeed
        "Please let me know if you have any questions with this policy."
        #\linefeed
        #\linefeed
        "In gratitude,"
        #\linefeed
        from-name ", Kindista"))

(defun post-new-inventory-item (type &key url)
  (require-active-user
    (let* ((tags (post-parameter-string-list "tag"
                                             #'(lambda (tag)
                                                 (scan *tag-scanner* tag))))
           (groups-selected (post-parameter-integer-list "groups-selected"))
           (groupid (post-parameter-integer "groupid"))
           (identity-selection (post-parameter-integer "identity-selection"))
           ;reset to public when changing identity
           (restrictedp (and (equalp (post-parameter "privacy-selection")
                                      "restricted")
                              (or (not identity-selection)
                                  (eql identity-selection
                                       (post-parameter-integer "prior-identity")))))
           (adminp (group-admin-p (or groupid identity-selection)))
           (title (post-parameter-string "title"))
           (details (when (scan +text-scanner+ (post-parameter "details"))
                      (post-parameter "details"))))

      (iter (for tag in (tags-from-string (post-parameter "tags")))
            (setf tags (cons tag tags)))

      (flet ((inventory-tags (&key error)
               (enter-inventory-tags :page-title (s+ "Post a new " type)
                                     :item-title title
                                     :details details
                                     :next (post-parameter "next")
                                     :action url
                                     :restrictedp restrictedp
                                     :identity-selection identity-selection
                                     :groupid groupid
                                     :groups-selected groups-selected
                                     :tags tags
                                     :error error
                                     :button-text (s+ "Post " type)
                                     :selected (s+ type "s"))))

        (cond
         ((post-parameter "cancel")
          (see-other (or (post-parameter "next") "/home")))

         ((not (confirmed-location))
          (flash "You must set your street address on your settings page before you can post an offer or a request." :error t)
          (see-other (or (post-parameter "next") "/home")))

         ((and groupid (not adminp))
          (permission-denied))

         ((not title)
          (flash (s+ "Please enter a better title for your " type ".")
                 :error t)
          (inventory-tags))

         ((> (length title) 140)
          (flash (s+ "Please shorten your title to 140 characters or less."))
          (inventory-tags))

         ((> (length details) 1000)
          (flash (s+ "Please shorten your description. Offers and Requests must be no longer than 1000 characters including line breaks."))
          (inventory-tags))

         ((and (not (post-parameter "create"))
               title)
           (inventory-tags))

         ((and restrictedp
               (post-parameter "create")
               (not groups-selected))
          (inventory-tags :error (s+ "Please allow at least one group to see this " type)))

         ((and (post-parameter "create")
               title)
          (if (intersection tags *top-tags* :test #'string=)
            (let ((new-id (create-inventory-item
                            :type (if (string= type "request") :request
                                                               :offer)
                            :by (if adminp
                                  (or groupid identity-selection)
                                  *userid*)
                            :privacy groups-selected
                            :title title
                            :details details
                            :tags tags)))
              (if (getf *user* :pending)
                (progn
                  new-id
                  (contact-opt-out-flash (list *userid*) :item-type type)
                  (when (string= type "offer")
                    (notice :new-pending-offer :id new-id))
                  (if (string= type "request")
                    (flash "Your item has been recorded. It will be posted after you post an offer and we have a chance to review it. In the meantime, please consider posting additional offers, requests, or statements of gratitude. Thank you for your patience.")
                    (flash "Your item has been recorded. It will be posted after we have a chance to review it. In the meantime, please consider posting additional offers, requests, or statements of gratitude. Thank you for your patience."))
                  (see-other "/home"))
                (progn
                  (contact-opt-out-flash (list *userid*) :item-type type)
                  (flash
                    (s+ "Congratulations, your "
                        type
                        " has been posted! "
                        " You will "
                        (if (getf *user* :notify-message)
                          " will be notified by email "
                          " will recieve a notification on Kindista ")
                        (s+ "when someone wants to "
                            (if (string= type "offer")
                              "receive this from you. "
                              "wants to share this with you. "))
                        " As a reminder, you are under no obligation to "
                        (if (string= type "offer")
                          "share with anyone"
                          "accept gifts from anyone")
                        "; you decide who you want to share with on Kindista."))
                  (when (string= type "offer")
                    (update-matchmaker-offer-data new-id))
                  (see-other (format nil (strcat "/" type "s/" new-id))))))

            (inventory-tags :error "You must select at least one keyword")))

         (t (inventory-tags)))))))

(defun post-existing-inventory-item (type &key id url)
  (require-user
    (let* ((id (parse-integer id))
           (item (db id))
           (by (getf item :by))
           (action-type (post-parameter-string "action-type"))
           (reply-text (post-parameter-string "reply-text"))
           (adminp (group-admin-p by))
           (next (post-parameter "next")))

      (cond
        ((and (not (eql by *userid*))
              (item-view-denied (result-privacy (gethash id *db-results*))))
         (permission-denied))

        ((post-parameter "cancel")
         (see-other (or next "/home")))

        ((and (or (post-parameter "reply-text")
                  (post-parameter "reply"))
              (getf *user* :pending))
         (pending-flash "contact other Kindista members")
         (see-other (or (referer) "/home")))

        ((or (post-parameter-string "reply-text")
             (and (post-parameter "reply-text")
                  (or (string= action-type "offer")
                      (string= action-type "request"))))
         (create-transaction :on id
                             :text (post-parameter-string "reply-text")
                             :action (cond
                                       ((string= action-type "offer")
                                        :offered)
                                       ((string= action-type "request")
                                        :requested))
                             :match-id (post-parameter-integer "match"))
         (flash (s+ "Your "
                    (or action-type "reply")
                    " has been sent."))
         (contact-opt-out-flash (list by (unless (eql *userid* by) *userid*)))
         (see-other (or next (script-name*))))

        ((or (post-parameter "reply")
             action-type
             ;; if ther's no action type
             (and (post-parameter "reply-text")
                  (not reply-text)
                  (not action-type)))

         (flet ((reply-html (type)
                  (inventory-item-reply
                    type
                    id
                    item
                    :text reply-text
                    :action-type action-type
                    :next next
                    :match (post-parameter-integer "match")
                    :error (when (and (not (post-parameter "reply"))
                                      (not reply-text)
                                      (not action-type))
                             :no-message))))
           (case (getf item :type)
             (:offer (reply-html "offer"))
             (:request (reply-html "request"))
             (t (not-found)))))

        ((post-parameter "love")
         (love id)
         (see-other (or (post-parameter "next") (referer))))

        ((post-parameter "unlove")
         (unlove id)
         (see-other (or (post-parameter "next") (referer))))

        (t
         (require-test ((or (eql *userid* (getf item :by))
                            adminp
                            (getf *user* :admin))
                      (s+ "You can only edit your own " type "s."))
           (let* ((tags (post-parameter-string-list "tag"
                                                    #'(lambda (tag)
                                                        (scan *tag-scanner*
                                                              tag))))
                  (groups-selected (or (post-parameter-integer-list "groups-selected")
                                       (getf item :privacy)))
                  (restrictedp (when
                                 (aif (post-parameter "privacy-selection")
                                   (string= "restricted" it)
                                   (getf item :privacy))
                                  t))
                  (new-title (post-parameter-string "title"))
                  (title (or new-title (getf item :title)))
                  (new-details (post-parameter-string "details")) 
                  (details (or new-details (getf item :details))))

             (iter (for tag in (tags-from-string (post-parameter "tags")))
                   (setf tags (cons tag tags)))

             (flet ((inventory-tags (&key error)
                      (enter-inventory-tags :page-title (s+ "Edit your " type)
                                            :action url
                                            :item-title title
                                            :details details
                                            :tags (or tags (getf item :tags))
                                            :groups-selected groups-selected
                                            :restrictedp restrictedp
                                            :next (or (post-parameter "next") (referer))
                                            :existingp t
                                            :groupid (when adminp by)
                                            :error error
                                            :button-text (s+ "Save " type)
                                            :selected (s+ type "s"))))

               (cond

                ((post-parameter "edit")
                 (inventory-tags))

                ((post-parameter "deactivate")
                 (confirm-delete :url url
                                 :type type
                                 :confirmation-question
                                   (s+ "Are you sure you want to deactivate this " type "?")
                                 :text (or (getf item :title)
                                           (getf item :details))
                                 :next-url (if (string= (referer) (strcat "/" type "s/" id))
                                             "/home"
                                             (referer))))

                ((and (post-parameter "really-delete")
                      (not (post-parameter "delete-inappropriate-item")))
                 (deactivate-inventory-item id)
                 (flash (s+ "Your " type " has been deactivated!"))
                 (if (equal (fourth (split "/" (post-parameter "next") :limit 4)) (subseq (script-name*) 1))
                   (see-other "/home")
                   (see-other (or (post-parameter "next") "/home"))))

                ((post-parameter "delete-pending-item")
                 (require-admin
                   (delete-pending-inventory-item id))
                 (flash (strcat (string-capitalize type) " " id " has been deleted."))
                 (see-other (script-name*)))

                ((post-parameter "inappropriate-item")
                 (require-admin
                   (confirm-delete :url url
                                   :next-url (referer)
                                   :confirmation-question
                                     (s+ "Are you sure you want to deactivate this " type "?")
                                   :type type
                                   :text (or (getf item :title)
                                             (getf item :details))
                                   :item-id id
                                   :inappropriate-item t)))

                ((post-parameter "delete-inappropriate-item")
                 (require-admin
                   (create-transaction :on id
                                       :pending-deletion t
                                       :text (post-parameter "explanation"))
                   (if (db by :pending)
                     (delete-pending-inventory-item id)
                     (deactivate-inventory-item id :violates-terms t))
                   (flash (strcat (string-capitalize type) " " id " has been deactivated."))
                   (see-other (if (string= (post-parameter "next")
                                           (strcat "/" type "s/" id))
                                "/home"
                                (post-parameter "next")))))

                ((not title)
                 (flash (s+ "Please enter a title for your " type "."))
                 (inventory-tags))

                ((and (post-parameter "title") (not new-title))
                 (flash (s+ "Please enter a better title for your " type ".")
                        :error t)
                 (inventory-tags))

                ((> (length title) 140)
                 (flash (s+ "Please shorten your title to 140 characters or less."))
                 (inventory-tags))

                ((> (length details) 1000)
                 (flash (s+ "Please shorten your description. Offers and Requests must be no longer than 1000 characters including line breaks."))
                 (inventory-tags))

                ((post-parameter "create")
                 (if (intersection tags *top-tags* :test #'string=)
                   (progn
                     (modify-inventory-item id :title (post-parameter "title")
                                               :details (post-parameter "details")
                                               :tags tags
                                               :privacy (when restrictedp
                                                          groups-selected))
                     (see-other (or (post-parameter "next") (strcat "/" type "s/" id))))

                   (inventory-tags :error "You must select at least one keyword")))

                (t
                  (inventory-tags)))))))))))

(defun simple-inventory-entry-html (preposition type &key groupid)
  (html
    (:div :class "item simple-inventory-entry"
      (:form :method "post" :action (s+ "/" type "s/new")
        (:input :type "hidden"
                :name "next"
                :value (script-name*))
        (awhen groupid
          (htm (:input :type "hidden" :name "groupid" :value it)))

        (:label :for "title"
         (:strong "Post " (str preposition) " " (str type) " ")
         (:span :class "inline-block"
           " ("
          (:span :id "title-count" "64")
          " characters available)"))
        (:table :class "inventory-title"
          (:tr
            (:td :class "inventory-details"
              (:input :type "text"
                      :id "title"
                      :name "title"
                      :onkeyup (ps-inline
                                 (limit-characters this 64 "title-count"))))
            (:td :id "inventory-title-button" (:button :class "yes" :type "submit" :name "post" "Post")))))
      (:p :class "help-text"
        "Enter a "
        (:strong "short title for a single " (str type))
        ". You can add details after you click \"post.\""))))


(defun enter-inventory-tags (&key page-title action item-title details existingp groupid identity-selection restrictedp error tags button-text selected groups-selected next)
  (let ((suggested (or tags (get-tag-suggestions item-title))))
    (standard-page page-title
     (html
       (:div :class "item inventory-details" :id "edit-tags"
        (str (pending-disclaimer))
        (when error
          (htm
            (:p :class "error" (str error))))
        (:h2 (str page-title) )
        (:form :class "post-next"
               :method "post"
               :action action
          (awhen next
            (htm (:input :type "hidden" :name "next" :value it)))
          (awhen groupid
            (htm (:input :type "hidden" :name "groupid" :value it)))
          (:input :type "hidden"
                  :name "prior-identity"
                  :value (or identity-selection groupid *userid*))


          (:div :class "help-text"
            (:strong (:span :id "title-count"
                      (str (aif item-title
                             (strcat (- 64 (length it)))
                             "64"))))
            " characters available")
          (:h3  "Enter a title ")
          (:input :type "text"
                  :name "title"
                  :onkeyup (ps-inline
                             (limit-characters this 64 "title-count"))
                  :value (awhen item-title
                           (str (escape-for-html it))))

          (:div :class "help-text"
            (:strong
              (:span :id "details-count" (str (aif details
                                                (strcat (- 1000 (length it)))
                                                "1000"))))
              " characters available")
          (:h3 "Include a description (optional)")
          (:textarea :class "review-text"
                     :name "details"
                     :rows "5"
                     :onkeyup (ps-inline
                                (limit-characters this 1000 "details-count"))
                     (awhen details
                       (str (escape-for-html it))))

          (unless (or groupid existingp)
            (awhen (groups-with-user-as-admin)
              (htm
                (:label (str (s+ (if (string= selected "offers")
                                   "Offered" "Requested")
                                 " by")))
                (str (identity-selection-html identity-selection it :onchange "this.form.submit()")))))

          (when (or (getf *user-group-privileges* :member)
                    (getf *user-group-privileges* :admin)
                    groups-selected)
            (str (privacy-selection-html
                   (if (string= selected "offers") "offer" "request")
                   restrictedp
                   (if (or (and identity-selection
                                (not (= identity-selection *userid*)))
                           groupid)
                     (list (aif identity-selection
                             (cons it (db it :name))
                             (cons groupid (db groupid :name))))
                     (append (groups-with-user-as-member)
                             (groups-with-user-as-admin)))
                   groups-selected
                   :onchange "this.form.submit()")))

          (:h3 "Select at least one keyword")
          (dolist (tag *top-tags*)
            (htm 
              (:div :class "tag"
                (:input :type "checkbox"
                        :name "tag"
                        :value tag
                        :checked (when (member tag suggested :test #'string=)
                                   (setf suggested (remove tag suggested :test #'string=))
                                   ""))
                   (:span (str tag)))))
          (:h3 "Additional keywords (optional)")
          (:input :type "text" :name "tags" :size 40
                  :placeholder "e.g. produce, bicycle, tai-chi"
                  :value (format nil "~{~a~^,~^ ~}" suggested))

          (:p
            (:strong :class "red" "Important: ")
            "You must read the "
            (:a :href "/faq#sharing-guidelines" 
                :target "_blank"
                "Guidelines for Sharing on Kindista")
            " before posting any offers or requests. "
            "Failure to adhere to these guidelines may result in account suspension.")

          (:p (:button :class "cancel" :type "submit" :class "cancel" :name "cancel" "Cancel")
              (:button :class "yes" :type "submit" :class "submit" :name "create" (str (or button-text "Post")))))))
     :right (sharing-guide-sidebar)
     :selected selected)))

; author
; creation date
; edited date
; text
; tags (at least 1)
; privacy ('all 'contacts or listname)

(defun nearby-inventory-items (type &key base (subtag-count 4) (distance 50) q)
  (with-location
    (let* ((stem-results (when q
                           (inventory-stem-index-query
                             (case type
                               (:offer *offer-stem-index*)
                               (t *request-stem-index*))
                             q)))
           (nearby (geo-index-query (case type
                                        (:offer *offer-geo-index*)
                                        (t *request-geo-index*))
                                        *latitude*
                                        *longitude*
                                      distance))
           (nearby-stem-matches (when q
                                  (remove-if-not #'(lambda (stem-result)
                                                     (find stem-result nearby))
                                                 stem-results
                                                 :key #'car)))
           (nearby-matches (if q
                             (mapcar #'car nearby-stem-matches)
                             nearby))
           (items nil))

      (let ((tags (make-hash-table :test 'equalp)))
        (dolist (item nearby-matches)
          (dolist (tag (result-tags item))
            (push item (gethash tag tags))))

        (if base
          ; get each base tag's list of items
          ; get intersection of those lists
          ; remove base tags from hashtable
          ; set all remaining tags lists to be intersection of tag list and previous intersection
          (progn
            (setf items (iter (for tag in base)
                              (reducing (gethash tag tags) by #'result-id-intersection)
                              (remhash tag tags)))
            (iter (for (tag tag-items) in-hashtable tags)
                  (let ((new-items (intersection tag-items items :key #'result-id)))
                    (if new-items
                      (setf (gethash tag tags) new-items)
                      (remhash tag tags)))))

          (setf items nearby-matches))

        ; for each tag, number of contents + ordered list of subtags (up to 4)
        (values (iter (for (tag tag-items) in-hashtable tags)
                      (collect (list tag
                                     (length tag-items)
                                     (when (cdr tag-items)
                                       (let* ((subtags (sort
                                                         (iter (for (subtag subtag-items) in-hashtable tags)
                                                               (unless (string= tag subtag)
                                                                 (awhen (intersection tag-items subtag-items :key #'result-id)
                                                                   (collect (cons subtag (length it))))))
                                                         #'> :key #'cdr))
                                              (top-subtags (subseq subtags 0
                                                                   (min (length subtags) subtag-count))))
                                         (if (< subtag-count (length subtags))
                                           (append (sort (subseq top-subtags 0 (- subtag-count 1))
                                                         #'string< :key #'car)
                                                   (list
                                                     (cons
                                                       "more"
                                                       (reduce #'+ (subseq subtags (- subtag-count 1)) :key #'cdr))))
                                           (sort top-subtags #'string< :key #'car)))))))
                (inventory-rank (if q
                                  (remove-if-not
                                    #'(lambda (result)
                                        (find result items))
                                    nearby-stem-matches
                                    :key #'car)
                                  (mapcar #'list items)))

               ;(safe-sort items #'> :key #'inventory-rank)
               )))))

(defun nearby-inventory-top-tags (type &key (count 9) (more t) base (subtag-count 4) q)
  (multiple-value-bind (nearby items)
      (nearby-inventory-items type :base base
                                   :subtag-count subtag-count
                                   :q q
                                   :distance (user-rdist))
    (let* ((tags (safe-sort (if base
                                nearby
                                (remove-if-not #'top-tag-p nearby :key #'first))
                   #'> :key #'second))
           (top-tags (subseq tags 0 (min count (length tags)))))
      (cond
        ((and more (> (length tags) (+ count 1)))
         (values
           (append (sort top-tags #'string< :key #'first)
                   (list
                     (let* ((more-tags (subseq tags count))
                            (subtags (iter (for tag in (subseq more-tags 0
                                                               (min 6 (length more-tags))))
                                           (collect
                                             (cons (first tag) (second tag))))))
                       (list "etc"
                         (reduce #'+ more-tags :key #'second)
                         (if (< 6 (length more-tags))
                           (append (sort (subseq subtags 0 5) #'string< :key #'car)
                                   (list
                                     (cons "more" (reduce #'+ (subseq more-tags 5) :key #'second))))
                           (sort subtags #'string< :key #'car))))))
                 items))
        ((and more (= (length tags) (+ count 1)))
         (values (sort tags #'string< :key #'first) items))
        (t
         (values (sort top-tags #'string< :key #'first) items))))))

(defun inventory-body-html (preposition type &key base q items start page)
  (let ((base-url (s+ "/" type "s")))
    (html
      (:div :class "activity"
        (when *user*
          (str
            (menu-horiz
              (html (:a :href (s+ "/people/" (username-or-id) "/" type "s") (str (s+ "show my " type "s")))))))

        (unless (or (not *user*)
                    (eq (getf *user* :active) nil)
                    base
                    q)
          (str (simple-inventory-entry-html preposition type)))

        (:div :class "item"
          (when q
            (htm
              (:span (:strong :class "small" (str (s+ "showing " type "s matching \"")) (str q) (:strong "\"")))))

          (str (rdist-selection-html (url-compose base-url "q" q "kw" base)
                                     :class "inline"
                                     :text (if q " within "
                                                 "showing results within ")))
          (when (or base q)
            (htm
              (:p (:a :href base-url (str (s+"show all " type "s")))))))

        (iter (for i from 0 to (+ start 20))
              (cond
                ((< i start)
                 (pop items))

                ((and (>= i start) items)
                 (str (inventory-activity-item (pop items)
                                               :show-when nil
                                               :show-distance t
                                               :truncate t
                                               :show-tags t)))
                (t
                 (when (< (user-rdist) 100)
                   (htm
                     (:div :class "item small"
                      (:em "Increasing the ")(:strong "show results within")(:em " distance may yield more results."))))
                 (finish)))

              (finally
                (when (or (> page 0) (cdr items))
                  (htm
                    (:div :class "item"
                     (when (> page 0)
                       (htm
                         (:a :href (url-compose base-url
                                                "p" (- page 1)
                                                "kw" base
                                                "q" q)
                          "< previous page"
                          )))
                     "&nbsp;"
                     (when (cdr items)
                       (htm
                         (:a :style "float: right;"
                             :href (url-compose base-url
                                                "p" (+ page 1)
                                                "q" q
                                                "kw" base)
                             "next page >"))))))))))))

(defun browse-inventory-tags (type &key q base tags)
  (let ((base-url (s+ "/" type "s")))
    (html
      (when base
        (htm
          (:p (:strong "categories selected: "))
          (:ul :class "keywords"
            (dolist (tag base)
              (htm
                (:li
                  (:a :href (url-compose base-url "kw" tag "q" q) (str tag))
                  " "
                  (:a :href (url-compose base-url "kw" (remove tag base :test #'string=) "q" q)
                      "[x]")
                  ))))))
      (:h3 "filter by category")
      (dolist (tag tags)
        (if (string= (first tag) "etc")
          (htm
            (:div :class "category"
             (:h3 (:a :href (s+ base-url "/all")
                      (str (s+ "etc (" (write-to-string (second tag)) ")"))))
             (iter (for subtag in (third tag))
                   (for i downfrom (length (third tag)))
                   (htm
                     (:a :href (if (string= (first subtag) "more")
                                 (s+ base-url "/all")
                                 (url-compose "" "kw" (format nil "~{~a+~}~a" base (first subtag)) "q" q) )
                         (str (s+ (car subtag) " (" (write-to-string (cdr subtag)) ")")))
                     (unless (= i 1)
                       (str ", "))))))
          (htm
            (:div :class "category"
             (:h3 (:a :href (url-compose "" "kw" (format nil "~{~a+~}~a" base (first tag)) "q" q)
                      (str (s+ (first tag) " (" (write-to-string (second tag)) ")"))))
             (iter (for subtag in (third tag))
                   (for i downfrom (length (third tag)))
                   (htm
                     (:a :href (url-compose "" "kw"
                                            (if (string= (first subtag) "more")
                                              (format nil "~{~a+~}~a" base (first tag))
                                              (format nil "~{~a+~}~a+~a" base (first tag) (first subtag)))
                                            "q" q)
                         (str (s+ (car subtag) " (" (write-to-string (cdr subtag)) ")")))
                     (unless (= i 1)
                       (str ", "))))))))
      (unless base
        (htm
          (:div :class "category"
           (:h3 (:a :href (s+ base-url "/all") "show all keywords"))))))))

(defun browse-all-inventory-tags (preposition type &key base tags)
  (html
    (unless base
      (str (simple-inventory-entry-html preposition type)))
    (let ((base-url (s+ "/" type "s")))
      (htm
        (:div :class "item"
        (:h2 "browse by keyword")
        (when base
          (htm
            (:p (:a :href base-url (str (s+ "show all " type "s"))))
            (:p (:strong "keywords selected: "))
            (:ul :class "keywords"
              (dolist (tag base)
                (htm
                  (:li
                    (:a :href (format nil (s+ base-url "?kw=~{~a~^+~}") (remove tag base :test #'string=))
                        "[x]")
                    " "
                    (:a :href (format nil (s+ base-url "?kw=~a") tag) (str tag))
                    ))))))
        (dolist (tag tags)
          (htm
            (:div :class "category"
             (:h3 (:a :href (format nil (s+ base-url "?kw=~{~a+~}~a") base (first tag))
                      (str (s+ (first tag) " (" (write-to-string (second tag)) ")"))))
             (iter (for subtag in (third tag))
                   (for i downfrom (length (third tag)))
                   (if (string= (car subtag) "more")
                     (htm
                       (:a :href (format nil (s+ base-url "?kw=~{~a+~}~a") base (first tag)) (str (strcat "more (" (second tag) ")"))))
                     (htm
                     (:a :href (format nil (s+ base-url "?kw=~{~a+~}~a+~a") base (first tag) (first subtag))
                         (str (s+ (car subtag) " (" (write-to-string (cdr subtag)) ")")))
                     (unless (= i 1)
                       (str ", ")))))))))))))

(defun inventory-item-reply (type id data &key action-type next match text error)
  (let ((next (or next (get-parameter "next")))
        (url (strcat "/" type "s/" id)))
    (if (item-view-denied (result-privacy (gethash id *db-results*)))
      (permission-denied)
      (standard-page
        "Reply"
        (html
          (when error
            (flash "Please enter a message to send." :error t))
          (htm
            (:h2
              (str (s+ (if action-type "Respond" "Reply")
                       " to "
                       (person-link (getf data :by) :possessive t)
                       type))))
          (:blockquote
            (:p
              (awhen (getf data :title)
                (htm (:strong (:a :href url (str (html-text it))))
                     (:br)))
              (awhen (getf data :details)
                (str (html-text it)))))
          (if action-type
            (htm (:h4 "Include a message: (optional)"))
            (htm (:h4 "Write your reply:")))
          (:div :class "reply item"
            (:form :method "post" :action url
              (:input :type "hidden" :name "next" :value next)
              (:input :type "hidden" :name "match" :value match)
              (:input :type "hidden" :name "action-type" :value action-type)

              (:textarea :cols "1000" :rows "4" :name "reply-text" (str text))

              (:button :type "submit" :class "cancel" :name "cancel" "Cancel")
              (:button :class "yes"
                       :type "submit"
                       :class "submit"
                (str (aif action-type
                       (s+ (string-capitalize it) " This")
                       "Reply"))))))

        :selected (s+ type "s")
        :class "inventory-reply"))))
