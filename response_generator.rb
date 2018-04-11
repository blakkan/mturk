require 'watir'
require 'rubystats'
#must also have installed chromedriver-helper
#require 'nokogiri'

#
# Helpers
#
def assert(value, printed_output = nil)
  unless value
    puts printed_output
    @browser.screenshot.save("screenshot.png")
    raise RuntimeError
  end
end

def negate(value, printed_output = nil)
  if value
    puts printed_output
    @browser.screenshot.save("screenshot.png")
    raise RuntimeError
  end
end





class Person

  attr_accessor :age, :male, :pre_food, :post_food

  def initialize( vegetarian = false, effect = -2 )

    @the_rand = Rubystats::BinomialDistribution.new(3,0.5)

    @age = 15 + rand(11)
    @male = (rand(2) == 0)

    @pre_food = {}
    @post_food = {}

    @pre_food['vegetables'] = rand(11)
    @pre_food['fruit'] = rand(11)
    @pre_food['dairy'] = rand(11)
    @pre_food['eggs'] = rand(11)
    @pre_food['beef'] = vegetarian ? 0 : (3 + @the_rand.rng)   # 3 plus binom n=3 p=0.5
    @pre_food['pork'] = vegetarian ? 0 : rand(11)

    @post_food['vegetables'] = rand(11)
    @post_food['fruit'] = rand(11)
    @post_food['dairy'] = rand(11)
    @post_food['eggs'] = rand(11)
    @post_food['beef'] = vegetarian ? 0 : (@pre_food['beef'] + rand(-1..1))
    @post_food['pork'] = vegetarian ? 0 : rand(11)

    @post_food['beef'] = 0 if @post_food['beef'] < 0
    @post_food['pork'] = 0 if @post_food['pork'] < 0


  end

  #
  # Treatment only affects males
  def add_treatment_to_post_beef(treatment_effect)
    if @male
      ;
    else
      @post_food['beef'] += treatment_effect
      @post_food['beef'] = 0 if @post_food['beef'] < 0
    end
  end

end

#translate vimeo video nuber into first and second digit indeces (which are one greater than the actual digit,
# due to "blank" being the first item in the drill-down selector)
video = {
  "263669431" => { first_digit: "5", second_digit: "4"},    #Video FDC
  "263669426" => { first_digit: "6", second_digit: "2"},    #Video FEA
  "263669422" => { first_digit: "7", second_digit: "9"},    #Video IFH
  "263669416" => { first_digit: "10", second_digit: "3"},    #Video IIB
  "263669413" => { first_digit: "8", second_digit: "1"},    #Video PGZ
  "263669402" => { first_digit: "9", second_digit: "4"}     #Video PHC
}
#############################################################################
#
#  Complete a single survey
#
#############################################################################
def complete_a_survey

  #instantiate a browser
  browser = Watir::Browser.new :chrome

  #instantiate a subject, with a certain probablity of being
  # a vegetarian
  subject = Person.new( vegetarian = (rand(10) == 9) )  #10% chance of vegetarian, others may be vegetarian those weeks by chance


  #
  # Take one survey with fixed results
  #

  browser.goto 'https://berkeley.qualtrics.com/jfe/form/SV_0jkOPWu76yzbV8V'

  browser.text_field(id: 'QR~QID1').set subject.age.to_s

  if subject.male
    browser.label(text: "Male").click
  else
    browser.label(text: "Female").click
  end

  sleep 0.1
  browser.text_field(id: 'QR~QID10~1').set subject.pre_food['vegetables'].to_s  #Vegetables
    sleep 0.1
  browser.text_field(id: 'QR~QID10~2').set subject.pre_food['fruit'].to_s   #Fruit
    sleep 0.1
  browser.text_field(id: 'QR~QID10~3').set subject.pre_food['dairy'].to_s   #Dairy
    sleep 0.1
  browser.text_field(id: 'QR~QID10~4').set subject.pre_food['eggs'].to_s   #Eggs
    sleep 0.1
  browser.text_field(id: 'QR~QID10~5').set subject.pre_food['beef'].to_s   #Beef
    sleep 0.1
  browser.text_field(id: 'QR~QID10~6').set subject.pre_food['pork'].to_s   #Pork


  #go to nextpage for the video
  sleep 1
  browser.input(id: 'NextButton').click
  sleep 0.5

  #Now determine which question was asked
  video_url = browser.iframe.src
  video_number = video_url.split("/")[-1]


  id_string = browser.element(:css, '.drillDownSelectDropDown').id
  id_string_prefix = id_string.split("~")[0..1].join("~")

  puts video_url
  puts video_number
  puts id_string_prefix

  video = {
    "263669431" => { first_digit: 5, second_digit: 4},    #Video FDC
    "263669426" => { first_digit: 6, second_digit: 2},    #Video FEA
    "263669422" => { first_digit: 7, second_digit: 9},    #Video IFH
    "263669416" => { first_digit: 10, second_digit: 3},    #Video IIB
    "263669413" => { first_digit: 8, second_digit: 1},    #Video PGZ
    "263669402" => { first_digit: 9, second_digit: 4}     #Video PHC
  }

  # Now select the numbers from the video Remeber that there is a blank as the
  #first child, so the index must be increased by 1
    sleep 0.25
  browser.element(:css, "[name=\"#{id_string_prefix}~1\"]").children[video[video_number][:first_digit]].click
    sleep 0.25
  browser.element(:css, "[name=\"#{id_string_prefix}~2\"]").children[video[video_number][:second_digit]].click

  treatment_effect = nil
  if video_number == "263669422" || video_number == "263669416"
    treatment_effect = 0   #water video
  elsif video_number == "263669413" || video_number == "263669402"
    treatment_effect = 0   #pasture video
  elsif video_number ==  "263669431" || video_number == "263669426"
    treatment_effect = (rand(2) == 1) ? -1 : 0 #feedlot video
  end

  subject.add_treatment_to_post_beef(treatment_effect)

  #go to nextpage
  sleep 1
  browser.input(id: 'NextButton').click
  sleep 1

  # Now fill out the other attention question


  if video_number == "263669422" || video_number == "263669416"
    browser.label(text: "Use of irrigation in agriculture").click
  else
    browser.label(text: "Use of animals in agriculture").click
  end

    sleep 0.1


  # Now fill out the post-data

  browser.text_field(id: 'QR~QID11~1').set subject.post_food['vegetables'].to_s  #Vegetables
    sleep 0.1
  browser.text_field(id: 'QR~QID11~2').set subject.post_food['fruit'].to_s   #Fruit
    sleep 0.1
  browser.text_field(id: 'QR~QID11~3').set subject.post_food['dairy'].to_s   #Dairy
    sleep 0.1
  browser.text_field(id: 'QR~QID11~4').set subject.post_food['eggs'].to_s   #Eggs
    sleep 0.1
  browser.text_field(id: 'QR~QID11~5').set subject.post_food['beef'].to_s   #Beef
    sleep 0.1
  browser.text_field(id: 'QR~QID11~6').set subject.post_food['pork'].to_s   #Pork
    sleep 0.1

  sleep 1
  browser.input(id: 'NextButton').click

  # Keep the connection open for a little bit, or qualtrics thinks we're not done.
  sleep 1

  #
  # Close the browser, we're done
  #
  browser.close

end

#####################################################
#
# run it
#
#####################################################
k = ARGV[0].to_i
k = 10 if k.nil?


(1..k).each do |index|
  puts index
  complete_a_survey
end
