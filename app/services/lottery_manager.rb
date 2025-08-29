# frozen_string_literal: true

module DiscourseLottery
  class LotteryManager
    def initialize(lottery)
      @lottery = lottery
      @topic = lottery.topic
    end
    
    def execute_draw!
      return unless @lottery.can_draw?
      
      ActiveRecord::Base.transaction do
        collect_participants!
        
        if should_proceed_with_draw?
          perform_draw!
          announce_results!
          send_notifications!
        else
          cancel_lottery!
          announce_cancellation!
        end
        
        finalize_lottery!
      end
    end
    
    private
    
    attr_reader :lottery, :topic
    
    def collect_participants!
      # 清除现有参与者记录
      @lottery.participants.destroy_all
      
      # 获取所有有效回复
      valid_posts = get_valid_posts
      
      # 创建参与者记录
      valid_posts.each do |post|
        @lottery.participants.create!(
          user: post.user,
          post: post,
          floor_number: post.post_number,
          participated_at: post.created_at
        )
      end
    end
    
    def get_valid_posts
      posts = @topic.posts.where('post_number > 1')
                    .includes(:user)
                    .where.not(user_deleted: true)
                    .where.not(hidden: true)
                    .where.not(user_id: @lottery.user_id) # 排除楼主
      
      # 排除被禁止的用户组
      excluded_groups = SiteSetting.lottery_excluded_groups.split('|')
      if excluded_groups.any?
        excluded_user_ids = GroupUser.joins(:group)
                                   .where(groups: { name: excluded_groups })
                                   .pluck(:user_id)
        posts = posts.where.not(user_id: excluded_user_ids) if excluded_user_ids.any?
      end
      
      # 每个用户只取最早的一条有效回复
      posts.group(:user_id)
           .having('MIN(post_number)')
           .order(:post_number)
    end
    
    def should_proceed_with_draw?
      participant_count = @lottery.effective_participants_count
      
      if participant_count >= @lottery.min_participants
        true
      else
        @lottery.should_continue_with_insufficient_participants?
      end
    end
    
    def perform_draw!
      if @lottery.draw_method == 'specific'
        perform_specific_floor_draw!
      else
        perform_random_draw!
      end
    end
    
    def perform_specific_floor_draw!
      target_floors = @lottery.specific_floors_array
      winners = []
      
      target_floors.each do |floor_number|
        participant = @lottery.participants.find_by(floor_number: floor_number)
        if participant
          participant.update!(is_winner: true)
          winners << participant
        end
      end
      
      if winners.empty?
        # 没有有效的指定楼层，取消抽奖
        @cancellation_reason = I18n.t('lottery.cancellation.no_valid_floors')
        return false
      end
      
      @winners = winners
      true
    end
    
    def perform_random_draw!
      participants = @lottery.participants.to_a.shuffle
      winner_count = [@lottery.winner_count, participants.length].min
      
      @winners = participants.first(winner_count)
      @winners.each { |p| p.update!(is_winner: true) }
    end
    
    def cancel_lottery!
      reason = @cancellation_reason || I18n.t('lottery.cancellation.insufficient_participants',
                                             required: @lottery.min_participants,
                                             actual: @lottery.effective_participants_count)
      @lottery.cancel_with_reason!(reason)
    end
    
    def announce_results!
      winners_info = @winners.map do |winner|
        {
          user_id: winner.user_id,
          username: winner.user.username,
          floor_number: winner.floor_number,
          post_id: winner.post_id
        }
      end
      
      @lottery.finish_with_winners!(winners_info)
      
      # 发布中奖公告
      announcement = build_winner_announcement
      PostCreator.create!(
        Discourse.system_user,
        topic_id: @topic.id,
        raw: announcement,
        skip_validations: true
      )
      
      # 更新标签
      update_topic_tags('已开奖')
    end
    
    def announce_cancellation!
      announcement = build_cancellation_announcement
      PostCreator.create!(
        Discourse.system_user,
        topic_id: @topic.id,
        raw: announcement,
        skip_validations: true
      )
      
      # 更新标签
      update_topic_tags('已取消')
    end
    
    def send_notifications!
      @winners.each do |winner|
        send_winner_notification(winner)
      end
    end
    
    def send_winner_notification(winner)
      PostCreator.create!(
        Discourse.system_user,
        title: I18n.t('lottery.notification.winner_title', name: @lottery.name),
        raw: I18n.t('lottery.notification.winner_message',
                   username: winner.user.username,
                   lottery_name: @lottery.name,
                   prize: @lottery.prize_description,
                   topic_url: @topic.url),
        target_usernames: winner.user.username,
        archetype: Archetype.private_message,
        skip_validations: true
      )
    end
    
    def build_winner_announcement
      winners_list = @winners.map do |winner|
        "- @#{winner.user.username} (#{winner.floor_display}楼)"
      end.join("\n")
      
      I18n.t('lottery.announcement.winners',
             lottery_name: @lottery.name,
             winners_list: winners_list,
             total_participants: @lottery.effective_participants_count)
    end
    
    def build_cancellation_announcement
      I18n.t('lottery.announcement.cancelled',
             lottery_name: @lottery.name,
             reason: @lottery.cancellation_reason,
             total_participants: @lottery.effective_participants_count)
    end
    
    def update_topic_tags(new_tag)
      current_tags = @topic.tags.pluck(:name) - ['抽奖中']
      new_tags = current_tags + [new_tag]
      DiscourseTagging.tag_topic_by_names(@topic, Guardian.new(Discourse.system_user), new_tags)
    end
    
    def finalize_lottery!
      @topic.update!(closed: true)
      
      # 发送实时更新
      MessageBus.publish("/lottery/#{@lottery.id}", {
        type: 'lottery_completed',
        status: @lottery.status,
        winners: @lottery.winners_data
      })
    end
  end
end
