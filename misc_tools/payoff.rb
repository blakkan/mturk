require 'aws-sdk-mturk'
require 'qualtrics_api'
require 'csv'
require 'zipruby'
require 'ethon'
require 'stringio'

#
# Get hash of bonus cash requestors, indexed by completion number from Qualtrics
# Note it is possible for qualtrics to have more survey takers than mTurk will have
# (e.g. race condition at end of survey, etc.)
#
code_to_payoff = {}
code_to_status = {}
code_to_cumulative_bonus = {}


########################################################################
#
# set up the qualtrics api with the token from the environment
# (gotten from the qualtrics management page), then pull down
# the survey results.
#
########################################################################

QualtricsAPI.configure do |config|
  config.api_token = ENV['QUALTRICS_KEY']
end

#
#
# There are several surveys there, just pull in
# the agricultural one (hence the search for "cult")
#
#

j = QualtricsAPI.surveys.collect.find do |survey|
  survey.name =~ /Pilot3/
end


export_service = j.export_responses({"format" => "csv", "use_labels" => true})
export = export_service.start

until export.completed?
  export.status
  sleep(1)
end


#
# use a ruby gem wrapper the curl lib rather than raw HTTP gets,
# just for convenience.
#

curl_instance = Ethon::Easy.new
curl_instance.http_request(export.file_url, :get, { :headers => {
    "x-api-token" => ENV['QUALTRICS_KEY'],
    "content-type" => "application/json",
    "format" => "csv"
  }})
curl_instance.perform


string_result = curl_instance.response_body





#And now fish it out of the zip archive; it should be the only thing
# in there, but loop on multiples, just for grins
k = []
tbl = nil
Zip::Archive.open_buffer(string_result) do |archive|
  archive.each_with_index do |entry, index|
    k[index] = entry.read
  end
end

#
# At this point, k[0] ought to have our max_results
#


list_with_extra_rows = k[0].split("\n")
string_without_extra_rows = ([list_with_extra_rows[0]] + list_with_extra_rows[3..-1]).join("\n")

file = Tempfile.new('spud')
file.write(string_without_extra_rows)
file.close


#array_of_arrays = CSV.parse(k[0])

#array_of_arrays.delete_at(1)  #get rid of long second and third lines
#array_of_arrays.delete_at(1)

#p array_of_arrays
#exit()


qualtrics_tbl = CSV.table(file.path)




file.unlink


# Remove anything without an mturk code; this would be an incomplete surveys
qualtrics_tbl.delete_if { |row| row[:mturkcode].nil? }


# Note type and if attention is correct
qualtrics_tbl[:video_type] = Array.new(qualtrics_tbl.length)
qualtrics_tbl[:attention_correct] = Array.new(qualtrics_tbl.length)

qualtrics_tbl.by_row!.each do |r|
  if ( !r[:q2_1].nil? )       #Here's where we'll add attention correct
    r[:video_type] =  "F"; r[:attention_correct] = (r[:q2_1].to_i == 5 && r[:q2_2].to_i == 1 )
  elsif ( !r[:q3_1].nil? )
    r[:video_type] =  "F"; r[:attention_correct] = (r[:q3_1].to_i == 4 && r[:q3_2].to_i == 3 )
  elsif ( !r[:q4_1].nil?  )
    r[:video_type] =  "P"; r[:attention_correct] = (r[:q4_1].to_i == 7 && r[:q4_2].to_i == 0 )
  elsif ( !r[:q5_1].nil? )
    r[:video_type] =  "P"; r[:attention_correct] = (r[:q5_1].to_i == 8 && r[:q5_2].to_i == 3 )
  elsif ( !r[:q6_1].nil?  )
    r[:video_type] =  "I"; r[:attention_correct] = (r[:q6_1].to_i == 9 && r[:q6_2].to_i == 2 )
  elsif ( !r[:q7_1].nil? )
    r[:video_type] =  "I"; r[:attention_correct] = (r[:q7_1].to_i == 6 && r[:q7_2].to_i == 8 )
  end
