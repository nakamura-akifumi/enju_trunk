class KeywordCountsController < ApplicationController
  add_breadcrumb "I18n.t('activerecord.models.keyword_count')", 'keyword_counts_path', :only => [:index]
  load_and_authorize_resource

  def index
    # KeywordCount.calc()
    @start_d = params[:start_d] ? params[:start_d] : (Date.today - 1.month).strftime("%Y-%m-%d")
    @end_d = params[:end_d] ? params[:end_d] : Date.today.strftime("%Y-%m-%d")
    # @keyword_counts, flash[:message] = KeywordCount.create_ranks(@start_d, @end_d, false)
    @all_results, flash[:message] = KeywordCount.create_ranks(@start_d, @end_d)
    @rank_results = []
    limit = 10
    @all_results.each do |result|
      break if result.rank > limit 
      @rank_results << result
    end
    respond_to do |format|
      format.html # index.html.erb
    # format.pdf { send_data Reserve.get_reservelist_pdf(@displist).generate, :filename => Setting.reservelist_report_pdf.filename }
      format.tsv { send_data KeywordCount.get_keyword_counts_list_tsv(@all_results), :filename => Setting.keyword_counts_list_print_tsv.filename }
    end
  end
end
