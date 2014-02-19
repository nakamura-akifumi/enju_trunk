class OrdersController < ApplicationController
  #before_filter :check_client_ip_address
  #authorize_function

  load_and_authorize_resource

  # GET /orders
  # GET /orders.json
  def index
      if params[:manifestation_id]
        @orders = Order.where(["manifestation_id = ?",params[:manifestation_id]]).order("publication_year desc").page(params[:page])
        @manifestation = Manifestation.find(params[:manifestation_id])
      else
        @orders = Order.order("publication_year desc").page(params[:page])
      end

    set_select_years

    respond_to do |format|
      format.html # index.html.erb
      format.json { render :json => @orders }
      format.rss
      format.atom
      format.csv
    end
  end

  # GET /orders/1
  # GET /orders/1.json
  def show
    @order = Order.find(params[:id])
    respond_to do |format|
      format.html # show.html.erb
      format.json { render :json => @order }
    end
  end

  # GET /orders/new
  # GET /orders/new.json
  def new
    @order = Order.new

    original_order = Order.where(:id => params[:order_id]).first
    if original_order
#/////////////
      @order = original_order.dup
      @order.order_identifier = Numbering.do_numbering('order')
      @order.order_identifier.slice!(0,4)
      @order.order_identifier = (Date.today.year.to_i + 1).to_s + @order.order_identifier
      @order.order_day = original_order.order_day + 1.years
      @order.publication_year = Date.today.year.to_i + 1
      @order.paid_flag = 0
#////////////
    else
      @order.auto_calculation_flag = 1
      @order.order_day = Date.today
      if params[:manifestation_id]
        @order.manifestation_id = params[:manifestation_id].to_i
      end 

      @order.order_identifier = Numbering.do_numbering('order')#Date.today.year.to_s 
    end
