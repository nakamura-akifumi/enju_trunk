class SeriesStatement < ActiveRecord::Base
  attr_accessible :original_title, :numbering, :title_subseries,
    :numbering_subseries, :title_transcription, :title_alternative,
    :series_statement_identifier, :issn, :periodical, :note,
    :title_subseries_transcription

  has_many :series_has_manifestations
  has_many :manifestations, :through => :series_has_manifestations
  has_many :child_relationships, :foreign_key => 'parent_id', :class_name => 'SeriesStatementRelationship', :dependent => :destroy
  has_many :parent_relationships, :foreign_key => 'child_id', :class_name => 'SeriesStatementRelationship', :dependent => :destroy
  has_many :children, :through => :child_relationships, :source => :child
  has_many :parents, :through => :parent_relationships, :source => :parent
  validates_presence_of :original_title
  validate :check_issn
  after_create :create_initial_manifestation

  acts_as_list
  searchable do
    text :title do
      original_title
    end
    text :numbering, :title_subseries, :numbering_subseries
    integer :manifestation_ids, :multiple => true do
      manifestations.collect(&:id)
    end
    integer :position
    boolean :periodical
    integer :parent_ids, :multiple => true do
      parents.pluck('series_statements.id')
    end
    integer :child_ids, :multiple => true do
      children.pluck('series_statements.id')
    end
  end

  normalize_attributes :original_title, :issn

  paginates_per 10

  def last_issue
    manifestations.where('serial_number IS NOT NULL').order('serial_number DESC').first || manifestations.first
#    manifestations.where('date_of_publication IS NOT NULL').order('date_of_publication DESC').first || manifestations.first
  end

  def last_issue_with_issue_number
    manifestations.where('issue_number IS NOT NULL').order('volume_number DESC').order('issue_number DESC').first || manifestations.first
  end

  def self.latest_issues
    manifestations = []
    series_statements = SeriesStatement.all
    series_statements.each do |series|
      manifestations << series.last_issue
    end
    return manifestations
  end

  def check_issn
#    self.issn = ISBN_Tools.cleanup(issn)
    if issn.present?
      unless StdNum::ISSN.valid?(issn)
        errors.add(:issn)
      end
    end
  end

  def create_initial_manifestation
    return nil if initial_manifestation
    return nil unless periodical
    manifestation = Manifestation.new(
      :original_title => original_title
    )
    manifestation.periodical_master = true
    self.manifestations << manifestation
  end

  def initial_manifestation
    manifestations.where(:periodical_master => true).first
  end

  def first_issue
    manifestations.order(:date_of_publication).first
  end

  def latest_issue
    manifestations.order(:date_of_publication).last
  end

  def manifestation_included(manifestation)
    series_has_manifestations.where(:manifestation_id => manifestation.id).first
  end

  def titles
    [
      original_title,
      title_transcription,
      parents.map{|parent| [parent.original_title, parent.title_transcription]},
      children.map{|child| [child.original_title, child.title_transcription]}
    ].flatten.compact
  end
end

# == Schema Information
#
# Table name: series_statements
#
#  id                          :integer         not null, primary key
#  original_title              :text
#  numbering                   :text
#  title_subseries             :text
#  numbering_subseries         :text
#  position                    :integer
#  created_at                  :datetime
#  updated_at                  :datetime
#  title_transcription         :text
#  title_alternative           :text
#  series_statement_identifier :string(255)
#  issn                        :string(255)
#  periodical                  :boolean
#

