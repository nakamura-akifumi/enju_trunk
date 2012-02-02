class ResourceImportTextfile < ActiveRecord::Base
  include ImportFile
  default_scope :order => 'id DESC'
  scope :not_imported, where(:state => 'pending', :imported_at => nil)

  has_attached_file :resource_import, :path => ":rails_root/private:url"

  validates_attachment_content_type :resource_import, :content_type => ['text/csv', 'text/plain', 'text/tab-separated-values', 'application/octet-stream']
  validates_attachment_presence :resource_import
  belongs_to :user, :validate => true
  has_many :resource_import_results
  before_create :set_digest
  
  state_machine :initial => :pending do
    event :sm_start do
      transition [:pending, :started] => :started
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
    if File.exists?(resource_import.queued_for_write[:original])
      self.file_hash = Digest::SHA1.hexdigest(File.open(resource_import.queued_for_write[:original].path, 'rb').read)
    end
  end

  def self.import(id = nil)
    if !id.nil?
      file = ResourceImportTextfile.find(id) rescue nil
      file.import_start unless file.nil?
    else
      ResourceImportTextfile.not_imported.each do |file|
        file.import_start
      end
    end
  rescue Exception => e
    logger.info "#{Time.zone.now} importing resources failed! #{e}"
  end
end
