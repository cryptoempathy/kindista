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

(defun go-home ()
  (see-other "/home"))

(defun home-rightbar ()
  (html
    #|
    (:div :style "padding-bottom: 1em;
                  border-bottom: 1px solid #ddd;
                  margin-bottom: 1em;"
      (:div :style "font-size: 2.5em; font-weight: bold" "2,000")
      (:div :style "font-size: 1em; font-weight: bold" "monthly donations")
      (:div :style "font-size: 2.5em; font-weight: bold" "$999,999")
      (:div :style "font-size: 1em; font-weight: bold" "per month of $99,999,999 " (:a :href "/donate" "goal"))
      (:button :style "font-size: 1.5em;
                       font-weight: bold;
                       background: #375497;
                       color: #fff;
                       border: 0;
                       border-radius: 4px;
                       margin-top: 0.5em;
                       padding: 0.25em 0.6em" "Donate to Kindista")
      (:div :style "font-size: 0.9em; margin-top: 1em;" (:a :href "#" "How does Kindista use the money?"))
      )
      |#
    (str (login-sidebar))

    (str (donate-sidebar))

    (str (invite-sidebar))

    (str (events-sidebar))

    (when *user*
      (let (people (suggested-people))
        (when people
          (htm
            (:div :class "item right only"
              (:h3 (:a :href "/people" "People") " with mutual connections")
              (:menu
                (dolist (data (suggested-people))
                  (htm
                    (:li (:a :href (strcat "/people/" (username-or-id (cdr data)))
                             (str (getf (db (cdr data)) :name))))))))))))))  

(defun standard-home ()
  (standard-page
    "Home"
    (html
      (:div :class "activity"
        (str 
          (menu-horiz "actions"
                      (html (:a :href "/gratitude/new" "express gratitude"))
                      (html (:a :href "/offers/new" "post an offer"))
                      (html (:a :href "/requests/new" "make a request"))
                      ;(:a :href "/announcements/new" "post announcement")
                      ))

      (when *user*
        (str (distance-selection-html "/home"
                                      :text "show activity within "
                                      :class "item")))
      (let ((page (if (scan +number-scanner+ (get-parameter "p"))
                   (parse-integer (get-parameter "p"))
                   0)))
        (with-location
          (str (local-activity-items :page page))))))
    :selected "home"
    :top (cond
           ((not *user*)
            (welcome-bar
              (html
                (:h2 "Kindista Demo")
                (:p "This is what Kindista looks like to someone living in Eugene, Oregon. "
                    "If you were logged in now, you'd see what's going on around you. "
                    "Use the menu "
                    (:span :class "menu-button" " (click the button on the header) ")
                    (:span :class "menu-showing" " on the left ")
                    " to explore the site.")
                (:p "Because we don't have the resources to fight spam, to create a Kindista account you will need an invitation from an existing Kindista member. Or, you can "
                    (:a :href "/request-invitation" (:strong "fill out an application")) "."))
              nil))
           ((getf *user* :help)
            (welcome-bar
              (html
                (:h2 "Getting started")
                (:p "We're so happy to have you join us! Here are some things you can do to get started:")
                (:ul
                  (unless (getf *user* :avatar)
                    (htm (:li (:a :href "/settings/personal" "Upload a picture") " so that other people can recognize you.")))
                  (:li (:a :href "/gratitude/new" "Express gratitude") " for someone who has affected your life.")
                  (:li (:a :href "/people" "Make a connection") " to say that you know someone.")
                  (:li (:a :href "/requests/new" "Post a request") " to the community for something you need.")
                  )
                (:p "On this page you can see what's going on around you and with people you have made
                     a connection with. Use the menu "
                    (:span :class "menu-button" " (click the button on the header) ")
                    (:span :class "menu-showing" " on the left ")
                    " to explore the site.")))))
  :right (home-rightbar)))

(defun newuser-home ()
  (standard-page
    "Welcome"
    (html
      (:div :class "item"
        (:div :class "setup"
          (:h2 "Welcome to Kindista!")
          (:p "Kindista is a social network for " (:strong "building and supporting real community") ".
               We use your location to help you find " (:strong "local people, offers, and events") ".
               To get started, we need to know where you call home.")
          (:p "We will never share your exact location with anyone else.
               If you would like to know more about how we use the information you share with us,
               please read our " (:a :href "/privacy" "privacy policy") ".")
          (:h2 "Where do you call home?")
          (:p 
            (:small
              "Enter a street address and click \"Next\". We'll show you a map to confirm the location."))
          (:form :method "post" :action "/settings"
            (:input :type "hidden" :name "next" :value "/home")
            (:input :type "text" 
                    :name "address" 
                    :placeholder "1600 Pennsylvania Avenue NW, Washington, DC"
                    :value (getf *user* :address))
            (:input :type "submit" :value "Next")))))
    :selected "home"))

(defun get-home ()
  (with-user
    (cond
      ((or (getf *user* :location) (not *user*))
       (notice :home)
       (standard-home))

      ((and (getf *user* :lat)
            (getf *user* :long))
       (notice :home-verify-location)
       (get-verify-address :next-url "/home"))

      (t
       (notice :home-setup)
       (newuser-home)))))
