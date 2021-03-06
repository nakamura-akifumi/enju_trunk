require EnjuTrunkOrder::Engine.root.join('app', 'models', 'user') if defined? EnjuTrunkOrder
class User < ActiveRecord::Base
  self.extend UsersHelper
  # Include default devise modules. Others available are:
  # :token_authenticatable, :lockable and :timeoutable
  devise :database_authenticatable, #:registerable, :confirmable,
         :recoverable, :rememberable, :trackable, #:validatable,
         :lockable, :lock_strategy => :none, :unlock_strategy => :none

  cattr_accessor :current_user
  attr_accessor :new_user_number

  # Setup accessible (or protected) attributes for your model
  attr_accessible :email, :password, :password_confirmation, :current_password,
    :remember_me, :email_confirmation, :library_id, :locale,
    :keyword_list, :auto_generated_password, :expired_at, :user_group_id, :role_id,
    :username, :own_password, :user_status_id, :function_class_id, :department_id
  attr_accessible :email, :password, :password_confirmation, :current_password,
    :remember_me, :email_confirmation, :library_id, :locale,
    :keyword_list, :auto_generated_password, :expired_at, :user_group_id, :role_id,
    :days_after_penalty, :in_penalty,
    :username, :own_password, :user_status_id, :department_id, :function_class, :as => :user_change_department
  attr_accessible :email, :password, :password_confirmation, :username,
    :current_password, :user_number, :remember_me,
    :email_confirmation, :note, :user_group_id, :library_id, :locale,
    :expired_at, :locked, :unable, :required_role_id, :role_id,
    :keyword_list, :user_has_role_attributes, :auto_generated_password, :own_password,
    :days_after_penalty, :in_penalty,
    :user_status_id, :department_id, :function_class_id, :as => :admin

  scope :administrators, where('roles.name = ?', 'Administrator').includes(:role)
  scope :librarians, where('roles.name = ? OR roles.name = ?', 'Administrator', 'Librarian').includes(:role)
  scope :suspended, where('locked_at IS NOT NULL')
  scope :adults, joins(:agent).where(["agents.date_of_birth <= ?", Date.today.years_ago(18).change(:month => 4, :day => 1)])
  scope :students, joins(:agent).where(["agents.date_of_birth < ? AND agents.date_of_birth >= ?", Date.today.years_ago(15).change(:month => 4, :day => 1), Date.today.years_ago(18).change(:month => 4, :day => 1)])
  scope :juniors, joins(:agent).where(["agents.date_of_birth < ? AND agents.date_of_birth >= ?", Date.today.years_ago(12).change(:month => 4, :day => 1), Date.today.years_ago(15).change(:month => 4, :day => 1)])
  scope :elementaries, joins(:agent).where(["agents.date_of_birth < ? AND agents.date_of_birth >= ?", Date.today.years_ago(6).change(:month => 4, :day => 1), Date.today.years_ago(12).change(:month => 4, :day => 1)])
  scope :children, joins(:agent).where(["agents.date_of_birth >= ?", Date.today.years_ago(6).change(:month => 4, :day => 1)])
  scope :provisional, where(:user_number => nil)
  scope :corporate, joins(:agent => :agent_type).where(["agent_types.name = ? ", "CorporateBody"])
  has_one :agent
  has_many :checkouts
  has_many :import_requests
  has_many :sent_messages, :foreign_key => 'sender_id', :class_name => 'Message'
  has_many :received_messages, :foreign_key => 'receiver_id', :class_name => 'Message'
  #has_many :user_has_shelves
  #has_many :shelves, :through => :user_has_shelves
  has_many :picture_files, :as => :picture_attachable, :dependent => :destroy
  has_many :import_requests
  has_one :user_has_role
  has_one :role, :through => :user_has_role
  if defined?(EnjuBookmark)
    has_many :bookmarks, :dependent => :destroy
  end
  has_many :reserves, :dependent => :destroy
  has_many :reserved_manifestations, :through => :reserves, :source => :manifestation
  has_many :questions
  has_many :answers
  has_many :search_histories, :dependent => :destroy
  has_many :baskets, :dependent => :destroy
  has_many :purchase_requests
  has_many :subscriptions
  has_many :checkout_stat_has_users
  has_many :user_checkout_stats, :through => :checkout_stat_has_users
  has_many :reserve_stat_has_users
  has_many :user_reserve_stats, :through => :reserve_stat_has_users
  belongs_to :library, :validate => true
  belongs_to :user_group
  belongs_to :required_role, :class_name => 'Role', :foreign_key => 'required_role_id' #, :validate => true
  has_one :agent_import_result
  has_one :family, :through => :family_user
  has_one :family_user
  has_many :barcode_lists, :foreign_key => 'created_by'
  belongs_to :user_status
  belongs_to :department
  has_many :copy_requests
  has_many :nacsis_user_requests, :dependent => :destroy
  belongs_to :function_class

  has_many :item_has_operators
  has_many :works, :through => :item_has_operators

  has_many :budgets

  validates :username, :presence => true, :format => {:with => eval(Setting.validator.username_format), :message => I18n.t('errors.messages.en_expected')} #, :uniqueness => true
  validates_uniqueness_of :username, :unless => proc{|user| SystemConfiguration.get('auto_user_number')}, :allow_blank => true
  validates_uniqueness_of :email, :scope => authentication_keys[1..-1], :case_sensitive => false, :allow_blank => true
  validates :email, :format => {:with => /\A([\w\.%\+\-]+)@([\w\-]+\.)+([\w]{2,})\z/i}, :allow_blank => true
  validates_date :expired_at, :allow_blank => true

  with_options :if => :password_required? do |v|
    v.validates_presence_of     :password
    v.validates_confirmation_of :password
    v.validates_length_of       :password, :within => eval(Setting.validator.user_password_length), :allow_blank => true
  end
