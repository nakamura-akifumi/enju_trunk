class ReminderListsController < ApplicationController
  before_filter :check_librarian

  def initialize
    @reminder_list_statuses = ReminderList.statuses
    @selected_state = @reminder_list_statuses.collect {|s| s[:id]}
    super
  end

  def index
    flash[:reserve_notice] = ""
    unless params[:do_search].blank?
      query = params[:query].to_s.strip
      @query = query.dup
      query = "#{query}*" if query.size == 1
 
      tmp_state_list = params[:state] || []
      @selected_state = tmp_state_list.collect {|s| s.to_i }
      logger.info @selected_state
      if @selected_state.blank?  
        flash[:reserve_notice] << t('item_list.no_list_condition') + '<br />'
      end
      states = nil
    end
    page = params[:page] || 1

    state_ids = @selected_state
    unless query.blank?
      @reminder_lists = ReminderList.search do
        fulltext query
        with(:status, state_ids) 
        order_by(:id, :asc)
        paginate :page => page.to_i, :per_page => ReminderList.per_page unless params[:output_pdf] or params[:output_csv]
      end.results
    else
      @reminder_lists =  ReminderList.where(:status => state_ids).order('id').page(page)
      @reminder_lists =  ReminderList.where(:status => state_ids).order('id') if params[:output_pdf] or params[:output_csv]
    end

    # output reminder_list (pdf or csv)
    unless @selected_state.blank? 
      output_file('reminder_list_pdf') if params[:output_pdf]
      output_file('reminder_list_csv') if params[:output_csv]
    end
  end

  def new
    @reminder_list = ReminderList.new
  end

  def edit
    @reminder_list = ReminderList.find(params[:id])
  end

  def show
    @reminder_list = ReminderList.find(params[:id])
  end

  def create
    @reminder_list = ReminderList.new(params[:reminder_list])
    if @reminder_list.save
      flash[:notice] = t('controller.successfully_created', :model => t('activerecord.models.reminder_list'))
      redirect_to(@reminder_list) 
    else
      render :action => "new" 
    end
  end

  def update
    @reminder_list = ReminderList.find(params[:id])
    if @reminder_list.update_attributes(params[:reminder_list])
      flash[:notice] = t('controller.successfully_updated', :model => t('activerecord.models.reminder_list'))
      redirect_to(@reminder_list) 
    else
      render :action => "edit" 
    end
  end

  def destroy
    @reminder_list = ReminderList.find(params[:id])
    @reminder_list.destroy
    redirect_to(reminder_lists_url)
  end

  def reminder_postal_card
  end

  def reminder_letter
  end

  def output_reminder_postal_card
    user_number = params[:user_number].strip
    # check exit user
    @user = User.where(:user_number => user_number).first
    unless @user
      flash[:notice] = t('reminder_list.no_user')
      render :reminder_postal_card and return 
    end
    # check user has over_due_item
    @reminder_lists = ReminderList.find(:all, :include => [:checkout => :user], :conditions => {:checkouts => {:users => {:user_number => user_number}}})
    unless @reminder_lists.size > 0
      flash[:notice] = t('reminder_list.no_item')
      render :reminder_postal_card and return 
    end

    begin
      # save
      @reminder_lists.each do |reminder_list|
        reminder_list.type1_printed_at = Time.zone.now
        reminder_list.save!
      end
      # output
      output_file('reminder_postal_card')
      flash[:notice] = t('reminder_list.successfully__output')
      render :reminder_postal_card
    rescue Exception => e
      logger.error "failed #{e}"
      flash[:notice] = t('reminder_list.failed_output')
      render :reminder_postal_card and return
    end
  end

  def output_reminder_letter
    user_number = params[:user_number].strip
    # check exit user
    @user = User.where(:user_number => user_number).first
    unless @user
      flash[:notice] = t('reminder_list.no_user')
      render :reminder_letter and return 
    end
    # check user has over_due_item
    @reminder_lists = ReminderList.find(:all, :include => [:checkout => :user], :conditions => {:checkouts => {:users => {:user_number => user_number}}})
    unless @reminder_lists.size > 0
      flash[:notice] = t('reminder_list.no_item')
      render :reminder_letter and return 
    end

    begin
      # save
      @reminder_lists.each do |reminder_list|
        reminder_list.type2_printed_at = Time.zone.now
        reminder_list.save!
      end
      # output
      output_file('reminder_letter')
      flash[:notice] = t('reminder_list.successfully__output')
      render :reminder_letter
    rescue Exception => e
      logger.error "failed #{e}"
      flash[:notice] = t('reminder_list.failed_output')
      render :reminder_letter and return
    end
  end

  def download_file
    path = params[:path]
    if File.exist?(path)
      send_file path #, :type => "application/pdf"
    else
      logger.warn "not exist file. path:#{path}"
      render :back and return
    end
  end

  private
  def output_file(output_type)
    out_dir = "#{RAILS_ROOT}/private/system/reminder_lists/"
    FileUtils.mkdir_p(out_dir) unless FileTest.exist?(out_dir)
    logger.info "output #{output_type}"

    case output_type
    when 'reminder_list_pdf'
      file = out_dir + configatron.reminder_list_pdf_print.filename
      ReminderList.output_reminder_list_pdf(file, @reminder_lists)
      send_file file
    when 'reminder_list_csv'
      file = out_dir + configatron.reminder_list_csv_print.filename
      ReminderList.output_reminder_list_csv(file, @reminder_lists)
      send_file file
    when 'reminder_postal_card'
      file = out_dir + configatron.reminder_postal_card_print.filename
      ReminderList.output_reminder_postal_card(file, @reminder_lists, @user, current_user)
      flash[:file] = file
    when 'reminder_letter'
      file = out_dir + configatron.reminder_letter_print.filename
      ReminderList.output_reminder_letter(file, @reminder_lists, @user, current_user)
      flash[:file] = file
    end
  end
end  
