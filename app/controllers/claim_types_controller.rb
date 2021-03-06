class ClaimTypesController < InheritedResources::Base
  add_breadcrumb "I18n.t('activerecord.models.claim_type')", 'claim_types_path'
  add_breadcrumb "I18n.t('page.new', :model => I18n.t('activerecord.models.claim_type'))", 'new_claim_type_path', :only => [:new, :create]
  add_breadcrumb "I18n.t('page.editing', :model => I18n.t('activerecord.models.claim_type'))", 'edit_claim_type_path(params[:id])', :only => [:edit, :update]
  respond_to :html, :json
  before_filter :check_client_ip_address
  load_and_authorize_resource

  def index
    @claim_types= ClaimType.page(params[:page])
  end
end
