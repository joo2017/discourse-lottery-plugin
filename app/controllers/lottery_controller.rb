# frozen_string_literal: true

module DiscourseLottery
  class LotteryController < ::ApplicationController
    requires_plugin 'discourse-lottery-plugin'
    
    before_action :ensure_logged_in
    before_action :ensure_lottery_enabled
    before_action :find_lottery, only: [:show, :participants, :cancel]
    
    def show
      render json: LotterySerializer.new(@lottery)
    end
    
    def participants
      participants = @lottery.participants
                            .includes(:user, :post)
                            .order(:floor_number)
      
      render json: {
        participants: participants.map do |p|
          {
            id: p.id,
            username: p.user.username,
            floor_number: p.floor_number,
            participated_at: p.participated_at,
            is_winner: p.is_winner,
            avatar_template: p.user.avatar_template
          }
        end,
        total_count: participants.count,
        winners_count: participants.where(is_winner: true).count
      }
    end
    
    def cancel
      unless can_cancel_lottery?
        render json: { error: I18n.t('lottery.errors.cannot_cancel') }, status: 403
        return
      end
      
      begin
        @lottery.cancel_with_reason!(I18n.t('lottery.cancellation.cancelled_by_user'))
        
        # 发布取消公告
        PostCreator.create!(
          current_user,
          topic_id: @lottery.topic_id,
          raw: I18n.t('lottery.announcement.user_cancelled', lottery_name: @lottery.name),
          skip_validations: true
        )
        
        # 更新标签
        update_topic_tags(@lottery.topic, '已取消')
        
        render json: { success: true, message: I18n.t('lottery.success.cancelled') }
      rescue StandardError => e
        render json: { error: e.message }, status: 422
      end
    end
    
    def stats
      running_count = Lottery.running.count
      finished_count = Lottery.finished.count
      cancelled_count = Lottery.cancelled.count
      
      render json: {
        running: running_count,
        finished: finished_count,
        cancelled: cancelled_count,
        total: running_count + finished_count + cancelled_count
      }
    end
    
    private
    
    def ensure_lottery_enabled
      unless SiteSetting.lottery_enabled
        render json: { error: I18n.t('lottery.errors.disabled') }, status: 403
      end
    end
    
    def find_lottery
      @lottery = Lottery.find(params[:id])
    rescue ActiveRecord::RecordNotFound
      render json: { error: I18n.t('lottery.errors.not_found') }, status: 404
    end
    
    def can_cancel_lottery?
      return false unless @lottery.status == 'running'
      return false if @lottery.locked?
      
      # 只有楼主和管理员可以取消
      current_user.id == @lottery.user_id || current_user.staff?
    end
    
    def update_topic_tags(topic, new_tag)
      current_tags = topic.tags.pluck(:name) - ['抽奖中']
      new_tags = current_tags + [new_tag]
      DiscourseTagging.tag_topic_by_names(topic, Guardian.new(current_user), new_tags)
    end
  end
end
