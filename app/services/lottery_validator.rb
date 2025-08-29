# frozen_string_literal: true

module DiscourseLottery
  class LotteryValidator
    include ActiveModel::Validations
    
    attr_accessor :lottery_name, :lottery_prize, :lottery_draw_time, 
                  :lottery_winner_count, :lottery_min_participants,
                  :lottery_backup_strategy, :lottery_specific_floors
    
    validates :lottery_name, presence: true, length: { maximum: 255 }
    validates :lottery_prize, presence: true, length: { maximum: 1000 }
    validates :lottery_draw_time, presence: true
    validates :lottery_winner_count, presence: true, 
              numericality: { greater_than: 0, only_integer: true }
    validates :lottery_min_participants, presence: true,
              numericality: { greater_than: 0, only_integer: true }
    validates :lottery_backup_strategy, presence: true,
              inclusion: { in: %w[continue cancel] }
    
    validate :draw_time_format_valid
    validate :draw_time_in_future
    validate :min_participants_meets_global_requirement
    validate :winner_count_within_limits
    validate :specific_floors_format_valid
    
    def initialize(custom_fields)
      @custom_fields = custom_fields || {}
      
      self.lottery_name = @custom_fields['lottery_name']
      self.lottery_prize = @custom_fields['lottery_prize']
      self.lottery_draw_time = @custom_fields['lottery_draw_time']
      self.lottery_winner_count = @custom_fields['lottery_winner_count'].to_i if @custom_fields['lottery_winner_count'].present?
      self.lottery_min_participants = @custom_fields['lottery_min_participants'].to_i if @custom_fields['lottery_min_participants'].present?
      self.lottery_backup_strategy = @custom_fields['lottery_backup_strategy']
      self.lottery_specific_floors = @custom_fields['lottery_specific_floors']
    end
    
    private
    
    def draw_time_format_valid
      return unless lottery_draw_time.present?
      
      begin
        parsed_time = Time.zone.parse(lottery_draw_time)
        return if parsed_time.is_a?(Time)
      rescue ArgumentError
        # 继续到错误处理
      end
      
      errors.add(:lottery_draw_time, I18n.t('lottery.errors.invalid_time_format'))
    end
    
    def draw_time_in_future
      return unless lottery_draw_time.present?
      
      begin
        parsed_time = Time.zone.parse(lottery_draw_time)
        if parsed_time <= Time.current
          errors.add(:lottery_draw_time, I18n.t('lottery.errors.draw_time_must_be_future'))
        end
      rescue ArgumentError
        # 时间格式错误会在draw_time_format_valid中处理
      end
    end
    
    def min_participants_meets_global_requirement
      return unless lottery_min_participants.present?
      
      global_min = SiteSetting.lottery_min_participants_global
      if lottery_min_participants < global_min
        errors.add(:lottery_min_participants, 
                  I18n.t('lottery.errors.min_participants_too_low', min: global_min))
      end
    end
    
    def winner_count_within_limits
      return unless lottery_winner_count.present?
      
      max_winners = SiteSetting.lottery_max_winner_count
      if lottery_winner_count > max_winners
        errors.add(:lottery_winner_count, 
                  I18n.t('lottery.errors.winner_count_too_high', max: max_winners))
      end
    end
    
    def specific_floors_format_valid
      return unless lottery_specific_floors.present?
      
      begin
        floors = lottery_specific_floors.split(',').map(&:strip).map(&:to_i)
        
        # 检查是否有无效的楼层号
        if floors.any?(&:zero?) || floors.any? { |f| f <= 1 }
          errors.add(:lottery_specific_floors, 
                    I18n.t('lottery.errors.invalid_floor_numbers'))
        end
        
        # 检查是否有重复的楼层号
        if floors.uniq.length != floors.length
          errors.add(:lottery_specific_floors, 
                    I18n.t('lottery.errors.duplicate_floor_numbers'))
        end
        
        # 检查楼层数量是否超过限制
        max_floors = SiteSetting.lottery_max_winner_count
        if floors.length > max_floors
          errors.add(:lottery_specific_floors, 
                    I18n.t('lottery.errors.too_many_floors', max: max_floors))
        end
        
      rescue StandardError
        errors.add(:lottery_specific_floors, 
                  I18n.t('lottery.errors.floor_format_invalid'))
      end
    end
  end
end
