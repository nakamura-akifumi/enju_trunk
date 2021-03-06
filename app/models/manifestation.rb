# -*- encoding: utf-8 -*-
require 'csv'
engines = []
engines << EnjuTrunkFrbr::Engine        if defined? EnjuTrunkFrbr
engines << EnjuTrunkCirculation::Engine if defined? EnjuTrunkCirculation
engines << EnjuTrunkOrder::Engine       if defined? EnjuTrunkOrder
engines.map{ |engine| require engine.root.join('app', 'models','manifestation') if defined?(engine) }

require 'enju_trunk/output_columns'
class Manifestation < ActiveRecord::Base
  extend ActiveRecordExtension
  self.extend ItemsHelper
  include EnjuNdl::NdlSearch
  include EnjuTrunk::OutputColumns

  has_many :creators, :through => :creates, :source => :agent, :order => :position
  has_many :contributors, :through => :realizes, :source => :agent, :order => :position
  has_many :publishers, :through => :produces, :source => :agent, :order => :position
  has_many :work_has_subjects, :foreign_key => 'work_id', :dependent => :destroy
  has_many :subjects, :through => :work_has_subjects, :order => :position
  has_many :reserves, :foreign_key => :manifestation_id, :order => :position
  has_many :picture_files, :as => :picture_attachable, :dependent => :destroy
  has_many :work_has_languages, :foreign_key => 'work_id', :dependent => :destroy, :order => :position
  has_many :languages, :through => :work_has_languages, :order => :position
  has_many :manifestation_has_classifications, :order => :position
  has_many :classifications, :through => :manifestation_has_classifications, :order => :position
  belongs_to :carrier_type
  belongs_to :sub_carrier_type
  belongs_to :manifestation_type
  has_one :series_has_manifestation, :dependent => :destroy
  has_one :series_statement, :through => :series_has_manifestation
  belongs_to :frequency
  belongs_to :required_role, :class_name => 'Role', :foreign_key => 'required_role_id', :validate => true
  has_one :resource_import_result
  has_many :purchase_requests
  has_many :table_of_contents
  has_many :checked_manifestations
  has_many :identifiers, :dependent => :destroy
  has_many :manifestation_exinfos, :dependent => :destroy
  has_many :manifestation_extexts, :dependent => :destroy
  has_one :approval

  belongs_to :manifestation_content_type, :class_name => 'ContentType', :foreign_key => 'content_type_id'
  belongs_to :country_of_publication, :class_name => 'Country', :foreign_key => 'country_of_publication_id'

  has_many :work_has_titles, :foreign_key => 'work_id', :order => 'position', :dependent => :destroy
  has_many :manifestation_titles, :through => :work_has_titles
  accepts_nested_attributes_for :work_has_titles, :reject_if => lambda{|attributes| attributes[:title].blank?}, :allow_destroy => true
  accepts_nested_attributes_for :identifiers, :reject_if => lambda{|attributes| attributes[:body].blank?}, :allow_destroy => true
  accepts_nested_attributes_for :work_has_languages, :reject_if => lambda{ |attributes| attributes[:language_id].blank? }, :allow_destroy => true
  accepts_nested_attributes_for :work_has_subjects, :allow_destroy => true
  
  belongs_to :catalog
  accepts_nested_attributes_for :items

  scope :without_master, where(:periodical_master => false)
  SELECT2_OBJ = Struct.new(:id, :name, :display_name)
  JPN_OR_FOREIGN = [ 
    SELECT2_OBJ.new(0, I18n.t('jpn_or_foreign.jpn'), I18n.t('jpn_or_foreign.jpn')), 
    SELECT2_OBJ.new(1, I18n.t('jpn_or_foreign.foreign'), I18n.t('jpn_or_foreign.foreign')) 
  ]

  SUNSPOT_EAGER_LOADING = {
    include: [
      :creators, :publishers, :contributors, :carrier_type,
      :manifestation_type, :languages, :series_statement,
      :original_manifestations,
      :identifiers, 
      items: :shelf,
      subjects: {classifications: :category},
    ]
  }

  SORT_PLANS = {
    1 => { "sort" => 'page.sort_desc', "sort_by" => 'activerecord.attributes.manifestation.date_of_publication' },
    2 => { "sort" => 'page.sort_asc', "sort_by" => 'activerecord.attributes.manifestation.date_of_publication' },
    3 => { "sort" => 'page.sort_desc', "sort_by" => 'manifestation.date_of_acquisition' },
    4 => { "sort" => 'page.sort_asc', "sort_by" => 'manifestation.date_of_acquisition' },
    5 => { "sort" => 'page.sort_desc', "sort_by" => 'activerecord.attributes.manifestation.original_title' },
    6 => { "sort" => 'page.sort_asc', "sort_by" => 'activerecord.attributes.manifestation.original_title' },
    7 => { "sort" => 'page.sort_desc', "sort_by" => 'agent.creator' },
    8 => { "sort" => 'page.sort_asc', "sort_by" => 'agent.creator' },
    9 => { "sort" => 'page.sort_desc', "sort_by" => 'activerecord.models.carrier_type' },
    10 => { "sort" => 'page.sort_asc', "sort_by" => 'activerecord.models.carrier_type' }
  }

  ISBN_IDENTIFIER_TYPE_IDS = [1,2,6]

  searchable(SUNSPOT_EAGER_LOADING) do
    text :extexts do
      if root_of_series? # 雑誌の場合
        series_manifestations_manifestation_extexts_values
      else
        manifestation_extexts.map(&:value).compact if try(:manifestation_extexts).size > 0
      end
    end
    text :fulltext, :contributor, :article_title, :series_title, :exinfo_1, :exinfo_6
    text :title, :default_boost => 2 do
      titles
    end
    text :series_title do
      series_statement.try(:original_title)
    end
    text :spellcheck do
      titles
    end
    text :note do
      if root_of_series? # 雑誌の場合
        series_manifestations.
          map(&:note).compact
      else
        note
      end
    end
    text :description do
      if root_of_series? # 雑誌の場合
        series_manifestations.
          map(&:description).compact
      else
        description
      end
    end
    text :creator do
      if root_of_series? # 雑誌の場合
        # 同じ雑誌の全号の著者のリストを取得する
        Agent.joins(:works).joins(:works => :series_statement).
          where(['series_statements.id = ?', self.series_statement.id]).
          collect(&:name).compact
      else
        creator
      end
    end
    text :publisher do
      if root_of_series? # 雑誌の場合
        # 同じ雑誌の全号の出版社のリストを取得する
        Agent.joins(:manifestations => :series_statement).
          where(['series_statements.id = ?', self.series_statement.id]).
          collect(&:name).compact
      else
        publisher
      end
    end
    text :subject do
      subjects.collect(&:term) + subjects.collect(&:term_transcription)
    end
    string :title, :multiple => true
    # text フィールドだと区切りのない文字列の index が上手く作成
    #できなかったので。 downcase することにした。
    #他の string 項目も同様の問題があるので、必要な項目は同様の処置が必要。
    string :connect_title do
      title.join('').gsub(/\s/, '').downcase
    end
    string :connect_creator do
      creator.join('').gsub(/\s/, '').downcase
    end
    string :connect_publisher do
      publisher.join('').gsub(/\s/, '').downcase
    end
    string :isbn, :multiple => true do
      if root_of_series? # 雑誌の場合
        # 同じ雑誌の全号のISBNのリストを取得する
        series_manifestations.
          map {|manifestation| [manifestation.isbn, manifestation.isbn10, manifestation.wrong_isbn, normalize_identifier_isbn] }.flatten.compact
      else
        [isbn, isbn10, wrong_isbn, normalize_identifier_isbn].flatten.compact
      end
    end
    string :issn, :multiple => true do
      if root_of_series? # 雑誌の場合
        # 同じ雑誌の全号のISSNのリストを取得する
        issns = []
        issns << series_statement.try(:issn)
        issns << series_manifestations.
          map(&:issn).compact
        issns.flatten
      else
        [issn, series_statement.try(:issn)]
      end
    end
    string :marc_number
    string :lccn
    string :nbn
    string :subject, :multiple => true do
      subjects.collect(&:term) + subjects.collect(&:term_transcription)
    end
    string :classification, :multiple => true do
      # "分類種類名-分類記号"の配列で登録する
      classifications.map do |c|
        "#{c.classification_type.name}-#{c.classification_identifier}"
      end
    end
    string :carrier_type do
      carrier_type.name
    end
    string :manifestation_type_position do
      manifestation_type.try(:position)
    end
    string :manifestation_type, :multiple => true do
      manifestation_type.try(:name)
      #if series_statement.try(:id) 
      #  1
      #else
      #  0
      #end
    end
    string :library, :multiple => true do
      items.map{|i| item_library_name(i)}
    end
    string :language, :multiple => true do
      languages.map{|language| language.name}
    end
    string :ndc, :multiple => true do
      if root_of_series? # 雑誌の場合
        series_manifestations.map.map(&:ndc).compact
      else
        ndc
      end
    end
    string :item_identifier, :multiple => true do
      if root_of_series? # 雑誌の場合
        # 同じ雑誌の全号の蔵書の蔵書情報IDのリストを取得する
        series_manifestations_items.
          collect(&:item_identifier).compact
      else
        items.collect(&:item_identifier)
      end
    end
    string :identifier, :multiple => true do
      if series_statement && series_statement.root_manifestation
        [identifier, series_statement.root_manifestation.identifier]
      else
        [identifier]  
      end
    end
    string :call_number, :multiple => true do
      items.collect{|i| i.call_number}
    end
    string :removed_at, :multiple => true do
      if root_of_series? # 雑誌の場合
        # 同じ雑誌の全号の除籍日のリストを取得する
        series_manifestations_items.
          collect(&:removed_at).compact
      else
        items.collect(&:removed_at)
      end
    end
    boolean :has_removed do
      has_removed?
    end
    boolean :is_article do
      self.article?
    end
    string :shelf, :multiple => true do
      items.collect{|i| "#{item_library_name(i)}_#{i.shelf.name}"}
    end
    integer :item_shelf_id, :multiple => true do
      items.collect{|i| i.shelf_id}
    end
    integer :item_required_id, :multiple => true do
      items.collect{|i| i.required_role_id}
    end
    string :user, :multiple => true do
    end
    time :created_at
    time :updated_at
    time :deleted_at
    time :date_of_publication
    string :pub_date, :multiple => true do
      if root_of_series? # 雑誌の場合
        # 同じ雑誌の全号の出版日のリストを取得する
        series_manifestations.
          map(&:date_of_publication).compact
      else
        date_of_publication
      end
    end
    integer :creator_ids, :multiple => true
    integer :contributor_ids, :multiple => true
    integer :publisher_ids, :multiple => true
    integer :item_ids, :multiple => true
    integer :original_manifestation_ids, :multiple => true
    integer :subject_ids, :multiple => true
    integer :required_role_id
    integer :height
    integer :width
    integer :depth
    integer :edition, :multiple => true
    integer :volume_number, :multiple => true
    integer :issue_number, :multiple => true
    long :serial_number, :multiple => true
    string :edition_display_value, :multiple => true do
      if root_of_series? # 雑誌の場合
        # 同じ雑誌の全号の出版日のリストを取得する
        series_manifestations.
          map(&:edition_display_value).compact
      else
        edition_display_value
      end
    end
    string :volume_number_string, :multiple => true do
      if root_of_series? # 雑誌の場合
        # 同じ雑誌の全号の出版日のリストを取得する
        series_manifestations.
          map(&:volume_number_string).compact
      else
        volume_number_string 
      end
    end
    string :issue_number_string, :multiple => true do
      if root_of_series? # 雑誌の場合
        # 同じ雑誌の全号の出版日のリストを取得する
        series_manifestations.
          map(&:issue_number_string).compact
      else
        issue_number_string 
      end
    end
    string :serial_number_string, :multiple => true do
      if root_of_series? # 雑誌の場合
        # 同じ雑誌の全号の出版日のリストを取得する
        series_manifestations.
          map(&:serial_number_string).compact
      else
        serial_number_string 
      end
    end
    string :start_page
    string :end_page
    integer :number_of_pages
    string :number_of_pages, :multiple => true do
      if root_of_series? # 雑誌の場合
        # 同じ雑誌の全号のページ数のリストを取得する
        series_manifestations.
          map(&:number_of_pages).compact
      else
        number_of_pages
      end
    end
    float :price
    string :price_string
    boolean :reservable do
      self.reservable?
    end
    boolean :in_process do
      self.in_process?
    end
    integer :series_statement_id do
      series_has_manifestation.try(:series_statement_id)
    end
    boolean :repository_content
    # for OpenURL
    text :aulast do
      creators.map{|creator| creator.last_name}
    end
    text :aufirst do
      creators.map{|creator| creator.first_name}
    end
    # OTC start
    string :creator, :multiple => true do
      creator.map{|au| au.gsub(' ', '')}
    end
    string :contributor, :multiple => true do
      contributor.map{|au| au.gsub(' ', '')}
    end
    string :publisher, :multiple => true do
      publisher.map{|au| au.gsub(' ', '')}
    end
    string :produces do
      NKF.nkf('-w --katakana', publishers[0].full_name_transcription) if publishers[0] and publishers[0].full_name_transcription
    end
    string :author do
      NKF.nkf('-w --katakana', creators[0].full_name_transcription) if creators[0] and creators[0].full_name_transcription
    end
    text :au do
      creator
    end
    text :atitle do
      title if series_statement.try(:periodical)
    end
    text :btitle do
      title unless series_statement.try(:periodical)
    end
    text :jtitle do
      if root_of_series? # 雑誌の場合
        series_statement.titles
      else                  # 雑誌以外（雑誌の記事も含む）
        original_manifestations.map{|m| m.title}.flatten
      end
    end
    text :isbn do  # 前方一致検索のためtext指定を追加
      if root_of_series? # 雑誌の場合
        # 同じ雑誌の全号のISBNのリストを取得する
        series_manifestations.
          map {|manifestation| [manifestation.isbn, manifestation.isbn10, manifestation.wrong_isbn] }.flatten.compact
      else
        [isbn, isbn10, wrong_isbn]
      end
    end
    text :issn do  # 前方一致検索のためtext指定を追加
      if root_of_series? # 雑誌の場合
        # 同じ雑誌の全号のISSNのリストを取得する
        issns = []
        issns << series_statement.try(:issn)
        issns << series_manifestations.
          map(&:issn).compact
        issns.flatten
      else
        [issn, series_statement.try(:issn)]
      end
    end
    string :other_identifier, :multiple => true do
      identifiers.map {|identifier|
        if Manifestation::ISBN_IDENTIFIER_TYPE_IDS.include?(identifier.identifier_type.id)
          "#{identifier.identifier_type.name}-#{Lisbn.new(identifier.body).isbn13 || identifier.body}"
        else
          "#{identifier.identifier_type.name}-#{identifier.body}"
        end
      }
    end
    string :sort_title
    string :original_title
    boolean :periodical do
      serial?
    end
    boolean :periodical_master
    time :acquired_at
    # 受入最古の所蔵情報を取得するためのSQLを構成する
    # (string :acquired_atでのみ使用する)
    item1 = Item.arel_table
    item2 = item1.alias

    mani1 = Manifestation.arel_table
    mani2 = mani1.alias

    shas1 = SeriesHasManifestation.arel_table
    shas2 = shas1.alias

    acquired_at_subq = item1.
      from(item2).
      project(
        shas2[:manifestation_id].as('grp_manifestation_id'),
        item2[:acquired_at].minimum.as('grp_min_acquired_at')
      ).
      join(mani2).on(
        mani2[:id].eq(item2[:manifestation_id]).
        and(item2[:acquired_at].not_eq(nil))
      ).
      join(shas2).on(
        shas2[:manifestation_id].eq(mani2[:id]).
        and(shas2[:series_statement_id].eq(Arel.sql('?')))
      ).
      group(shas2[:manifestation_id]).
      as('t')

    acquired_at_q = item1.
      project(item1['*']).
      join(mani1).on(
        mani1[:id].eq(item1[:manifestation_id]).
        and(item1[:acquired_at].not_eq(nil))
      ).
      join(shas1).on(
        shas1[:manifestation_id].eq(mani1[:id]).
        and(shas1[:series_statement_id].eq(Arel.sql('?')))
      ).
      join(acquired_at_subq).on(
        item1[:acquired_at].eq(acquired_at_subq['grp_min_acquired_at']).
        and(mani1[:id].eq(acquired_at_subq['grp_manifestation_id']))
      )
    string :acquired_at, :multiple => true do
      if root_of_series? # 雑誌の場合
        # 同じ雑誌の全号について、それぞれの最古の受入日のリストを取得する
        Item.find_by_sql([acquired_at_q.to_sql, series_statement.id, series_statement.id]).map(&:acquired_at)
      else
        acquired_at
      end
    end
    boolean :except_recent
    boolean :item_non_searchable do
      item_non_searchable?
    end
    integer :item_shelf_id, :multiple => true do
      items.collect(&:shelf_id).compact
    end
    string :has_available_items, :multiple => true do
      availables = []
      Role.all.collect(&:id).each do |required_role_id|
        availables << "#{required_role_id}_has_available_items" if has_available_items?(required_role_id)
      end
      availables
    end
    boolean :hide do
      # 定期刊行物でないroot_manifestationは隠す
      root_of_series? and periodical == false 
    end
    string :exinfo_1
    string :exinfo_2
    string :exinfo_3
    string :exinfo_4
    string :exinfo_5
    string :exinfo_6
    string :exinfo_7
    string :exinfo_8
    string :exinfo_9
    string :exinfo_10
    text :extext_1
    text :extext_2
    text :extext_3
    text :extext_4
    text :extext_5
    integer :bookbinder_id, :multiple => true do
      items.collect(&:bookbinder_id).compact
    end
    integer :id
    integer :missing_issue
    boolean :circulation_status_in_process do
      true if items.any? {|i| item_circulation_status_name(i) == 'In Process' }
    end
    boolean :circulation_status_in_factory do
      true if items.any? {|i| item_circulation_status_name(i) == 'In Factory' }
    end
    boolean :no_item do
      no_items?
    end

  end

  enju_manifestation_viewer
  #enju_amazon
  enju_oai
  #enju_calil_check
  #enju_cinii
  #has_ipaper_and_uses 'Paperclip'
  #enju_scribd
  has_paper_trail
  if Setting.uploaded_file.storage == :s3
    has_attached_file :attachment, :storage => :s3, :s3_credentials => "#{Rails.root.to_s}/config/s3.yml"
  else
    has_attached_file :attachment
  end

  validates_presence_of :carrier_type, :manifestation_type, :country_of_publication
  validates_associated :carrier_type, :languages, :manifestation_type, :country_of_publication
  validates_numericality_of :acceptance_number, :allow_nil => true
  validates_uniqueness_of :nacsis_identifier, :allow_nil => true
  validate :check_rank
  before_validation :set_language, :if => :during_import
  before_validation :uniq_options
  before_validation :set_manifestation_type, :set_country_of_publication
  before_save :set_series_statement

  after_save :index_series_statement
  after_destroy :index_series_statement

  attr_accessor :during_import, :creator, :contributor, :publisher, :subject, :manifestation_exinfo, :creator_transcription, :publisher_transcription, :contributor_transcription, :subject_transcription

  paginates_per 10

  if defined?(EnjuBookmark)
    has_many :bookmarks, :include => :tags, :dependent => :destroy, :foreign_key => :manifestation_id
    has_many :users, :through => :bookmarks

    searchable do
      string :tag, :multiple => true do
        if root_of_series? # 雑誌の場合
          Bookmark.joins(:manifestation => :series_statement).
            where(['series_statements.id = ?', self.series_statement.id]).
            includes(:tags).
            tag_counts.collect(&:name).compact
        else
          tags.collect(&:name)
        end
      end
      text :tag do
        if root_of_series? # 雑誌の場合
          Bookmark.joins(:manifestation => :series_statement).
            where(['series_statements.id = ?', self.series_statement.id]).
            includes(:tags).
            tag_counts.collect(&:name).compact
        else
          tags.collect(&:name)
        end
      end
    end

    def bookmarked?(user)
      return true if user.bookmarks.where(:url => url).first
      false
    end

    def tags
      if self.bookmarks.first
        self.bookmarks.tag_counts
      else
        []
      end
    end
  end

  def index
    reload if reload_for_index
    solr_index
  end

  def check_rank
    if self.manifestation_type && self.manifestation_type.is_article?
      if self.items and self.items.size > 0
        unless self.items.map{ |item| item.rank.to_i }.compact.include?(0)
          errors[:base] << I18n.t('manifestation.not_has_original')
        end
      end
    end
  end

  def set_language
    self.languages << Language.where(:name => "Japanese").first if self.languages.blank?
  end

  def set_manifestation_type
    self.manifestation_type = ManifestationType.where(:name => 'unknown').first if self.manifestation_type.nil?
  end

  def root_of_series?
    return true if series_statement.try(:root_manifestation_id) == self.id
    false
  end

  def serial?
    if series_statement.try(:periodical) and !periodical_master
      return true unless root_of_series?
    end
    false
  end

  def article?
    self.try(:manifestation_type).try(:is_article?)
  end

  def japanese_article?
    self.try(:manifestation_type).try(:is_japanese_article?)
  end

  def series?
    return true if series_statement
    return false
