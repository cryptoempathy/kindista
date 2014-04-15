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

(defun signup-identity-selection ()
  (html
    (:div :class "identity-selection"
      (:h3 "What kind of an account is this?")
      (:input :type "radio"
       :class "first-option"
              :name "account-type"
              :value "person") 
      "An individual person"
      (:input :type "radio"
              :name "account-type"
              :value "group") 
      "A group (business, non-profit, school, community, church, etc.)")))

(defun signup-page (&key error name email)
  (standard-page
    "Sign up"
    (html
      (:h2 "Sign up for Kindista ")
      (:h3 "Step 1 of 3: Verify Your Email Address")
      (:p (:em
            (:strong "Please note: ")
            "To prevent spam and abuse, some features on "
            "Kindista may only be available after you post your first "
            "offers and we have a chance to review your initial activity. "
            (:br)
            (:strong :class "red"
             " If you have already recieved an invitation to join Kindista "
             "from us or from a friend , please follow the link in your "
             "invitation email instead of filling out this form.")))
      (:form :method "POST" :action "/signup" :id "signup"
        (when error
          (flash error :error t))
        (:label :for "name" "Full Name")
        (:input :type "text" :id "name" :name "name" :value name)
        (:br)
        (:label :for "email" "Email")
        (:input :type "text" :id "email" :name "email" :value email)
        (:br)
        (:label :for "email-2" "Confirm Email")
        (:input :type "text" :id "email-2" :name "email-2")
        (:br)
        (:div
          (str (signup-identity-selection)))
        (:p :class "fineprint" "By creating an account, you are agreeing to our "
          (:a :href "/terms" "Terms of Service") " and " (:a :href "/privacy" "Privacy Policy"))

        (:br)
        (:button :class "yes" :type "submit" "Sign up") 

        (:span "Already have an account? " (:a :href "/login" "Log in"))))))

(defun email-verification-page (&key error name email token host)
  (standard-page
    "Sign up"
    (html
      (if (eq host +kindista-id+)
        (htm (:h2 "Create a Kindista account")
             (:h3 "Step 2 of 3: Set your password"))
        (htm (:h2 "Please RSVP to your invitation. ")))
      (:p "Your activation code is:  " (:strong (str token))
        (:br) "Your email address is: " (:strong (str email)))
      (:p "You will be able to change your email address on the Settings page after you sign up.")
      (:form :method "POST" :action "/signup" :id "signup"
        (:input :type "hidden" :name "token" :value token)
        (:input :type "hidden" :name "email" :value email)
        (unless (eq host +kindista-id+)
          (htm (:h2 "Create an account")))
        (when error
          (flash error :error t))
        (:label :for "name" "Full Name")
        (:input :type "text" :id "name" :name "name" :value name)
        (:br)
        (:label :for "password" "Password")
        (:input :type "password" :id "password" :name "password")
        (:br)
        (:label :for "password-2" "Confirm Password")
        (:input :type "password" :id "password" :name "password-2")
        (:div
          (str (signup-identity-selection)))
        (:p :class "fineprint" "By creating an account, you are agreeing to our "
          (:a :href "/terms" "Terms of Service") " and " (:a :href "/privacy" "Privacy Policy"))

        (:br)
        (:button :class "yes" :type "submit" "Sign up") 

        (:span "Already have an account? " (:a :href "/login" "Log in"))))

    :top (when (get-parameter "action")
           (welcome-bar
             (html
               "If you want to do more than browse and search Kindista, you'll need to "
               (:a :href "/signup" "create an account") ". Or, " (:a :href "/login" "log in")
               " if you've already got one!")
             nil))))

