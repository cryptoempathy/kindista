## When posting new gratitude
[x] select whether it's for an existing offer/request or for something not on kindista
[x] when it's for an existing item, display potential items that could be associated with the gratitude

## Pending gratitude index
- key user/group id
- value: plist (:offers (results) :requests (results))

## Tracking inventory item transaction conversations
[x] combine top 2 options when replying to an inventory item (comment or question)
[x] change text in inbox for transaction items (is requesting/offering or has a question/comment)
[x] change replies to transactions
[x] create a transaction log property for each transaction
     - (:time time :party (personid . groupid) :action :value :gratitude gratitudeid)
[x] write a function for data migration
[x] edit transaction inbox item, conversation view, email notification as necessary (even when no comment has occured)
[x] what about gratitudes on inventory items w/o transactions
   - need a way to index for inbox
   - may need special treatment when deleting the gratitude
[x] finish editing indirect-object for transaction action text
[x] finish transaction-othe-party function
[x] test new email notification
[x] calculate number of transactions pending gratitude
   - number for user
   - number for user's groups
[x] allow giver to deactivate an offer within the trasaction UI
[x] test deleting gratitude
[x] choose options and language to display based on current data structure (current state of participant role)
[x] prompt statement of gratitude as necessary (in inbox, through email, through (see-other...) etc.
[x] test deleting inappropriate offer/request/pending-account
[x] inbox items have gratitude post link after gratitude has been posted
[x] gratitude activity item doesn't include the title for the on-item description
[x] remove dates from offers/requests pages
[x] big fucking button on inventory items to request/offer or reply
[x] test replying w/o offering/requesting
[x] test offering/requesting w/o a message
[x] test to make sure requesting/offering w/ a comment sends only one email
[x] change transaction email text before link
[x] change the inbox message for transactions where last action is a message
[ ] make transaction option buttons actual buttons
[x] confirm page for receipt or having given it
[x] on confirm receipt, send an email "congrats on receiving a gift, post gratitude"
[x] when you post an offer/request, flash "congrats, your offer/req has been posted"
[ ] change news to "current activity"

## TEST before server migration

## Server migration
[ ] stop-acceptor or end
[ ] ,d on migrate-to-new-transaction-format
[ ] quickload
[ ] load-db
[ ] pray
[ ] (run)

