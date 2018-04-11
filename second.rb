require 'aws-sdk-mturk'
require 'qualtrics_api'
require 'csv'
require 'zipruby'

#
# Get hash of bonus cash requestors, indexed by completion number from Qualtrics
# Note it is possible for qualtrics to have more survey takers than mTurk will have
# (e.g. race condition at end of survey, etc.)
#
code_to_payoff = {}
code_to_status = {}
code_to_cumulative_bonus = {}


#
# set up the qualtrics api with the token from the environment
# (gotten from teh qualtrics management page)
#


QualtricsAPI.configure do |config|
  config.api_token = ENV['QUALTRICS_KEY']
end

#
# There are several surveys there, just pull in
# the agricultural one (hence the search for "cult")
#

j = QualtricsAPI.surveys.collect.find do |survey|
  survey.name =~ /cult/
end

export_service = j.export_responses({"format" => "csv"})
export = export_service.start

until export.completed?
  export.status
  sleep(1)
end

#
# Great moments in software engineering:  Too lazy to get the thing
# with HTTP calls, just shell out to curl (Will want to change this
# if we ever make this into a web if __FILE__ == $PROGRAM_NAME
#


cmd =  "curl --header \"x-api-token: " + ENV['QUALTRICS_KEY'] + "\" "  +
             "--header \"content-type: application/json\" " +
             "--header \"format: csv\" " +
             export.file_url
