# -*- encoding: utf-8 -*-
class SeriesStatementsController < ApplicationController
  add_breadcrumb "I18n.t('page.configuration')", 'page_configuration_path'
  add_breadcrumb "I18n.t('page.listing', :model => I18n.t('activerecord.models.series_statement'))", 'series_statements_path'
  add_breadcrumb "I18n.t('page.new', :model => I18n.t('activerecord.models.series_statement'))", 'new_series_statement_path', :only => [:new, :create]
  add_breadcrumb "I18n.t('page.editing', :model => I18n.t('activerecord.models.series_statement'))", 'edit_series_statement_path([:id])', :only => [:edit, :update]
  add_breadcrumb "I18n.t('activerecord.models.series_statement')", 'series_statement_path([:id])', :only => [:show]
  load_and_authorize_resource
  before_filter :get_work, :only => [:index, :new, :edit]
  before_filter :get_manifestation, :only => [:index, :new, :edit]
  before_filter :prepare_options, :only => [:new, :edit]
  cache_sweeper :page_sweeper, :only => [:create, :update, :destroy]
  after_filter :solr_commit, :only => [:create, :update, :destroy]

  # GET /series_statements
  # GET /series_statements.json
  def index
    search = Sunspot.new_search(SeriesStatement)
    query = params[:query].to_s.strip
    page = params[:page] || 1
    unless query.blank?
      @query = query.dup
      query = query.gsub('　', ' ')
    end
    search.build do
      fulltext query if query.present?
      paginate :page => page.to_i, :per_page => SeriesStatement.default_per_page
      order_by :position, :asc
    end

    @basket = Basket.find(params[:basket_id]) if params[:basket_id]

    #work = @work
    manifestation = @manifestation
    unless params[:mode] == 'add'
      search.build do
      #  with(:work_id).equal_to work.id if work
        with(:manifestation_ids).equal_to manifestation.id if manifestation
      end
    end
    page = params[:page] || 1
    search.query.paginate(page.to_i, SeriesStatement.default_per_page)
    @series_statements = search.execute!.results

    respond_to do |format|
      format.html # index.html.erb
      format.json { render :json => @series_statements }
    end
  end

  # GET /series_statements/1
  # GET /series_statements/1.json
  def show
    #@manifestations = @series_statement.manifestations.periodical_children.page(params[:manifestation_page]).per_page(Manifestation.default_per_page)

    respond_to do |format|
      format.html { # show.html.erb
        if user_signed_in? and current_user.has_role?('Librarian')
          redirect_to series_statement_manifestations_url(@series_statement, :all_manifestations => true)
        else
          redirect_to series_statement_manifestations_url(@series_statement)
        end
      }
      format.json { render :json => @series_statement }
      #format.js
      format.mobile {
        if user_signed_in? and current_user.has_role?('Librarian')
          redirect_to series_statement_manifestations_url(@series_statement, :all_manifestations => true)
        else
          redirect_to series_statement_manifestations_url(@series_statement)
        end
      }
    end

  end

  # GET /series_statements/new
  # GET /series_statements/new.json
  def new
    @series_statement = SeriesStatement.new
    original_series_statement = SeriesStatement.where(:id => params[:series_statement_id]).first if params[:series_statement_id]
    if original_series_statement # GET /series_statements/new?series_statement_id=1
      @series_statement = original_series_statement.dup
      if @series_statement.root_manifestation
        @manifestation = @series_statement.root_manifestation
        @series_statement.root_manifestation = @manifestation
        if @manifestation.manifestation_exinfos
          @manifestation.manifestation_exinfos.each { |exinfo| eval("@#{exinfo.name} = '#{exinfo.value}'") }
        end
        if @manifestation.manifestation_extexts
          @manifestation.manifestation_extexts.each { |extext| eval("@#{extext.name} = '#{extext.value}'") }
        end
      else
        @manifestation = @series_statement.root_manifestation
        @series_statement.root_manifestation = Manifestation.new
      end
    else # GET /series_statements/new
      @manifestation = @series_statement.root_manifestation
      @series_statement.root_manifestation = Manifestation.new
    end
    @series_work_has_languages = @series_statement.root_manifestation.work_has_languages
    @creates = @series_statement.root_manifestation.creates.order(:position)
    @realizes = @series_statement.root_manifestation.realizes.order(:position)
    @produces = @series_statement.root_manifestation.produces.order(:position)
    new_work_has_title
    respond_to do |format|
      format.html # new.html.erb
      format.json { render :json => @series_statement }
    end
  end

  # GET /series_statements/1/edit
  def edit
    @series_statement.work = @work if @work
    @series_statement.root_manifestation = Manifestation.new unless @series_statement.root_manifestation
    @series_work_has_languages = @series_statement.root_manifestation.work_has_languages
    @creates = @series_statement.root_manifestation.creates.order(:position)
    @realizes = @series_statement.root_manifestation.realizes.order(:position)
    @produces = @series_statement.root_manifestation.produces.order(:position)
    if @series_statement.root_manifestation
      manifestation = @series_statement.root_manifestation
      @subject = manifestation.subjects.collect(&:term).join(';')
      @subject_transcription = manifestation.subjects.collect(&:term_transcription).join(';')
      manifestation.manifestation_exinfos.each { |exinfo| eval("@#{exinfo.name} = '#{exinfo.value}'") } if manifestation.manifestation_exinfos
      manifestation.manifestation_extexts.each { |extext| eval("@#{extext.name} = '#{extext.value}'") } if manifestation.manifestation_extexts
    end
    new_work_has_title
  end

  # POST /series_statements
  # POST /series_statements.json
  def create
    create_titles
    set_agent_instance_from_params # Implemented in application_controller.rb
    @series_statement = SeriesStatement.new(params[:series_statement])
    @series_statement.root_manifestation = Manifestation.new(params[:manifestation])
    @series_work_has_languages = WorkHasLanguage.create_attrs(params[:language_id].try(:values), params[:language_type].try(:values))
    SeriesStatement.transaction do
      if @series_statement.periodical
        @series_statement.root_manifestation.original_title = params[:series_statement][:original_title] if  params[:series_statement][:original_title]
        @series_statement.root_manifestation.title_transcription = params[:series_statement][:title_transcription] if params[:series_statement][:title_transcription]
        @series_statement.root_manifestation.title_alternative = params[:series_statement][:title_alternative] if params[:series_statement][:title_alternative]
        @series_statement.root_manifestation.periodical_master = true
        params[:exinfos].each { |key, value| eval("@#{key} = '#{value}'") } if params[:exinfos]
        params[:extexts].each { |key, value| eval("@#{key} = '#{value}'") } if params[:extexts]
        @subject = params[:manifestation][:subject]
        @subject_transcription = params[:manifestation][:subject_transcription]
        @series_statement.root_manifestation.subjects = Subject.import_subjects(@subject, @subject_transcription) unless @subject.blank?
        @series_statement.root_manifestation.save! # if @series_statement.periodical
        @series_statement.root_manifestation.work_has_languages = WorkHasLanguage.new_objs(@series_work_has_languages.uniq)
        @series_statement.root_manifestation.creates = Create.new_from_instance(@creates, @del_creators, @add_creators)
        @series_statement.root_manifestation.realizes = Realize.new_from_instance(@realizes, @del_contributors, @add_contributors)
        @series_statement.root_manifestation.produces = Produce.new_from_instance(@produces, @del_publishers, @add_publishers)
        @series_statement.manifestations << @series_statement.root_manifestation
      end
      @series_statement.save!

      if @series_statement.periodical
        # exinfos, extextsの追加
        @series_statement.root_manifestation.
          manifestation_exinfos = ManifestationExinfo.add_exinfos(params[:exinfos], @series_statement.root_manifestation.id) if params[:exinfos] 
        @series_statement.root_manifestation.
          manifestation_extexts = ManifestationExtext.add_extexts(params[:extexts], @series_statement.root_manifestation.id) if params[:extexts] 
      end

      respond_to do |format|
        format.html { redirect_to series_statement_manifestations_path(@series_statement, :all_manifestations => true), :notice => t('controller.successfully_updated', :model => t('activerecord.models.series_statement')) }
        format.json { render :json => @series_statement, :status => :created, :location => @series_statement }
      end
    end
    rescue Exception => e
      logger.error "Failed to create: #{e}"
      prepare_options
      new_work_has_title
      respond_to do |format|
        format.html { render :action => "new" }
        format.json { render :json => @series_statement.errors, :status => :unprocessable_entity }
      end
  end

  # PUT /series_statements/1
  # PUT /series_statements/1.json
  def update
    if params[:move]
      move_position(@series_statement, params[:move])
      return
    end
    create_titles
    set_agent_instance_from_params # Implemented in application_controller.rb
    @series_statement.assign_attributes(params[:series_statement])
    @series_statement.root_manifestation = @series_statement.root_manifestation if @series_statement.root_manifestation
    @series_work_has_languages = WorkHasLanguage.create_attrs(params[:language_id].try(:values), params[:language_type].try(:values))

    respond_to do |format|
      begin
        SeriesStatement.transaction do
          @subject = params[:manifestation][:subject]
          @subject_transcription = params[:manifestation][:subject_transcription]
          params[:exinfos].each { |key, value| eval("@#{key} = '#{value}'") } if params[:exinfos]
          params[:extexts].each { |key, value| eval("@#{key} = '#{value}'") } if params[:extexts]
          if params[:series_statement][:periodical].to_s == "1"
            if @series_statement.root_manifestation
              @series_statement.root_manifestation.assign_attributes(params[:manifestation])
            else
              @series_statement.root_manifestation = Manifestation.new(params[:manifestation])
              @series_statement.root_manifestation.original_title = params[:series_statement][:original_title] if params[:series_statement][:original_title]
              @series_statement.root_manifestation.title_transcription = params[:series_statement][:title_transcription] if params[:series_statement][:title_transcription]
              @series_statement.root_manifestation.title_alternative = params[:series_statement][:title_alternative] if params[:series_statement][:title_alternative]
              @series_statement.root_manifestation.periodical_master = true
            end
            #TODO update position to edit agents without destroy
            @series_statement.root_manifestation.subjects = Subject.import_subjects(@subject, @subject_transcription)
            if params[:exinfos]
              @series_statement.root_manifestation.
                manifestation_exinfos = ManifestationExinfo.add_exinfos(params[:exinfos], @series_statement.root_manifestation.id)
            end
            if params[:extexts]
              @series_statement.root_manifestation.
                manifestation_extexts = ManifestationExtext.add_extexts(params[:extexts], @series_statement.root_manifestation.id)
            end
            @series_statement.root_manifestation.save!
            @series_statement.root_manifestation.work_has_languages = WorkHasLanguage.new_objs(@series_work_has_languages.uniq)
            @series_statement.root_manifestation.creates = Create.new_from_instance(@creates, @del_creators, @add_creators)
            @series_statement.root_manifestation.realizes = Realize.new_from_instance(@realizes, @del_contributors, @add_contributors)
            @series_statement.root_manifestation.produces = Produce.new_from_instance(@produces, @del_publishers, @add_publishers)
            @series_statement.manifestations << @series_statement.root_manifestation unless @series_statement.manifestations.include?(@series_statement.root_manifestation)
          else
            if @series_statement.root_manifestation && @series_statement.valid?
              @series_statement.root_manifestation.destroy
              @series_statement.root_manifestation = nil
            end
            @series_statement.periodical = false
          end
          @series_statement.save!
          @series_statement.manifestations.map { |manifestation| manifestation.index } if @series_statement.manifestations
          format.html { redirect_to series_statement_manifestations_path(@series_statement, :all_manifestations => true), :notice => t('controller.successfully_updated', :model => t('activerecord.models.series_statement')) }
          format.json { head :no_content }
        end
      rescue Exception => e
        logger.error "Failed to update: #{e}"
        @series_statement.root_manifestation = @series_statement.root_manifestation || Manifestation.new(params[:manifestation])
        prepare_options
        new_work_has_title
        format.html { render :action => "edit" }
        format.json { render :json => @series_statement.errors, :status => :unprocessable_entity }
      end
    end
  end

  # DELETE /series_statements/1
  # DELETE /series_statements/1.json
  def destroy
    respond_to do |format|
      begin
        SeriesStatement.transaction do
          if @series_statement.manifestations
            if @series_statement.manifestations.size == 1
               manifestation = @series_statement.manifestations.first
               if manifestation == @series_statement.root_manifestation
                 manifestation.destroy
               end
            end
          end
          @series_statement.destroy
          format.html { redirect_to series_statements_url }
          format.json { head :no_content }
        end
      rescue
        format.html { redirect_to(series_statements_path) }
        format.json { render :json => @series_statement.errors, :status => :unprocessable_entity }
      end
    end
  end

  def numbering
    manifestation_identifier = params[:type].present? ? Numbering.do_numbering(params[:type]) : nil 
    render :json => {:success => 1, :manifestation_identifier => manifestation_identifier}
  end 

  private
  def prepare_options
    @carrier_types = CarrierType.all
    @manifestation_types = ManifestationType.series
    @frequencies = Frequency.all
    @countries = Country.all
    @languages = Language.all_cache
    @language_types = LanguageType.all
    @roles = Role.all
    @create_types = CreateType.find(:all, :select => "id, display_name")
    @realize_types = RealizeType.find(:all, :select => "id, display_name")
    @produce_types = ProduceType.find(:all, :select => "id, display_name")
    @default_language = Language.where(:iso_639_1 => @locale).first
    @numberings = Numbering.where(:numbering_type => 'manifestation')
    @title_types = TitleType.find(:all, :select => "id, display_name", :order => "position")
    @use_licenses = UseLicense.all
    @sequence_patterns = SequencePattern.all
    @creates = [] if @creates.blank?
    @realizes = [] if @realizes.blank?
    @produces = [] if @produces.blank?
    @del_creators = [] if @del_creators.blank?
    @del_contributors = [] if @del_contributors.blank?
    @del_publishers = [] if @del_publishers.blank?
    @add_creators = [{}] if @add_creators.blank?
    @add_contributors = [{}] if @add_contributors.blank?
    @add_publishers = [{}] if @add_publishers.blank?
  end

  def create_titles

    return unless SystemConfiguration.get('manifestation.use_titles')

    if params[:manifestation][:work_has_titles_attributes]
      @work_has_titles = params[:manifestation][:work_has_titles_attributes]
      @work_has_titles.each do |key, value|
        if value[:title_id] != ""
          @title = Title.find(value[:title_id])
          @title.title = params[:manifestation_title][key]
          @title.save
        else
          @title = Title.new(:title => params[:manifestation_title][key])
          @title.save
          value[:title_id] = @title.id
        end
      end
    end
  end

  def new_work_has_title

    @count_titles = 0
    if SystemConfiguration.get('manifestation.use_titles')

      manifestation = @series_statement.root_manifestation

      @count_titles = manifestation.work_has_titles.size
      if manifestation.work_has_titles.empty?
        @workhastitle = WorkHasTitle.new(:title_id => 1, :title_type_id => 1, :position => 0)
        manifestation.work_has_titles << @workhastitle
        manifestation.work_has_titles[0].title_id = nil
        @count_titles = 1
      end
    end
  end

end
