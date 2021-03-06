class AcceptsController < ApplicationController
  load_and_authorize_resource except: :index
  authorize_resource only: :index
  before_filter :get_basket, only: [:index, :create]

  # GET /accepts
  # GET /accepts.json
  def index
    if params[:format] == 'txt'
      @accepts = Accept.order('accepts.created_at DESC').page(params[:page]).per(65534)
    else
      if params[:accept]
        @query = params[:accept][:item_identifier].to_s.strip
        item = Item.where(item_identifier: @query).first if @query.present?
      end

      if item
        @accepts = Accept.order('accepts.created_at DESC').where(item_id: item.id).page(params[:page])
      else
        if @basket
          @accepts = @basket.accepts.page(params[:page])
        else
          @accepts = Accept.page(params[:page])
        end
      end
    end

    respond_to do |format|
      format.html # index.html.erb
      format.json { render json: @accepts }
      format.js { @accept = Accept.new }
      #format.txt
    end
  end

  # GET /accepts/1
  # GET /accepts/1.json
  def show
    respond_to do |format|
      format.html # show.html.erb
      format.json { render json: @accept }
    end
  end

  # GET /new
  # GET /new.json
  def new
    @basket = Basket.new
    @basket.user = current_user
    @basket.save!
    @accept = Accept.new
    @accepts = []

    respond_to do |format|
      format.html # new.html.erb
      format.json { render json: @accept }
    end
  end

  # GET /accepts/new
  # GET /accepts/1/edit
  def edit
  end

  # POST /accepts
  # POST /accepts.json
  def create
    unless @basket
      access_denied; return
    end
    @accept.basket = @basket
    @accept.librarian = current_user

    item = nil
    order = nil

    flash[:message] = ''
    if @accept.item_identifier.blank?
      flash[:message] << t('accept.enter_item_identifier')

      @accepts = @basket.accepts.page(params[:page])

      respond_to do |format|
        format.html { render action: "index" }
        format.json { render json: @accept.errors, status: :unprocessable_entity }
        format.js { render action: "index" }
      end

      return
    else
      order = Order.where(purchase_order_number: @accept.item_identifier.to_s.strip).first
      if order
        item = order.item
      else
        item = Item.where(item_identifier: @accept.item_identifier.to_s.strip).first
      end
    end
    @accept.item = item
    @accept.order = order

    respond_to do |format|
      if @accept.save
        if order
          order.accept = @accept
          order.save!

          if order.item
            item = order.item
            status = CirculationStatus.where(name: "On Order").first rescue nil
            if status
              item.circulation_status = status
              item.save!
            end
          end
        end
        flash[:message] << t('accept.successfully_accepted', model:  t('activerecord.models.accept'))
        format.html { redirect_to accepts_url(basket_id: @basket.id) }
        format.json { render json: @accept, status: :created, location:  @accept }
        format.js { redirect_to accepts_url(basket_id: @basket.id, format: :js) }
      else
        @accepts = @basket.accepts.page(params[:page])
        format.html { render action: "index" }
        format.json { render json: @accept.errors, status: :unprocessable_entity }
        format.js { render action: "index" }
      end
    end
  end

  # PUT /accepts/1
  # PUT /accepts/1.json
  def update
    respond_to do |format|
      if @accept.update_attributes(params[:accept])
        format.html { redirect_to @accept, notice:  t('controller.successfully_updated', model:  t('activerecord.models.accept')) }
        format.json { head :no_content }
      else
        format.html { render action: "edit" }
        format.json { render json: @accept.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /accepts/1
  # DELETE /accepts/1.json
  def destroy
    @accept.destroy

    respond_to do |format|
      format.html { redirect_to accepts_url, notice: t('controller.successfully_deleted', model: t('activerecord.models.accept')) }
      format.json { head :no_content }
    end
  end
end