#  validates_presence_of :email, :email_confirmation, :on => :create #, :if => proc{|user| !user.operator.try(:has_role?, 'Librarian')}
  validates_associated :agent, :user_group, :library
  validates_presence_of :user_group, :library, :locale #, :user_number
  validates :user_number, :uniqueness => true, :format => {:with => /\A[0-9A-Za-z_\-\.]+\Z/}, :allow_blank => true
  validates_confirmation_of :email, :on => :create#, :if => proc{|user| !user.operator.try(:has_role?, 'Librarian')}
  validates_confirmation_of :email, :on => :update, :if => Proc.new { |user| user.email != User.find(user.id).email }
  before_validation :set_role_and_agent, :on => :create
  before_validation :set_lock_information
  before_validation :set_user_number, :on => :create
  before_destroy :check_item_before_destroy, :check_role_before_destroy
  before_save :check_expiration
  before_create :set_expired_at
  after_destroy :remove_from_index
  after_create :set_confirmation
  after_save :index_agent
  after_destroy :index_agent

  validates :days_after_penalty, numericality: true
  #validates :in_penalty

  extend FriendlyId
  friendly_id :username
  #acts_as_tagger
  has_paper_trail
  normalize_attributes :username, :user_number #, :email

  searchable do
    text :username, :email, :note, :user_number
    text :telephone_number_1_1 do
      agent.telephone_number_1.gsub("-", "") if agent && agent.telephone_number_1
    end
    text :telephone_number_1_2 do
      agent.telephone_number_1 if agent && agent.telephone_number_1
    end
    text :extelephone_number_1_1 do
      agent.extelephone_number_1.gsub("-", "") if agent && agent.extelephone_number_1
    end
    text :extelephone_number_1_2_ do
      agent.extelephone_number_1 if agent && agent.extelephone_number_1
    end
    text :fax_number_1_1 do
      agent.fax_number_1.gsub("-", "") if agent && agent.fax_number_1
    end
    text :fax_number_1_2 do
      agent.fax_number_1 if agent && agent.fax_number_1
    end
    text :telephone_number_2_1 do
      agent.telephone_number_2.gsub("-", "") if agent && agent.telephone_number_2
    end
    text :telephone_number_2_2 do
      agent.telephone_number_2 if agent && agent.telephone_number_2
    end
    text :extelephone_number_2_1 do
      agent.extelephone_number_2.gsub("-", "") if agent && agent.extelephone_number_2
    end
    text :extelephone_number_2_2 do
      agent.extelephone_number_2 if agent && agent.extelephone_number_2
    end
    text :fax_number_2_1 do
      agent.fax_number_2.gsub("-", "") if agent && agent.fax_number_2
    end
    text :fax_number_2_2 do
      agent.fax_number_2 if agent && agent.fax_number_2
    end
    text :address do
      addresses = []
      addresses << agent.address_1 if agent
      addresses << agent.address_2 if agent
    end
    text :address_1 do
      agent.address_1 if agent
    end
    text :name do
      agent.name if agent
    end
    text :department do
      department.try(:display_name)
    end
    string :username
    string :email
    string :user_number
    string :telephone_number do
      agent.telephone_number_1.gsub("-", "") if agent && agent.telephone_number_1
    end
    string :full_name do
      agent.full_name_transcription if agent
    end
    string :telephone_number do
      agent.telephone_number_1 if agent && agent.telephone_number_1
    end
    integer :required_role_id
    integer :id
    time :created_at
    time :updated_at
    time :date_of_birth do
      agent.date_of_birth if agent
    end
    boolean :active do
      active_for_authentication?
    end
    time :confirmed_at
    string :library do
      library.try(:name)
    end
    string :role do
      role.display_name
    end
    string :agent_type do
      agent.agent_type.name if agent
    end
    string :user_status do
      user_status.name
    end
    boolean :unable

    integer :department_id
    integer :user_group_id
  end

  attr_accessor :first_name, :middle_name, :last_name, :full_name,
    :first_name_transcription, :middle_name_transcription,
    :last_name_transcription, :full_name_transcription,
    :zip_code, :address, :address_1, :telephone_number, :fax_number, :address_note,
    :role_id, :agent_id, :operator, :password_not_verified,
    :update_own_account, :auto_generated_password,
    :locked, :current_password, :birth_date, :death_date #, :email

  paginates_per 10

  def password_required?
    !persisted? || !password.nil? || !password_confirmation.nil?
  end

  def has_role?(role_in_question)
    return false unless role
    return true if role.name == role_in_question
    case role.name
    when 'Administrator'
      return true
    when 'Librarian'
      return true if role_in_question == 'User'
    else
      false
    end
  end

  def set_role_and_agent
    #self.required_role = Role.find_by_name('Librarian')
