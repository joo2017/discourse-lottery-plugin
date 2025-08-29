# frozen_string_literal: true

module Jobs
  class ExecuteLotteryDraw < ::Jobs::Base
    def execute(args)
      lottery_id = args[:lottery_id]
      
      begin
        lottery = ::DiscourseLottery::Lottery.find(lottery_id)
        
        unless lottery.can_draw?
          Rails.logger.warn("尝试执行无法开奖的抽奖 ID: #{lottery_id}, 状态: #{lottery.status}")
          return
        end
        
        Rails.logger.info("开始执行抽奖 ID: #{lottery_id}, 名称: #{lottery.name}")
        
        manager = ::DiscourseLottery::LotteryManager.new(lottery)
        manager.execute_draw!
        
        Rails.logger.info("抽奖执行完成 ID: #{lottery_id}, 最终状态: #{lottery.reload.status}")
        
      rescue ActiveRecord::RecordNotFound
        Rails.logger.error("抽奖记录未找到 ID: #{lottery_id}")
      rescue StandardError => e
        Rails.logger.error("执行抽奖失败 ID: #{lottery_id}, 错误: #{e.message}")
        Rails.logger.error(e.backtrace.join("\n"))
        
        # 尝试将抽奖标记为错误状态
        begin
          lottery&.cancel_with_reason!("系统错误: #{e.message}")
        rescue StandardError => inner_e
          Rails.logger.error("标记抽奖错误状态失败: #{inner_e.message}")
        end
        
        raise e # 重新抛出异常以便Sidekiq记录
      end
    end
  end
end
