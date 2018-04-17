require 'qualtrics_api'      #for access
require 'csv'                #for manipulation
require 'zipruby'            #for decompressing results
require 'ethon'              #curl library for pulling over results


class Survey < ApplicationRecord

  QualtricsAPI.configure do |config|
    config.api_token = ENV['QUALTRICS_KEY']
  end

  ###########################################################
  #
  # list_surveys
  #
  #   returns a list of text strings, all surveys by name
  #
  ############################################################
  def self.list_surveys
    QualtricsAPI.surveys.map{|survey| survey.name}.sort
  end

  ############################################################
  #
  # survey_name_to_csv
  #
  #   Given a survey name, looks it up and renders the CSV
  #
  #############################################################
  def self.survey_name_to_csv(survey_name)

    j = QualtricsAPI.surveys.collect.find do |survey|
      survey.name == survey_name
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
    file.binmode
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

    return qualtrics_tbl.to_csv


  end



end
