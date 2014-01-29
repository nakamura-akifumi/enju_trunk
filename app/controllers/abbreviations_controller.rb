class AbbreviationsController < ApplicationController
  respond_to :html, :json
  before_filter :check_client_ip_address
  load_and_authorize_resource

  def new
    @abbreviation = Abbreviation.new

    respond_to do |format|
      format.html
      format.json { render :json => @abbreviation }
    end
  end

  def edit
  end

  def create
    @abbreviation = Abbreviation.new(params[:abbreviation])

    respond_to do |format|
      if @abbreviation.save
        flash[:notice] = t('controller.successfully_created', :model => t('activerecord.models.abbreviation'))
        format.html { redirect_to(@abbreviation) }
        format.json { render :json => @abbreviation, :status => :created, :location => @abbreviation }
      else
        format.html { render :action => "new" }
        format.json { render :json => @abbreviation.errors, :status => :unprocessable_entity }
      end
    end
  end

  def update
    respond_to do |format|
      if @abbreviation.update_attributes(params[:abbreviation])
        flash[:notice] = t('controller.successfully_updated', :model => t('activerecord.models.abbreviation'))
        format.html { redirect_to abbreviation_url(@abbreviation) }
        format.json { head :no_content }
      else
        format.html { render :action => "edit" }
        format.json { render :json => @abbreviation.errors, :status => :unprocessable_entity }
      end
    end
  end

  def destroy
    @abbreviation.destroy

    respond_to do |format|
      format.html { redirect_to(abbreviations_url) }
      format.json { head :no_content }
    end
  end
end
