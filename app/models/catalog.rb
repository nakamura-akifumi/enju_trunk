class Catalog < ActiveRecord::Base
  has_many :manifestations
  attr_accessible :display_name, :nacsis_identifier, :name, :note

  validates_presence_of :name
  validates_uniqueness_of :name
end