end
qualtrics_tbl.by_col!


#p qualtrics_tbl[:video_type]
#p qualtrics_tbl[:attention_correct]

# Get rid of all but the keepers
[:responseid, :responseset, :ipaddress, :startdate, :enddate,
 :recipientlastname, :recipientfirstname, :recipientemail, :externaldatareference,
 :finished, :status, :robrfl_10, :doqq10, :doqq8, :doqq11, :locationlatitude,
 :locationlongitude, :locationaccuracy, :q16_1_group, :q16_2_group,
 :q16_3_group, :q16_4_group, :q16_5_group,
 :doqq14, :doqq15, :doqq17].each { |s| qualtrics_tbl.delete(s) }

 ["q2_", "q3_", "q4_", "q5_", "q6_", "q7_"].each do |prefix|

   ["1", "2", "3"].each do |suffix|
      qualtrics_tbl.delete((prefix + suffix).to_sym)
   end

 end


puts qualtrics_tbl.to_csv




#Check for duplicates in the pseudorandom mturk code.   Very bad if we have them.
if qualtrics_tbl[:mturkcode].uniq.length == qualtrics_tbl[:mturkcode].length
  STDERR.puts "No duplicate mturk codes, length = #{qualtrics_tbl.length}"
else
  STDERR.puts "Saw duplicate mturk codes"
  exit()
end

exit()



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

#qualtrics_tbl.by_row.each_with_index { |row,i|
#  puts "#{i} #{row[:q16_1]}, #{row[:q16_2]}, #{row[:q16_3]}"
#}




#########################################################################################
#
#  Second part of problem:  Get the results from Amazon turk (including completion code)
#
# This happens to pull in the user id and the user secret from a fixed file location or
# an environment variable, whichever it finds first
#
#########################################################################################

mturk = Aws::MTurk::Client.new()

# This is rather curdely done; two hashes to map the MTurk completion code to the
# Amazon assignment ID, and to the worker id
code_to_assignment_id = {}
code_to_worker_id = {}

# Here's a hash we use as a set to look for duplicat workers
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

    #parse out the completion code code from the XML, use it to index, the point this to the assignment_id
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
#@     mturk.approve_assignment({assignment_id: code_to_assignment_id[key],
#@                            requester_feedback: "Thank you for completing our food and agriculture survey (bonus will be processed shortly)"})
    puts "Considering bonus"
      if code_to_payoff[key]['cash'] > code_to_cumulative_bonus[key]
        payment = (code_to_payoff[key]['cash'] - code_to_cumulative_bonus[key]).to_s
#@      mturk.send_bonus(worker_id: code_to_worker_id[key],
#@                      bonus_amount: payment,
#@                      assignment_id: code_to_assignment_id[key],
#@                      reason: "Cash portion of bonus you selected; if you entered drawing, winner will be contacted by March 31" )
        puts "paying some bonus #{payment}"
     else
       puts "already paid maximum requested bonus"
     end
  elsif code_to_status[key] == "Approved"
    puts "Already approved, reconsidering bonus"

    if code_to_payoff[key]['cash'] > code_to_cumulative_bonus[key]
        payment = (code_to_payoff[key]['cash'] - code_to_cumulative_bonus[key]).to_s
#@        mturk.send_bonus(worker_id: code_to_worker_id[key],
#@                     bonus_amount: payment,
#@                     assignment_id: code_to_assignment_id[key],
#@                     reason: "Cash portion of bonus you selected; if you entered drawing, winner will be contacted by March 31" )
        puts "paying some bonus #{payment}"
    else
      puts "Not paying bonus, nothing left to pay"
    end
  else

    puts "already something other than submitted or approved, so not paying"
  end

##########################################################################################################
#
#  Print out the spreadsheet we care about
#
##########################################################################################################

end
