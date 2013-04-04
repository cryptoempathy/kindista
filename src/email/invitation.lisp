(in-package :kindista)

(defun invitation-email-text (invitation-id token to from &key text)
  (let ((sender (getf (db from) :name)))
    (s+ sender
" has invited you to join Kindista, the social network for building "
"community and sharing local resources.
      
Your invitation code is " (write-to-string token) ".
This invitation will expire in 30 days. 

" 

      (when text
        (s+ sender " says: 
            \""
            text "\"
                  
"))

sender
" only has a limited number of invitations and they sent one to you"
" because they think you would make a valuable addition to the"
" Kindista community. 

"

"Please click on this link or copy and paste it into your browser"
" to RSVP: 
"
(url-compose (s+ +base-url+ "/signup")
             "id" invitation-id
             "email" to
             "token" token
             "from" sender)

"

You will then have the option to join Kindista, or decline the "
      " invitation so " sender " can give it to someone else.  
      
"
      "-The Kindista Team")))


(defun invitation-email-html (invitation-id token to from &key text)
  (let ((sender (getf (db from) :name)))
    (html-email-base
      (html
        (:p :style *style-p* 
          (str (person-email-link from)) 
          " has invited you to join Kindista, the social network for building "
          "community and sharing local resources. ")
        
        (:p :style *style-p*
         "Your invitation code is " (:strong (str (write-to-string token)) ".")         
         (:br)
         "This invitation will expire in 30 days.")

        (when text
          (htm (:table :cellspacing 0
                       :cellpadding 0
                       :style *style-quote-box*
                 (:tr (:td :style "padding: 4px 12px;"

                        (str sender) " says:"
                          (:br)
                          "\"" (str text) "\"")))))

        (:p :style *style-p*
          (str sender)
          " only has a limited number of invitations and they sent one to you"
          " because they think you would make a valuable addition to the"
          " Kindista community.  ")

        (:p :style *style-p* 
          "Please click on this link or copy and paste it into your browser"
          " to RSVP: "
          (:br)
          (:a :href (url-compose (s+ +base-url+ "/signup")
                                 "id" invitation-id
                                 "email" to
                                 "from" sender
                                 "token" token
                                 )
                    (str (url-compose (s+ +base-url+ "/signup")
                                      "id" invitation-id
                                      "email" to
                                      "from" sender
                                      "token" token
                                      ))))


        (:p :style *style-p* 
          "You will then have the option to join Kindista, or decline the "
          " invitation so " (str sender) " can give it to someone else.  ")

        (:p "-The Kindista Team")))))