#    self.try(:manifestation_type).try(:is_series?)
  end

  # true for items.empty, dupricate with has_items? (:no_item index)
  def item_non_searchable?
    return false if periodical_master
    items.each do |i|
      return false unless i.non_searchable
      return false if item.try(:circulation_status).try(:name) != 'Removed'
    end
    return true
  end
  
  def no_items?
    unless root_of_series?
      return true if items.blank?
      return true if items.joins(:circulation_status).where(['circulation_statuses.name != ?', 'Removed']).blank?
    end
    return false
  end

  def has_available_items?(role_id = 1)
    unless article? or root_of_series?
      return false if items.empty?
      is = items.where(['required_role_id <= ?', role_id])
      if SystemConfiguration.get('manifestation.search.hide_not_for_loan')
        is = items.joins(:item_has_use_restriction).where('item_has_use_restrictions.use_restriction_id NOT IN (?)', UseRestriction.where(:name => 'Not For Loan').collect(&:id))
      end
      if unsearchables = CirculationStatus.where(:unsearchable => true).collect(&:id)
        is = is.where('circulation_status_id NOT IN (?)', CirculationStatus.where(:unsearchable => true).collect(&:id)) unless unsearchables.blank?
      end
      if SystemConfiguration.get('manifestation.manage_item_rank')
        is = is.where('rank < 2')
      end
      shelves = Shelf.where(['required_role_id <= ?', role_id])
      is = is.where('shelf_id in (?)', shelves.collect(&:id))
      is = is.joins(:circulation_status).where(['circulation_statuses.name != ?', 'Removed'])
      return false if is.blank?
    end
    return true
  end

  def has_removed?
    items.each do |i|
      return true if item_circulation_status_name(i) == "Removed" and !i.removed_at.nil?
    end
    false
  end

  def available_checkout_types(user)
    if user
      user.user_group.user_group_has_checkout_types.available_for_carrier_type(self.carrier_type)
    end
  end

  def new_serial?
    return false unless self.serial?    
    return true if self.series_statement.last_issues.include?(self)
