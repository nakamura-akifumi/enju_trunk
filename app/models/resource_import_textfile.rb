require 'roo'

class ResourceImportTextfile < ActiveRecord::Base
  attr_accessible :adapter_name, :resource_import_text, :extraparams

  include ImportFile
  default_scope :order => 'resource_import_textfiles.id DESC'
  scope :not_imported, where(:state => 'pending', :imported_at => nil)

  has_attached_file :resource_import_text, :path => ":rails_root/private:url"

#  validates_attachment_content_type :resource_import_text,
#    :content_type => %w(text/plain application/vnd.openxmlformats-officedocument.spreadsheetml.sheet application/octet-stream application/vnd.ms-excel),
#    :message => I18n.t('resource_import_textfile.wrong_content_type')
  validates_attachment_presence :resource_import_text
  belongs_to :user, :validate => true
  has_many :resource_import_textresults
  before_create :set_digest
  
  
  state_machine :initial => :pending do
    event :sm_request do
      transition :pending => :requested
    end

    event :sm_start do
      transition [:pending, :requested] => :started
    end

    event :sm_complete do
      transition :started => :completed
    end

    event :sm_fail do
      transition :started => :failed
    end
  end

  def adapter_display_name
    EnjuTrunk::ResourceAdapter::Base.find_by_classname(self.adapter_name).display_name rescue nil
  end

  def set_digest(options = {:type => 'sha1'})
    if File.exists?(resource_import_text.queued_for_write[:original])
      self.file_hash = Digest::SHA1.hexdigest(File.open(resource_import_text.queued_for_write[:original].path, 'rb').read)
    end
  end

  def self.import(id = nil)
    if !id.nil?
      file = ResourceImportTextfile.find(id) rescue nil
      file.import_start if file
    else
      ResourceImportTextfile.not_imported.each do |file|
        file.import_start 
      end 
    end
  rescue Exception => e
    puts $!
    logger.info "#{Time.zone.now} importing resources failed! #{e}"
    logger.info "#{Time.zone.now} #{$@}"
  end

  def import_start
    # check state
    if self.state == 'pending' || self.state == 'requested' 
      sm_start!
      ResourceImport.new.import(self)
      self.update_attribute(:imported_at, Time.zone.now)
      sm_complete!
    end
  end
end
