# frozen_string_literal: true

module Jobs
  class LockLotteryPost < ::Jobs::Base
    def execute(args)
      lottery_id = args[:lottery_id]
      
      begin
        lottery = ::DiscourseLottery::Lottery.find(lottery_id)
        
        # 只锁定仍在运行且未锁定的抽奖
        unless lottery.status == 'running' && !lottery.locked?
          Rails.logger.info("跳过锁定抽奖 ID: #{lottery_id}, 状态: #{lottery.status}, 已锁定: #{lottery.locked?}")
          return
        end
        
        Rails.logger.info("开始锁定抽奖帖子 ID: #{lottery_id}")
        
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
        
        Rails.logger.info("抽奖帖子锁定完成 ID: #{lottery_id}")
        
      rescue ActiveRecord::RecordNotFound
        Rails.logger.error("抽奖记录未找到 ID: #{lottery_id}")
      rescue StandardError => e
        Rails.logger.error("锁定抽奖帖子失败 ID: #{lottery_id}, 错误: #{e.message}")
        Rails.logger.error(e.backtrace.join("\n"))
        raise e
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
