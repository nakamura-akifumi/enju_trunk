# -*- encoding: utf-8 -*-
require EnjuTrunkFrbr::Engine.root.join('app', 'models', 'item')
require EnjuTrunkCirculation::Engine.root.join('app', 'models', 'item') if Setting.operation
require EnjuTrunkOrder::Engine.root.join('app', 'models', 'item') if defined? EnjuTrunkOrder
class Item < ActiveRecord::Base
  extend ActiveRecordExtension
  attr_accessible :library_id, :shelf_id, :checkout_type_id, :circulation_status_id,
                  :retention_period_id, :call_number, :bookstore_id, :price, :price_string, :url,
                  :include_supplements, :use_restriction_id, :required_role_id,
                  :acquired_at, :acquired_at_string, :note, :item_identifier, :rank, :remove_reason_id,
                  :use_restriction, :manifestation_id, :manifestation,
                  :shelf_id, :circulation_status, :bookstore, :remove_reason, :checkout_type,
                  :shelf, :bookstore, :retention_period, :accept_type_id, :accept_type, :required_role,
                  :non_searchable, :item_has_operators_attributes,
                  :non_searchable, :item_exinfo, :claim_attributes, :location_category_id, :location_symbol_id,
                  :statistical_class_id, :budget_category_id, :tax_rate_id, :excluding_tax, :tax, :item_extexts_attributes,
                  :manifestation_id, :identifier, :circulation_restriction_id

  self.extend ItemsHelper

  scope :sort_rank, order('rank')
  scope :for_checkout, where('item_identifier IS NOT NULL || identifier IS NOT NULL')
  scope :not_for_checkout, where(:identifier => nil)
  scope :on_shelf, where('shelf_id != 1')
  scope :on_web, where(:shelf_id => 1)
  scope :for_retain_from_own, lambda{|library| where('shelf_id IN (?)', library.excludescope_shelf_ids).order('created_at ASC')}
  scope :for_retain_from_others, lambda{|library| where('shelf_id NOT IN (?)', library.excludescope_shelf_ids).order('created_at ASC')}
  scope :series_statements_item, lambda {|library_ids, bookstore_ids, acquired_at|
    s = joins(:manifestation => :series_statement, :shelf => :library).
      where(['libraries.id in (?)', library_ids])
    s = s.where(['items.bookstore_id in (?)', bookstore_ids]) if bookstore_ids != :all
    s = s.where(['items.acquired_at >= ?', acquired_at]) if acquired_at.present?
    s
  }
  scope :where_ndcs_libraries_carrier_types, lambda {|ndcs, library_ids, carrier_type_ids|
    tm = Manifestation.arel_table
    tl = Library.arel_table

    ndcs_cond = nil
    (ndcs || []).each do |ndc|
      like = tm[:ndc].matches("#{ndc}%")
      if ndcs_cond.nil?
        ndcs_cond = like
      else
        ndcs_cond = ndcs_cond.or(like)
      end
    end

    s = joins(:manifestation, :shelf => :library)
    s = s.where(tl[:id].in(library_ids).to_sql)
    s = s.where(tm[:carrier_type_id].in(carrier_type_ids).to_sql)
    s = s.where(ndcs_cond.to_sql) if ndcs_cond
    s
  }
  has_many :checkouts
  has_many :reserves
  has_many :reserved_agents, :through => :reserves, :class_name => 'Agent'
  has_many :owns
  has_many :agents, :through => :owns
  belongs_to :shelf, :counter_cache => true, :validate => true
  delegate :display_name, :to => :shelf, :prefix => true
  has_many :checked_items, :dependent => :destroy
  has_many :baskets, :through => :checked_items
  belongs_to :circulation_status, :validate => true
  belongs_to :remove_reason
  belongs_to :accept_type
  belongs_to :retention_period, :validate => true
  belongs_to :bookstore, :validate => true
  has_many :donates
  has_many :donors, :through => :donates, :source => :agent
  has_one :item_has_use_restriction, :dependent => :destroy
  has_one :use_restriction, :through => :item_has_use_restriction
  has_many :reserves
  belongs_to :required_role, :class_name => 'Role', :foreign_key => 'required_role_id', :validate => true
  belongs_to :checkout_type
  #belongs_to :resource_import_textresult
  has_many :answer_has_items, :dependent => :destroy
  has_many :answers, :through => :answer_has_items
  has_one :resource_import_result
  has_many :expenses
  has_many :binding_items, :class_name => 'Item', :foreign_key => 'bookbinder_id'
  belongs_to :binder_item, :class_name => 'Item', :foreign_key => 'bookbinder_id'
  has_many :item_has_operators, :dependent => :destroy, :validate => true
  has_many :operators, :through => :item_has_operators, :source => :user
  accepts_nested_attributes_for :item_has_operators, :allow_destroy => true, :reject_if => lambda{|a| a[:username].blank? && a[:note].blank?}
  has_many :item_exinfos, :dependent => :destroy
  has_many :item_extexts, :dependent => :destroy
  accepts_nested_attributes_for :item_extexts, allow_destroy: true, reject_if: lambda { |a| a[:value].blank? and !(ItemExtext.find(a[:id]) rescue nil) }
  belongs_to :claim, :dependent => :destroy
  accepts_nested_attributes_for :claim, :allow_destroy => true, :reject_if => :all_blank
  belongs_to :location_symbol, :class_name => 'Keycode', :foreign_key => 'location_symbol_id'
  belongs_to :location_category, :class_name => 'Keycode', :foreign_key => 'location_category_id'
  belongs_to :statistical_class, :class_name => 'Keycode', :foreign_key => 'statistical_class_id'
  belongs_to :circulation_restriction, :class_name => 'Keycode'
  belongs_to :tax_rate, :class_name => 'TaxRate', :foreign_key => 'tax_rate_id'
  belongs_to :budget_category

  validates_associated :circulation_status, :shelf, :bookstore, :checkout_type, :retention_period
  validates_presence_of :circulation_status, :checkout_type, :retention_period, :rank, :circulation_restriction_id
  validate :is_original?, :if => proc{ SystemConfiguration.get("manifestation.manage_item_rank") }
  before_validation :set_circulation_status, :set_circulation_restriction, :on => :create
  before_save :set_use_restriction, :set_retention_period, :check_remove_item, :except => :delete
  before_save :set_rank, :unless => proc{ SystemConfiguration.get("manifestation.manage_item_rank") }
  #after_save :check_price, :except => :delete
  after_save :reindex

  before_validation :set_item_operator, :if => proc { SystemConfiguration.get('manifestation.use_item_has_operator') }

  has_many :orders

  def order_list
    order_list = nil
    if orders.present?
      order_list = orders.first.order_list rescue nil
    end
    return order_list
  end

  def available_order?
    unavailable_statuses = ["On PrepareOrder", "On Ordered"]

    return true unless self.circulation_status

    available_status = true

    if unavailable_statuses.include?(circulation_status.name)
      available_status = false
    end

    return available_status
  end

  def has_view_role?(current_role_id)
    current_role_id = Role.default_role.id unless current_role_id
    if self.required_role_id <= current_role_id && (self.shelf.required_role_id.nil? || self.shelf.required_role_id <= current_role_id)
      return TRUE
    else
      return FALSE
    end
  end

  def set_item_operator
    item_has_operators.each do |operator|
      operator.item = self if operator.item.blank?
    end
  end

  before_validation :check_user_number
  def check_user_number
    item_has_operators.each_with_index do |operator, i|
      operator.user_number = @user_number_list[i.to_s] if @user_number_list
    end
  end

  #enju_union_catalog
  has_paper_trail

  searchable(
    include: {
      shelf: :library,
      manifestation: [
        :creators,
        :contributors,
        :publishers
      ],
    }
  ) do
    text :item_identifier, :note, :title, :creator, :contributor, :publisher, :library
    string :item_identifier
    string :library
    integer :required_role_id
    integer :circulation_status_id
    integer :accept_type_id
    integer :retention_period_id
    integer :manifestation_id do
      manifestation.try(:id)
    end
    integer :shelf_id
    integer :agent_ids, :multiple => true
    integer :rank
    integer :remove_reason_id
    boolean :non_searchable
    integer :bookbinder_id
    integer :order_id if defined? EnjuTrunkOrder
    time :created_at
    time :updated_at
  end

  paginates_per 10

  RANK_ORIGINAL = 0
  RANK_COPY =  1
  RANK_SPARE = 2

  def reindex
    manifestation.try(:index)
  end

  def set_circulation_status
    self.circulation_status = CirculationStatus.where(:name => 'In Process').first if self.circulation_status.nil?
  end

  def set_use_restriction
    if self.use_restriction_id
      self.use_restriction = UseRestriction.where(:id => self.use_restriction_id).first
    else
      self.use_restriction = UseRestriction.where(:name => 'Limited Circulation, Normal Loan Period').first
    end
  end

  def set_circulation_restriction
     self.circulation_restriction_id = Keycode.where(:name => 'item.circulation_restriction', :v => '0').try(:first).try(:id) unless self.circulation_restriction_id
  end

  def checkout_status(user)
    user.user_group.user_group_has_checkout_types.find_by_checkout_type_id(self.checkout_type.id)
  end

  def retain_item!
    self.circulation_status = CirculationStatus.find(:first, :conditions => ["name = ?", 'Available For Pickup'])
    self.save
  end

  def cancel_retain!
    self.circulation_status = CirculationStatus.find(:first, :conditions => ["name = ?", 'Available On Shelf'])
    self.save
  end

  def creator
    manifestation.try(:creator)
  end

  def contributor
    manifestation.try(:contributor)
  end

  def publisher
    manifestation.try(:publisher)
  end

  def library
    shelf.library.name if shelf
  end

  def shelf_name
    shelf.name
  end

  def hold?(library)
    return true if self.shelf.library == library
    false
  end

  def lending_rule(user)
    lending_policy = Struct.new(:fixed_due_date, :loan_period, :renewal)
    rule = UserGroupHasCheckoutType.where(:user_group_id => user.user_group.id, :checkout_type_id => self.checkout_type_id).first
    if rule
      lending_rule = lending_policy.new
      lending_rule.fixed_due_date = rule.fixed_due_date
      lending_rule.loan_period = rule.checkout_period
      lending_rule.renewal = rule.checkout_renewal_limit
    end
    return lending_rule || nil
  end

  def owned(agent)
    owns.where(:agent_id => agent.id).first
  end

  def library_url
    "#{LibraryGroup.site_config.url}libraries/#{self.shelf.library.name}"
  end

  def manifestation_url
    Addressable::URI.parse("#{LibraryGroup.site_config.url}manifestations/#{self.manifestation.id}").normalize.to_s if self.manifestation
  end

  def deletable?
    return false unless Setting.operation
    checkouts.not_returned.empty? && (self.manifestation.items.size > 1 || self.circulation_status.name == "Removed" || SystemConfiguration.get("items.confirm_destroy") == false)
  end

  def not_for_loan?
    if use_restriction.try(:name) == 'Not For Loan'
      true
    else
      false
    end
  end

  def in_library_use_only?
    if circulation_restriction.v == '0'
      return false
    else
      return true
    end
  end

  def check_remove_item
    if self.circulation_status_id == CirculationStatus.where(name: 'Removed').first.try(:id) or self.remove_reason
      self.removed_at = Time.zone.now if self.removed_at.nil?
      manifestation = nil
      if self.manifestation
        manifestation = self.manifestation
      else
        manifestation = Manifestation.find(self.manifestation_id)
      end
      unless manifestation.article?
        self.rank = 1 if self.rank == 0
      end
    else
      self.removed_at = nil
    end
  end

  def check_price
    record = Expense.where(:item_id => self.id).order("id DESC").first
    begin
      unless record.nil?
        record.acquired_at_ym = select_acquired_at
        record.acquired_at = self.acquired_at
        record.save!

        original_library_id = record.budget.library_id rescue nil
        logger.info "@@@@@"
        logger.info "price=#{self.price} / record_price=#{record.price} , library_id=#{self.library_id} / original_library_id=#{original_library_id}"

        if self.price == record.price && self.library_id == original_library_id
          logger.info "no change. price and library_id"
          return
        end
        Expense.transaction do
          Expense.create!(:item_id => self.id, :budget_id => record.budget_id, :price => record.price*-1, :acquired_at_ym  => select_acquired_at, :acquired_at => self.acquired_at)
          #TODO
          budget = Budget.joins(:term).where(:library_id => self.shelf.library.id).order("terms.start_at DESC").first
          if budget
            budget_id = budget.id
          else
            budget_id = nil
          end
          Expense.create!(:item_id => self.id, :budget_id => budget_id, :price => self.price, :acquired_at_ym => select_acquired_at, :acquired_at => self.acquired_at)
        end
      else
        return true if self.price.nil?
        return true if Budgets.count == 0
        budget = Budget.joins(:term).where(:library_id => self.shelf.library.id).order("terms.start_at DESC").first rescue nil
        yyyymm = select_acquired_at
        Expense.create!(:item => self, :budget => budget, :price => self.price, :acquired_at_ym => yyyymm, :acquired_at => self.acquired_at)
      end
    rescue Exception => e
      logger.error "Failed to update expense: #{e}"
      logger.error $@
    end
  end

  def is_original?
    if self.rank == 0
      manifestation = nil
      if self.manifestation
        manifestation = self.manifestation
      else
        manifestation = Manifestation.find(self.manifestation_id) rescue nil
      end
      return true if manifestation.nil?
      return errors[:base] << I18n.t('item.original_item_require_item_identidier') unless self.item_identifier

      ranks = manifestation.items.map { |i| i.rank unless i == self }.compact.uniq
      return errors[:base] << I18n.t('item.already_original_item_created') if ranks.include?(0)
    end
  end

  def set_retention_period
    unless self.retention_period
      self.retention_period = RetentionPeriod.find(1)
    end
  end

  def set_rank
    self.rank = 0
  end

  def item_bind(bookbinder_id)
    Item.transaction do
      self.bookbinder_id = bookbinder_id
      self.circulation_status = CirculationStatus.where(:name => 'Binded').first
      if self.save
        self.manifestation.index
        return true
      else
        return false
      end
    end
  end

  def binded_manifestations(sort = :id)
    if sort == :serial_number
      binding_item, not_binding_item = self.binding_items.partition{|binding_items| binding_items.manifestation.serial_number?}
      if binding_item
        binding_item.map(&:manifestation).sort_by(&sort) + not_binding_item.map(&:manifestation)
      else
        not_binding_item(&:manifestation)
      end
    else
      self.binding_items.map(&:manifestation).sort_by(&sort)
    end
  end

  def binded_missing_manifestations(sort = :id)
    if sort == :serial_number
      missing_manifestations = self.binding_items.where(:circulation_status_id => CirculationStatus.where(:name => 'Missing').first.id).map(&:manifestation)
      binding_item, not_binding_item = missing_manifestations.partition{|binding_items| binding_items.serial_number?}
      if binding_item
        binding_item.sort_by(&sort) + not_binding_item
      else
        not_binding_item
      end
    else
      self.binding_items.where(:circulation_status_id => CirculationStatus.where(:name => 'Missing').first.id).map(&:manifestation).sort_by(&sort)
    end
  end

  def exchangeable?
    case self.circulation_status.name
    when "In Process", "Available On Shelf"
      return true
    else
      return false
    end
  end

  def self.numbering_item_identifier(numbering_name, options = {})
    begin
      item_identifier = Numbering.do_numbering(numbering_name, true, options)
    end while Item.where(:item_identifier => item_identifier).first
    return item_identifier
  end

  # XLSX形式でのエクスポートのための値を生成する
  # ws_type: ワークシートの種別
  # ws_col: ワークシートでのカラム名
  # sep_flg: 分割指定(ONのときture)
  # ccount: 分割指定OKのときのカラム数
  def excel_worksheet_value(ws_type, ws_col, sep_flg, ccount)
    helper = Object.new
    helper.extend(ItemsHelper)
    helper.instance_eval { def t(*a) I18n.t(*a) end } # NOTE: ItemsHelper#i18n_rankの中でtを呼び出しているが、ヘルパーを直接利用しようとするとRedCloth由来のtが見えてしまうため、その回避策
    val = nil
    case ws_col
    when 'library'
      val = shelf.library.display_name || ''

    when 'bookstore', 'checkout_type', 'circulation_status', 'required_role', 'tax_rate'
      val = __send__(ws_col).try(:name) || ''

    when 'item.budget_category'
      val = __send__(ws_col.split('.').last).try(:name) || ''

    when 'accept_type', 'retention_period', 'remove_reason', 'shelf'
      val = __send__(ws_col).try(:display_name) || ''

    when 'rank'
      val = helper.i18n_rank(rank) || ''

    when 'use_restriction'
      val = not_for_loan? ? 'TRUE' : ''

    when 'item.location_symbol', 'item.statistical_class', 'item.location_category'
      val = __send__(ws_col.split('.').last).try(:v) || ''


    else
      splits = ws_col.split('.')
      case splits[0]
      when 'item_extext'
        val = [nil]*ccount
        extexts = ItemExtext.where(name: splits[1], item_id: __send__(:id)).order(:position)
        extexts.each_with_index do |record, i|
          val[i] =  record.value
        end
      when 'item_exinfo'
        val = [nil]*ccount
        exinfos = ItemExinfo.where(name: splits[1], item_id: __send__(:id))
        exinfos.each_with_index do |record, i|
          v = __send__(:"#{splits.last}")
          if v.class == Keycode
            val[i] = v.keyname
          else
            val[i] = record.value
          end
        end
      else
        val = __send__(ws_col.split('.').last) || ''
      end
    end

    val
  end

  def self.export_removing_list(out_dir, file_type = nil)
    raise "invalid parameter: no path" if out_dir.nil? || out_dir.length < 1
    tsv_file = out_dir + "removing_list.tsv"
    pdf_file = out_dir + "removing_list.pdf"
    logger.info "output removing_list tsv: #{tsv_file} pdf: #{pdf_file}"
    # create output path
    FileUtils.mkdir_p(out_dir) unless FileTest.exist?(out_dir)

    items = Item.where('removed_at IS NOT NULL').order('removed_at ASC, id ASC')
    if items
      # tsv
      if file_type.nil? || file_type == "tsv"
        columns = [
          ['item_identifier','activerecord.attributes.item.item_identifier'],
          ['acquired_at_string', 'activerecord.attributes.item.acquired_at_string'],
          [:created_at, 'activerecord.attributes.item.created_at'],
          [:call_number, 'activerecord.attributes.item.call_number'],
          [:original_title,'activerecord.attributes.manifestation.original_title'],
          ['removed_at', 'activerecord.models.remove_reason'],
#          ['price', 'activerecord.attributes.item.price'],
          [:agent_publisher,'agent.publisher'],
          [:agent_creator, 'agent.creator'],
          [:date_of_publication, 'activerecord.attributes.manifestation.date_of_publication'],
          [:removed_reason, 'activerecord.models.remove_reason'],
          ['note', 'activerecord.attributes.item.note']
        ]
        File.open(tsv_file, "w") do |output|
          # add UTF-8 BOM for excel
          output.print "\xEF\xBB\xBF".force_encoding("UTF-8")

          # タイトル行
          row = []
          columns.each do |column|
            row << I18n.t(column[1])
          end
          output.print '"'+row.join("\"\t\"")+"\n"

          items.each do |item|
            row = []
            columns.each do |column|
              case column[0]
              when "removed_at"
                row << item.removed_at.strftime("%Y/%m/%d") rescue ""
              when :created_at
                row << item.created_at.strftime("%Y/%m/%d") rescue ""
              when :original_title
                row << item.manifestation.original_title
              when :removed_reason
                row << item.try(:remove_reason).try(:display_name) || "" rescue ""
              when :call_number
                row << item.call_number || "" rescue ""
              when :date_of_publication
                if item.manifestation.date_of_publication.nil?
                  row << ""
                else
                  row << item.manifestation.date_of_publication.strftime("%Y/%m/%d") rescue ""
                end
              when :agent_creator
                row << agents_list(item.manifestation.creators)
              when :agent_publisher
                row << agents_list(item.manifestation.publishers)
              else
                row << get_object_method(item, column[0].split('.')).to_s.gsub(/\r\n|\r|\n/," ").gsub(/\"/,"\"\"")
              end # end of case column[0]
            end #end of columns.each
            output.print '"'+row.join("\"\t\"")+"\"\n"
          end # end of items.each
        end
      end
      # pdf
      if file_type.nil? || file_type == "pdf"
        report = EnjuTrunk.new_report('removing_list.tlf')
        report.events.on :page_create do |e|
          e.page.item(:page).value(e.page.no)
        end
        report.events.on :generate do |e|
          e.pages.each do |page|
            page.item(:total).value(e.report.page_count)
          end
        end

        report.start_new_page do |page|
          page.item(:date).value(Time.now)
          items.each do |item|
            page.list(:list).add_row do |row|
              row.item(:item_identifier).value(item.item_identifier)
              row.item(:acquired_at).value(item.acquired_at_string) if item.acquired_at_string
              row.item(:created_at).value(item.created_at.strftime("%Y/%m/%d")) if item.created_at
              row.item(:call_number).value(item.call_number)
              unless item.removed_at.nil?
                row.item(:removed_at).value(item.removed_at.strftime("%Y/%m/%d"))
              end
              row.item(:removed_reason).value(item.remove_reason.display_name) if item.remove_reason
              row.item(:title).value(item.manifestation.original_title)
              unless item.manifestation.date_of_publication.nil?
                #row.item(:date_of_publication).value(item.manifestation.date_of_publication.strftime("%Y/%m/%d"))
              end
              # row.item(:price).value(to_format(item.price))
              row.item(:agent_creator).value(agents_list(item.manifestation.creators))
              row.item(:agent_publisher).value(agents_list(item.manifestation.publishers))
              row.item(:date_of_publication).value(item.manifestation.date_of_publication.strftime("%Y/%m")) rescue nil
             end
          end
        end
        report.generate_file(pdf_file)
      end
    end  #end of method
  end

  def self.export_item_register(type, out_dir, file_type = nil)
    raise "invalid parameter: no path" if out_dir.nil? || out_dir.length < 1
    tsv_file = out_dir + "item_register_#{type}.tsv"
    pdf_file = out_dir + "item_register_#{type}.pdf"
    logger.info "output item_register_#{type} tsv: #{tsv_file} pdf: #{pdf_file}"
    # create output path
    FileUtils.mkdir_p(out_dir) unless FileTest.exist?(out_dir)
    # get item
    if type == 'all'
      @items = Item.order("bookstore_id DESC, acquired_at ASC, item_identifier ASC").all
    else
      @items = Item.joins(:manifestation).where(["manifestations.manifestation_type_id in (?)", ManifestationType.type_ids(type)]).order("items.bookstore_id DESC, items.acquired_at ASC, items.item_identifier ASC").all
    end
    # make tsv
    make_item_register_tsv(tsv_file, @items) if file_type.nil? || file_type == "tsv"
    # make pdf
    make_item_register_pdf(pdf_file, @items, "item_register_#{type}") if file_type.nil? || file_type == "pdf"
  end

  def self.export_audio_list(out_dir, file_type = nil)
    raise "invalid parameter: no path" if out_dir.nil? || out_dir.length < 1
    tsv_file = out_dir + "audio_list.tsv"
    pdf_file = out_dir + "audio_list.pdf"
    logger.info "output audio_list tsv: #{tsv_file} pdf: #{pdf_file}"
    # create output path
    FileUtils.mkdir_p(out_dir) unless FileTest.exist?(out_dir)
    # get item
    carrier_type_ids = CarrierType.audio.inject([]){|ids, c| ids << c.id}
    @items = Item.joins(:manifestation).where(["manifestations.carrier_type_id IN (?)", carrier_type_ids]).order("bookstore_id DESC, acquired_at ASC, item_identifier ASC").all
    # make tsv
    make_audio_list_tsv(tsv_file, @items) if file_type.nil? || file_type == "tsv"
    # make pdf
    make_audio_list_pdf(pdf_file, @items) if file_type.nil? || file_type == "pdf"
  end


  private
  def self.agents_list(agents)
    ApplicationController.helpers.agents_list(agents, {:nolink => true})
  end

  def self.make_item_register_tsv(tsvfile, items)
    columns = [
      [:bookstore, 'activerecord.models.bookstore'],
      ['item_identifier', 'activerecord.attributes.item.item_identifier'],
      ['acquired_at_string', 'activerecord.attributes.item.acquired_at_string'],
      [:creator, 'agent.creator'],
      [:original_title, 'activerecord.attributes.manifestation.original_title'],
      [:pub_year, 'activerecord.attributes.manifestation.pub_year'],
      [:publisher, 'agent.publisher'],
      [:price, 'activerecord.attributes.manifestation.price'],
      [:call_number, 'activerecord.attributes.item.call_number'],
      [:marc_number, 'activerecord.attributes.manifestation.marc_number'],
      ['note', 'activerecord.attributes.item.note']
    ]

    File.open(tsvfile, "w") do |output|
      # add UTF-8 BOM for excel
      output.print "\xEF\xBB\xBF".force_encoding("UTF-8")

      # タイトル行
      row = []
      columns.each do |column|
        row << I18n.t(column[1])
      end
      output.print '"'+row.join("\"\t\"")+"\"\n"
      if items.nil? || items.size < 1
        logger.warn "item data is empty"
      else
        items.each do |item|
          row = []
          columns.each do |column|
            case column[0]
            when :bookstore
              row << item.try(:bookstore).try(:name) || ""
            when :creator
              creators = item.manifestation.creators.inject([]){|names, creator| names << creator.full_name if creator.full_name; names}.join("\t")
              row << creators || ""
            when :original_title
              row << item.try(:manifestation).try(:original_title) || ""
            when :pub_year
              pub_year = item.try(:manifestation).try(:date_of_publication).strftime("%Y") rescue nil
              row << pub_year || ""
            when :publisher
              publishers = item.publisher.delete_if{ |p|p.blank? }.join("\t") if item.publisher
              row << publishers || ""
            when :price
              row << item.try(:manifestation).try(:price) || ""
            when :marc_number
              marc_number = item.try(:manifestation).try(:marc_number)[0, 10] rescue nil
              row << marc_number || ""
            when :call_number
              call_number = call_numberformat(item)
              row << call_numberformat(item) || ""
            else
              row << get_object_method(item, column[0].split('.')).to_s.gsub(/\r\n|\r|\n/," ").gsub(/\"/,"\"\"")
            end
          end
          output.print '"'+row.join("\"\t\"")+"\"\n"
        end
      end
    end
  end

  def self.make_audio_list_tsv(tsvfile, items)
    columns = [
      [:library, 'activerecord.models.library'],
      [:carrier_type, 'activerecord.models.carrier_type'],
      [:shelf, 'activerecord.models.shelf'],
      ['item_identifier', 'activerecord.attributes.item.item_identifier'],
      ['acquired_at_string', 'activerecord.attributes.item.acquired_at_string'],
      [:original_title, 'activerecord.attributes.manifestation.original_title'],
      [:creator, 'agent.creator'],
      [:pub_year, 'activerecord.attributes.manifestation.pub_year'],
      [:publisher, 'agent.publisher'],
      [:call_number, 'activerecord.attributes.item.call_number'],
      ['note', 'activerecord.attributes.item.note']
    ]

    File.open(tsvfile, "w") do |output|
      # add UTF-8 BOM for excel
      output.print "\xEF\xBB\xBF".force_encoding("UTF-8")

      # タイトル行
      row = []
      columns.each do |column|
        row << I18n.t(column[1])
      end
      output.print '"'+row.join("\"\t\"")+"\"\n"
      if items.nil? || items.size < 1
        logger.warn "item data is empty"
      else
        items.each do |item|
          row = []
          columns.each do |column|
            case column[0]
            when :library
              row << item.try(:shelf).try(:library).try(:display_name).localize || ""
            when :creator
              row << item.manifestation.creators.inject([]){|names, creator| names << creator.full_name if creator.full_name; names}.join("\t") if item.manifestation.creators
            when :original_title
              row << item.try(:manifestation).try(:original_title)
            when :pub_year
              pub_year = item.manifestation.date_of_publication.strftime("%Y") rescue nil
              row << pub_year || ""
            when :publisher
              row << item.publisher.delete_if{|p|p.blank?}.join("\t") if item.publisher
            when :carrier_type
              row << item.try(:manifestation).try(:carrier_type).display_name.localize || ""
            when :shelf
              row << item.try(:shelf).display_name.localize || ""
            when :call_number
              call_number = call_numberformat(item)
              row << call_number || ""
            else
              row << get_object_method(item, column[0].split('.')).to_s.gsub(/\r\n|\r|\n/," ").gsub(/\"/,"\"\"")
            end
          end
          output.print '"'+row.join("\"\t\"")+"\"\n"
        end
      end
    end
  end

  def self.make_item_register_pdf(pdf_file, items, list_title = nil)
    report = EnjuTrunk.new_report('item_register.tlf')
    report.events.on :page_create do |e|
      e.page.item(:page).value(e.page.no)
    end
    report.events.on :generate do |e|
      e.pages.each do |page|
        page.item(:total).value(e.report.page_count)
        page.item(:list_title).value(I18n.t("item_register.#{list_title}"))
      end
    end

    bookstore_ids = [nil] + items.inject([]){|ids, item| ids << item.bookstore_id; ids}.uniq!  rescue [nil]
    if bookstore_ids
      bookstore_ids.each do |bookstore_id|
        report.start_new_page do |page|
          page.item(:date).value(Time.now)
          page.item(:bookstore).value(Bookstore.find(bookstore_id).name) rescue nil
          items.each do |item|
            if item.bookstore_id == bookstore_id
              page.list(:list).add_row do |row|
                row.item(:item_identifier).value(item.item_identifier)
                row.item(:acquired_at).value(item.acquired_at_string) if item.acquired_at_string
                row.item(:agent).value(item.manifestation.creators[0].full_name) if item.manifestation && item.manifestation.creators[0]
                row.item(:title).value(item.manifestation.original_title) if item.manifestation
                row.item(:pub_year).value(item.manifestation.date_of_publication.strftime("%Y")) if item.manifestation && item.manifestation.date_of_publication
                row.item(:publisher).value(item.publisher.delete_if{|p|p.blank?}[0]) if item.publisher
                row.item(:price).value(to_format(item.price)) if item.price
                row.item(:call_number).value(call_numberformat(item)) if item.call_number
                row.item(:marc_number).value(item.manifestation.marc_number[0,10]) if item.manifestation && item.manifestation.marc_number
                row.item(:note).value(item.note.split("\r\n")[0]) if item.note
              end
            end
          end
        end
      end
    else
      report.start_new_page do |page|
        page.item(:date).value(Time.now)
        page.item(:bookstore).value(nil)
      end
    end
    report.generate_file(pdf_file)
  end

  def self.make_audio_list_pdf(pdf_file, items)
    filename = I18n.t('item_register.audio_list')
    report = EnjuTrunk.new_item_list('item_list')

    report.events.on :page_create do |e|
      e.page.item(:page).value(e.page.no)
    end
    report.events.on :generate do |e|
      e.pages.each do |page|
        page.item(:total).value(e.report.page_count)
      end
    end

    report.start_new_page
    report.page.item(:date).value(Time.now)
    report.page.item(:list_name).value(filename)
    @items.each do |item|
      report.page.list(:list).add_row do |row|
        row.item(:library).value(item.shelf.library.display_name.localize) if item.shelf && item.shelf.library
        row.item(:carrier_type).value(item.manifestation.carrier_type.display_name.localize) if item.manifestation && item.manifestation.carrier_type
        row.item(:shelf).value(item.shelf.display_name) if item.shelf
        row.item(:ndc).value(item.manifestation.ndc) if item.manifestation
        row.item(:item_identifier).value(item.item_identifier)
        row.item(:call_number).value(call_numberformat(item))
        row.item(:title).value(item.manifestation.original_title) if item.manifestation
      end
    end
    report.generate_file(pdf_file)
    logger.error "created report: #{Time.now}"
  end

  def self.make_export_item_list_pdf(items, filename)
    return false if items.blank?
    report = EnjuTrunk.new_book_list('item_list')

    report.events.on :page_create do |e|
      e.page.item(:page).value(e.page.no)
    end
    report.events.on :generate do |e|
      e.pages.each do |page|
        page.item(:total).value(e.report.page_count)
      end
    end
    report.start_new_page
    report.page.item(:date).value(Time.now)
    report.page.item(:list_name).value(filename)
    items.each do |item|
      report.page.list(:list).add_row do |row|
        row.item(:library).value(item.shelf.library.display_name.localize) if item.shelf && item.shelf.library
        row.item(:carrier_type).value(item.manifestation.carrier_type.display_name.localize) if item.manifestation && item.manifestation.carrier_type
        row.item(:shelf).value(item.shelf.display_name) if item.shelf
        row.item(:ndc).value(item.manifestation.ndc) if item.manifestation
        row.item(:item_identifier).value(item.item_identifier)
        row.item(:call_number).value(call_numberformat(item))
        row.item(:title).value(item.manifestation.original_title) if item.manifestation
      end
    end
    return report
  end

  def self.make_export_item_list_tsv(items)
    data = String.new
    data << "\xEF\xBB\xBF".force_encoding("UTF-8") + "\n"
    columns = [
      [:library, 'activerecord.models.library'],
      [:carrier_type, 'activerecord.models.carrier_type'],
      [:shelf, 'activerecord.models.shelf'],
      [:ndc, 'activerecord.attributes.manifestation.ndc'],
      ['item_identifier', 'activerecord.attributes.item.item_identifier'],
      [:call_number, 'activerecord.attributes.item.call_number'],
      [:title, 'activerecord.attributes.manifestation.original_title'],
    ]

    # title column
    row = columns.map {|column| I18n.t(column[1])}
    data << '"'+row.join("\"\t\"")+"\"\n"

    items.each do |item|
      row = []
      columns.each do |column|
        case column[0]
        when :library
          row << item.shelf.library.display_name.localize
        when :carrier_type
          row << item.manifestation.carrier_type.display_name.localize
        when :shelf
          row << item.shelf.display_name
        when :ndc
          row << item.manifestation.ndc
        when :title
          row << item.manifestation.original_title
        when :call_number
          row << call_numberformat(item)
        else
          row << get_object_method(item, column[0].split('.')).to_s.gsub(/\r\n|\r|\n/," ").gsub(/\"/,"\"\"")
        end
      end
      data << '"'+row.join("\"\t\"")+"\"\n"
    end
    return data
  end

  def self.make_export_new_item_list_pdf(items)
    return false if items.blank?
    report = EnjuTrunk.new_book_list('new_item_list')

    report.events.on :page_create do |e|
      e.page.item(:page).value(e.page.no)
    end
    report.events.on :generate do |e|
      e.pages.each do |page|
        page.item(:total).value(e.report.page_count)
      end
    end
    report.start_new_page
    report.page.item(:date).value(Time.now)
    term = Time.zone.now.months_ago(1).strftime("%Y/%m/%d").to_s + ' -  ' + Time.now.strftime("%Y/%m/%d").to_s
    report.page.item(:term).value(term)
    items.each do |item|
      report.page.list(:list).add_row do |row|
        row.item(:library).value(item.shelf.library.display_name.localize) if item.shelf && item.shelf.library
        row.item(:carrier_type).value(item.manifestation.carrier_type.display_name.localize) if item.manifestation && item.manifestation.carrier_type
        row.item(:shelf).value(item.shelf.display_name) if item.shelf
        row.item(:ndc).value(item.manifestation.ndc) if item.manifestation
        row.item(:item_identifier).value(item.item_identifier)
        row.item(:call_number).value(call_numberformat(item))
        row.item(:created_at).value(item.created_at.strftime("%Y/%m/%d"))
        row.item(:title).value(item.manifestation.original_title) if item.manifestation
      end
    end
    return report
  end

  def self.make_export_new_item_list_tsv(items)
    data = String.new
    data << "\xEF\xBB\xBF".force_encoding("UTF-8") + "\n"

    # set term
    term = Time.zone.now.months_ago(1).strftime("%Y/%m/%d").to_s + ' -  ' + Time.now.strftime("%Y/%m/%d").to_s
    data << '"' + term + "\"\n"

    columns = [
      [:library, 'activerecord.models.library'],
      [:carrier_type, 'activerecord.models.carrier_type'],
      [:shelf, 'activerecord.models.shelf'],
      [:ndc, 'activerecord.attributes.manifestation.ndc'],
      ['item_identifier', 'activerecord.attributes.item.item_identifier'],
      [:call_number, 'activerecord.attributes.item.call_number'],
      [:created_at, 'activerecord.attributes.item.created_at'],
      [:title, 'activerecord.attributes.manifestation.original_title'],
    ]

    # title column
    row = columns.map {|column| I18n.t(column[1])}
    data << '"'+row.join("\"\t\"")+"\"\n"

    items.each do |item|
      row = []
      columns.each do |column|
        case column[0]
        when :library
          row << item.shelf.library.display_name.localize
        when :carrier_type
          row << item.manifestation.carrier_type.display_name.localize
        when :shelf
          row << item.shelf.display_name
        when :ndc
          row << item.manifestation.ndc
        when :title
          row << item.manifestation.original_title
        when :created_at
          row << item.created_at.strftime("%Y/%m/%d") if item.created_at
        when :call_number
          row << call_numberformat(item)
        else
          row << get_object_method(item, column[0].split('.')).to_s.gsub(/\r\n|\r|\n/," ").gsub(/\"/,"\"\"")
        end
      end
      data << '"'+row.join("\"\t\"")+"\"\n"
    end
    return data
  end

  def self.make_export_removed_list_pdf(items)
    return false if items.blank?
    report = EnjuTrunk.new_book_term('removed_list')

    report.events.on :page_create do |e|
      e.page.item(:page).value(e.page.no)
    end
    report.events.on :generate do |e|
      e.pages.each do |page|
        page.item(:total).value(e.report.page_count)
      end
    end
    report.start_new_page
    report.page.item(:date).value(Time.now)
    items.each do |item|
      report.page.list(:list).add_row do |row|
        row.item(:library).value(item.shelf.library.display_name.localize) if item.shelf && item.shelf.library
        row.item(:carrier_type).value(item.manifestation.carrier_type.display_name.localize) if item.manifestation && item.manifestation.carrier_type
        row.item(:shelf).value(item.shelf.display_name) if item.shelf
        row.item(:remove_reason).value(item.remove_reason.display_name) if item.remove_reason
        row.item(:item_identifier).value(item.item_identifier)
        row.item(:call_number).value(call_numberformat(item))
        row.item(:removed_at).value(item.removed_at.strftime("%Y/%m/%d")) if item.removed_at
        row.item(:title).value(item.manifestation.original_title) if item.manifestation
      end
    end
    return report
  end

  def self.make_export_removed_list_tsv(items)
    data = String.new
    data << "\xEF\xBB\xBF".force_encoding("UTF-8") + "\n"

    columns = [
      [:library, 'activerecord.models.library'],
      [:carrier_type, 'activerecord.models.carrier_type'],
      [:shelf, 'activerecord.models.shelf'],
      [:ndc, 'activerecord.attributes.manifestation.ndc'],
      [:remove_reason, 'activerecord.models.remove_reason'],
      ['item_identifier', 'activerecord.attributes.item.item_identifier'],
      [:call_number, 'activerecord.attributes.item.call_number'],
      [:removed_at, 'activerecord.attributes.item.removed_at'],
      [:title, 'activerecord.attributes.manifestation.original_title'],
    ]

    # title column
    row = columns.map {|column| I18n.t(column[1])}
    data << '"'+row.join("\"\t\"")+"\"\n"

    items.each do |item|
      row = []
      columns.each do |column|
        case column[0]
        when :library
          row << item.shelf.library.display_name.localize
        when :carrier_type
          row << item.manifestation.carrier_type.display_name.localize
        when :shelf
          row << item.shelf.display_name
        when :ndc
          row << item.manifestation.ndc
        when :title
          row << item.manifestation.original_title
        when :removed_at
          row << item.removed_at.strftime("%Y/%m/%d") rescue ""
        when :remove_reason
          row << item.try(:remove_reason).try(:display_name) || "" rescue ""
        when :call_number
          row << item.call_number || ""
        else
          row << get_object_method(item, column[0].split('.')).to_s.gsub(/\r\n|\r|\n/," ").gsub(/\"/,"\"\"")
        end
      end
      data << '"'+row.join("\"\t\"")+"\"\n"
    end
    return data
  end

  def self.make_export_new_book_list_pdf(items)
    return false if items.blank?
    report = EnjuTrunk.new_report('new_book_list')

    report.events.on :page_create do |e|
      e.page.item(:page).value(e.page.no)
    end
    report.events.on :generate do |e|
      e.pages.each do |page|
        page.item(:total).value(e.report.page_count)
      end
    end
    report.start_new_page
    report.page.item(:date).value(Time.now)
    date_ago = Time.zone.now - SystemConfiguration.get("new_book_term").day
    term = date_ago.strftime("%Y/%m/%d").to_s + ' -  '
    report.page.item(:term).value(term)
    items.each do |item|
      report.page.list(:list).add_row do |row|
        row.item(:library).value(item.shelf.library.display_name.localize) if item.shelf && item.shelf.library
        row.item(:carrier_type).value(item.manifestation.carrier_type.display_name.localize) if item.manifestation && item.manifestation.carrier_type
        row.item(:shelf).value(item.shelf.display_name) if item.shelf
        row.item(:ndc).value(item.manifestation.ndc) if item.manifestation
        row.item(:item_identifier).value(item.item_identifier)
        row.item(:pub_date).value(item.manifestation.pub_date)
        row.item(:acquired_at).value(item.acquired_at_string) if item.acquired_at_string
        row.item(:title).value(item.manifestation.original_title) if item.manifestation
      end
    end
    return report
  end

  def self.make_export_new_book_list_tsv(items)
    data = String.new
    data << "\xEF\xBB\xBF".force_encoding("UTF-8") + "\n"

    # set term
    date_ago = Time.zone.now - SystemConfiguration.get("new_book_term").day
    term = date_ago.strftime("%Y/%m/%d").to_s + ' -  '
    data << '"' + term + "\"\n"

    columns = [
      [:library, 'activerecord.models.library'],
      [:carrier_type, 'activerecord.models.carrier_type'],
      [:shelf, 'activerecord.models.shelf'],
      [:ndc, 'activerecord.attributes.manifestation.ndc'],
      ['item_identifier', 'activerecord.attributes.item.item_identifier'],
      [:pub_date, 'activerecord.attributes.manifestation.pub_date'],
      ['acquired_at_string', 'activerecord.attributes.item.acquired_at_string'],
      [:title, 'activerecord.attributes.manifestation.original_title'],
    ]

    # title column
    row = columns.map {|column| I18n.t(column[1])}
    data << '"'+row.join("\"\t\"")+"\"\n"

    items.each do |item|
      row = []
      columns.each do |column|
        case column[0]
        when :library
          row << item.shelf.library.display_name.localize
        when :carrier_type
          row << item.manifestation.carrier_type.display_name.localize
        when :shelf
          row << item.shelf.display_name
        when :ndc
          row << item.manifestation.ndc
        when :title
          row << item.manifestation.original_title
        when :pub_date
          row << item.manifestation.pub_date
        else
          row << get_object_method(item, column[0].split('.')).to_s.gsub(/\r\n|\r|\n/," ").gsub(/\"/,"\"\"")
        end
      end
      data << '"'+row.join("\"\t\"")+"\"\n"
    end
    return data
  end

  def self.make_export_series_statements_latest_list_pdf(items)
    return false if items.blank?
    report = EnjuTrunk.new_report('series_statements_latest_list')

    report.events.on :page_create do |e|
      e.page.item(:page).value(e.page.no)
    end
    report.events.on :generate do |e|
      e.pages.each do |page|
        page.item(:total).value(e.report.page_count)
      end
    end
    report.start_new_page
    report.page.item(:date).value(Time.now)
    items.each do |item|
      report.page.list(:list).add_row do |row|
        row.item(:library).value(item.shelf.library.display_name.localize) if item.shelf && item.shelf.library
        row.item(:acquired_at).value(item.acquired_at_string) if item.acquired_at_string
        row.item(:bookstore).value(item.bookstore.name) if item.bookstore
        row.item(:item_identifier).value(item.item_identifier)
        row.item(:volume_number_string).value(item.manifestation.volume_number_string) if item.manifestation
        row.item(:issue_number_string).value(item.manifestation.issue_number_string) if item.manifestation
        row.item(:serial_number_string).value(item.manifestation.serial_number_string) if item.manifestation
        row.item(:title).value(item.manifestation.original_title) if item.manifestation
      end
    end
    return report
  end

  def self.make_export_series_statements_latest_list_tsv(items)
    data = String.new
    data << "\xEF\xBB\xBF".force_encoding("UTF-8") + "\n"

    columns = [
      [:library, 'activerecord.models.library'],
      ['acquired_at', 'activerecord.attributes.item.acquired_at'],
      [:bookstore, 'activerecord.models.bookstore'],
      ['item_identifier', 'activerecord.attributes.item.item_identifier'],
      [:volume_number_string, 'activerecord.attributes.manifestation.volume_number_string'],
      [:issue_number_string, 'activerecord.attributes.manifestation.issue_number_string'],
      [:serial_number_string, 'activerecord.attributes.manifestation.serial_number_string'],
      [:title, 'activerecord.attributes.manifestation.original_title'],
    ]

    # title column
    row = columns.map {|column| I18n.t(column[1])}
    data << '"'+row.join("\"\t\"")+"\"\n"

    items.each do |item|
      row = []
      columns.each do |column|
        case column[0]
        when :library
          row << item.shelf.library.display_name.localize
        when :bookstore
          bookstore = ""
          bookstore = item.bookstore.name if item.bookstore and item.bookstore.name
          row << bookstore
        when :volume_number_string
          row << item.manifestation.volume_number_string || "" rescue ""
        when :issue_number_string
          row << item.manifestation.issue_number_string || "" rescue ""
        when :serial_number_string
          row << item.manifestation.serial_number_string || "" rescue ""
        when :title
          row << item.manifestation.original_title || "" rescue ""
        else
          row << get_object_method(item, column[0].split('.')).to_s.gsub(/\r\n|\r|\n/," ").gsub(/\"/,"\"\"")
        end
      end
      data << '"'+row.join("\"\t\"")+"\"\n"
    end
    return data
  end

  def self.make_export_series_statements_list_pdf(items, acquired_at)
    return false if items.blank?
    report = EnjuTrunk.new_report('series_statements_list')

    report.events.on :page_create do |e|
      e.page.item(:page).value(e.page.no)
    end
    report.events.on :generate do |e|
      e.pages.each do |page|
        page.item(:total).value(e.report.page_count)
      end
    end
    report.start_new_page
    report.page.item(:date).value(Time.now)
    if acquired_at.size > 0
      start_date = Time.zone.parse(acquired_at).strftime("%Y/%m/%d").to_s
    else
      start_date = ""
    end
    term = start_date + ' - ' + Time.now.strftime("%Y/%m/%d").to_s
    report.page.item(:term).value(term)
    items.each do |item|
      report.page.list(:list).add_row do |row|
        row.item(:library).value(item.shelf.library.display_name.localize) if item.shelf && item.shelf.library
        row.item(:acquired_at).value(item.acquired_at_string) if item.acquired_at_string
        row.item(:bookstore).value(item.bookstore.name) if item.bookstore
        row.item(:item_identifier).value(item.item_identifier)
        row.item(:volume_number_string).value(item.manifestation.volume_number_string) if item.manifestation
        row.item(:issue_number_string).value(item.manifestation.issue_number_string) if item.manifestation
        row.item(:serial_number_string).value(item.manifestation.serial_number_string) if item.manifestation
        row.item(:title).value(item.manifestation.original_title) if item.manifestation
      end
    end
    return report
  end

  def self.make_export_series_statements_list_tsv(items, acquired_at)
    data = String.new
    data << "\xEF\xBB\xBF".force_encoding("UTF-8") + "\n"

    # set term
    if acquired_at.size > 0
      start_date = Time.zone.parse(acquired_at).strftime("%Y/%m/%d").to_s
    else
      start_date = ""
    end
    term = start_date + ' - ' + Time.now.strftime("%Y/%m/%d").to_s
    data << '"' + term + "\"\n"

    columns = [
      [:library, 'activerecord.models.library'],
      ['acquired_at_string', 'activerecord.attributes.item.acquired_at_string'],
      [:bookstore, 'activerecord.models.bookstore'],
      ['item_identifier', 'activerecord.attributes.item.item_identifier'],
      [:volume_number_string, 'activerecord.attributes.manifestation.volume_number_string'],
      [:issue_number_string, 'activerecord.attributes.manifestation.issue_number_string'],
      [:serial_number_string, 'activerecord.attributes.manifestation.serial_number_string'],
      [:title, 'activerecord.attributes.manifestation.original_title'],
    ]

    # title column
    row = columns.map {|column| I18n.t(column[1])}
    data << '"'+row.join("\"\t\"")+"\"\n"

    items.each do |item|
      row = []
      columns.each do |column|
        case column[0]
        when :library
          row << item.shelf.library.display_name.localize
        when :bookstore
          bookstore = ""
          bookstore = item.bookstore.name if item.bookstore and item.bookstore.name
          row << bookstore
        when :volume_number_string
          row << item.manifestation.volume_number_string
        when :issue_number_string
          row << item.manifestation.issue_number_string
        when :serial_number_string
          row << item.manifestation.serial_number_string
        when :title
          row << item.manifestation.original_title
        else
          row << get_object_method(item, column[0].split('.')).to_s.gsub(/\r\n|\r|\n/," ").gsub(/\"/,"\"\"")
        end
      end
      data << '"'+row.join("\"\t\"")+"\"\n"
    end
    return data
  end

  def self.output_catalog(type, out_dir, file_type = nil)
    raise "invalid parameter: no path" if out_dir.nil? || out_dir.length < 1
    pdf_file = out_dir + "#{type}_catalog.pdf"
    logger.info "output #{type}_catalog  pdf: #{pdf_file}"
