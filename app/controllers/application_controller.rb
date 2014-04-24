# -*- encoding: utf-8 -*-
class ApplicationController < ActionController::Base
  if defined?(EnjuCustomize) && cutomize_gem = EnjuCustomize.get_gem
    helper cutomize_gem::Engine.helpers
  end

  protect_from_forgery
  require_dependency 'language'

  rescue_from CanCan::AccessDenied, :with => :render_403
  rescue_from ActiveRecord::RecordNotFound, :with => :render_404
  rescue_from Errno::ECONNREFUSED, :with => :render_500
  rescue_from RSolr::Error::Http, :with => :render_500_solr
  rescue_from ActionView::MissingTemplate, :with => :render_404_invalid_format

  #before_filter :get_library_group, :set_locale, :set_available_languages, :prepare_for_mobile, :set_current_user
  before_filter :get_library_group, :set_locale, :set_available_languages, :set_current_user, :get_current_basket
  #helper_method :mobile_device?

  protected
  def add_breadcrumb name, url=''
    name = eval(name) unless name.blank?
    url = eval(url) if !url.blank? && url =~ /_path|_url|@|session/
    while session[:breadcrumbs] && session[:breadcrumbs].key?(name)
      session[:breadcrumbs].delete(session[:breadcrumbs].to_a.last.first)
    end
    session[:breadcrumbs] = {I18n.t('breadcrumb.lib_top') => root_path} if session[:breadcrumbs].nil? || session[:breadcrumbs].empty?
    session[:breadcrumbs].store(name, url) unless name.blank?
  end

  def self.add_breadcrumb name, url, options = {}
    before_filter options do |controller|
      controller.send(:add_breadcrumb, name, url)
    end
  end

  def clear_breadcrumbs
    session[:breadcrumbs].clear if session[:breadcrumbs]
  end

  def self.clear_breadcrumbs options = {}
    before_filter options do |controller|
      controller.send(:clear_breadcrumbs)
    end
  end

  private
  def render_403
    #debugger
    return if performed?
    if user_signed_in?
      respond_to do |format|
        format.html {render :template => 'page/403', :status => 403}
        format.mobile {render :template => 'page/403', :status => 403}
        format.xml {render :template => 'page/403', :status => 403}
        format.json
      end
    else
      respond_to do |format|
        format.html {redirect_to new_user_session_url}
        format.mobile {redirect_to new_user_session_url}
        format.xml {render :template => 'page/403', :status => 403}
        format.json
      end
    end
  end

  def render_404
    return if performed?
    logger.warn $@
    logger.warn $!

    respond_to do |format|
      format.html {render :template => 'page/404', :status => 404}
      format.mobile {render :template => 'page/404', :status => 404}
      format.xml {render :template => 'page/404', :status => 404}
      format.json
    end
  end

  def render_404_invalid_format
    return if performed?
    render :file => "#{Rails.root}/public/404.html"
  end

  def render_500
    return if performed?
    logger.warn $@
    logger.warn $!

    #flash[:notice] = t('page.connection_failed')
    respond_to do |format|
      format.html {render :file => "#{Rails.root.to_s}/public/500.html", :layout => false, :status => 500}
      format.mobile {render :file => "#{Rails.root.to_s}/public/500.html", :layout => false, :status => 500}
    end
  end

  def render_500_solr
    return if performed?
    #flash[:notice] = t('page.connection_failed')

    logger.warn $@
    logger.warn $!

    respond_to do |format|
      format.html {render :template => 'page/500', :status => 500}
      format.mobile {render :template => 'page/500', :status => 500}
      format.xml {render :template => 'page/500', :status => 500}
      format.json
    end
  end

  def set_current_user
    if user_signed_in?
      User.current_user = current_user
    end
  end

  def get_library_group
    @library_group = LibraryGroup.site_config
  end

  def set_locale
    if params[:locale]
      unless I18n.available_locales.include?(params[:locale].to_s.intern)
        raise InvalidLocaleError
      end
    end
    if user_signed_in?
      locale = params[:locale] || session[:locale] || current_user.locale.to_sym
    else
      locale = params[:locale] || session[:locale]
    end
    if locale
      I18n.locale = @locale = session[:locale] = locale.to_sym
    else
      I18n.locale = @locale = session[:locale] = I18n.default_locale
    end
  rescue InvalidLocaleError
    @locale = I18n.default_locale
  end

  def default_url_options(options={})
    {:locale => nil}
  end

  def set_available_languages
    if Rails.env == 'production'
      @available_languages = Rails.cache.fetch('available_languages'){
        Language.where(:iso_639_1 => I18n.available_locales.map{|l| l.to_s}).select([:id, :iso_639_1, :name, :native_name, :display_name, :position]).all
      }
    else
      @available_languages = Language.where(:iso_639_1 => I18n.available_locales.map{|l| l.to_s})
    end
  end

  def reset_params_session
    session[:params] = nil
  end

  def not_found
    raise ActiveRecord::RecordNotFound
  end

  def access_denied
    raise CanCan::AccessDenied
  end

  def get_agent
    @agent = Agent.find(params[:agent_id]) if params[:agent_id]
    authorize! :show, @agent if @agent
  end

  def get_work
    @work = Manifestation.find(params[:work_id]) if params[:work_id]
    authorize! :show, @work if @work
  end

  def get_expression
    @expression = Manifestation.find(params[:expression_id]) if params[:expression_id]
    authorize! :show, @expression if @expression
  end

  def get_manifestation
    @manifestation = Manifestation.find(params[:manifestation_id]) if params[:manifestation_id]
    authorize! :show, @manifestation if @manifestation
  end

  def get_item
    @item = Item.find(params[:item_id]) if params[:item_id]
    authorize! :show, @item if @item
  end

  def get_carrier_type
    @carrier_type = CarrierType.find(params[:carrier_type_id]) if params[:carrier_type_id]
  end

  def get_shelf
    @shelf = Shelf.find(params[:shelf_id], :include => :library) if params[:shelf_id]
  end

  def get_basket
    @basket = Basket.find(params[:basket_id]) if params[:basket_id]
  end

  def get_agent_merge_list
    @agent_merge_list = AgentMergeList.find(params[:agent_merge_list_id]) if params[:agent_merge_list_id]
  end

  def get_user
    @user = User.where(:username => params[:user_id]).first if params[:user_id]
    #authorize! :show, @user if @user
  end

  def get_user_if_nil
    @user = User.where(:username => params[:user_id]).first if params[:user_id]