(defun get-signup ()
  (let* ((get-email (get-parameter "email"))
         (get-token (get-parameter "token"))
         (valid-email (gethash get-email *invitation-index*))
         (valid-token (rassoc get-token valid-email :test #'equal))
         (invitation-id (car valid-token))
         (invitation (db invitation-id))
         (host (getf invitation :host))
         (name (getf invitation :name)))
    (cond
      (*user*
       (see-other "/home"))
      ((and get-token (not valid-token))
       (flash "Your invitation code is incorrect or is no longer valid. No worries, you can still sign up for Kindista below.") 
       (signup-page))
      ((not valid-token)
       (signup-page))
      (t
       (email-verification-page :email get-email
                                :token get-token
                                :host host
                                :name name)))))

(defun post-signup ()
  (with-user
    (let* ((token (post-parameter "token"))
           (person-p (string= (post-parameter "account-type") "person"))
           (group-p (string= (post-parameter "account-type") "group"))
           (name (unless group-p (post-parameter "name")))
           (email (post-parameter "email"))
           (valid-email-invites (gethash email *invitation-index*))
           (valid-token (rassoc token valid-email-invites :test #'equal))
           (id (car valid-token))
           (invitation (db id))
           (host (getf invitation :host))
           (invite-request-id (getf invitation :invite-request-id))
           (new-id nil))
      (when *user* (reset-token-cookie))
      (if invitation
        (labels ((try-again (e)
                   (email-verification-page :error e
                                            :name name
                                            :email email
                                            :token token
                                            :host host)))
          (cond
            ((not valid-token)
             (try-again "The invitation code you have entered is not valid. Please sign up using te link provided in a valid Kindista invitation."))
            ((gethash email *banned-emails-index*)
             (flash (s+ "The email you have entered, "
                        email
                        ", is associated with an account "
                        "that has been banned for posting inappropriate "
                        "content or otherwise violating Kindista's "
                        "Terms of Use. "
                        "If you believe this to be an error, please email us "
                        "so we can resolve this issue.")
                    :error t)
             (see-other "/home"))

            ((gethash email *email-index*)
             (try-again "The email address you have entered already belongs to another Kindista member. Please try again, or contact us if this really is your email address."))

            ((< (getf invitation :valid-until) (get-universal-time))
             (try-again "Your invitation has expired. Please contact the person who invited you to join Kindista and request another invitation."))

            (group-p
             (try-again "This form is for creating personal accounts only. Once you create your personal account you can create group accounts from the \"Groups\" section of Kindista. If you ignore this warning you will create mass confusion for our community and will not be able to invite people to join your group. (Also we will probably end up deleting group accounts created with this form.)"))

            ((not (and (< 0 (length name))
                       (< 0 (length (post-parameter "password")))
                       (< 0 (length (post-parameter "password-2")))))
             (try-again "All fields are required"))
            ((> 8 (length (post-parameter "password")))
             (try-again "Please use a strong password of at least 8 characters."))
            ((not (validate-name name))
             (try-again "Please use your full name"))
            ((not (string= (post-parameter "password") (post-parameter "password-2")))
             (try-again "Your password confirmation did not match the password you entered."))

            ((not person-p)
              (try-again "Please select an account type"))

            (t
               (setf new-id
                     (if (integerp invite-request-id)
                       ;for legacy invitation requests
                       ;this can be removed when there are no 
                       ;invite requests in *invite-request-index*
                       (let ((it invite-request-id))
                         (progn
                           (modify-db it :type :person
                                         :name name
                                         :emails (list email)
                                         :host +kindista-id+
                                         :active t
                                         :help t
                                         :pass (new-password (post-parameter "password"))
                                         :created (get-universal-time)
                                         :notify-gratitude t
                                         :notify-message t
                                         :notify-kindista t
                                         :notify-reminders t
                                         :email nil
                                         :requested nil)
                           (with-locked-hash-table (*db-results*)
                             (remhash it *db-results*))
                           (when (member it *invite-request-index* :key #'result-id)
                             (with-mutex (*invite-request-mutex*)
                              (setf *invite-request-index* (remove it *invite-request-index* :key #'result-id))))
                           (index-person it (db it))
                           it))
                       (create-person :name (post-parameter "name")
                                      :pending (when (eq host +kindista-id+) t)
                                      :host host
                                      :email (post-parameter "email")
                                      :password (post-parameter "password"))))
               (setf (token-userid *token*) new-id)
               (dolist (group (getf invitation :groups))
                 (add-group-member new-id group))
               (add-contact host new-id)
               (with-locked-hash-table (*invited-index*)
                 (pushnew new-id (gethash host *invited-index*)))
               ;; see if anyone has invited this email to a group
               ;; or added to contacts
               (pending-email-actions email new-id)
               (see-other "/home"))))

    (labels ((try-again (e)
               (signup-page :error e :name name :email email)))
      (cond
        (group-p
         (try-again "This form is for creating personal accounts only. Once you create your personal account you can create group accounts from the \"Groups\" section of Kindista. If you ignore this warning you will create mass confusion for our community and will not be able to invite people to join your group. (Also we will probably end up deleting group accounts created with this form.)"))

        ((not (validate-name name))
         (try-again "Please use your full name"))

        ((not (scan +email-scanner+ email))
         (try-again "There was a problem with the email address you entered. Please use a valid email address."))

        ((not (string= email (post-parameter "email-2")))
         (try-again "Your email confirmation did not match the email you entered"))
        ((not person-p)
         (try-again "Please select an account type"))

        (t
         (aif (find email (unconfirmed-invites +kindista-id+)
                    :key #'(lambda (item) (getf item :email))
                    :test #'string=)
           (resend-invitation (getf it :id))
           (create-invitation email :host +kindista-id+
                                    :name name
                                    :expires (* 90 +day-in-seconds+)))
         (flash "We have sent an invitation to the email address you entered. Please check your email and follow the instructions we sent you to complete the sign-up process.")
         (see-other "/home"))))))))