###puts cmd
string_result = %x[ #{cmd} ]

#And now fish it out of the zip archive; it should be the only thing
# in there, but loop on multiples, just for grins
k = []
Zip::Archive.open_buffer(string_result) do |archive|
  archive.each_with_index do |entry, index|
    k[index] = entry.read
  end
end

#
# At this point, k[0] ought ot have our results
#puts k[0]
#exit()






#
# Now lets step through our csv file.  We need to toss the
# first 3 lines, since they're the headers.

# This hardcodes the position of the requested cash payoff, beef payoff,
# and fruit payoff

# Build a hash indexed by the random completion code (no mturk information
# makes it to qualtrics, but the completion code will be copied from
# qualtrics into amazon by the subject)

CSV.parse(k[0]).drop(3).each do |r|
  if code_to_payoff.key?(r[-1])
    puts "Saw duplicate of completion code #{r[11]} in the qualtrics data"
    exit()
  end
  code_to_payoff[r[11]] = { 'cash' =>  r[45].to_f/100.0, 'beef' => r[46].to_f/100.0, 'fruit' => r[47].to_f/100.0 }
end



#
# Now read it from amazon
#
# This happens to pull in the user id and the user secret from a fixed file location or
# an environment variable, whichever it finds first
#
mturk = Aws::MTurk::Client.new()


code_to_assignment_id = {}
code_to_worker_id = {}
worker_seen_set = {}

#
# Search through all our human intelligence tasks, just look for the one of interest
#
mturk.list_hits.hits.each do |the_hit|

  #This is the one of interest; skip all others by early exit of the loop
  #TODO - won't work if we have more than one agriculture; will process more than once

  next unless the_hit.title =~ /griculture/

  # Loop through all the assignments for the HIT of interest (note that hard coded 100...)
  mturk.list_assignments_for_hit(hit_id: the_hit.hit_id, max_results: 100).assignments.each do |the_assignment|
    #puts "    assignment_id: #{the_assignment.assignment_id}  assignment_status: #{the_assignment.assignment_status}"
    #puts "    worker_id: #{the_assignment.worker_id}"

    #parse out the completion code code, use it to index, the point this to the assignment_id
    mturk_completion_code = Nokogiri::XML(the_assignment.answer).at_css("FreeText").child.text

    if code_to_assignment_id.include?(mturk_completion_code)
      puts "In mturk data, saw duplicate of #{mturk_completion_code}"
      exit()
    else
      code_to_assignment_id[mturk_completion_code] = the_assignment.assignment_id
      code_to_status[mturk_completion_code] = the_assignment.assignment_status
      code_to_worker_id[mturk_completion_code] = the_assignment.worker_id
    end

    #Now just a paranoid check for duplicate workers
    if worker_seen_set.include?(the_assignment.worker_id)
      puts("in mturk data, saw duplicate worker id #{the_hit.worker_id}")
      exit()
    else
      worker_seen_set[the_assignment.worker_id] = true
    end

    #Now get all the bonues paid so far for this assignment.
    code_to_cumulative_bonus[mturk_completion_code] =
      mturk.list_bonus_payments(assignment_id: the_assignment.assignment_id).bonus_payments.reduce(0.0) do |sum,payment|
        sum += payment.bonus_amount.to_f
      end
      #puts "        Bonus: #{payment.bonus_amount}   #{payment.reason}"
    #end

    #puts "    answer code: #{Nokogiri::XML(the_assignment.answer).at_css("FreeText").child.text}"
    #puts "    cash bonus requested:  #{bonus_cash[Nokogiri::XML(the_assignment.answer).at_css("FreeText").child.text]}"
    #mturk.list_bonus_payments(assignment_id: the_assignment.assignment_id).bonus_payments.each do |payment|
    #  puts "        Bonus: #{payment.bonus_amount}   #{payment.reason}"
    #end

  end

end

#
# Now let's check; we should have the same keys from both qualtrics and amazon
#


matching_list = code_to_payoff.keys().to_set & code_to_assignment_id.keys().to_set

####puts "Length of list #{matching_list.length}"
####puts matching_list.sort
puts "assignment,worker_id,bonus_cash_req,bonus_beef_req,bonus_fruit_req,status,comp_code,bonus_paid"
code_to_assignment_id.keys.sort.each do |key|
  puts "#{code_to_assignment_id[key]}, " +\
       "#{code_to_worker_id[key]}, " +\
       "#{code_to_payoff[key]['cash']}, " +\
       "#{code_to_payoff[key]['beef']}, " +\
       "#{code_to_payoff[key]['fruit']}, " +\
       "#{code_to_status[key]}, " +\
       "#{key}, " +\
       "#{code_to_cumulative_bonus[key]}"
end



#
# Now we will pay the requested cash amount less any cash already sent
#




code_to_assignment_id.keys.sort.each do |key|

  #next unless key =~ /0$/  #just do 10% in debug

  puts "considering paying"
  if code_to_status[key] == "Submitted"
    puts "Approving"
     mturk.approve_assignment({assignment_id: code_to_assignment_id[key],
                            requester_feedback: "Thank you for completing our food and agriculture survey (bonus will be processed shortly)"})
    puts "Considering bonus"
     if code_to_payoff[key]['cash'] > code_to_cumulative_bonus[key]
        payment = (code_to_payoff[key]['cash'] - code_to_cumulative_bonus[key]).to_s
      mturk.send_bonus(worker_id: code_to_worker_id[key],
                      bonus_amount: payment,
                      assignment_id: code_to_assignment_id[key],
                      reason: "Cash portion of bonus you selected; if you entered drawing, winner will be contacted by March 31" )
        puts "paying some bonus #{payment}"
     else
       puts "already paid maximum requested bonus"
     end
  elsif code_to_status[key] == "Approved"
    puts "Already approved, reconsidering bonus"

    if code_to_payoff[key]['cash'] > code_to_cumulative_bonus[key]
        payment = (code_to_payoff[key]['cash'] - code_to_cumulative_bonus[key]).to_s
        mturk.send_bonus(worker_id: code_to_worker_id[key],
                     bonus_amount: payment,
                     assignment_id: code_to_assignment_id[key],
                     reason: "Cash portion of bonus you selected; if you entered drawing, winner will be contacted by March 31" )
        puts "paying some bonus #{payment}"
    else
      puts "Not paying bonus, nothing left to pay"
    end
  else

    puts "already something other than submitted or approved, so not paying"
  end

end