#    @numbering = Numbering.find(:first, :conditions => {:numbering_type => 'order'})
#    number = @numbering.last_number.to_i
#    number = (number + 1).to_s
#    @order.order_identifier += number.rjust(@numbering.padding_number,@numbering.padding_character.to_s);

    @select_patron_tags = Order.struct_patron_selects
    @currencies = Currency.all

    respond_to do |format|
      format.html # new.html.erb
      format.json { render :json => @order }
    end
  end

  # GET /orders/1/edit
  def edit
    @order = Order.find(params[:id])
    @select_patron_tags = Order.struct_patron_selects
    @currencies = Currency.all
  end

  # POST /orders
  # POST /orders.json
  def create

    @order = Order.new(params[:order])
    @manifestation_identifier = params[:manifestation_identifier]
    manifestation = Manifestation.where(["identifier = ?", @manifestation_identifier]) unless @manifestation_identifier.blank?

    @order.manifestation_id = manifestation.id if manifestation
 
    respond_to do |format|
      if @order.save
        flash[:notice] = t('controller.successfully_created', :model => t('activerecord.models.order'))
        if @purchase_request
          format.html { redirect_to purchase_request_order_url(@order.purchase_request, @order) }
          format.json { render :json => @order, :status => :created, :location => @order }
        else
          format.html { redirect_to(@order) }
          format.json { render :json => @order, :status => :created, :location => @order }
        end
      else

        @select_patron_tags = Order.struct_patron_selects
        @currencies = Currency.all
        @order_lists = OrderList.not_ordered
        format.html { render :action => "new" }
        format.json { render :json => @order.errors, :status => :unprocessable_entity }
      end
    end
  end

  # PUT /orders/1
  # PUT /orders/1.json
  def update
    @order = Order.find(params[:id])

    respond_to do |format|
      if @order.update_attributes(params[:order])
        flash[:notice] = t('controller.successfully_updated', :model => t('activerecord.models.order'))
        if @purchase_request
          format.html { redirect_to purchase_request_order_url(@order.purchase_request, @order) }
          format.json { head :no_content }
        else
          format.html { redirect_to(@order) }
          format.json { head :no_content }
        end
      else
          @select_patron_tags = Order.struct_patron_selects
          @currencies = Currency.all
        @order_lists = OrderList.not_ordered
        format.html { render :action => "edit" }
        format.json { render :json => @order.errors, :status => :unprocessable_entity }
      end
    end
  end

  # DELETE /orders/1
  # DELETE /orders/1.json
  def destroy
    @order = Order.find(params[:id])

    respond_to do |format|
      if @order.destroy?
        @order.destroy
        format.html {redirect_to(orders_url)}
      else
        flash[:message] = t('order.cannot_delete')
        format.html {redirect_to(orders_url)}
      end
    end
  end

  def paid

    @order = Order.find(params[:order_id])
    @flag =  self.class.helpers.get_paid_flag
    @order.paid_flag = @flag.id if @flag
    @order.save
    Payment.create_paid(params[:order_id])

    respond_to do |format|
      flash[:notice] = t('controller.successfully_created', :model => t('payment.paid'))
      format.html {redirect_to(@order)}
    end
  end

  def search

    unless params[:publication_year].blank?
    @years_selected = params[:publication_year].to_i

      unless params[:manifestation_identifier].blank?
        @orders = Order.joins(:manifestation).where(["publication_year = ? AND identifier = ?", params[:publication_year].to_i, params[:manifestation_identifier]]).page(params[:page])

        @search_manifestation = Manifestation.where("identifier = ?", params[:manifestation_identifier])
        if @search_manifestation.size == 0
          flash.now[:message] = t('order.no_matches_found_manifestation')
          @search_manifestation = nil
        else
          @search_manifestation = @search_manifestation.first
        end

      else
        @orders = Order.where(["publication_year = ?", params[:publication_year].to_i]).page(params[:page])
      end
    else

      unless params[:manifestation_identifier].blank?

        @orders = Order.joins(:manifestation).where(["identifier = ?",params[:manifestation_identifier]]).order("publication_year desc").page(params[:page])

        @search_manifestation = Manifestation.where("identifier = ?", params[:manifestation_identifier])

        if @search_manifestation.size == 0
          flash.now[:message] = t('order.no_matches_found_manifestation')
          @search_manifestation = nil
        else
          @search_manifestation = @search_manifestation.first
        end

      else
        @orders = Order.order("publication_year desc").page(params[:page])
      end
    end

    @manifestation_selected = params[:manifestation_identifier]
    set_select_years

    respond_to do |format|
      format.html {render "index"}
    end

  end

  def set_select_years

    @years = Order.select(:publication_year).uniq.order('publication_year desc')
    @select_years = []
    @years.each do |p|
      @select_years.push [p.publication_year, p.publication_year] unless p.publication_year.blank?
    end

  end

  def create_subsequent_year_orders

    if params[:manifestation_identifier].blank?
      @orders = Order.where(["publication_year = ?", params[:year].to_i])
    else
      @orders = Order.joins(:manifestation).where(["publication_year = ? AND identifier = ?", params[:year].to_i, params[:manifestation_identifier]]).readonly(false)

    end

    @orders.each do |order|
      if order.order_form && order.order_form.v == '1'

        @new_order = order.dup
        @new_order.order_identifier = Numbering.do_numbering('order')
        @new_order.order_identifier.slice!(0,4)
        @new_order.order_identifier = (Date.today.year.to_i + 1).to_s + @new_order.order_identifier
        @new_order.order_day = @new_order.order_day + 1.years
        @new_order.publication_year = Date.today.year.to_i + 1
        @new_order.paid_flag = 0
        @new_order.save
      end
    end
    
    flash[:notice] = t('controller.successfully_created', :model => t('order.subsequent_year_orders'))

    redirect_to :action => "search", :publication_year => params[:year], :test => "test", :manifestation_identifier => params[:manifestation_identifier]

    #respond_to do |format|
    #  format.html {redirect_to :action => "index"}
    #end

  end




end
