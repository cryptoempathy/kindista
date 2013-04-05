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

(defun get-login ()
  (with-user
    (if *user*
      (see-other "/home")
      (standard-page
        "Login"
        (html
          (:form :method "POST" :action "/login" :id "login"
            (awhen (get-parameter "retry")
              (htm (:p :class "error" "The email/username or password was incorrect.")
                   (unless (string= it "")
                       (htm (:p (:a :href (s+ "/signup?email=" it)
                                    "Would you like to create an account?"))))))
            (awhen (get-parameter "next")
              (htm (:input :type "hidden" :name "next" :value it)))
            (:label :for "username" "Username or email")
            (:input :type "text" :name "username" :value (get-parameter "retry"))
            (:label :for "password" "Password")
            (:input :type "password" :name "password")
            (:input :type "submit" :value "Log in")
            (:p (:a :href "/reset" "Forgot your password?"))
            (:p "New to Kindista?"
             (:br)
             (:a :href "/signup" "Create an account"))))))))

(defun post-login ()
  (with-token
    (let ((user (post-parameter "username"))
          (next (post-parameter "next")))
      (if (find #\@ user :test #'equal)
        (setf user (gethash user *email-index*))
        (setf user (gethash user *username-index*)))
      (cond
        ((password-match-p user (post-parameter "password"))
         (setf (token-userid *token*) user)
         (setf (return-code*) +http-see-other+)
         (setf (header-out :location) (if (and (< 0 (length next))
                                               (equal #\/ (elt next 0)))
                                        next
                                        "/home"))
         (notice :login "")
         "")
        (t
         (setf (return-code*) +http-see-other+)
         (setf (header-out :location) "/home")
         (flash "<p>The email or password you entered was not recognized.</p><p>Please try again.</p><p>If you would like to join Kindista please request an invitation from someone you know.</p>" :error t)
         (notice :auth-failure "")
         "")))))

(defun get-logout ()
  (notice :logout "")
  (delete-token-cookie)
  (see-other "/"))