#    unless self.serial_number.blank?
#      return true if self == self.series_statement.last_issue
#    else
#      return true if self == self.series_statement.last_issue_with_issue_number
#    end
  end

  def in_basket?(basket)
    basket.manifestations.include?(self)
  end

  def checkout_period(user)
    if available_checkout_types(user)
      available_checkout_types(user).collect(&:checkout_period).max || 0
    end
  end

  def reservation_expired_period(user)
    if available_checkout_types(user)
      available_checkout_types(user).collect(&:reservation_expired_period).max || 0
    end
  end

  def agents
    (creators + contributors + publishers).flatten
  end

  def reservable_with_item?(user = nil) #TODO reservabl? メソッドと重複？
    #TODO reserve.not_reserve_on_loan 変数名と実態が異なる
    # true で 貸出中のみ予約可能
    if SystemConfiguration.get("reserve.not_reserve_on_loan")
      return true if user.try(:has_role?, 'Librarian')
      items.each do |i|
        return false unless i.available_for_reserve_with_config?
      end
    end
    return true
  end

  def reservable?
    unless SystemConfiguration.get("reserves.able_for_not_item")
      return false if items.for_checkout.empty? 
    end
    return false if self.periodical_master?
    if SystemConfiguration.get("reserve.not_reserve_on_loan")
      items.each do |i|
        return false unless i.available_for_reserve_with_config?
      end
    end
    return true
  end

  def in_process?
    return true if items.map{ |i| i.shelf.try(:open_access)}.include?(9)
    false
  end

  def checkouts(start_date, end_date)
    Checkout.completed(start_date, end_date).where(:item_id => self.items.collect(&:id))
  end

  def creator(reload = false)
    creators(reload).collect(&:name).flatten
  end

  def contributor
    contributors.collect(&:name).flatten
  end

  def publisher(reload = false)
    publishers(reload).collect(&:name).flatten
  end

  # TODO: よりよい推薦方法
  def self.pickup(keyword = nil)
    return nil if self.cached_numdocs < 5
    manifestation = nil
    # TODO: ヒット件数が0件のキーワードがあるときに指摘する
    response = Manifestation.search(:include => [:creators, :contributors, :publishers, :subjects, :items]) do
      fulltext keyword if keyword
      order_by(:random)
      paginate :page => 1, :per_page => 1
    end
    manifestation = response.results.first
  end

  def extract_text
    return nil unless attachment.path
    # TODO: S3 support
    response = `curl "#{Sunspot.config.solr.url}/update/extract?&extractOnly=true&wt=ruby" --data-binary @#{attachment.path} -H "Content-type:text/html"`
    self.fulltext = eval(response)[""]
    save(:validate => false)
  end

  def created(agent)
    creates.where(:agent_id => agent.id).first
  end

  def realized(agent)
    realizes.where(:agent_id => agent.id).first
  end

  def produced(agent)
    produces.where(:agent_id => agent.id).first
  end

  def sort_title
    NKF.nkf('-w --katakana', title_transcription) if title_transcription
  end

  def questions(options = {})
    id = self.id
    options = {:page => 1, :per_page => Question.per_page}.merge(options)
    page = options[:page]
    per_page = options[:per_page]
    user = options[:user]
    Question.search do
      with(:manifestation_id).equal_to id
      any_of do
        unless user.try(:has_role?, 'Librarian')
          with(:shared).equal_to true
        #  with(:username).equal_to user.try(:username)
        end
      end
      paginate :page => page, :per_page => per_page
    end.results
  end

  def web_item
    items.where(:shelf_id => Shelf.web.id).first
  end

  def index_series_statement
    series_statement.try(:index)
  end

  def set_series_statement
    if self.series_statement_id
      series_statement = SeriesStatement.find(self.series_statement_id)
      self.series_statement = series_statement unless series_statement.blank?   
    end
  end 
 
  def uniq_options
    self.creators.uniq!
    self.contributors.uniq!
    self.publishers.uniq!
    self.subjects.uniq!
  end

  def set_country_of_publication
    self.country_of_publication = Country.where(:name => 'Japan').first || Country.find(1) if self.country_of_publication.blank?
  end

  def last_checkout_datetime
    Manifestation.find(:last, :include => [:items, :items => :checkouts], :conditions => {:manifestations => {:id => self.id}}, :order => 'items.created_at DESC').items.first.checkouts.first.created_at rescue nil
  end

  def reserve_count(type)
    sum = 0
    case type
    when nil
    when :all
      sum = Reserve.where(:manifestation_id=>self.id).count
    when :previous_term
      term = Term.previous_term
      if term
        sum = Reserve.where("manifestation_id = ? AND created_at >= ? AND created_at <= ?", self.id, term.start_at, term.end_at).count 
      end
    when :current_term
      term = Term.current_term
      if term
        sum = Reserve.where("manifestation_id = ? AND created_at >= ? AND created_at <= ?", self.id, term.start_at, term.end_at).count 
      end
    end
    return sum
  end

  def checkout_count(type)
    sum = 0
    case type
    when nil
    when :all
      self.items.all.each {|item| sum += Checkout.where(:item_id=>item.id).count} 
    when :previous_term
      term = Term.previous_term
      if term
        self.items.all.each {|item| sum += Checkout.where("item_id = ? AND created_at >= ? AND created_at <= ?", item.id, term.start_at, term.end_at).count }
      end
    when :current_term
      term = Term.current_term
      if term
        self.items.all.each {|item| sum += Checkout.where("item_id = ? AND created_at >= ? AND created_at <= ?", item.id, term.start_at, term.end_at).count } 
      end
    end
    return sum
  end

  def next_item_for_retain(lib)
    items = self.items_ordered_for_retain(lib)
    items.each do |item|
      return item if item.available_for_checkout? && item.circulation_status != CirculationStatus.find(:first, :conditions => ["name = ?", 'Available For Pickup'])
    end
    return nil
  end

  def items_ordered_for_retain(lib = nil)
    if lib.nil?
      items = self.items
    else
      items = self.items.for_retain_from_own(lib).concat(self.items.for_retain_from_others(lib)).flatten
    end
  end
 
  def ordered?
    self.purchase_requests.each do |p|
