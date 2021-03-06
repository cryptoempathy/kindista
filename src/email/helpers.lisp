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

(defparameter *style-a* "color:#5c8a2f;
                         text-decoration:none;")

(defparameter *style-p* "max-width:70em;
                         margin-top:.9em;
                         margin-bottom:.9em;")

(defparameter *style-quote-box* "border-collapse: collapse;
                                 background: #ebf2e4;
                                 margin: 8px;
                                 border: thin solid #bac2b2;")

(defparameter *email-url* (or (awhen *test-email-ip*
                                (s+ it "/"))
                              +base-url+))

(defun person-email-link (id)
  (awhen (db id)
    (html
      (:a :href (strcat *email-url*
                        (if (eql (getf it :type) :person)
                          "people/"
                          "groups/")
                        (username-or-id id))
          (str (getf it :name))))))

(defun person-name (id)
  (db id :name))

(defun no-reply-notice
  (&optional (instructions "do so from their profile on Kindista.org"))
  (strcat "PLEASE DO NOT REPLY TO THIS EMAIL, IT WILL NOT BE DELIVERED TO THE SENDER. If you want to contact the sender, please " instructions "."))

(defun amazon-smile-reminder (&optional html)
  (if html
    (html
      (:div :class *style-p*
         "Do you shop at Amazon.com? If so, please "
         (:a :href *amazon-smile-link* "click here")
         " and Amazon will donate a portion of your purchases to Kindista through our parent organization, CommonGoods Network."))
    (strcat
      #\linefeed #\linefeed
      "Do you shop at Amazon.com? If so, please click here and Amazon will donate a portion of your purchases to Kindista through our parent organization, CommonGoods Network:"
      #\linefeed
      *amazon-smile-link*)))

(defun unsubscribe-notice-ps-text
  (unsubscribe-code
   email-address
   notification-description
   &key (detailed-notification-description notification-description)
        groupid)

(strcat*
#\linefeed #\linefeed
"-------------------------------------"
#\linefeed
"Why am I receiving this? "
"In your Kindista communications settings, you are subscribed to receive "
notification-description
". "
"If you no longer wish to receive "
detailed-notification-description
", you may unsubscribe: "
#\linefeed
(unsubscribe-url email-address unsubscribe-code groupid)))

(defun unsubscribe-notice-ps-html
  (unsubscribe-code
   email-address
   notification-description
   &key (detailed-notification-description notification-description)
        groupid)
(html
  (:p :style (s+ *style-p* " font-size: 0.85em;")
    "Why am I receiving this? "
    "In your Kindista communications settings, you are subscribed to receive "
    (str notification-description)
    ". "
    "If you no longer wish to receive "
    (str detailed-notification-description)
    ", you may "
    (:a :href (unsubscribe-url email-address unsubscribe-code groupid)
        "unsubscribe")
    ".")))

(defun unsubscribe-url (email-address unsubscribe-code &optional groupid)
  (url-compose (strcat *email-url* "settings/communication")
               "groupid" groupid
               "email" email-address
               "k" unsubscribe-code))

(defun html-email-base (content)
  (html
    (:html
      (:head
        (:style :type "text/css"
                      "a:hover {text-decoration:underline;}
a {color: #5C8A2F;}")
        (:title "Kindista"))

      (:body :style "font-family: Ubuntu, Roboto, \"Segoe UI\", \"Helvetica Neue\", Tahoma, sans-serif;"
        (:table :cellspacing 0
                :cellpadding 0
                :style "border-collapse: collapse; width: 98%;"
                :border 0

          (:tr (:td :style "background: #fafafa;
                            border-bottom: 1px solid #eeeeee;
                            padding: 6px 6px 3px;"

                 (:a :href "http://kindista.org/"
                     :style "text-decoration: none;
                             color: #799f56;
                             font-size: 22px;
                             font-weight: 500;"
                     (:img :src "http://media.kindista.org/logo.png" :alt "kindista" :width 136 :height 26))))

          (:tr (:td :style "padding: 10px;
                            color: #000000;
                            background: #ffffff;"
                 (str content))))))))
