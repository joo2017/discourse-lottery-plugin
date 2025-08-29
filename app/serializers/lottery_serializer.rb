# frozen_string_literal: true

module DiscourseLottery
  class LotterySerializer < ApplicationSerializer
    attributes :id, :name, :prize_description, :prize_image_url,
               :draw_time, :winner_count, :min_participants,
               :backup_strategy, :description, :draw_method,
               :status, :locked, :created_at, :updated_at,
               :effective_participants_count, :winners_data,
               :can_participate, :can_cancel, :time_until_draw,
               :specific_floors_display
    
    has_one :user, embed: :objects, serializer: BasicUserSerializer
    has_one :topic, embed: :objects, serializer: BasicTopicSerializer
    
    def draw_time
      object.draw_time.iso8601
    end
    
    def effective_participants_count
      object.effective_participants_count
    end
    
    def can_participate
      return false unless scope.user.present?
      return false if object.status != 'running'
      return false if object.user_id == scope.user.id
      return false if object.draw_time <= Time.current
      
      # 检查是否在被排除的用户组中
      excluded_groups = SiteSetting.lottery_excluded_groups.split('|')
      if excluded_groups.any?
        user_groups = scope.user.groups.pluck(:name)
        return false if (user_groups & excluded_groups).any?
      end
      
      true
    end
    
    def can_cancel
      return false unless scope.user.present?
      return false unless object.status == 'running'
      return false if object.locked?
      
      scope.user.id == object.user_id || scope.user.staff?
    end
    
    def time_until_draw
      return 0 if object.draw_time <= Time.current
      
      (object.draw_time - Time.current).to_i
    end
    
    def specific_floors_display
      return nil unless object.draw_method == 'specific'
      
      object.specific_floors_array.map { |floor| "#{floor}楼" }.join(', ')
    end
    
    def include_winners_data?
      object.status == 'finished' && object.winners_data.present?
    end
    
    def winners_data
      return nil unless object.winners_data.present?
      
      object.winners_data.map do |winner|
        winner.merge(
          'avatar_template' => User.find(winner['user_id'])&.avatar_template
        )
      end
    end
  end
end