FileUtils.mkdir_p(out_dir) unless FileTest.exist?(out_dir)
if type == 'title'
      @manifestations = Manifestation.order("original_title ASC")
    elsif type == 'author'
      @manifestations = Manifestation.includes(:creates => :agent).order("agents.full_name ASC")
    elsif type == 'classifild'
      @manifestations = Manifestation.order("ndc ASC")
    end
    make_catalog_pdf(pdf_file, @manifestations, "#{type}_catalog") if file_type.nil? || file_type == "pdf"
  end

  def self.make_catalog_pdf(pdf_file, manifestations, list_title = nil)
    report = EnjuTrunk.new_report("#{list_title}.tlf")
    #report page
    report.events.on :page_create do |e|
      e.page.item(:page).value(e.page.no)
    end
    report.events.on :generate do |e|
      e.pages.each do |page|
        page.item(:total).value(e.report.page_count)
      end
    end
    report.start_new_page
    report.page.item(:date).value(Time.now)
    report.page.item(:list_name).value(I18n.t("item_register.#{list_title}"))
#TODO : Monkey patch
class << manifestations
  def batch_order
    "#{self.order_values.join(',')}"
  end
end
    manifestations.find_each do |manifestation|
      manifestation.items.each do |item|
        report.page.list(:list).add_row do |row|
          row.item(:title).value(item.manifestation.original_title) if item.manifestation
          row.item(:agent).value(item.manifestation.creators[0].full_name) if item.manifestation && item.manifestation.creators[0]
          row.item(:carrier_type).value(item.manifestation.carrier_type.display_name.localize) if item.manifestation && item.manifestation.carrier_type

          row.item(:library).value(item.shelf.library.display_name.localize) if item.shelf && item.shelf.library
          row.item(:shelf).value(item.shelf.display_name) if item.shelf
          row.item(:ndc).value(item.manifestation.ndc) if item.manifestation
          row.item(:item_identifier).value(item.item_identifier) if item.item_identifier
          row.item(:call_number).value(call_numberformat(item)) if call_numberformat(item)
        end
      end
    end
    report.generate_file(pdf_file)
  end

  def self.make_export_item_list_job(file_name, file_type, method, dumped_query, args, user)
    job_name = GenerateItemListJob.generate_job_name
    Delayed::Job.enqueue GenerateItemListJob.new(job_name, file_name, file_type, method, dumped_query, args, user)
    job_name
  end

  class GenerateItemListJob
    include Rails.application.routes.url_helpers
    include BackgroundJobUtils

    def initialize(job_name, file_name, file_type, method, dumped_query, args, user)
      @job_name = job_name
      @file_name = file_name
      @file_type = file_type
      @method = method
      @dumped_query = dumped_query
      @args = args
      @user = user
    end
    attr_accessor :job_name, :file_name, :file_type, :method, :dumped_query, :args, :user

    def perform
      user_file = UserFile.new(user)

      # get data
      query = Marshal.load(dumped_query)
      logger.info "SQL start at #{Time.now}"
      items = query.all
      logger.info "SQL end at #{Time.now}\nfound #{items.length rescue 0} records"
      logger.info "list_type=#{file_name} file_type=#{file_type}"

      data = Item.__send__("#{method}_#{file_type}", items, *args)
      if file_type == 'pdf'
        raise I18n.t('item_list.no_record') unless data
        data = data.generate
      end

      io, info = user_file.create(:item_list, "#{file_name}.#{file_type}")
      begin
        io.print data
      ensure
        io.close
      end

      url = my_account_url(:filename => info[:filename], :category => info[:category], :random => info[:random])
      message(
        user,
        I18n.t('item_list.export_job_success_subject', :job_name => job_name),
        I18n.t('item_list.export_job_success_body', :job_name => job_name, :url => url))

    rescue => exception
      message(
        user,
        I18n.t('item_list.export_job_error_subject', :job_name => job_name),
        I18n.t('item_list.export_job_error_body', :job_name => job_name, :message => exception.message))
    end
  end

  def self.make_export_register_job(file_name, file_type, method, args, user)
    job_name = GenerateItemRegisterJob.generate_job_name
    Delayed::Job.enqueue GenerateItemRegisterJob.new(job_name, file_name, file_type, method, args, user)
    job_name
  end

  class GenerateItemRegisterJob
    include Rails.application.routes.url_helpers
    include BackgroundJobUtils

    def initialize(job_name, file_name, file_type, method, args, user)
      @job_name = job_name
      @file_name = file_name
      @file_type = file_type
      @method = method
      @args = args
      @user = user
    end
    attr_accessor :job_name, :file_name, :file_type, :method, :args, :user

    def perform
      fn = "#{file_name}.#{file_type}"
      user_file = UserFile.new(user)
      url = nil
      logger.error "SQL start at #{Time.now}"

      Dir.mktmpdir do |tmpdir|
        Item.__send__(method, *args, tmpdir + '/', file_type)
        o, info = user_file.create(:item_register, fn)
        begin
          open(File.join(tmpdir, fn)) do |i|
            FileUtils.copy_stream(i, o)
          end
        ensure
          o.close
        end

        url = my_account_url(:filename => info[:filename], :category => info[:category], :random => info[:random])
      end

      message(
        user,
        I18n.t('item_register.export_job_success_subject', :job_name => job_name),
        I18n.t('item_register.export_job_success_body', :job_name => job_name, :url => url))

      logger.error "created report: #{Time.now}"

    rescue => exception
      message(
        user,
        I18n.t('item_register.export_job_error_subject', :job_name => job_name),
        I18n.t('item_register.export_job_error_body', :job_name => job_name, :message => exception.message)
        )
    end
  end
end

# == Schema Information
#
# Table name: items
#
#  id                          :integer         not null, primary key
#  call_number                 :string(255)
#  item_identifier             :string(255)
#  circulation_status_id       :integer         not null
#  checkout_type_id            :integer         default(1), not null
#  created_at                  :datetime
#  updated_at                  :datetime
#  deleted_at                  :datetime
#  shelf_id                    :integer         default(1), not null
#  include_supplements         :boolean         default(FALSE), not null
#  checkouts_count             :integer         default(0), not null
#  owns_count                  :integer         default(0), not null
#  resource_has_subjects_count :integer         default(0), not null
#  note                        :text
#  curl                         :string(255)
#  price                       :integer
#  lock_version                :integer         default(0), not null
#  required_role_id            :integer         default(1), not null
#  state                       :string(255)
#  required_score              :integer         default(0), not null
#  acquired_at                 :datetime
#  bookstore_id                :integer
#

