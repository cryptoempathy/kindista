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

(defun new-gratitude-notice-handler ()
  (send-gratitude-notification-email (getf (cddddr *notice*) :id)))

(defun create-gratitude (&key author subjects text on transaction-id (time (get-universal-time)))
  (let* ((people-list (mailbox-ids subjects))
         (people (mapcar #'(lambda (mailbox)
                             (cons mailbox :unread))
                         people-list))
         (message-folders (list :inbox (remove-duplicates (mapcar #'car people-list))))
         (gratitude (insert-db `(:type :gratitude
                                 :author ,author
                                 :subjects ,subjects
                                 :people ,people
                                 :transaction-id ,transaction-id
                                 :message-folders ,message-folders
                                 :text ,text
                                 :on ,on
                                 :created ,time))))
    (notice :new-gratitude :time time
                           :id gratitude)
    gratitude))

(defun add-gratitude-subjects (gratitude-id subject-ids)
"To add subjects to misattributed statements of gratitude from the REPL"
  (let* ((gratitude (db gratitude-id))
         (people-list (mailbox-ids subject-ids))
         (people (mapcar #'(lambda (mailbox)
                             (cons mailbox :unread))
                         people-list))
         (folders (getf gratitude :message-folders))
         (bad-subject-ids))

    (setf bad-subject-ids
          (loop for id in subject-ids
                for subject-type = (db id :type)
                unless (or (eql subject-type :person)
                           (eql subject-type :group))
                collect id))
    (cond
      ((not (eql (getf gratitude :type) :gratitude))
       (strcat "Error: " gratitude-id " is not of type :gratitude"))
      (bad-subject-ids
       (strcat "Error: " (car bad-subject-ids) " is not of type :person or :group"))
      (t
       (dolist (id people-list)
         (pushnew (car id) (getf folders :inbox)))

       (deindex-gratitude gratitude-id)
       (remove-message-from-indexes gratitude-id)

       (amodify-db gratitude-id :subjects (append subject-ids it)
                                :people (append people it)
                                :message-folders folders)

       (let ((new-data (db gratitude-id)))
         (index-gratitude gratitude-id new-data)
         new-data))
      )))

(defun remove-gratitude-subject (gratitude-id subject-id)
"To remove subjects to misattributed statements of gratitude using the REPL."
  (let* ((gratitude (db gratitude-id))
         (subject-type (db subject-id :type))
         (new-mailboxes)
         (new-people)
         (folders (getf gratitude :message-folders)))

    (cond
      ((= (length (getf gratitude :subjects)) 1)
       (strcat "Error: You cannot remove the last subject. Please add another subject-id before removing subject id: " subject-id "."))
      ((not (eql (getf gratitude :type) :gratitude))
       (strcat "Error: " gratitude-id " is not of type :gratitude"))
      ((nor (eql subject-type :person)
            (eql subject-type :group))
       (strcat "Error: " subject-id " is not of type :group or :person"))
      (t
       ;; remove mailboxes (including group mailboxes) from "people"
       (flet ((find-subject-mailboxes (mailbox)
                (eql subject-id (if (eq subject-type :person)
                                  (car mailbox)
                                  (cdr mailbox)))))
         (setf new-mailboxes
               (remove-if #'find-subject-mailboxes (getf gratitude :people)
                 :key #'car)))

      ;; get a list of all people who should have access to message
      (setf new-people (remove-duplicates (mapcar #'caar new-mailboxes)))

      (doplist (folder ids folders)
        (asetf (getf folders folder)
               (remove-if-not #'(lambda (id) (find id new-people)) it)))

      (deindex-gratitude gratitude-id)
      (remove-message-from-indexes gratitude-id)

      (amodify-db gratitude-id :subjects (remove subject-id it)
                               :people new-mailboxes
                               :message-folders folders)

      (let ((new-data (db gratitude-id)))
        (index-gratitude gratitude-id new-data)
        new-data)))) )

(defun index-gratitude-link (gratitude-id on-item-id &optional (time (get-universal-time)))
  (with-mutex (*completed-transactions-mutex*)
    (stable-sort (push (list :time time
                             :gratitude gratitude-id
                             :on on-item-id)
                       *completed-transactions-index*)
                 #'>
                 :key #'(lambda (item) (getf item :time)))))

(defun deindex-gratitude-link (gratitude-id)
  (with-mutex (*completed-transactions-mutex*)
    (asetf *completed-transactions-index*
           (remove gratitude-id
                   it
                   :key #'(lambda (link)
                            (getf link :gratitude))))))

(defun index-gratitude (id data)
  (let* ((author-id (getf data :author))
         (author (db author-id))
         (created (getf data :created))
         (subjects (getf data :subjects))
         (people (cons (getf data :author) subjects))
         (result (make-result :latitude (getf author :lat)
                              :longitude (getf author :long)
                              :people people
                              :time created
                              :type :gratitude
                              :id id)))

   (with-locked-hash-table (*db-results*)
     (setf (gethash id *db-results*) result))

   (with-locked-hash-table (*gratitude-index*)
     (push id (gethash author-id *gratitude-index*)))

   (with-locked-hash-table (*profile-activity-index*)
     (dolist (person people)
       (asetf (gethash person *profile-activity-index*)
              (safe-sort (push result it) #'> :key #'result-time))))

   (awhen (getf data :on)
     (index-gratitude-link id it created))

   (unless (getf data :transaction-id)
     (index-message id data))

   ;; unless gratitude is older than 180 days
   (unless (< (result-time result) (- (get-universal-time) 15552000))

     (geo-index-insert *activity-geo-index* result)

     ;;unless gratitude is older than 30 days
     (unless (< (result-time result) (- (get-universal-time) 2592000))
       (with-mutex (*recent-activity-mutex*)
         (push result *recent-activity-index*)))

     (with-locked-hash-table (*gratitude-results-index*)
       (dolist (subject subjects)
         (let* ((user (db subject))
                (location (getf user :location))
                (result (make-result :type :gratitude
                                     :latitude (getf user :lat)
                                     :longitude (getf user :long)
                                     :people people
                                     :id id
                                     :time created)))
           (push result (gethash id *gratitude-results-index*))
           (when location (geo-index-insert *activity-geo-index* result))))))))

(defun parse-subject-list (subject-list &key remove)
  (delete-duplicates
    (iter (for subject in (split #\, subject-list))
          (unless (equalp subject remove)
            (acond
              ((scan +number-scanner+ subject)
               (setf subject (parse-integer subject))
               (awhen (db subject)
                 (when (or (eq (getf it :type) :person)
                           (eq (getf it :type) :group))
                   (collect subject at beginning))))
              ((gethash subject *username-index*)
               (collect it at beginning))
              ((gethash subject *email-index*)
               (collect it at beginning)))))))

(defun modify-gratitude (id text)
  (let ((now (get-universal-time)))
    (refresh-item-time-in-indexes id :time now)
    (modify-db id :text text :edited now)))

(defun deindex-gratitude (id)
  (let* ((result (gethash id *db-results*))
         (data (db id))
         (people (cons (getf data :author) (getf data :subjects))))

    (when (getf data :on) (deindex-gratitude-link id))

    (with-locked-hash-table (*gratitude-results-index*)
      (dolist (result (gethash id *gratitude-results-index*))
        (geo-index-remove *activity-geo-index* result))
      (remhash id *gratitude-results-index*))

    (with-mutex (*recent-activity-mutex*)
      (asetf *recent-activity-index* (remove id it :key #'result-id)))

    (with-locked-hash-table (*profile-activity-index*)
      (dolist (person people)
        (asetf (gethash person *profile-activity-index*)
               (remove result it))))

    (when result (geo-index-remove *activity-geo-index* result))

    (with-locked-hash-table (*db-results*)
      (remhash id *db-results*)) ))

(defun delete-gratitude (id)
  (let* ((data (db id))
         (transaction-id (getf data :transaction-id))
         (transaction-pending-gratitude-p))
    (dolist (image-id (getf data :images))
      (delete-image image-id))
    (delete-comments id)
    ;; remove it from the transaction-log
    (when transaction-id
      (amodify-db transaction-id
                  :log (remove-if #'(lambda (event)
                                      (eql (getf event :comment) id))
                                  it))
      (setf transaction-pending-gratitude-p
            (transaction-pending-gratitude-p transaction-id))

      (if (and transaction-pending-gratitude-p (getf data :on))
        (let* ((item-id (getf data :on))
               (item (db item-id))
               (by (getf item :by))
               (result (when item ; prior to 6/3/2014 inventory items could be deleted
                         (inventory-item-result item-id
                                                :data item
                                                :by-id by))))

          (when result
            (with-locked-hash-table (*pending-gratitude-index*)
              (case (getf item :type)
                (:offer
                  (pushnew (cons result id)
                           (getf (gethash (getf data :by)
                                          *pending-gratitude-index*)
                                 :offers)
                           :test #'equal))
                (:request
                  (pushnew (cons result id)
                            (getf (gethash by *pending-gratitude-index*)
                                  :requests)
                            :test #'equal)))))))))

  (when (gethash id *db-messages*)
    (remove-message-from-indexes id))
  (deindex-gratitude id)
  (remove-from-db id))

(defun gratitude-on-item-html
  (gratitude-id
    &key gratitude-data
         on-data
    &aux (gratitude-data (or gratitude-data (db gratitude-id)))
         (on-id (getf gratitude-data :on))
         (on-data (or on-data (db on-id)))
         (on-type (getf on-data :type))
         (on-title (getf on-data :title))
         (on-details (getf on-data :details))
         (on-url (strcat (if (eq on-type :offer) "offers/" "/requests/") on-id)))

  (html
    (:div
      (:div :class "gratitude-on-item"
        (:img :alt "sharing:" :src "/media/icons/share.png")
        (case on-type
          (:offer
            (htm
              (str (person-link (getf on-data :by)))
              " shared a gift with "
              (str (person-link (getf gratitude-data :author)))))
          (:request
            (htm
              (str (name-list (getf gratitude-data :subjects)))
              " fulfilled "
              (str (person-link (getf gratitude-data :author) :possessive t))
              (:a :href on-url "request")
              )))
        (:div
          (when on-title
            (htm
              (:h3 (:a :href on-url (str on-title)))))
          (when on-details
            (str (ellipsis on-details :length 81 :see-more on-url))))))))

(defun select-linked-inventory-html (result &key on-id)
  (html
    (:tr :class "select-linked-inventory"
      (:td (:input :type "radio"
                   :name "on-id"
                   :value (str (result-id result))
                   :checked (when (eql on-id (result-id result))
                              "checked")))
      (:td
        (:div :class "option-text"
          (str (inventory-item-content result
                                       :truncate t
                                       :show-distance t)))))))

(defun simple-gratitude-compose
  (entity-id
   &key (entity (db entity-id))
        (button-location :right)
        next
        transaction-id
        post-as
        on-id
        autofocus-p
        (submit-name "submit")
   &aux (groupid (when (eql (getf entity :type) :group) entity-id))
        (submit-button (html (:button :class "yes submit" :type "submit" :name submit-name "Post"))))
  (html
    (:div :class "post-gratitude item"
     (:h4 "Do you have gratitude to share for " (str (getf entity :name)) "?")
     (:form :method "post" :action "/gratitude/new"
       (unless (or post-as (member *userid* (getf entity :admins)))
         (awhen (groups-with-user-as-admin)
           (htm
             (:strong :class "small" "Post gratitude from "))
             (str (identity-selection-html (or groupid *userid*)
                                           it
                                           :class "identity small profile-gratitude"))))
       (awhen post-as
         (htm (:input :type "hidden" :name "identity-selection" :value it)))
       (awhen on-id
         (htm (:input :type "hidden" :name "on-id" :value it)))
       (awhen transaction-id
         (htm (:input :type "hidden" :name "transaction-id" :value it)))
       (:input :type "hidden" :name "subject" :value entity-id)
       (:input :type "hidden" :name "next" :value next)
       (:table :class "post"
        (:tr
          (:td (:textarea :cols "1000" :rows "4" :name "text" :autofocus autofocus-p))
          (when (eq button-location :right)
            (htm (:td (str submit-button)))))
        (when (eql button-location :bottom)
          (htm
            (:tr
              (:td
                (:button :class "cancel"
                         :type "submit"
                         :name "cancel"
                  "Cancel")
                (str submit-button))))))))))

(defun gratitude-compose
  (&key error
        subjects
        text
        next
        existing-url
        single-recipient
        single-recipient-name
        groupid
        on-type
        on-id
        on-item
        relevant-offers
        relevant-requests
   &aux (submit-buttons
          (html
            (:tr :class "select-linked-inventory" 
              (:td)
              (:td
                (:button :type "submit"
                         :class "cancel"
                         :name "cancel"
                         "Cancel")
                 (:button :class "yes"
                          :type "submit"
                          :name "create"
                          (str (if existing-url "Save" "Create"))))))))
  (if subjects
    (standard-page
      (if existing-url "Edit your statement of gratitude" "Express gratitude")
      (html
        (when error (flash (getf error :text) :error t))
        (:div :class "item"
         (:h2 (str (if existing-url "Edit your statement of gratitude"
                     "Express gratitude")))
         (:div :class "item"
          (:form :method "post"
           :action (or existing-url "/gratitude/new")
           :class "recipients"
           (:label "About:")
           (:menu :type "toolbar" :class "recipients"
            (unless subjects
              (htm (:li (:em "nobody yet"))))
            (dolist (subject subjects)
              (htm
                (:li
                  (str (db subject :name))
                  (unless (or single-recipient existing-url)
                    (htm
                      (:button :class "text large x-remove" :type "submit" :name "remove" :value subject " ⨯ "))))))
            (unless (or single-recipient existing-url)
              (htm
                (:li :class "recipients" (:button :type "submit" :class "text" :name "add" :value "new" "+ Add a person or group")))))

           (when subjects
             (htm (:input :type "hidden" :name "subject" :value (format nil "~{~A~^,~}" subjects))))
           (when next
             (htm (:input :type "hidden" :name "next" :value next)))

           (unless existing-url
             (awhen (groups-with-user-as-admin)
               (htm
                 (:div :class "clear"
                  (:label :class "from" "From:")
                  (str (identity-selection-html (or groupid *userid*)
                                                it
                                                :class "identity recipients profile-gratitude"
                                                :onchange "this.form.submit()"))))))
           (:textarea :rows "8" :name "text" (str text))

           (:div :class (s+ "gratitude-selectors "
                            (when (string= (getf error :field) "on-type")
                              "error-border"))
            (:h3 :class (when (string= (getf error :field) "on-type") "red")
             "This statement of gratitude is for...")

            (when (and relevant-offers
                       single-recipient-name)
              (htm
                (:div ;:class "inline-block"
                  (:input :type "radio"
                   :name "on-type"
                   :value "offer"
                   :onclick "this.form.submit()"
                   :checked (when (string= on-type "offer") "checked"))
                  "An offer posted by "
                  (str single-recipient-name))))

            (when relevant-requests
              (htm
                (:div ;:class "inline-block"
                  (:input :type "radio"
                   :name "on-type"
                   :value "request"
                   :onclick "this.form.submit()"
                   :checked (when (string= on-type "request") "checked"))
                  "A request I made on Kindista")))

            (when (or relevant-offers relevant-requests)
              (htm
                (:div ;:class "inline-block"
                  (:input :type "radio"
                   :name "on-type"
                   :value "other"
                   :onclick "this.form.submit()"
                   :checked (when (string= on-type "other") "checked"))
                  "Something else"))))

           (if (and (or relevant-offers relevant-requests)
                    on-type
                    (not (string= on-type "other")))
             (htm
               (:div :class (s+ "gratitude-selectors "
                                (when (string= (getf error :field) "on-id")
                                  "error-border"))
                (:h3 :class (when (string= (getf error :field) "on-id") "red")
                 "Please select the "
                 (str on-type)
                 " you are posting gratitude about:")

                (:table
                  (loop for i from 1
                        for result in (if (string= on-type "offer")
                                        relevant-offers
                                        relevant-requests)

                        do (str (select-linked-inventory-html result :on-id on-id))
                        when (eql (mod i 3) 0)
                        do (str submit-buttons)
                        finally (unless (eql (mod i 3) 1)
                                  (htm
                                    (:tr (:td)
                                     (:td (str submit-buttons)))))))))

             (htm
               (awhen on-item
                 (str it))

               (:p
                 (:button :type "submit"
                  :class "cancel"
                  :name "cancel"
                  "Cancel")
                 (:button :class "yes"
                  :type "submit"
                  :name "create"
                  (str (if existing-url "Save" "Create")))))))))))

    ;; else
    (gratitude-add-subject :text text :next next)))

(defun gratitude-add-subject (&key subjects text next (results 'none) groupid)
  (standard-page
    "Express gratitude"
    (html
      (:div :class "item"
       (str (pending-disclaimer "statement of gratitude"))
       (:h2 "Who would you like to write about?")
       (:h3 "Search for a person or group")
       (:form :method "post" :class "new-gratitude" :action "/gratitude/new"
         (:input :type "text" :name "name")
         (:button :type "submit" :class "yes input-height" :name "search" "Search")

         (if (eq results 'none)
           (progn
             (htm
               (:h3 "Or, select one of your contacts")
               (:menu :type "toolbar"
                 (dolist (contact (contacts-alphabetically *user*))
                   (htm (:li (:button :class "text" :type "submit" :value (car contact) :name "add" (str (cadr contact)))))))))
           (progn
             (htm
               (:h3 "Search results")
               (dolist (group (car results))
                 (str (id-button (car group) "add")))
               (dolist (person (cdr results))
                 (str (id-button (car person) "add" (cdr person)))))))

         (:input :type "submit" :class "cancel" :name "cancel" :value "Back")

         (when groupid
           (htm (:input :type "hidden" :name "identity-selection" :value groupid)))
         (when subjects
           (htm (:input :type "hidden" :name "subject" :value (format nil "~{~A~^,~}" subjects))))
         (when next
           (htm (:input :type "hidden" :name "next" :value next)))

         (when text
           (htm (:input :type "hidden" :name "text" :value (escape-for-html text))))

         )))))

(defun get-gratitudes-new ()
  (require-user
    (gratitude-compose :subjects (parse-subject-list (get-parameter "subject"))
                       :next (referer))))

(defun possible-inventory-for-gratitude
  (thanker-id
    &optional thankee-id
    &aux (pending-gratitudes-by-account (gethash thanker-id
                                                 *pending-gratitude-index*))
         (pending-requests ; returns '((result . transaction-id)...)
           (mapcar #'car (getf pending-gratitudes-by-account :requests)))
         (pending-offers ; returns '((result . transaction-id)...)
           (mapcar #'car (getf pending-gratitudes-by-account :offers))))

    (flet ((calculate-relevant-items (pending-items all-account-items-of-type)
             (let ((relevant-items (when thankee-id
                                     (remove-if-not #'(lambda (result)
                                                        (find thankee-id
                                                              (result-people result)))
                                                    pending-items))))
               (remove nil
                       (append
                         relevant-items
                         (sort
                           (remove-private-items
                             (set-difference
                               (mapcar #'(lambda (id)
                                           (gethash id *db-results*))
                                       all-account-items-of-type)
                               relevant-items))
                           #'>
                           :key #'result-time))))))

      (list :offers (calculate-relevant-items
                      pending-offers
                      (when thankee-id
                        (append
                          (gethash thankee-id *account-inactive-offer-index*)
                          (gethash thankee-id *offer-index*))))
            :requests (calculate-relevant-items
                        pending-requests
                        (append
                          (gethash thanker-id *account-inactive-request-index*)
                          (gethash thanker-id *request-index*))))))

(defun post-gratitudes-new ()
  (require-active-user
    (let* ((groupid (post-parameter-integer "identity-selection"))
           (adminp (group-admin-p groupid))
           (recipient-id (if adminp groupid *userid*))
           (posted-on-type (post-parameter-string "on-type"))
           (on-types (cond
                       ((string= posted-on-type "offer") :offers)
                       ((string= posted-on-type "request") :requests)))
           (on-id (post-parameter-integer "on-id"))
           (text (post-parameter-string "text"))
           (next (post-parameter-string "next"))
           (subjects (remove (post-parameter-integer "remove")
                             (parse-subject-list
                               (format nil "~A,~A" (post-parameter "add")
                                                   (post-parameter "subject"))
                               :remove (write-to-string *userid*))))
           (single-recipient (or (post-parameter-integer "single-recipient")
                                 (when (= (length subjects) 1)
                                   (car subjects))))
           (single-recipient-name (db single-recipient :name))
           (relevant-inventory (possible-inventory-for-gratitude
                                 recipient-id
                                 single-recipient))
           (relevant-requests (getf relevant-inventory :requests))
           (transaction-id (post-parameter-integer "transaction-id"))
           (relevant-offers (getf relevant-inventory :offers)))

      (flet ((g-compose (&key single-recipient (subjects subjects) error)
               (gratitude-compose :subjects subjects
                                  :single-recipient single-recipient
                                  :single-recipient-name single-recipient-name
                                  :groupid (when adminp groupid)
                                  :text text
                                  :next next
                                  :on-type posted-on-type
                                  :on-id on-id
                                  :error error
                                  :relevant-offers relevant-offers
                                  :relevant-requests relevant-requests))

             (g-add-subject (&key results subjects)
               (gratitude-add-subject :results results
                                      :subjects subjects
                                      :text text
                                      :next next
                                      :groupid (when adminp groupid))))

        (cond
          ((post-parameter "cancel")
           (see-other (or next "/home")))

          ((not (confirmed-location))
           (flash "You must set your street address on your settings page before you can post gratitude about someone." :error t)
           (see-other (or next "/home")))

          ((post-parameter "add")
           (if (string= (post-parameter "add") "new")
             (g-add-subject
               :subjects subjects)
             (g-compose
               :single-recipient (post-parameter "single-recipient")
               :subjects subjects)))

          ((post-parameter "search")
           (g-add-subject
             :subjects (parse-subject-list (post-parameter "subject"))
             :results (cons (search-groups (post-parameter "name"))
                            (search-people (post-parameter "name")))))

          ((not text)
            (if transaction-id
              (progn
                (flash "Please enter some more details about what you are grateful for." :error t)
                (see-other (or next "/home")))
             (g-compose :error '(:text "Please enter some more details about what you are grateful for."
                                 :field "text"))))

          ((and (or relevant-offers relevant-requests)
                (not on-id)
                (not posted-on-type))
           (g-compose :error '(:text "Please let us know what this statement of gratitude is in reference to."
                               :field "on-type")))

          ((and (or (and relevant-offers (eq on-types :offers))
                    (and relevant-requests (eq on-types :requests)))
                (not (post-parameter "on-id"))
                (post-parameter "create"))
           (g-compose :error '(:text "Please select the item you are posting gratitude about from the list below."
                               :field "on-id")))

          ((and (post-parameter "create")
                subjects
                text)

           (let* ((time (get-universal-time))
                  (new-id (create-gratitude :author recipient-id
                                            :subjects (remove recipient-id
                                                              subjects)
                                            :on on-id
                                            :transaction-id transaction-id
                                            :time time
                                            :text text))
                  (gratitude-url (format nil "/gratitude/~A" new-id)))

             (if (getf *user* :pending)
               (progn
                 new-id
                 (flash "Your item has been recorded. It will be posted after you post an offer and we have a chance to review it. In the meantime, please consider posting additional offers, requests, or statements of gratitude. Thank you for your patience.")
                 (see-other (or next "/home")))
               (progn
                 (awhen on-id
                   (let* ((inventory-result (gethash on-id *db-results*))
                          (pending-association (assoc inventory-result
                                                      (getf (gethash recipient-id
                                                                     *pending-gratitude-index*)
                                                            on-types)))
                          (transaction-id (or (cdr pending-association)
                                              (post-parameter-integer "transaction-id"))))

                     (when pending-association

                       (with-locked-hash-table (*pending-gratitude-index*)
                         (asetf (getf (gethash recipient-id
                                               *pending-gratitude-index*)
                                      on-types)
                                (remove pending-association it :test #'equal))))

                     (when transaction-id
                       (amodify-db transaction-id
                                   :log (append
                                          it
                                          (list (list :time time
                                                      :party (if adminp
                                                               (cons *userid* groupid)
                                                               (list *userid*))
                                                      :action :gratitude-posted
                                                      :comment new-id)))))))

                 (flash "Your statement of gratitude has been posted")
                 (see-other (or next gratitude-url))))))

          (t
           (g-compose :subjects subjects)))))))


(defun get-gratitude (id)
  (setf id (parse-integer id))
  (aif (db id)
    (require-user
      (let* ((message (gethash id *db-messages*))
             (mailboxes (when message
                          (loop for person in (message-people message)
                                when (eq (caar person) *userid*)
                                collect (car person)))))

        (when (member (list *userid*) mailboxes :test #'equal)
          (update-folder-data message :read))

        (standard-page
          "Gratitude"
          (html
            (:div :class "gratitude item"
              (str (gratitude-activity-item (make-result :id id
                                                         :time (getf it :created)
                                                         :people (cons (getf it :author)
                                                                       (getf it :subjects))))))
            (str (item-images-html id)))
          :selected (awhen (get-parameter-string "menu") it))))
    (not-found)))

(defun post-gratitude (id)
  (require-active-user
    (setf id (parse-integer id))
    (aif (db id)
      (cond
        ((and (post-parameter "love")
              (member (getf it :type) '(:gratitude :offer :request)))
         (love id)
         (see-other (or (post-parameter "next") (referer))))
        ((and (post-parameter "unlove")
              (member (getf it :type) '(:gratitude :offer :request)))
         (unlove id)
         (see-other (or (post-parameter "next") (referer))))

        (t
         (require-test ((or (eql *userid* (getf it :author))
                            (group-admin-p (getf it :author))
                            (getf *user* :admin))
                       (s+ "You can only edit your own statatements of gratitude."))
           (cond
             ((post-parameter "delete")
              (confirm-delete :url (script-name*)
                              :type "gratitude"
                              :text (getf it :text)
                              :next-url (referer)))
             ((post-parameter "really-delete")
              (delete-gratitude id)
              (flash "Your statement of gratitude has been deleted!")
              (see-other (or (post-parameter "next") "/home")))
             ((post-parameter "edit")
              (see-other (strcat "/gratitude/" id "/edit")))))))
      (not-found))))

(defun get-gratitude-edit (id)
  (require-user
    (let* ((gratitude (db (parse-integer id)))
           (author (getf gratitude :author))
           (adminp (group-admin-p author)))
      (require-test ((or (eql *userid* author) adminp)
                     "You can only edit gratitudes you have written.")
        (let* ((subjects (getf gratitude :subjects))
               (single-recipient (when (= (length subjects) 1)
                                   (car subjects)))
               (on-item (awhen (getf gratitude :on)
                          (html (:blockquote (str (html-text (db it :details)))))))
               (relevant-inventory (unless on-item
                                     (possible-inventory-for-gratitude
                                       author
                                       single-recipient)))
               (relevant-requests (getf relevant-inventory :requests))
               (relevant-offers (getf relevant-inventory :offers)))
          (gratitude-compose :subjects subjects
                             :text (getf gratitude :text)
                             :on-item on-item
                             :relevant-offers relevant-offers
                             :relevant-requests relevant-requests
                             :existing-url (s+ "/gratitude/" id "/edit")))))))

(defun post-gratitude-edit (id)
  (require-user
    (let* ((gratitude (db (parse-integer id)))
           (author (getf gratitude :author)))
      (require-test ((or (eql *userid* author)
                         (group-admin-p author))
                     "You can only edit statements of gratitude that you have written.")
        (let* ((subjects (getf gratitude :subjects))
               (single-recipient (when (= (length subjects) 1)
                                   (car subjects)))
               (on-item (awhen (getf gratitude :on)
                          (html (:blockquote (str (html-text (db it :details)))))))
               (relevant-inventory (unless on-item
                                     (possible-inventory-for-gratitude
                                       author
                                       single-recipient)))
               (relevant-requests (getf relevant-inventory :requests))
               (relevant-offers (getf relevant-inventory :offers)) )

          (cond

            ((post-parameter "cancel")
             (see-other (or (post-parameter "next") "/home")))

            ((post-parameter "create")
               (if (post-parameter "text")
                 (progn
                   (modify-gratitude (parse-integer id) (post-parameter "text"))
                   (see-other (s+ "/gratitude/" id)))
                 "no text"))

            (t
             (gratitude-compose :subjects (getf gratitude :subjects)
                                :text (getf gratitude :text)
                                :on-item on-item
                                :relevant-offers relevant-offers
                                :relevant-requests relevant-requests
                                :existing-url (s+ "/gratitude/" id "/edit")))))))))