#    self.locale = I18n.default_locale.to_s
    unless self.agent
#      self.agent = Agent.create(:full_name => self.username) if self.username
    end
  end

  def set_lock_information
    return unless state_id = self.try(:user_status).try(:state_id)
    if state_id > 1 and self.active_for_authentication?
      lock_access!
    elsif state_id == 1 and !self.active_for_authentication?
      unlock_access!
    end
  end

  def set_confirmation
    if operator and respond_to?(:confirm!)
      reload
      confirm!
    end
  end

  def set_user_number
    self.user_number = self.username if SystemConfiguration.get('auto_user_number')
  end

  def index_agent
    if self.agent
      self.agent.index
    end
  end

  def check_expiration
    return if self.has_role?('Administrator')
    if expired_at
      if expired_at.beginning_of_day < Time.zone.now.beginning_of_day
        lock_access! if self.active_for_authentication?
      end
    end
  end

  def check_item_before_destroy
    # TODO: 貸出記録を残す場合
    if checkouts.size > 0
      raise 'This user has items still checked out.'
    end
  end

  def check_role_before_destroy
    if self.has_role?('Administrator')
      raise 'This is the last administrator in this system.' if Role.find_by_name('Administrator').users.size == 1
    end
  end

  def set_auto_generated_password
    password = Devise.friendly_token[0..7]
    self.reset_password!(password, password)
    self.own_password = false
  end

  def reset_checkout_icalendar_token
    self.checkout_icalendar_token = Devise.friendly_token
  end

  def delete_checkout_icalendar_token
    self.checkout_icalendar_token = nil
  end

  def reset_answer_feed_token
    self.answer_feed_token = Devise.friendly_token
  end

  def delete_answer_feed_token
    self.answer_feed_token = nil
  end

  def self.lock_expired_users
    User.find_each do |user|
      user.lock_access! if user.expired? and user.active_for_authentication?
    end
  end

  def expired?
    if expired_at
      true if expired_at.beginning_of_day < Time.zone.now.beginning_of_day
    end
  end

  def checked_item_count
    checkout_count = {}
    CheckoutType.all.each do |checkout_type|
      # 資料種別ごとの貸出中の冊数を計算
      checkout_count[:"#{checkout_type.name}"] = self.checkouts.count_by_sql(["
        SELECT count(item_id) FROM checkouts
          WHERE item_id IN (
            SELECT id FROM items
              WHERE checkout_type_id = ?
          )
          AND user_id = ? AND checkin_id IS NULL", checkout_type.id, self.id]
      )
    end
    return checkout_count
  end

  def reached_reservation_limit?(manifestation)
    return true if self.user_group.user_group_has_checkout_types.available_for_carrier_type(manifestation.carrier_type).where(:user_group_id => self.user_group.id).collect(&:reservation_limit).max.to_i <= self.reserves.waiting.size
    false
  end

  def is_admin?
    true if self.has_role?('Administrator')
  end

  def last_librarian?
    if self.has_role?('Librarian')
      role = Role.where(:name => 'Librarian').first
      true if role.users.size == 1
    end
  end

  def send_message(status, options = {})
    MessageRequest.transaction do
      request = MessageRequest.new
      request.sender = User.find(1)
      request.receiver = self
      request.message_template = MessageTemplate.localized_template(status, self.locale)
      request.save_message_body(options)
      request.sm_send_message!
    end
    rescue Exception => e
      logger.error "Failed to send message: #{e}"
  end

  def owned_tags_by_solr
    bookmark_ids = bookmarks.collect(&:id)
    if bookmark_ids.empty?
      []
    else
      Tag.bookmarked(bookmark_ids)
    end
  end

  def check_update_own_account(user)
    if user == self
      self.update_own_account = true
      return true
    end
    false
  end

  def send_confirmation_instructions
    unless self.operator
      Devise::Mailer.delay.confirmation_instructions(self) if self.email.present?
    end
  end

  def set_expired_at
    if self.user_group.valid_period_for_new_user > 0
      self.expired_at = self.user_group.valid_period_for_new_user.days.from_now.end_of_day
    end
  end

  def deletable_by(current_user)
    # 未返却の資料のあるユーザを削除しようとした
    if self.checkouts.not_returned.count > 0
      errors[:base] << I18n.t('user.this_user_has_checked_out_item')
    end

    if self.has_role?('Librarian')
      # 管理者以外のユーザが図書館員を削除しようとした。図書館員の削除は管理者しかできない
      unless current_user.has_role?('Administrator')
        errors[:base] << I18n.t('user.only_administrator_can_destroy')
      end
      # 最後の図書館員を削除しようとした
      if self.last_librarian?
        errors[:base] << I18n.t('user.last_librarian')
      end
    end

    # 最後の管理者を削除しようとした
    if self.has_role?('Administrator')
      if Role.where(:name => 'Administrator').first.users.size == 1
        errors[:base] << I18n.t('user.last_administrator')
      end
    end

    if errors[:base] == []
      true
    else
      false
    end
  end

  def self.create_with_params(params, has_role_id)
    logger.debug "create_with_params start."
    user = User.new
    user.assign_attributes(params, :as => :admin)

    #puts "****"
    #puts params

    user_group = UserGroup.find(params[:user_group_id])
    user.user_group = user_group if user_group
    user.locale = params[:locale]
    library = Library.find(params[:library_id])
    user.library = library if library
    user.operator = current_user

    logger.debug "create_with_params create-1"

    if params
      #self.username = params[:user][:login]
      user.note = params[:note]
      user.user_group_id = params[:user_group_id] ||= 1
      user.library_id = params[:library_id] ||= 1
      # user.role_id = params[:role_id] ||= 1

      if !params[:role_id].blank? and has_role_id.blank?
        user.role_id = params[:role_id] ||= 1
        user.role = Role.find(user.role_id)
      elsif !has_role_id.blank?
        user.role_id = has_role_id ||= 1
        user.role = Role.find(has_role_id)
      else
        user.role_id = Role.where(:name => 'User').first.id ||= 1
        user.role = Role.where(:name => 'User').first
      end

      user.required_role_id = params[:required_role_id] ||= 1
      user.required_role = Role.find(user.required_role_id)
      user.keyword_list = params[:keyword_list]
      user.user_number = params[:user_number]
      user.locale = params[:locale]
    end

    logger.debug "create_with_params create-10"

    if user.agent_id
      user.agent = Agent.find(user.agent_id) rescue nil
    end
    logger.debug "create_with_params end."
    user
  end

  def update_with_params(params)
    self.operator = current_user
    self.openid_identifier = params[:openid_identifier]
    self.keyword_list = params[:keyword_list]
    self.checkout_icalendar_token = params[:checkout_icalendar_token]
    self.email = params[:email]
    #self.note = params[:note]
    #self.username = params[:login]

    if current_user.has_role?('Librarian')
      self.email = params[:email]
      self.expired_at = params[:expired_at]
      self.note = params[:note]
      self.user_group_id = params[:user_group_id] || 1
      self.library_id = params[:library_id] || 1
      self.role_id = params[:role_id]
      self.required_role_id = params[:required_role_id] || 1
      self.locale = params[:locale]
      self.user_number = params[:user_number]
      self.locked = params[:locked]
      self.expired_at = params[:expired_at]
      self.unable = params[:unable]
    end
    self
  end

  def deletable?
    true if checkouts.not_returned.empty? and id != 1
  end

  # TODO: function name
  def available_for_reserve?
    if SystemConfiguration.get("penalty.user_penalty")
      if self.user_group.restrict_reservation_in_penalty == true
        self.checkouts.each do |checkout|
          days_overdue = checkout.days_overdue
          if days_overdue >= user_group.penalty_day
            return false
          end
        end
      end
    end
    return true
  end

  def set_family(user_id)
    family = User.find(user_id).family rescue nil
    if family
      family.users << self
    else
        family = Family.create()
        user = User.find(user_id)
        family.users << self
        family.users << user
    end
  end

  def out_of_family
    begin
      family_user = FamilyUser.find(:first, :conditions => ['user_id=?', self.id])
      family_id = family_user.family_id
      family_user.destroy
      all_users = FamilyUser.find(:all, :conditions => ['family_id=?', family_id])
      if all_users && all_users.length == 1
        all_users.each do |user|
          user.destroy
        end
      end
    rescue Exception => e
      logger.error e
    end
  end

  def family
    FamilyUser.find(:first, :conditions => ['user_id=?', id]).family
  end

  def user_notice
    @messages = []
    @messages << I18n.t('user.not_connect', :user => self.username) if self.unable
    overdues = self.checkouts.overdue(Time.zone.today.beginning_of_day) rescue nil
    @messages << I18n.t('user.overdue_item', :user => self.username, :count => overdues.length) unless overdues.empty?
    if SystemConfiguration.get('penalty.user_penalty') && [1,2].include?(self.user_group.restrict_checkout_in_penalty)
      if self.in_penalty
        @messages << I18n.t('user.in_penalty')
      elsif self.has_penalty?
        @messages << I18n.t('user.has_penalty')
      elsif self.days_after_penalty > 0
        @messages << I18n.t('user.checkout_probation', :num => self.user_group.checkout_limit_after_penalty_in_probation)
      end
    end
    reserves = self.reserves.hold rescue nil
    @messages << I18n.t('user.retained_reserve', :user => self.username, :count => reserves.length) unless reserves.empty?
    return @messages
  end

  def has_penalty?
    self.checkouts.not_returned.each do |c| 
      return true if c.days_overdue >= self.user_group.days_to_penalty
    end 
    return false
  end 

  def self.set_penalty(date = Date.yesterday)
    return unless SystemConfiguration.get('penalty.user_penalty')
    Checkout.overdue(date).each do |checkout|
      checkout.user.update_attribute(:in_penalty, true) if checkout.user.has_penalty?
    end
  end

  def age
    Date.today.year - agent.date_of_birth.year
  end

  def set_color
    @color = nil
    @color = SystemConfiguration.get("user.unable.background") if self.unable == true
    @color = SystemConfiguration.get("user.locked.background") if self.user_status.state_id == 3 # unless self.locked_at.blank?
    return @color
  end

  def available_for_reservation?
    return false if self.user_number.blank? or self.locked_at or (self.expired_at and self.expired_at < Time.zone.today.beginning_of_day)
    true
  end

  def delete_reserves
    items = []
    if self.reserves.not_waiting
      self.reserves.not_waiting.each do |reserve|
        if reserve.item
          items << reserve.item
          Reserve.delete(reserve)
        end
      end
    end

    items.each do |item|
      item.cancel_retain!
      item.set_next_reservation if item.manifestation.next_reservation
    end
  end

  def current_basket
    Basket.where(:user_id => current_user.id, :basket_type => 1).first || Basket.create(:user_id => current_user.id, :basket_type => 1)
  end

  def self.set_query(query = nil, birth = nil, add = nil)
    date_of_birth = nil
    # query
    query = query.to_s
    query = query.gsub("-", "") if query
    query = "*#{query}*" if query.size == 1

    # birth date
    if birth.present?
      logger.debug "birth=#{birth}"
      birth_date_from = Date.expand_date(birth)
      birth_date_to = Date.expand_date(birth, mode: 'to')
      logger.debug "birth_date_from=#{birth_date_from} birth_date_to=#{birth_date_to}"
      unless birth_date_from
        message = I18n.t('user.birth_date_invalid')
      else
        begin
          #date_of_birth = Time.zone.parse(birth_date_from).beginning_of_day.utc.iso8601
          date_of_birth = birth_date_from.utc.iso8601
        rescue
          message = I18n.t('user.birth_date_invalid')
        end
        #date_of_birth_end = Time.zone.parse(birth_date_to).end_of_day.utc.iso8601 rescue nil
        date_of_birth_end = birth_date_to.utc.iso8601 rescue nil
      end
      logger.debug "from=#{date_of_birth} to=#{date_of_birth_end}"
    end
    # address
    address = add

    query = "#{query} date_of_birth_d:[#{date_of_birth} TO #{date_of_birth_end}]" unless date_of_birth.blank?
    query = "#{query} address_text:#{address}" unless address.blank?

    logger.info "query #{query}"
    logger.info message

    return query, message
  end

  def self.set_sort(sort_by, order)
    sort = { :sort_by => set_sort_by(sort_by), :order => set_order(order) }
  end

  def self.set_sort_by(sort_by)
    sort = nil
    case sort_by
    when 'username'
      sort = 'username'
    when 'telephone_number_1'
      sort = 'telephone_number'
    when 'full_name'
      sort = 'full_name'
    when 'user_number'
      sort = 'user_number'
    when 'library'
      sort = 'library'
    else
      sort = 'created_at'
    end
  end

  def self.set_order(order)
    sort = nil
    case order
    when 'asc'
      sort = 'asc'
    else 'desc'
      sort = 'desc'
    end
  end

  def self.output_userlist_pdf(users)
    report = EnjuTrunk.new_report('userlist.tlf')

    # set page_num
    report.events.on :page_create do |e|
      e.page.item(:page).value(e.page.no)
    end
    report.events.on :generate do |e|
      e.pages.each do |page|
        page.item(:list_title).value(I18n.t('page.listing', :model => I18n.t('activerecord.models.user')))
        page.item(:total).value(e.report.page_count)
      end
    end

    report.start_new_page do |page|
      page.item(:date).value(Time.now)
      users.each do |user|
        page.list(:list).add_row do |row|
          row.item(:full_name).value(user.try(:agent).try(:full_name))
#          row.item(:username).value(user.username)
          row.item(:department).value(user.try(:department).try(:display_name))
          row.item(:user_number).value(user.user_number)
          row.item(:tel1).value(user.try(:agent).try(:telephone_number_1)) if user.try(:agent).try(:telephone_number_1)
          row.item(:e_mail).value(user.try(:agent).try(:email)) if user.try(:agent).try(:email)
          row.item(:created_at).value(user.created_at)
          if user.active_for_authentication?
            row.item(:user_status).value(user.try(:user_status).try(:display_name))
          else
            row.item(:user_status).value(user.try(:user_status).try(:display_name) + "#{I18n.t('activerecord.attributes.user.locked_no')}")
          end
          row.item(:unable).value(I18n.t('activerecord.attributes.user.unable_yes')) unless user.unable
          row.item(:unable).value(I18n.t('activerecord.attributes.user.unable_no')) if user.unable
        end
      end
    end
    return report
  end

  def self.output_userlist_tsv(users)
    columns = [
      [:full_name, 'activerecord.attributes.agent.full_name'],
      [:full_name_transcription, 'activerecord.attributes.agent.full_name_transcription'],
      [:full_name_alternative, 'activerecord.attributes.agent.full_name_alternative'],
      [:first_name, 'activerecord.attributes.agent.first_name'],
      [:first_name_transcription, 'activerecord.attributes.agent.first_name_transcription'],
      [:last_name, 'activerecord.attributes.agent.last_name'],
      [:last_name_transcription, 'activerecord.attributes.agent.last_name_transcription'],
      ['username', 'activerecord.attributes.user.username'],
      ['user_number', 'activerecord.attributes.user.user_number'],
      [:library, 'activerecord.attributes.user.library'],
      [:user_group, 'activerecord.attributes.user.user_group'],
      [:department, 'activerecord.attributes.user.department'],
      [:expired_at, 'activerecord.attributes.user.expired_at'],
      [:status, 'activerecord.attributes.user.user_status'],
      [:unable, 'activerecord.attributes.user.unable'],
      [:agent_type, 'activerecord.models.agent_type'],
      [:email, 'activerecord.attributes.agent.email'],
      [:url, 'activerecord.attributes.agent.url'],
      [:other_designation, 'activerecord.attributes.agent.other_designation'],
      [:place, 'activerecord.attributes.agent.place'],
      [:language, 'activerecord.models.language'],
      [:country, 'activerecord.models.country'],
      [:zip_code_1, 'activerecord.attributes.agent.zip_code_1'],
      [:address_1, 'activerecord.attributes.agent.address_1'],
      [:telephone_number_1, 'activerecord.attributes.agent.telephone_number_1'],
      [:telephone_number_1_type_id, 'activerecord.attributes.agent.telephone_number_1_type'],
      [:extelephone_number_1, 'activerecord.attributes.agent.extelephone_number_1'],
      [:extelephone_number_1_type_id, 'activerecord.attributes.agent.extelephone_number_1_type'],
      [:fax_number_1, 'activerecord.attributes.agent.fax_number_1'],
      [:fax_number_1_type_id, 'activerecord.attributes.agent.fax_number_1_type'],
      [:address_1_note, 'activerecord.attributes.agent.address_1_note'],
      [:zip_code_2, 'activerecord.attributes.agent.zip_code_2'],
      [:address_2, 'activerecord.attributes.agent.address_2'],
      [:telephone_number_2, 'activerecord.attributes.agent.telephone_number_2'],
      [:telephone_number_2_type_id, 'activerecord.attributes.agent.telephone_number_2_type'],
      [:extelephone_number_2, 'activerecord.attributes.agent.extelephone_number_2'],
      [:extelephone_number_2_type_id, 'activerecord.attributes.agent.extelephone_number_2_type'],
      [:fax_number_2, 'activerecord.attributes.agent.fax_number_2'],
      [:fax_number_2_type_id, 'activerecord.attributes.agent.fax_number_2_type'],
      [:address_2_note, 'activerecord.attributes.agent.address_2_note'],
      [:birth_date, 'activerecord.attributes.agent.date_of_birth'],
      [:death_date, 'activerecord.attributes.agent.date_of_death'],
      [:note, 'activerecord.attributes.agent.note'],
      [:note_update_at, 'activerecord.attributes.agent.note_update_at'],
      [:note_update_by, 'activerecord.attributes.agent.note_update_by'],
      [:note_update_library, 'activerecord.attributes.agent.note_update_library'],
      [:agent_identifier, 'agent.agent_identifier'],
      [:role, 'activerecord.models.role'],
      [:created_at, 'page.created_at'],
      [:updated_at, 'page.updated_at'],
      [:del_flg, 'resource_import_textfile.excel.book.del_flg']
    ]

    data = String.new

    data << "\xEF\xBB\xBF".force_encoding("UTF-8") #+ "\n"
    # title column
    row = []
    columns.each do |column|
      row << I18n.t(column[1])
    end
    if SystemConfiguration.get("set_output_format_type") == false
      data << '"'+row.join("\",\"")+"\"\n"
    else
      data << '"'+row.join("\"\t\"")+"\"\n"
    end
    users.each do |user|
      row = []
      columns.each do |column|
        case column[0]
        when :full_name
          row << user.try(:agent).try(:full_name)
        when :full_name_transcription
          row << user.try(:agent).try(:full_name_transcription)
        when :full_name_alternative
          row << user.try(:agent).try(:full_name_alternative)
        when :first_name
          row << user.try(:agent).try(:first_name)
        when :first_name_transcription
          row << user.try(:agent).try(:first_name_transcription)
        when :last_name
          row << user.try(:agent).try(:last_name)
        when :last_name_transcription
          row << user.try(:agent).try(:last_name_transcription)
        when :library
          row << user.try(:library).try(:name)
        when :user_group
          row << user.try(:user_group).try(:display_name)
        when :department
          row << user.try(:department).try(:display_name)
        when :expired_at
          row << user.expired_at
        when :status
          row << user.try(:user_status).try(:display_name)
        when :unable
          row << user.try(:unable)
        when :agent_type
          row << user.try(:agent).try(:agent_type_id)
        when :email
          row << user.try(:agent).try(:email)
        when :url
          row << user.try(:agent).try(:url)
        #TODO 現在は表示されていない
        when :other_designation
          row << user.try(:agent).try(:other_designation)
        #TODO 現在は表示されていない
        when :place
          row << user.try(:agent).try(:place)
        when :language
          row << user.try(:agent).try(:language).try(:display_name).try(:localize)
        when :country
          row << user.try(:agent).try(:country).try(:display_name).try(:localize)
        when :zip_code_1
          row << user.try(:agent).try(:zip_code_1)
        when :address_1
          row << user.try(:agent).try(:address_1)
        when :telephone_number_1
          row << user.try(:agent).try(:telephone_number_1)
        when :telephone_number_1_type_id
          row << user.try(:agent).try(:telephone_number_1_type_id)
        when :extelephone_number_1
          row << user.try(:agent).try(:extelephone_number_1)
        when :extelephone_number_1_type_id
          row << user.try(:agent).try(:extelephone_number_1_type_id)
        when :fax_number_1
          row << user.try(:agent).try(:fax_number_1)
        when :fax_number_1_type_id
          row << user.try(:agent).try(:fax_number_1_type_id)
=begin
        when :telephone_number_1
          telephone_number_1 = user.try(:agent).try(:telephone_number_1)
          telephone_number_1 += ' (' + I18n.t(i18n_telephone_type(user.try(:agent).try(:telephone_number_1_type_id)).try(:strip_tags)) +')' unless user.try(:agent).try(:telephone_number_1).blank?
          row << telephone_number_1
        when :extelephone_number_1
          extelephone_number_1 = user.try(:agent).try(:extelephone_number_1)
          extelephone_number_1 += ' (' + I18n.t(i18n_telephone_type(user.agent.extelephone_number_1_type_id).try(:strip_tags)) +')' unless user.try(:agent).try(:extelephone_number_1).blank?
          row << extelephone_number_1
        when :fax_number_1
          fax_number_1 = user.try(:agent).try(:fax_number_1)
          fax_number_1 += ' (' + I18n.t(i18n_telephone_type(user.agent.fax_number_1_type_id).try(:strip_tags)) +')' unless user.try(:agent).try(:fax_number_1).blank?
          row << fax_number_1
=end
        when :address_1_note
          row << user.try(:agent).try(:address_1_note )
        when :zip_code_2
          row << user.try(:agent).try(:zip_code_2)
        when :address_2
          row << user.try(:agent).try(:address_2)
        when :telephone_number_2
          row << user.try(:agent).try(:telephone_number_2)
        when :telephone_number_2_type_id
          row << user.try(:agent).try(:telephone_number_2_type_id)
        when :extelephone_number_2
          row << user.try(:agent).try(:extelephone_number_2)
        when :extelephone_number_2_type_id
          row << user.try(:agent).try(:extelephone_number_2_type_id)
        when :fax_number_2
          row << user.try(:agent).try(:fax_number_2)
        when :fax_number_2_type_id
          row << user.try(:agent).try(:fax_number_2_type_id)
=begin
        when :telephone_number_2
          telephone_number_2 = user.try(:agent).try(:telephone_number_2)
          telephone_number_2 += ' (' + I18n.t(i18n_telephone_type(user.agent.telephone_number_2_type_id).try(:strip_tags)) +')' unless user.try(:agent).try(:telephone_number_2).blank?
          row << telephone_number_2
        when :extelephone_number_2
          extelephone_number_2 = user.try(:agent).try(:extelephone_number_2)
          extelephone_number_2 += ' (' + I18n.t(i18n_telephone_type(user.agent.extelephone_number_2_type_id).try(:strip_tags)) +')' unless user.try(:agent).try(:extelephone_number_2).blank?
          row << extelephone_number_2
        when :fax_number_2
          fax_number_2 = user.try(:agent).try(:fax_number_2)
          fax_number_2 += ' (' + I18n.t(i18n_telephone_type(user.agent.fax_number_2_type_id).try(:strip_tags)) +')' unless user.try(:agent).try(:fax_number_2).blank?
          row << fax_number_2
=end
        when :address_2_note
          row << user.try(:agent).try(:address_2_note)
        when :birth_date
          row << user.try(:agent).try(:birth_date)
        when :death_date
          row << user.try(:agent).try(:death_date)
        when :note
          row << user.try(:agent).try(:note)
        when :note_update_at
          row << user.agent.note_update_at.strftime("%Y/%m/%d %H:%M:%S") if user.try(:agent).try(:note_update_at)
        when :note_update_by
          row << user.try(:agent).try(:note_update_by) if user.try(:agent).try(:note_update_by)
        when :note_update_library
          row << user.try(:agent).try(:note_update_library) if user.try(:agent).try(:note_update_library)
        when :agent_identifier
          row << user.try(:agent).try(:agent_identifier)
        when :role
          row << user.try(:user_has_role).try(:role_id)
        when :created_at
          row << user.created_at.strftime("%Y/%m/%d %H:%M:%S")
        when :updated_at
          row << user.updated_at.strftime("%Y/%m/%d %H:%M:%S")
        when :del_flg
          row << nil
        else
          row << get_object_method(user, column[0].split('.')).to_s.gsub(/\r\n|\r|\n/," ").gsub(/\"/,"\"\"")
        end
      end
      if SystemConfiguration.get("set_output_format_type") == false
        data << '"'+row.join("\",\"")+"\"\n"
      else
        data << '"'+row.join("\"\t\"")+"\"\n"
      end
    end
    return data
  end

  alias_method :original_update_with_password, :update_with_password
  def update_with_password(params = {}, *options)
    User.transaction do
      self.own_password = true
      saved = self.original_update_with_password(params, *options)
      self.own_password = false unless saved
      return saved
    end
  end

  def self.get_user(identifier)
    user = User.where(:user_number => identifier).first
    user = User.where(:username => identifier).first unless user
    unless user
      agent = Agent.where(:agent_identifier => identifier).first
      user = agent.user if agent
    end
    return user
  end

  private
  def self.get_object_method(obj,array)
    _obj = obj.send(array.shift)
    return get_object_method(_obj, array) if array.present?
    return _obj
  end
end

# == Schema Information
#
# Table name: users
#
#  id                       :integer         not null, primary key
#  email                    :string(255)     default("")
#  encrypted_password       :string(255)
#  confirmation_token       :string(255)
#  confirmed_at             :datetime
#  confirmation_sent_at     :datetime
#  reset_password_token     :string(255)
#  reset_password_sent_at   :datetime
#  remember_token           :string(255)
#  remember_created_at      :datetime
#  sign_in_count            :integer         default(0)
#  current_sign_in_at       :datetime
#  last_sign_in_at          :datetime
#  current_sign_in_ip       :string(255)
#  last_sign_in_ip          :string(255)
#  failed_attempts          :integer         default(0)
#  unlock_token             :string(255)
#  locked_at                :datetime
#  authentication_token     :string(255)
#  password_salt            :string(255)
#  created_at               :datetime
#  updated_at               :datetime
#  deleted_at               :datetime
#  username                 :string(255)
#  library_id               :integer         default(1), not null
#  user_group_id            :integer         default(1), not null
#  reserves_count           :integer         default(0), not null
#  expired_at               :datetime
#  libraries_count          :integer         default(0), not null
#  bookmarks_count          :integer         default(0), not null
#  checkouts_count          :integer         default(0), not null
#  checkout_icalendar_token :string(255)
#  questions_count          :integer         default(0), not null
#  answers_count            :integer         default(0), not null
#  answer_feed_token        :string(255)
#  due_date_reminder_days   :integer         default(1), not null
#  note                     :text
#  share_bookmarks          :boolean         default(FALSE), not null
#  save_search_history      :boolean         default(FALSE), not null
#  save_checkout_history    :boolean         default(FALSE), not null
#  required_role_id         :integer         default(1), not null
#  keyword_list             :text
#  user_number              :string(255)
#  state                    :string(255)
#  required_score           :integer         default(0), not null
#  locale                   :string(255)
#  openid_identifier        :string(255)
#  oauth_token              :string(255)
#  oauth_secret             :string(255)
#  enju_access_key          :string(255)
#

