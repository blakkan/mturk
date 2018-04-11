require 'aws-sdk-mturk'
require 'qualtrics_api'
require 'csv'

#
# Get hash of bonus cash requestors, indexed by completion number from Qualtrics
# Note it is possible for qualtrics to have more survey takers than mTurk will have
# (e.g. race condition at end of survey, etc.)
#
code_to_payoff = {}
code_to_status = {}
code_to_cumulative_bonus = {}


CSV.read("F.csv").drop(3).each do |r|
  if code_to_payoff.key?(r[-1])
    puts "Saw duplicate of completion code #{r[-1]} in the qualtrics data"
    exit()
  end
  code_to_payoff[r[-1]] = { 'cash' =>  r[-4], 'beef' => r[-3], 'fruit' => r[-2] }
end





# Now read it from amazon
mturk = Aws::MTurk::Client.new()

QualtricsAPI.configure do |config|
  config.api_token = ENV['QUALTRICS_KEY']
end

code_to_assignment_id = {}
code_to_worker_id = {}
worker_seen_set = {}
#
# Search throug all our human intelligence tasks, just look for the one of interest
#

mturk.list_hits.hits.each do |the_hit|

  #This is the one of interest
  next unless the_hit.title =~ /griculture/
  ###puts "HIT id: #{the_hit.hit_id}  Title: #{the_hit.title}  Completed: #{the_hit.number_of_assignments_completed}"
  ###puts " HIT status: #{the_hit.hit_status}  Review status: #{the_hit.hit_review_status}  Reward: #{the_hit.reward}"
  ###puts " HIT status: #{the_hit.number_of_assignments_pending}"

  #Now step through the assignments; verify unique workers

  mturk.list_assignments_for_hit(hit_id: the_hit.hit_id, max_results: 100).assignments.each do |the_assignment|
    #puts "    assignment_id: #{the_assignment.assignment_id}  assignment_status: #{the_assignment.assignment_status}"
    #puts "    worker_id: #{the_assignment.worker_id}"

    #extract the code, use it to index, the point this to the assignment_id
    if code_to_assignment_id.include?(Nokogiri::XML(the_assignment.answer).at_css("FreeText").child.text)
      puts "In mturk data, saw duplicate of #{Nokogiri::XML(the_assignment.answer).at_css("FreeText").child.text}"
      exit()
    else
      code_to_assignment_id[Nokogiri::XML(the_assignment.answer).at_css("FreeText").child.text] =
        the_assignment.assignment_id
      code_to_status[Nokogiri::XML(the_assignment.answer).at_css("FreeText").child.text] =
        the_assignment.assignment_status
      code_to_worker_id[Nokogiri::XML(the_assignment.answer).at_css("FreeText").child.text] =
        the_assignment.worker_id
    end

    #Now just a paranoid check for duplicate workers
    if worker_seen_set.include?(the_assignment.worker_id)
      puts("in mturk data, saw duplicate worker id #{the_hit.worker_id}")
      exit()
    else
      worker_seen_set[the_assignment.worker_id] = true
    end

    #Now get all the bonues paid so far.
    code_to_cumulative_bonus[Nokogiri::XML(the_assignment.answer).at_css("FreeText").child.text] =
      mturk.list_bonus_payments(assignment_id: the_assignment.assignment_id).bonus_payments.reduce(0) do |sum,payment|
        sum += payment.bonus_amount.to_i
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

puts "Length of list #{matching_list.length}"
puts matching_list.sort
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
# Now we will pay
#
exit()
code_to_assignment_id.keys.sort.each do |key|

  puts "considering paying"
  if code_to_status[key] == "Submitted"
    puts "Approving"
     mturk.approve_assignment({assignment_id: code_to_assignment_id[key],
                            requester_feedback: "Thank you for completing our food and agriculture survey (bonus will be processed shortly)"})

     if code_to_payoff[key]['cash'].to_i > code_to_cumulative_bonus[key].to_i
  ##       mturk.send_bonus(worker_id: code_to_worker_id[key],
  ##                    bonus_amount: ((code_to_payoff[key]['cash'].to_i - code_to_cumulative_bonus[key].to_i).to_f/100.00).to_s,
  ##                    assignment_id: code_to_assignment_id[key],
  ##                    reason: "Cash portion of bonus you selected; if you entered drawing, winner will be contacted by March 31" )
         puts "paying some bonus"
     else
       puts "already paid maximum requested bonus"
     end
  elsif code_to_status[key] == "Approved"
    puts "Considering bonus"
    puts code_to_worker_id[key]
    puts ((code_to_payoff[key]['cash'].to_i - code_to_cumulative_bonus[key].to_i).to_f/100.00).to_s
    puts code_to_assignment_id[key]

    if code_to_payoff[key]['cash'].to_i > code_to_cumulative_bonus[key].to_i
  ##      mturk.send_bonus(worker_id: code_to_worker_id[key],
  ##                   bonus_amount: ((code_to_payoff[key]['cash'].to_i - code_to_cumulative_bonus[key].to_i).to_f/100.00).to_s,
  ##                   assignment_id: code_to_assignment_id[key],
  ##                   reason: "Cash portion of bonus you selected; if you entered drawing, winner will be contacted by March 31" )
        puts "paying some bonus"
    else
      puts "Not paying bonus, nothing left to pay"
    end
  else

    puts "already something other than submitted, so not paying"
  end

end
