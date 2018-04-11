require 'aws-sdk-mturk'



mturk = Aws::MTurk::Client.new()


resp = mturk.notify_workers({
  subject: "Food and agriculture survey: you have won the gift card",
  message_text: "You recently completed a survy regarding food and agriculture, and elected to receive a portion of your bonus in the form of a chance in a drawing for a $50(US) giftcard for Harry and Davids.  You have won the gift card.  Please email your mailing address to john.blakkan@berkeley.edu, and the card will be mailed to you.",
  worker_ids: ["A298V1W5XVLKIZ"]
  })

p resp


p resp.notify_workers_failure_statuses #=> Array
p resp.notify_workers_failure_statuses[0].notify_workers_failure_code #=> String, one of "SoftFailure", "HardFailure"
p resp.notify_workers_failure_statuses[0].notify_workers_failure_message #=> String
p resp.notify_workers_failure_statuses[0].worker_id #=> String
