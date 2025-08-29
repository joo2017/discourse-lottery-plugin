# frozen_string_literal: true

module Jobs
  class ExecuteLotteryDraw < ::Jobs::Scheduled
    every 1.minute  # 每分钟检查一次待开奖的活动
    
    def execute(args)
      return unless SiteSetting.lottery_enabled
      
      # 查找需要开奖的抽奖活动
      pending_lotteries = ::DiscourseLottery::Lottery.where(
        status: 'running'
      ).where('draw_time <= ?', Time.current)
      
      pending_lotteries.find_each do |lottery|
        begin
          Rails.logger.info("开始执行抽奖 ID: #{lottery.id}, 名称: #{lottery.name}")
          
          manager = ::DiscourseLottery::LotteryManager.new(lottery)
          manager.execute_draw!
          
          Rails.logger.info("抽奖执行完成 ID: #{lottery.id}, 最终状态: #{lottery.reload.status}")
          
        rescue StandardError => e
          Rails.logger.error("执行抽奖失败 ID: #{lottery.id}, 错误: #{e.message}")
          Rails.logger.error(e.backtrace.join("\n"))
          
          # 尝试将抽奖标记为错误状态
          begin
            lottery.cancel_with_reason!("系统错误: #{e.message}")
          rescue StandardError => inner_e
            Rails.logger.error("标记抽奖错误状态失败: #{inner_e.message}")
          end
        end
      end
    end
  end
end
