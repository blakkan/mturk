class SurveysController < ApplicationController


  def show_index
    #default page displayed
  end


  def get_csv

    if params[:which_survey] =~ /\S/
      send_data Survey.survey_name_to_csv(params[:which_survey]), type: "text/csv",
        filename: (params[:which_survey] + ".csv"),
        disposition: 'attachment'
      return
    else
      redirect_to"/"
      return
    end
  end

end
