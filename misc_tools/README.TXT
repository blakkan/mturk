Files:

generate_digits_for_qualtrics_drill_down.rb
  This generates a 1000-line long set of exhaustive combinations of values
for the qualtrics survey drill-down used after each video to ask subjects
to record up to three digits seen during the video.  (For attention
verification)

drill_down.csv
  The file produced by the ruby script above

key.csv
  A sample output file for the "payoff.rb" script, giving more detail
on the meaning of each column of the output.

payoff.rb
  Script to pull the results of a selected survey over from qualtrics,
and do some pre-processing, deleting extraneous columns and calculating
a few columns (e.g. checking for proper response on the attention-digits
drill-down).   It also connects to mturk API to approve HIT assignments
if attention-digits are correct.

response_generator.rb
  A Ruby/Watir web QA script.   This is a robot to run an arbitrary number
of simulated users taking the survey.   It takes about 20 sec. per survey
(but multiple copies may be run in parallel).   Ruby/Watir is built on top
of the Selenium infrastructure and drives chrome/chromium browsers.

robot_small.mp4
  A short demo of a preliminary version of response_generator running

vimeo_URLs_for_videos
  After trying to host .mp4 and .webm files on both the vimeo streaming
service and on github, the ultimate decision was to use vimeo for greater
assurance that different browsers could view them.  (Note, however, that
github hosting of the videos gave a better auto-scaling for phones and
tablets.  Our pilots showed us that our mturk workers were all using
laptop/desktop, so that advantage was moot.  This file lists the URLs
of the 6 final videos.   File names are encoded: Initial F for feedlot,
I for irrigation (control), and P for pasture video.   Second and third
letters in the file name encode the "attention-digits" flashed
during the video.