#    if @user
#      authorize! :show, @user
#    else
#      raise ActiveRecord::RecordNotFound
#    end
    return @user
  end

  def get_user_group
    @user_group = UserGroup.find(params[:user_group_id]) if params[:user_group_id]
  end

  def get_library
    @library = Library.find(params[:library_id]) if params[:library_id]
  end

  def get_libraries
    @libraries = Library.all_cache
  end

  def get_real_libraries
    @libraries = Library.real.all
  end

  def get_library_group
    @library_group = LibraryGroup.site_config
  end

  def get_question
    @question = Question.find(params[:question_id]) if params[:question_id]
    authorize! :show, @question if @question
  end

  def get_event
    @event = Event.find(params[:event_id]) if params[:event_id]
  end

  def get_bookstore
    @bookstore = Bookstore.find(params[:bookstore_id]) if params[:bookstore_id]
  end

  def get_subject
    @subject = Subject.find(params[:subject_id]) if params[:subject_id]
  end

  def get_classification
    @classification = Classification.find(params[:classification_id]) if params[:classification_id]
  end

  def get_subscription
    @subscription = Subscription.find(params[:subscription_id]) if params[:subscription_id]
  end

  def get_order_list
    @order_list = OrderList.find(params[:order_list_id]) if params[:order_list_id]
  end

  def get_purchase_request
    @purchase_request = PurchaseRequest.find(params[:purchase_request_id]) if params[:purchase_request_id]
  end

  def get_checkout_type
    @checkout_type = CheckoutType.find(params[:checkout_type_id]) if params[:checkout_type_id]
  end

  def get_subject_heading_type
    @subject_heading_type = SubjectHeadingType.find(params[:subject_heading_type_id]) if params[:subject_heading_type_id]
  end

  def get_series_statement
    @series_statement = SeriesStatement.find(params[:series_statement_id]) if params[:series_statement_id]
    @periodical_master = @series_statement.try(:root_manifestation) if @series_statement
  end

  def get_reserve_states
    @reserve_states = Reserve.states
  end

  def get_reserve_information_types
    @reserve_information_types = Reserve.information_type_ids
  end

  def get_bookbinding
    @bookbinding = Bookbinding.find(params[:bookbinding_id]) if params[:bookbinding_id]
  end

  def get_current_basket
    @current_basket = current_user.current_basket if current_user
  end

  def convert_charset
    case params[:format]
    when 'csv'
      return unless Setting.csv_charset_conversion
      # TODO: 他の言語
      if @locale.to_sym == :ja
        headers["Content-Type"] = "text/csv; charset=Shift_JIS"
        response.body = NKF::nkf('-Ws', response.body)
      end
    when 'xml'
      if @locale.to_sym == :ja
        headers["Content-Type"] = "application/xml; charset=Shift_JIS"
        response.body = NKF::nkf('-Ws', response.body)
      end
    end
  end

  def my_networks?
    return true if LibraryGroup.site_config.network_access_allowed?(request.remote_ip, :network_type => 'lan')
    false
  end

  def admin_networks?
    return true if LibraryGroup.site_config.network_access_allowed?(request.remote_ip, :network_type => 'admin')
    false
  end

  def check_client_ip_address
    access_denied unless my_networks?
  end

  def check_admin_network
    access_denied unless admin_networks?
  end

  def check_dsbl
    library_group = LibraryGroup.site_config
    return true if library_group.network_access_allowed?(request.remote_ip, :network_type => 'lan')
    begin
      dsbl_hosts = library_group.dsbl_list.split.compact
      reversed_address = request.remote_ip.split(/\./).reverse.join(".")
      dsbl_hosts.each do |dsbl_host|
        result = Socket.gethostbyname("#{reversed_address}.#{dsbl_host}.").last.unpack("C4").join(".")
        raise SocketError unless result =~ /^127\.0\.0\./
        access_denied
      end
    rescue SocketError
      nil
    end
  end

  def store_page
    flash[:page] = params[:page].to_i if params[:page]
  end

  def store_location
    if request.get? and request.format.try(:html?) and !request.xhr?
      session[:user_return_to] = request.fullpath
    end
  end

  def check_librarian
    access_denied unless current_user && current_user.has_role?('Librarian')
  end

  def check_admin
    access_denied unless current_user && current_user.has_role?('Admin')
  end

  def set_role_query(user, search)
    role = user.try(:role) || Role.default_role
    search.build do
      with(:required_role_id).less_than_or_equal_to role.id
    end
  end

  def solr_commit
    Sunspot.commit
  end

  def get_version
    @version = params[:version_id].to_i if params[:version_id]
    @version = nil if @version == 0
  end

  def clear_search_sessions
    session[:query] = nil
    session[:params] = nil
    session[:search_params] = nil
    session[:manifestation_ids] = nil
  end

  def api_request?
    true unless params[:format].nil? or params[:format] == 'html'
  end

  def current_ability
    @current_ability ||= Ability.new(current_user, request.remote_ip)
  end

  def get_top_page_content
    if defined?(EnjuNews)
      @news_feeds = Rails.cache.fetch('news_feed_all'){NewsFeed.all}
      @news_posts = NewsPost.limit(3)
    end
    @libraries = Library.real
  end

  def prepare_for_mobile
    #request.format = :mobile if request.smart_phone?
  end

  def move_position(resource, direction)
    if ['higher', 'lower'].include?(direction)
      resource.send("move_#{direction}")
      redirect_to url_for(:controller => resource.class.to_s.pluralize.underscore)
      return
    end
  end

  def append_info_to_payload(payload)
    super
    payload[:current_user] = current_user rescue nil
    payload[:session_id] = request.session_options[:id] rescue nil
    payload[:remote_ip] = request.remote_ip
  end

  def get_manifestation_types
    @manifestation_types = ManifestationType.all
  end

  def get_carrier_types
    @carrier_types = CarrierType.all
  end

  def get_index_agent
    agent = {}
    case
    when params[:agent_id]
      agent[:agent] = Agent.find(params[:agent_id])
    when params[:creator_id]
      agent[:creator] = Agent.find(params[:creator_id])
    when params[:contributor_id]
      agent[:contributor] = Agent.find(params[:contributor_id])
    when params[:publisher_id]
      agent[:publisher] = Agent.find(params[:publisher_id])
    end
    agent
  end

  def self.authorize_function
    before_filter :authorize_function!
  end

  def authorize_function!
    unless FunctionClassAbility.permit?(self.class, action_name, current_user)
      logger.info "access denied by FunctionClassAbility: user=#{current_user.try(:id)},action=#{action_name},function_class=#{current_user.try(:function_class_id)}"
      raise CanCan::AccessDenied
    end
  end

  def set_agent_instance_from_params # Use manifestations_controller.rb and series_statements_controller.rb
    logger.error "########### create = #{params[:creates]} ###########"
    @creates = Create.new_attrs(params[:creates].try(:keys), params[:creates].try(:values))
    @realizes = Realize.new_attrs(params[:realizes].try(:keys), params[:realizes].try(:values))
    @produces = Produce.new_attrs(params[:produces].try(:keys), params[:produces].try(:values))
    @del_creators = params[:del_creator_ids].nil? ? [] : params[:del_creator_ids]
    @del_contributors = params[:del_contributor_ids].nil? ? [] : params[:del_contributor_ids]
    @del_publishers = params[:del_publisher_ids].nil? ? [] : params[:del_publisher_ids]
    @add_creators = set_agent_attrs(
      params[:creator_ids].try(:values),
      params[:creator_full_names].try(:values),
      params[:creator_full_name_transcriptions].try(:values),
      params[:creator_type_ids].try(:values)
    )
    @add_contributors = set_agent_attrs(
      params[:contributor_ids].try(:values),
      params[:contributor_full_names].try(:values),
      params[:contributor_full_name_transcriptions].try(:values),
      params[:contributor_type_ids].try(:values)
    )
    @add_publishers = set_agent_attrs(
      params[:publisher_ids].try(:values),
      params[:publisher_full_names].try(:values),
      params[:publisher_full_name_transcriptions].try(:values),
      params[:publisher_type_ids].try(:values)
    )
  end

  def set_agent_attrs(agent_ids, full_names, full_name_reads, type_ids)
    list = []
    if agent_ids
      agent_ids.each_with_index.each do |agent_id ,i|
        next if agent_id.blank?
        param = {}
        param[:agent_id] = agent_id
        param[:type_id] = type_ids[i] if type_ids
        list << param
      end
    elsif full_names
      full_names.each_with_index.each do |full_name ,i|
        next if full_name.blank?
        param = {}
        param[:full_name] = full_name
        param[:full_name_transcription] = full_name_reads[i] if full_name_reads
        param[:type_id] = type_ids[i] if type_ids
        list << param
      end
    else
      list = []
    end
    list
  end

  def set_subject_instance_from_params # Use manifestations_controller.rb and series_statements_controller.rb
    logger.error "########### subject= #{params[:subjects]} ###########"
    logger.error "########### subject= #{params[:subjects.inspect]} ###########"
    @subjects = Subject.new_attrs(params[:subjects])
    @del_subjects = params[:del_subject_ids].nil? ? [] : params[:del_subject_ids]
    @add_subjectss = set_subject_attrs(
      params[:subject_ids].try(:values),
      params[:subject_term].try(:values),
      params[:subject_term_transcriptions].try(:values)
    )
  end

  def set_subject_attrs(subject_ids, terms, term_trascriptions)
    list = []
    if subject_ids
      subject_ids.each_with_index.each do |subject_id ,i|
        next if subject_id.blank?
        param = {}
        param[:subject_id] = subject_id
        list << param
      end
    elsif terms
      terms.each_with_index.each do |term ,i|
        next if term.blank?
        param = {}
        param[:term] = term
        param[:term_transcription] = term_transcriptions[i] if term_transcriptions
        list << param
      end
    else
      list = []
    end
    list
  end
end

class InvalidLocaleError < StandardError
end
