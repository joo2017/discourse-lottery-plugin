# frozen_string_literal: true

module DiscourseLottery
  class Lottery < ActiveRecord::Base
    self.table_name = 'lotteries'
    
    belongs_to :topic
    belongs_to :user
    has_many :participants, class_name: 'LotteryParticipant', dependent: :destroy
    has_many :participant_users, through: :participants, source: :user
    
    validates :name, presence: true, length: { maximum: 255 }
    validates :prize_description, presence: true
    validates :draw_time, presence: true
    validates :winner_count, presence: true, numericality: { greater_than: 0 }
    validates :min_participants, presence: true, numericality: { greater_than: 0 }
    validates :backup_strategy, presence: true, inclusion: { in: %w[continue cancel] }
    validates :draw_method, presence: true, inclusion: { in: %w[random specific] }
    validates :status, presence: true, inclusion: { in: %w[running finished cancelled] }
    
    validate :draw_time_in_future, on: :create
    validate :winner_count_within_limits
    validate :min_participants_meets_global_requirement
    validate :specific_floors_valid_when_required
    
    scope :running, -> { where(status: 'running') }
    scope :finished, -> { where(status: 'finished') }
    scope :cancelled, -> { where(status: 'cancelled') }
    scope :pending_draw, -> { running.where('draw_time <= ?', Time.current) }
    scope :lockable, -> { running.where(locked: false) }
    
    def locked?
      locked
    end
    
    def can_be_edited?
      status == 'running' && !locked?
    end
    
    def specific_floors_array
      return [] unless specific_floors.present?
      specific_floors.split(',').map(&:strip).map(&:to_i).reject(&:zero?)
    end
    
    def actual_winner_count
      if draw_method == 'specific'
        specific_floors_array.length
      else
        winner_count
      end
    end
    
    def has_enough_participants?
      effective_participants_count >= min_participants
    end
    
    def effective_participants_count
      participants.count
    end
    
    def should_continue_with_insufficient_participants?
      backup_strategy == 'continue'
    end
    
    def winners
      participants.where(is_winner: true).includes(:user, :post)
    end
    
    def can_draw?
      status == 'running' && draw_time <= Time.current
    end
    
    def lock!
      update!(locked: true, locked_at: Time.current)
      topic.update!(archived: true) if topic.present?
    end
    
    def finish_with_winners!(winners_data)
      update!(
        status: 'finished',
        winners_data: winners_data
      )
    end
    
    def cancel_with_reason!(reason)
      update!(
        status: 'cancelled',
        cancellation_reason: reason
      )
    end
    
    private
    
    def draw_time_in_future
      return unless draw_time.present?
      
      if draw_time <= Time.current
        errors.add(:draw_time, I18n.t('lottery.errors.draw_time_must_be_future'))
      end
    end
    
    def winner_count_within_limits
      return unless winner_count.present?
      
      max_winners = SiteSetting.lottery_max_winner_count
      if winner_count > max_winners
        errors.add(:winner_count, I18n.t('lottery.errors.winner_count_too_high', max: max_winners))
      end
    end
    
    def min_participants_meets_global_requirement
      return unless min_participants.present?
      
      global_min = SiteSetting.lottery_min_participants_global
      if min_participants < global_min
        errors.add(:min_participants, 
                  I18n.t('lottery.errors.min_participants_too_low', min: global_min))
      end
    end
    
    def specific_floors_valid_when_required
      return unless draw_method == 'specific'
      
      if specific_floors.blank?
        errors.add(:specific_floors, I18n.t('lottery.errors.specific_floors_required'))
        return
      end
      
      floors = specific_floors_array
      if floors.empty?
        errors.add(:specific_floors, I18n.t('lottery.errors.specific_floors_invalid'))
      end
      
      if floors.length > SiteSetting.lottery_max_winner_count
        errors.add(:specific_floors, 
                  I18n.t('lottery.errors.too_many_specific_floors', 
                        max: SiteSetting.lottery_max_winner_count))
      end
    end
  end
end