#      return true if p.state == "ordered"
      return true if ["ordered", "accepted", "pending"].include?(p.state)
    end
    return false
  end

  def add_subject(terms)
    terms.to_s.split(';').each do |s|
      s = s.to_s.exstrip_with_full_size_space
      subject = Subject.where(:term => s).first
      unless subject
        subject = Subject.create(:term => s, :subject_type_id => 1)
      end
      self.subjects << subject unless self.subjects.include?(subject)
    end
  end

  def vol_string
    if volume_number_string.present?
      if issue_number_string.present?
        "#{volume_number_string}[#{issue_number_string}]"
      else
        volume_number_string
      end
    elsif issue_number_string.present?
      "[#{issue_number_string}]"
    end
  end

  def normalize_identifier_isbn
    [] unless identifiers
    # normalize
    identifiers.where(identifier_type_id: ISBN_IDENTIFIER_TYPE_IDS).pluck(:body).map {|identifier| Lisbn.new(identifier).isbn13 || identifier }
  end

  # isbn > identifier.body の順で検索して最初の識別子をかえす。
  def call_isbn
    isbn_normalize = ""
    if isbn.present?
      isbn_normalize = Lisbn.new(isbn)
    else
      isbn_normalize = identifiers.where(identifier_type_id: ISBN_IDENTIFIER_TYPE_IDS).pluck(:body).first
      if isbn_normalize 
        isbn_normalize = Lisbn.new(isbn_normalize)
      end
    end
    if isbn_normalize
      isbn_normalize = isbn_normalize.isbn13
    end
    return isbn_normalize
  end

  def call_isbn?
    identifier = ""
    if isbn.present?
      identifier = isbn
    else 
      identifier = identifiers.where(identifier_type_id: ISBN_IDENTIFIER_TYPE_IDS).pluck(:body).first
    end
    return identifier.present?
  end

  def series_manifestations_manifestation_extexts_values
    values = []
    series_manifestations.each do |m|
      values << m.manifestation_extexts.map(&:value).compact if m.manifestation_extexts.size > 0
    end
    return values.flatten.compact
  end

  def self.build_search_for_manifestations_list(search, query, with_filter, without_filter)
    search.build do
      fulltext query unless query.blank?
      with_filter.each do |field, op, value|
        with(field).__send__(op, value)
      end
      without_filter.each do |field, op, value|
        without(field).__send__(op, value)
      end
    end

    search
  end

  # 要求された書式で書誌リストを生成する。
  # 生成結果を構造体で返す。構造体がoutputのとき:
  #
  #  output.result_type: 生成結果のタイプ
  #    :data: データそのもの
  #    :path: データを書き込んだファイルのパス名
  #    :delayed: 後で処理する
  #  output.data: 生成結果のデータ(result_typeが:dataのとき)
  #  output.path: 生成結果のパス名(result_typeが:pathのとき)
  #  output.job_name: 後で処理する際のジョブ名(result_typeが:delayedのとき)
  def self.generate_manifestation_list(solr_search, output_type, current_user, search_condition_summary, cols=[], threshold = nil, &block)
    solr_search.build {
      paginate :page => 1, :per_page => Manifestation.count
    }

    get_total = proc do
      series_statements_total =
        Manifestation.where(:id => solr_search.execute.raw_results.map(&:primary_key)).joins(:series_statement => :manifestations).count
    end
    
    get_all_ids = proc do
      solr_search.execute.raw_results.map(&:primary_key)
    end


    threshold ||= Setting.background_job.threshold.export rescue nil
    if threshold && threshold > 0 && get_total.call > threshold
      # 指定件数以上のときにはバックグラウンドジョブにする。
      user_file = UserFile.new(current_user)

      io, info = user_file.create(:manifestation_list_prepare, 'manifestation_list_prepare.tmp')
      begin
        Marshal.dump(get_all_ids.call, io)
      ensure
        io.close
      end

      job_name = GenerateManifestationListJob.generate_job_name
      Delayed::Job.enqueue GenerateManifestationListJob.new(job_name, info, output_type, current_user, search_condition_summary, cols)
      output = OpenStruct.new
      output.result_type = :delayed
      output.job_name = job_name
      block.call(output)
      return
    end
    manifestation_ids = get_all_ids.call
    generate_manifestation_list_internal(manifestation_ids, output_type, current_user, search_condition_summary, cols, &block)
  end

  # TODO: エクセル、TSV、PDF利用部分のメソッド名を修正すること	
  def self.generate_manifestation_list_internal(manifestation_ids, output_type, current_user, summary, cols, &block)
    output = OpenStruct.new
    output.result_type = output_type == :excelx ? :path : :data
    case output_type
    when :pdf 
      method = 'get_manifestation_list_pdf'
      type  = cols.first =~ /\Aarticle./ ? :article : :book
      result = output.__send__("#{output.result_type}=", 
        self.__send__(method, manifestation_ids, current_user, summary, type))
    when :request
      method = 'get_missing_list_pdf'
      result = output.__send__("#{output.result_type}=", 
        self.__send__(method, manifestation_ids, current_user))
    when :excelx, :tsv
      method = 'get_manifestation_list_excelx'
      if output_type == :tsv
        result = output.__send__("#{output.result_type}=",
          self.__send__('get_manifestation_list_tsv_csv', manifestation_ids, cols))
      else
        result = output.__send__("#{output.result_type}=", 
          self.__send__('get_manifestation_list_excelx', manifestation_ids, current_user, cols))
      end
    when :label
      method = 'get_label_list_tsv_csv'
      result = output.__send__("#{output.result_type}=", 
        self.__send__(method, manifestation_ids))
    end

    if output_type == :label
      if SystemConfiguration.get("set_output_format_type")
        output.filename = Setting.manifestation_label_list_print_tsv.filename
      else
        output.filename = Setting.manifestation_label_list_print_csv.filename
      end
    elsif output_type == :tsv
      if SystemConfiguration.get("set_output_format_type")
        output.filename = Setting.manifestation_list_print_tsv.filename
      else
        output.filename = Setting.manifestation_list_print_csv.filename
      end
    else
      filename_method = method.sub(/\Aget_(.*)(_[^_]+)\z/) { "#{$1}_print#{$2}" }
      output.filename = Setting.__send__(filename_method).filename
    end

    if output.result_type == :path
      output.path, output.data = result
    else
      output.data = /_pdf\z/ =~ method ? result.generate : result
    end
    block.call(output)
  end

  # 指定された内部キーについて、
  # 出力対象となる書誌のうちの最大件数を導出する。
  # たとえば'book.creator'ならば、
  # 対象書誌のそれぞれに関係付けられている
  # 著者の数が最も多いものを調べ、
  # その登録数を返す。
  #
  # ただし、最大数が0となった場合でも、
  # 出力フィールドを生成する(出力フィールド自体が
  # なくなってしまわないようにする)ために1を返す。
  def self.get_manifestation_list_separated_column_count(manifestation_ids, field_key, outer_cache = {})
    field, field_ext = field_key.split(/\./, 2)

    case field_ext
    when /\Aother_title(?:_type|_transcription|_alternativ|_transcription|_alternativee)?\z/
      table = :manifestation_titles
    when /\Aother_identifier(?:_type)?\z/
      table = :identifiers
    when /\Alanguage(?:_type)?\z/
      table = :languages
    when /\Acreator(?:_type|_transcription)?\z/
      table = :creators
    when /\Apublisher(?:_type|_transcription)?\z/
      table = :publishers
    when /\Acontributor(?:_type|_transcription)?\z/
      table = :contributors
    when /\Asubject(?:_transcription)?\z/
      table = :subjects
    when /\Atheme(?:_publish)?\z/
      # TODO:
      # book.theme、book.theme_publishについては
      # enju_trunk_theme側でカウント方法を提供できるようにする
      table = :themes
    when /\Amanifestation_extext/
      table = :manifestation_extexts
    when /\Amanifestation_exinfo/
      table = :manifestation_exinfos
    when /\Aitem_extext/
      table = :item_extexts
    when /\Aitem_exinfo/
      table = :item_exinfos
    else
      table = nil
    end

    case field
    when 'book'
      scope = scoped
    when 'root'
      scope = scoped.joins(:series_statement).
        where('series_statements.root_manifestation_id=manifestations.id')
    else
      table = nil
    end

    cache_key = [table, field]
    return outer_cache[cache_key] if outer_cache[cache_key]

    if table =~ /\Aitem/
      count = scope.joins(:items => table).group('items.id').
        select('count(items.id) column_count').
        order('column_count desc').first.
        try(:column_count).try(:to_i) || 1
    elsif table
      count = scope.joins(table).group('manifestations.id').
        select('count(manifestations.id) column_count').
        order('column_count desc').first.
        try(:column_count).try(:to_i) || 1
    else
      count = 1
    end

    outer_cache[cache_key] = count
  end

  def self.get_manifestation_list_header_row(column_spec, sheet_name)
    row = []
    column_spec[sheet_name].each do |field, field_ext, sep_flg, ccount|
      field_key = "#{field}.#{field_ext}"
      if sep_flg
        1.upto(ccount) do |n|
          row << ResourceImport::Sheet.suffixed_field_name(field_key, n)
        end
      else
        row << ResourceImport::Sheet.field_name(field_key)
      end
    end
    row
  end

  def self.get_manifestation_list_excelx(manifestation_ids, current_user, selected_column = [])
    user_file = UserFile.new(current_user)
    excel_filepath, excel_fileinfo = user_file.create(:manifestation_list, Setting.manifestation_list_print_excelx.filename)

    begin
      require 'axlsx_hack'
      ws_cls = Axlsx::AppendOnlyWorksheet
    rescue LoadError
      require 'axlsx'
      ws_cls = Axlsx::Worksheet
    end
    pkg = Axlsx::Package.new
    wb = pkg.workbook
    sty = wb.styles.add_style :font_name => Setting.manifestation_list_print_excelx.fontname
    sheet_name = {
      'book'    => 'book_list',
      'series'  => 'series_list',
      'article' => 'article_list',
    }
    worksheet = {}
    style = {}

    # ヘッダー部分
    column = set_column(selected_column, manifestation_ids)
    column.keys.each do |type|
      if column[type].blank?
        column.delete(type); next
      end
      worksheet[type] = ws_cls.new(wb, :name => sheet_name[type]).tap do |sheet|
        row = get_manifestation_list_header_row(column, type)
        style[type] = [sty]*row.size
        sheet.add_row row, :types => :string, :style => style[type]
      end
    end

    # データ部分
    set_manifestations_data(column, manifestation_ids) do |row, type_of_row|
      worksheet[type_of_row].add_row row, :types => :string, :style => style[type_of_row]
    end
    pkg.serialize(excel_filepath)

    [excel_filepath, excel_fileinfo]
  end

  def self.get_manifestation_list_tsv_csv(manifestation_ids, selected_column = [])
    csv_sep = SystemConfiguration.get("set_output_format_type") ? "\t" : ","
    bom = "\xEF\xBB\xBF"
    bom.force_encoding("UTF-8")
    data = ""

    # 出力カラム書式の生成
    column = set_column(selected_column, manifestation_ids)
    column.keys.each do |type|
      if column[type].blank?
        column.delete(type); next
      end
    end
    return data if column.blank?

    if column['book'] && column['series']
      # bookとseriesを同じCSV中に含めるために
      # 包含関係にあるseriesによりbookをカバーする。
      # 出力カラム数を合わせるために
      # series用の出力カラム定義から
      # book用のもののみを残すものに変換する。
      column['book'] = column['series'].map do |field, *rest|
        if field == 'book'
          [field, *rest]
        else
          [nil, *rest]
        end
      end
    end

    CSV(data, col_sep: csv_sep, force_quotes: true) do |csv|
      # ヘッダー部分
      type = column.keys.include?('article') ? 'article' : 'series'
      header_row = get_manifestation_list_header_row(column, type)
      csv << header_row

      # データ部分
      set_manifestations_data(column, manifestation_ids) do |row, type_of_row|
        csv << row
      end
    end

    bom + data
  end

  def self.get_label_list_tsv_csv(manifestation_ids)
    split = SystemConfiguration.get("set_output_format_type") ? "\t" : ","
    data = String.new
    data << "\xEF\xBB\xBF".force_encoding("UTF-8")

    where(:id => manifestation_ids).includes(:items => [:shelf]).find_in_batches do |manifestations|
      manifestations.each do |manifestation|
        manifestation.items.each do |item|
          row = []
          row << item.manifestation.ndc
          row << item.manifestation.manifestation_exinfos(:name => 'author_mark').first.try(:value)# 著者記号
          row << item.shelf.name 
          data << row.join(split) +"\n" 
        end
      end       
    end
    return data
  end

  # 与えられたカラム(出力カラム定義上の内部キー)のリストから
  # 必要となる出力フィールド定義を生成して返す。
  #
  # 返り値は以下の形式のハッシュ:
  #
  #   {type => [[field, field_ext, separated?, column_count], ...], ...}
  def self.set_column(selected_column, manifestation_ids)
    col_spec = OUTPUT_COLUMN_FIELDS.inject({}) do |spec, name|
      spec[name] = select_output_column_spec(name)
      spec
    end

    column = {
      'book'    => [], # 一般書誌(manifestation_type.is_{series,article}?がfalse
      'series'  => [], # 雑誌(manifestation_type.is_series?がtrue)
      'article' => [], # 文献(manifestation_type.is_article?がtrue)
    }
    series_book_column = []
    series_root_column = []

    all_cols = all_output_columns
    cc_cache = {}
    selected_column.each do |type_col|
      next unless all_cols.include?(type_col)
      next unless /\A([^.]+)\.([^.]+(?:\.[^.]+)*)\z/ =~ type_col

      field, field_ext = $1, $2
      sep_flg = col_spec[field][type_col] == :plural
      column_count = !sep_flg ? 1 : get_manifestation_list_separated_column_count(manifestation_ids, type_col, cc_cache)
      column[field] << [field, field_ext, sep_flg, column_count]

      if field == 'book'
        # NOTE:
        # 一般書誌向けのカラムをリストに加える
        # (雑誌の行は雑誌向けカラム+一般書誌向けカラム+root書誌向けカラム
        # 参照: resource_import_textfile.excel)
        series_book_column << ['book', field_ext, sep_flg, column_count]

        fk = "root.#{field_ext}"
        if col_spec['root'].include?(fk)
          # "root.#{field_ext}"の出力カラム定義がある場合は
          # root書誌情報用としてリストに加える
          sf = col_spec['root'][fk] == :plural
          cc = !sf ? 1 : get_manifestation_list_separated_column_count(manifestation_ids, fk, cc_cache)
          series_root_column << ['root', field_ext, sf, cc]
        end
      end
    end
    column['series'] += series_root_column + series_book_column

    return column
  end

  def self.set_manifestations_data(column, manifestation_ids)
    logger.debug "begin export manifestations"
    transaction do
      where(:id => manifestation_ids).
          includes(
            :carrier_type, :required_role,
            :frequency, :creators, :contributors,
            :publishers, :subjects, :manifestation_type,
            :series_statement,
            :creates => [:agent],
            :realizes => [:agent],
            :produces => [:agent],
            :work_has_languages => [:language, :language_type],
            :items => [
              :bookstore, :checkout_type,
              :circulation_status, :required_role,
              :accept_type, :retention_period,
              :use_restriction, :tax_rate,
              :shelf => :library,
            ]
          ).
          find_in_batches do |manifestations|
        logger.debug "begin a batch set"
        manifestations.each do |manifestation|
          if SystemConfiguration.get('manifestations.split_by_type') and manifestation.article?
            type = 'article'
            target = [manifestation]
          elsif manifestation.series?
            type = 'series'
            # target = manifestation.series_statement.manifestations
            # XXX: 検索結果由来とseries_statement由来とでmanifestationレコードに重複が生じる可能性があることに注意(32b51f2c以前のコード>をそのまま残した)
            # TODO:重複はさせない
             if manifestation.periodical_master
               #target = manifestation.series_statement.manifestaitions
               target = manifestation.series_statement.manifestations.map{ |m| m unless m.periodical_master }.compact
             else
               target = [manifestation]
             end
          else # 一般書誌
            type = 'book'
            target = [manifestation]
          end

          # 出力すべきカラムがない場合はスキップ
          next if column[type].blank?
          target.each do |m|
            if m.items.blank?
              items = [nil]
            else
              items = m.items
            end
            items.each do |i|
              row = []
              column[type].each do |field, field_ext, sep_flg, ccount|
                if field.nil?
                  row << [nil]*ccount
                else
                  row << m.excel_worksheet_value(field, field_ext, sep_flg, ccount, i)
                end
              end
              yield(row.flatten, type)

              if Setting.export.delete_article
                # 文献をエクスポート時にはその文献情報を削除する
                # copied from app/models/resource_import_textresult.rb:92-98
                if i && type == 'article' && m.article?
                  if i.reserve
                    i.reserve.revert_request rescue nil
                  end
                  i.destroy
                end
              end
            end

            if Setting.export.delete_article
              # 文献をエクスポート時にはその文献情報を削除する
              # copied from app/models/resource_import_textresult.rb:102-105
              if type == 'article' && m.article?
                manifestation.destroy if manifestation.items.count == 0
              end
            end
          end # target.each
        end # manifestations.each
        logger.debug "end a batch set"
      end # find_in_batches
    end # transaction
    logger.debug "end export manifestations"
  end

  # XLSX形式でのエクスポートのための値を生成する
  # ws_type: ワークシートの種別
  # ws_col: ワークシートでのカラム名
  # item: 対象とするItemレコード
  def excel_worksheet_value(ws_type, ws_col, sep_flg, ccount, item = nil)
    if ws_type == 'root'
      if root_manifestation = series_statement.try(:root_manifestation)
        root_manifestation.excel_worksheet_value('book', ws_col, sep_flg, ccount, item)
      else
        [nil]*ccount
      end
    end

    helper = Object.new
    helper.extend(ManifestationsHelper)
    val = nil

    case ws_col
    #when 'manifestation_type'
    #  val = manifestation_type.try(:display_name) || ''

    when 'original_title', 'title_transcription', 'series_statement_identifier', 'periodical', 'issn', 'note'
      if ws_type == 'series'
        val = series_statement.excel_worksheet_value(ws_type, ws_col, sep_flg, ccount)
      end

    when 'title'
      if ws_type == 'article'
        val = article_title.to_s
      end

    when 'url'
      if ws_type == 'article'
        val = access_address.to_s
      end

    when 'volume_number_string'
      if ws_type == 'article' &&
          volume_number_string.present? && issue_number_string.present?
        val = "#{volume_number_string}*#{issue_number_string}"
      elsif volume_number_string.present?
        val = volume_number_string.to_s
      else
        val = ''
      end

    when 'number_of_page'
      if start_page.present? && end_page.present?
        val = "#{start_page}-#{end_page}"
      elsif start_page
        val = start_page.to_s
      else
        val = ''
      end

    when 'carrier_type', 'sub_carrier_type', 'required_role', 'manifestation_type', 'country_of_publication', 'catalog'
      val = __send__(ws_col).try(:name) || ''

    when 'frequency'
      val = __send__(ws_col).try(:display_name) || ''

    when 'creator', 'contributor', 'publisher',
        'creator_transcription', 'contributor_transcription', 'publisher_transcription',
        'creator_type', 'contributor_type', 'publisher_type'
      if sep_flg
        case ws_col
        when /^creator/
          name = 'create'
        when /^contributor/
          name = 'realize'
        when /^publisher/
          name = 'produce'
        end

        val = [nil]*ccount
        __send__("#{name}s").each_with_index do |record, i|
          case ws_col
          when /_type$/
            val[i] = record.try("#{name}_type_id")
          when /_transcription$/
            val[i] = record.agent.try(:full_name_transcription)
          else
            val[i] = record.agent.try(:full_name)
          end
        end

      else
        dlm = ';'
        if ws_col == 'creator' &&
            ws_type == 'article' && !japanese_article?
          dlm = ' '
        end
        val = __send__("#{ws_col}s").map(&:full_name).join(dlm)
        if ws_col == 'creator' &&
            ws_type == 'article' && japanese_article? && !val.blank?
          val += dlm
        end
      end

    when 'subject', 'subject_transcription', 'subject_type'
      if sep_flg
        val = [nil]*ccount
        subjects.each_with_index do |record, i|
          if ws_col == 'subject'
            val[i] = record.term
          elsif ws_col == 'subject_transcription'
            val[i] = record.term_transcription
          else
            val[i] = record.subject_type.try(:name)
          end
        end

      else
        dlm = ';'
        if ws_type == 'article' && !japanese_article?
          dlm = '*'
        end
        val = subjects.map(&:term).join(dlm)
      end

    when 'language', 'language_type'
      method = ws_col.to_sym
      if sep_flg
        val = [nil]*ccount
        work_has_languages.each_with_index do |record, i|
          val[i] = record.try(method).try(:name)
        end

      else
        dlm = ';'
        if ws_type == 'article' && !japanese_article?
          dlm = '*'
        end
        val = work_has_languages.map(&method).map(&:name).join(dlm)
      end

    when 'other_title', 'other_title_transcription', 'other_title_alternative', 'other_title_type'
      val = [nil]*ccount
      work_has_titles.each_with_index do |record, i|
        if ws_col == 'other_title'
          val[i] = record.manifestation_title.try(:title)
        elsif ws_col == 'other_title_transcription'
          val[i] = record.manifestation_title.try(:title_transcription)
        elsif ws_col == 'other_title_alternative'
          val[i] = record.manifestation_title.try(:title_alternative)
        else
          val[i] = record.title_type.try(:name)
        end
      end

    when 'other_identifier', 'other_identifier_type'
      val = [nil]*ccount
      identifiers.each_with_index do |record, i|
        if ws_col == 'other_identifier'
          val[i] = record.body
        else
          val[i] = record.identifier_type_id
        end
      end

    when 'classification', 'classification_type'
      if sep_flg
        val = [nil]*ccount
        classifications.each_with_index do |record, i|
          if ws_col == 'classification'
            val[i] = record.category
          else
            val[i] = record.classification_type.name
          end
        end

      else
        dlm = ';'
        val = classifications.pluck(:category).join(dlm)
      end

    when 'theme', 'theme_publish'
      # TODO: enju_trunk_themeに処理を移す
      val = [nil]*ccount
      if defined?(EnjuTrunkTheme)
        themes.each_with_index do |record, i|
          if ws_col == 'theme'
            val[i] = record.name
          else
            val[i] = record.publish
          end
        end
      end

    when 'use_license'
      if defined?(EnjuTrunkOrder)
        val = use_license_id
      end

    when 'missing_issue'
      val = helper.missing_status(missing_issue) || ''

    when 'del_flg'
      val = '' # モデルには格納されない情報

    else
      splits = ws_col.split('.')
      case splits[0]
      when 'manifestation_extext'
        val = [nil]*ccount
        extexts = ManifestationExtext.where(name: splits[1], manifestation_id: __send__(:id)).order(:position) 
        extexts.each_with_index do |record, i|
          if splits.last == 'type'
            val[i] = Keycode.find(record.type_id).try(:keyname) || ''
          else
            val[i] = record.value
          end
        end
      when 'manifestation_exinfo'
        exinfo = ManifestationExinfo.where(name: splits[1], manifestation_id: __send__(:id)).try(:first)
        val =  exinfo.try(:value) || ''
      end
    end
    return val unless val.nil?

    # その他の項目はitemまたはmanifestationの
    # 同名属性からそのまま転記する
    if item
      if /\Aitem/ =~ ws_col
        begin
          val = item.excel_worksheet_value(ws_type, ws_col, sep_flg, ccount) || ''
        rescue NoMethodError
        end
      end

      if val.nil?
        if ws_col != 'note' and ws_col != 'price' and ws_col != 'price_string'
          begin
            val = item.excel_worksheet_value(ws_type, ws_col, sep_flg, ccount) || ''
          rescue NoMethodError
          end
        end
      end
    end

    if val.nil?
      begin
        val = __send__(ws_col) || ''
      rescue NoMethodError
        val = ''
      end
    end
    val

  end

  def self.get_missing_list_pdf(manifestation_ids, current_user)
    where(:id => manifestation_ids).find_in_batches do |manifestations|
      manifestations.each do |manifestation|
        manifestation.missing_issue = 2 unless manifestation.missing_issue == 3
        manifestation.save!(:validate => false)
      end
    end
    return get_manifestation_list_pdf(manifestation_ids, current_user)
  end

  def self.get_manifestation_list_pdf(manifestation_ids, current_user, summary = nil, type = :book)
    report = EnjuTrunk.new_report('searchlist.tlf')

    # set page_num
    report.events.on :page_create do |e|
      e.page.item(:page).value(e.page.no)
    end
    report.events.on :generate do |e|
      e.pages.each do |page|
        page.item(:total).value(e.report.page_count)
      end
    end
    # set data
    report.start_new_page do |page|
      page.item(:date).value(Time.now)
      page.item(:query).value(summary)

      where(:id => manifestation_ids).find_in_batches do |manifestations|
        manifestations.each do |manifestation|
          if type == :book
             next if manifestation.article?
          else
             next unless manifestation.article?
          end
          page.list(:list).add_row do |row|
            # modified data format
            item_identifiers = manifestation.items.map{ |item| item.item_identifier }
            creator = manifestation.creators.readable_by(current_user).map{ |agent| agent.full_name }
            contributor = manifestation.contributors.readable_by(current_user).map{ |agent| agent.full_name }
            publisher = manifestation.publishers.readable_by(current_user).map{ |agent| agent.full_name }
            reserves = Reserve.waiting.where(:manifestation_id => manifestation.id, :checked_out_at => nil)
            # set list
            row.item(:title).value(manifestation.original_title)
            if type == :book
              row.item(:item_identifier).value(item_identifiers.join(',')) unless item_identifiers.empty?
            end
            row.item(:creator).value(creator.join(',')) unless creator.empty?
            row.item(:contributor).value(contributor.join(',')) unless contributor.empty?
            row.item(:publisher).value(publisher.join(',')) unless publisher.empty?
            row.item(:pub_date).value(manifestation.pub_date)
          end
        end
      end
    end
    return report
  end

  def self.get_manifestation_locate(manifestation, current_user)
    report = EnjuTrunk.new_report('manifestation_reseat.tlf')
   
    # footer
    report.layout.config.list(:list) do
      use_stores :total => 0
      events.on :footer_insert do |e|
        e.section.item(:date).value(Time.now.strftime('%Y/%m/%d %H:%M'))
      end
    end
    # main
    report.start_new_page do |page|
      # set manifestation_information
      7.times { |i|
        label, data = "", ""
        page.list(:list).add_row do |row|
          case i
          when 0
            label = I18n.t('activerecord.attributes.manifestation.original_title')
            data  = manifestation.original_title
          when 1
            label = I18n.t('agent.creator')
            data  = manifestation.creators.readable_by(current_user).map{|agent| agent.full_name}
            data  = data.join(",")
          when 2
            label = I18n.t('agent.publisher')
            data  = manifestation.publishers.readable_by(current_user).map{|agent| agent.full_name}
            data  = data.join(",")
          when 3
            label = I18n.t('activerecord.attributes.manifestation.price')
            data  = manifestation.price
          when 4
            label = I18n.t('activerecord.attributes.manifestation.page')
            data  = manifestation.number_of_pages.to_s + 'p' if manifestation.number_of_pages
          when 5
            label = I18n.t('activerecord.attributes.manifestation.size')
            data  = manifestation.height.to_s + 'cm' if manifestation.height
          when 6
            label = I18n.t('activerecord.attributes.series_statement.original_title')
            data  = manifestation.series_statement.original_title if manifestation.series_statement
          when 7
            label = I18n.t('activerecord.attributes.manifestation.isbn')
            data  = manifestation.isbn
          end
          row.item(:label).show
          row.item(:data).show
          row.item(:dot_line).hide
          row.item(:label).value(label.to_s + ":")
          row.item(:data).value(data)
        end
      }

      # set item_information
      manifestation.items.each do |item|
        if SystemConfiguration.get('manifestation.manage_item_rank')
          if current_user.nil? or !current_user.has_role?('Librarian')
            next unless item.rank <= 1
            next if item.retention_period.non_searchable
            next if item.circulation_status.name == "Removed"
            next if item.non_searchable
          end
        end
        6.times { |i|
          label, data = "", ""
          page.list(:list).add_row do |row|
            row.item(:label).show
            row.item(:data).show
            row.item(:dot_line).hide
            case i
            when 0
              row.item(:label).hide
              row.item(:data).hide
              row.item(:dot_line).show
            when 1
              label = I18n.t('activerecord.models.library')
              data  = item.shelf.library.display_name.localize
            when 2
              label = I18n.t('activerecord.models.shelf')
              data  = item.shelf.display_name.localize
            when 3
              label = I18n.t('activerecord.attributes.item.call_number')
              data  = call_numberformat(item)
            when 4
              label = I18n.t('activerecord.attributes.item.item_identifier')
              data  = item.item_identifier
            when 5
              label = I18n.t('activerecord.models.circulation_status')
              data  = item.circulation_status.display_name.localize
            end
            row.item(:label).value(label.to_s + ":")
            row.item(:data).value(data)
          end
        }
      end
    end
    return report 
  end

  class GenerateManifestationListJob
    include Rails.application.routes.url_helpers
    include BackgroundJobUtils

    def initialize(name, fileinfo, output_type, user, search_condition_summary, cols)
      @name = name
      @fileinfo = fileinfo
      @output_type = output_type
      @user = user
      @search_condition_summary = search_condition_summary
      @cols = cols
    end
    attr_accessor :name, :fileinfo, :output_type, :user, :search_condition_summary, :cols

    def perform
      user_file = UserFile.new(user)
      path, = user_file.find(fileinfo[:category], fileinfo[:filename], fileinfo[:random])
      manifestation_ids = open(path, 'r') {|io| Marshal.load(io) }

      Manifestation.generate_manifestation_list_internal(manifestation_ids, output_type, user, search_condition_summary, cols) do |output|
        io, info = user_file.create(:manifestation_list, output.filename)
        if output.result_type == :path
          open(output.path) {|io2| FileUtils.copy_stream(io2, io) }
        else
          io.print output.data
        end
        io.close

        url = my_account_url(:filename => info[:filename], :category => info[:category], :random => info[:random])
        message(
          user,
          I18n.t('manifestation.output_job_success_subject', :job_name => name),
          I18n.t('manifestation.output_job_success_body', :job_name => name, :url => url))
      end

    rescue => exception
      message(
        user,
        I18n.t('manifestation.output_job_error_subject', :job_name => name),
        #I18n.t('manifestation.output_job_error_body', :job_name => name, :message => exception.message))
        I18n.t('manifestation.output_job_error_body', :job_name => name, :message => exception.message+exception.backtrace))
    end
  end

  private

    INTERNAL_ITEM_ATTR_CACHE = {}
    def internal_item_attr_cache
      if INTERNAL_ITEM_ATTR_CACHE[:limit] &&
          INTERNAL_ITEM_ATTR_CACHE[:limit] > Time.now
        return INTERNAL_ITEM_ATTR_CACHE
      end

      self.class.init_internal_item_attr_cache!
      INTERNAL_ITEM_ATTR_CACHE
    end

    def item_attr_with_cache(attr_key, attr_id)
      cache = internal_item_attr_cache
      if cache[attr_key].include?(attr_id)
        return cache[attr_key][attr_id]
      end
      cache[attr_key][attr_id] = yield
    end

    def item_attr_without_cache(attr_key, attr_id)
      yield
    end

    def self.init_internal_item_attr_cache!
      INTERNAL_ITEM_ATTR_CACHE.clear
      INTERNAL_ITEM_ATTR_CACHE[:limit] = Time.now + 60*60*24
      INTERNAL_ITEM_ATTR_CACHE[:rp_non_searchable] = {}
      INTERNAL_ITEM_ATTR_CACHE[:cs_unsearchable] = {}
      INTERNAL_ITEM_ATTR_CACHE[:cs_name] = {}
      INTERNAL_ITEM_ATTR_CACHE[:library_name] = {}
    end

    def self.enable_item_attr_cache!
      alias_method :item_attr, :item_attr_with_cache
      define_method(:reload_for_index) { false }
      init_internal_item_attr_cache!
      logger.info 'Internal item attributions cache for Manifestation is enabled.'
    end

    def self.disable_item_attr_cache!
      alias_method :item_attr, :item_attr_without_cache
      define_method(:reload_for_index) { true }
      init_internal_item_attr_cache!
      logger.info 'Internal item attributions cache for Manifestation is disabled.'
    end

    if ENV['ENABLE_ITEM_ATTR_CACHE']
      enable_item_attr_cache!
    else
      disable_item_attr_cache!
    end

    def item_retention_period_non_searchable?(item)
      item_attr(:rp_non_searchable, item.retention_period_id) do
        item.retention_period.try(:non_searchable)
      end
    end

    def item_circulation_status_unsearchable?(item)
      item_attr(:cs_name, item.circulation_status_id) do
        item.circulation_status.try(:unsearchable)
      end
    end

    def item_circulation_status_name(item)
      item_attr(:cs_unsearchable, item.circulation_status_id) do
        item.circulation_status.try(:name)
      end
    end

    def item_library_name(item)
      item_attr(:library_name, item.shelf.library_id) do
        item.shelf.library.name
      end
    end

    def series_manifestations
      if !reload_for_index &&
          @_series_manifestations_cache
        @_series_manifestations_cache
      end

      @_series_manifestations_cache =
        Manifestation.joins(:series_statement).
          where(['series_statements.id = ?', self.series_statement.id])
    end

    def series_manifestations_items
      if !reload_for_index &&
          @_series_manifestations_items_cache
        @_series_manifestations_items_cache
      end

      @_series_manifestations_items_cache =
        Item.joins(:manifestation => :series_statement).
          where(['series_statements.id = ?', self.series_statement.id])
    end

