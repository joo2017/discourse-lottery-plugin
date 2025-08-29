# frozen_string_literal: true

module Jobs
  class LockLotteryPosts < ::Jobs::Scheduled
    every 5.minutes  # 每5分钟检查一次需要锁定的抽奖帖子
    
    def execute(args)
      return unless SiteSetting.lottery_enabled
      return if SiteSetting.lottery_post_lock_delay_minutes <= 0
      
      # 计算锁定时间点
      lock_delay = SiteSetting.lottery_post_lock_delay_minutes.minutes
      lock_time = Time.current - lock_delay
      
      # 查找需要锁定的抽奖活动
      lotteries_to_lock = ::DiscourseLottery::Lottery.where(
        status: 'running',
        locked: false
      ).where('created_at <= ?', lock_time)
      
      lotteries_to_lock.find_each do |lottery|
        begin
          Rails.logger.info("开始锁定抽奖帖子 ID: #{lottery.id}")
          
          # 锁定抽奖记录
          lottery.lock!
          
          # 锁定主题的第一个帖子（楼主帖）
          first_post = lottery.topic.first_post
          if first_post
            first_post.update!(locked_by_id: Discourse.system_user.id)
            Rails.logger.info("主题 #{lottery.topic_id} 的楼主帖已锁定")
          end
          
          # 发送锁定通知给楼主
          send_lock_notification(lottery)
          
          Rails.logger.info("抽奖帖子锁定完成 ID: #{lottery.id}")
          
        rescue StandardError => e
          Rails.logger.error("锁定抽奖帖子失败 ID: #{lottery.id}, 错误: #{e.message}")
          Rails.logger.error(e.backtrace.join("\n"))
        end
      end
    end
    
    private
    
    def send_lock_notification(lottery)
      return unless lottery.user.present?
      
      begin
        PostCreator.create!(
          Discourse.system_user,
          title: I18n.t('lottery.notification.post_locked_title'),
          raw: I18n.t('lottery.notification.post_locked_message',
                     lottery_name: lottery.name,
                     topic_url: lottery.topic.url),
          target_usernames: lottery.user.username,
          archetype: Archetype.private_message,
          skip_validations: true
        )
      rescue StandardError => e
        Rails.logger.error("发送锁定通知失败: #{e.message}")
      end
    end
  end
end
