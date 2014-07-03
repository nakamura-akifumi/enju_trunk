class ItemExtext < ActiveRecord::Base
  attr_accessible :item_id, :name, :display_name, :position, :value

  belongs_to :item

  acts_as_list
  default_scope :order => "position"
  before_save { |c| c.logger.info '######### before_save #########' }
  after_save { |c| c.logger.info '######### after_save #########' }

  has_paper_trail

  def self.add_extexts(extexts, item_id)
    logger.error "####### self.add_extexts start ########"
    return [] if extexts.blank?
    list = []
    position = 1
    extexts.each do |key, value|
      next if value.blank?
      item_extext = ItemExtext.where(
        name: key,
        item_id: item_id
      ).first
      if item_extext
        if value.blank?
          item_extext.destroy
          next
        else
          item_extext.value = value
        end
      else
        next if value.blank?
        item_extext = ItemExtext.new(
          name: key,
          value: value,
          item_id: item_id
        )
      end
      item_extext.position = position
      item_extext.save
      list << item_extext
      position += 1
    end
    logger.error "####### self.add_extexts end ########"
    return list
  end
end