end

# == Schema Information
#
# Table name: manifestations
#
#  id                              :integer         not null, primary key
#  original_title                  :text            not null
#  title_alternative               :text
#  title_transcription             :text
#  classification_number           :string(255)
#  identifier                      :string(255)
#  date_of_publication             :datetime
#  date_copyrighted                :datetime
#  created_at                      :datetime
#  updated_at                      :datetime
#  deleted_at                      :datetime
#  access_address                  :string(255)
#  language_id                     :integer         default(1), not null
#  carrier_type_id                 :integer         default(1), not null
#  extent_id                       :integer         default(1), not null
#  start_page                      :integer
#  end_page                        :integer
#  height                          :decimal(, )
#  width                           :decimal(, )
#  depth                           :decimal(, )
#  isbn                            :string(255)
#  isbn10                          :string(255)
#  wrong_isbn                      :string(255)
#  nbn                             :string(255)
#  lccn                            :string(255)
#  oclc_number                     :string(255)
#  issn                            :string(255)
#  price                           :integer
#  fulltext                        :text
#  volume_number_string              :string(255)
#  issue_number_string               :string(255)
#  serial_number_string              :string(255)
#  edition                         :integer
#  note                            :text
#  produces_count                  :integer         default(0), not null
#  embodies_count                  :integer         default(0), not null
#  work_has_subjects_count         :integer         default(0), not null
#  repository_content              :boolean         default(FALSE), not null
#  lock_version                    :integer         default(0), not null
#  required_role_id                :integer         default(1), not null
#  state                           :string(255)
#  required_score                  :integer         default(0), not null
#  frequency_id                    :integer         default(1), not null
#  subscription_master             :boolean         default(FALSE), not null
#  ipaper_id                       :integer
#  ipaper_access_key               :string(255)
#  attachment_file_name            :string(255)
#  attachment_content_type         :string(255)
#  attachment_file_size            :integer
#  attachment_updated_at           :datetime
#  nii_type_id                     :integer
#  title_alternative_transcription :text
#  description                     :text
#  abstract                        :text
#  available_at                    :datetime
#  valid_until                     :datetime
#  date_submitted                  :datetime
#  date_accepted                   :datetime
#  date_caputured                  :datetime
#  file_hash                       :string(255)
#  pub_date                        :string(255)
#  periodical_master               :boolean         default(FALSE), not null
#

