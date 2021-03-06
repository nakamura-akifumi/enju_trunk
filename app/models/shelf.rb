class Shelf < ActiveRecord::Base
  attr_accessible  :name, :display_name, :note, :library_id, :open_access, :required_role_id

  include MasterModel
  self.extend ItemsHelper
  default_scope :order => 'shelves.position'
  scope :real, where('library_id >= 1')
  belongs_to :library, :validate => true
  has_many :items, :include => [:circulation_status]
  has_many :picture_files, :as => :picture_attachable, :dependent => :destroy
  has_many :statistics
  belongs_to :required_role, :class_name => 'Role', :foreign_key => 'required_role_id', :validate => true

  validates_associated :library
  validates_presence_of :library, :open_access
  validates_uniqueness_of :display_name, :scope => :library_id
  
  acts_as_list :scope => :library

  has_paper_trail

  after_save :delay_reindex_manifestation
  # ManifestationsController#index の manifestation をキャッシュしているため
  # 本棚更新時は manifestation.updated_at を更新する
  after_update :touch_manifestation, :if => lambda{ self.display_name_changed? || self.required_role_id_changed?}
  def touch_manifestation
    ActiveRecord::Base.connection.update_sql("update manifestations set updated_at = current_timestamp where id in (select manifestation_id from items where shelf_id = #{self.id})");
  end
  
  searchable do
    string :library do
      library.name if library
    end
    integer :open_access
  end

  paginates_per 10

  def web_shelf?
    #TODO return true if self.id == 1
    false
  end

  def self.web
    Shelf.find(1)
  end

  def first?
    # 必ずposition順に並んでいる
    return true if library.shelves.first.position == position
    false
  end

  def localized_display_name
    display_name.localize
  end

  def destroy?
    return false if Item.where(:shelf_id => self.id).first
    return true
  end

  def open?
    return true if self.open_access == 0
    return false
  end

  def self.get_closing_report(item)
    logger.error "closing report"
    begin
      report = EnjuTrunk.new_report('close_shelf.tlf')
      report.start_new_page
      report.page.item(:export_date).value(Time.now)
      report.page.item(:title).value(item.manifestation.original_title)
      report.page.item(:call_number).value(call_numberformat(item))
      report.page.item(:library).value(item.shelf.library.display_name.localize)
      report.page.item(:shelf).value(item.shelf.display_name.localize)
      logger.error "created report: #{Time.now}"
      return report.generate
    rescue Exception => e
      logger.error "failed #{e}"
      return false
    end
  end

  def delay_reindex_manifestation
    if self.required_role_id_changed? && self.items.present?
      self.delay.reindex_manifestation
    end
  end
 
  def reindex_manifestation
    self.items.collect(&:manifestation_id).compact.each do |manifestation_id|
      Manifestation.find(manifeststaion_id).try(:index)
    end
  end
end

# == Schema Information
#
# Table name: shelves
#
#  id           :integer         not null, primary key
#  name         :string(255)     not null
#  display_name :text
#  note         :text
#  library_id   :integer         default(1), not null
#  items_count  :integer         default(0), not null
#  position     :integer
#  created_at   :datetime
#  updated_at   :datetime
#  deleted_at   :datetime
#

