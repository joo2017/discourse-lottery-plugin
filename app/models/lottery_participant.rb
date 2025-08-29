# frozen_string_literal: true

module DiscourseLottery
  class LotteryParticipant < ActiveRecord::Base
    self.table_name = 'lottery_participants'
    
    belongs_to :lottery
    belongs_to :user
    belongs_to :post
    
    validates :floor_number, presence: true, numericality: { greater_than: 1 }
    validates :participated_at, presence: true
    
    scope :winners, -> { where(is_winner: true) }
    scope :by_floor, -> { order(:floor_number) }
    scope :by_participation_time, -> { order(:participated_at) }
    
    def winner?
      is_winner
    end
    
    def floor_display
      "##{floor_number}"
    end
    
    def participation_time_display
      participated_at.strftime('%Y-%m-%d %H:%M:%S')
    end
  end
end
