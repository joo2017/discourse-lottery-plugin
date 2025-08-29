# frozen_string_literal: true

module DiscourseLottery
  class LotteryCreator
    include Service
    
    def initialize(topic, user, editing: false)
      @topic = topic
      @user = user
      @editing = editing
    end
    
    def call
      return failure(I18n.t('lottery.errors.disabled')) unless lottery_enabled?
      
      begin
        ActiveRecord::Base.transaction do
          validate_basic_requirements!
          extract_lottery_data!
          validate_lottery_data!
          
          if @editing
            update_existing_lottery!
          else
            create_new_lottery!
          end
          
          schedule_jobs!
          handle_immediate_lock!
          add_lottery_tag!
        end
        
        success(I18n.t('lottery.success.created'))
      rescue StandardError => e
        handle_error(e)
        failure(e.message)
      end
    end
    
    private
    
    attr_reader :topic, :user, :editing
    
    def lottery_enabled?
      SiteSetting.lottery_enabled
    end
    
    def validate_basic_requirements!
      validator = LotteryValidator.new(@topic.custom_fields)
      unless validator.valid?
        errors = validator.errors.full_messages.join(', ')
        post_error_message(errors)
        raise StandardError, errors
      end
    end
    
    def extract_lottery_data!
      fields = @topic.custom_fields
      
      @lottery_data = {
        name: fields['lottery_name'],
        prize_description: fields['lottery_prize'],
        prize_image_url: fields['lottery_prize_image'],
        draw_time: parse_draw_time(fields['lottery_draw_time']),
        winner_count: fields['lottery_winner_count'].to_i,
        specific_floors: fields['lottery_specific_floors'],
        min_participants: fields['lottery_min_participants'].to_i,
        backup_strategy: fields['lottery_backup_strategy'],
        description: fields['lottery_description']
      }
      
      # 智能判断抽奖方式
      if @lottery_data[:specific_floors].present?
        @lottery_data[:draw_method] = 'specific'
        floors = parse_specific_floors(@lottery_data[:specific_floors])
        @lottery_data[:winner_count] = floors.length
      else
        @lottery_data[:draw_method] = 'random'
      end
    end
    
    def validate_lottery_data!
      # 验证全局最小参与人数
      global_min = SiteSetting.lottery_min_participants_global
      if @lottery_data[:min_participants] < global_min
        raise StandardError, I18n.t('lottery.errors.min_participants_too_low', min: global_min)
      end
      
      # 验证开奖时间
      if @lottery_data[:draw_time] <= Time.current
        raise StandardError, I18n.t('lottery.errors.draw_time_must_be_future')
      end
      
      # 验证获奖人数
      max_winners = SiteSetting.lottery_max_winner_count
      if @lottery_data[:winner_count] > max_winners
        raise StandardError, I18n.t('lottery.errors.winner_count_too_high', max: max_winners)
      end
    end
    
    def create_new_lottery!
      @lottery = Lottery.create!(
        topic: @topic,
        user: @user,
        **@lottery_data
      )
    end
    
    def update_existing_lottery!
      @lottery = Lottery.find_by!(topic: @topic)
      @lottery.update!(@lottery_data)
    end
    
    def schedule_jobs!
      # 现在使用定时任务，不需要手动调度特定任务
      # 定时任务会自动检查和处理到期的抽奖
      Rails.logger.info("抽奖 ID: #{@lottery.id} 将由定时任务在开奖时间自动处理")
    end
    
    def handle_immediate_lock!
      # 如果延迟时间为0，立即锁定
      lock_delay = SiteSetting.lottery_post_lock_delay_minutes
      if lock_delay <= 0 && !@editing
        @lottery.lock!
        
        # 锁定主题的第一个帖子
        first_post = @lottery.topic.first_post
        if first_post
          first_post.update!(locked_by_id: Discourse.system_user.id)
        end
        
        Rails.logger.info("抽奖 ID: #{@lottery.id} 已立即锁定")
      end
    end
    
    def add_lottery_tag!
      DiscourseTagging.tag_topic_by_names(@topic, Guardian.new(@user), ['抽奖中'])
    end
    
    def post_error_message(error_message)
      PostCreator.create!(
        Discourse.system_user,
        topic_id: @topic.id,
        raw: I18n.t('lottery.errors.creation_failed', 
                    error: error_message, 
                    username: @user.username),
        skip_validations: true
      )
    end
    
    def parse_draw_time(time_string)
      return Time.current + 1.day unless time_string.present?
      
      begin
        Time.zone.parse(time_string)
      rescue ArgumentError
        raise StandardError, I18n.t('lottery.errors.invalid_draw_time')
      end
    end
    
    def parse_specific_floors(floors_string)
      return [] unless floors_string.present?
      
      floors_string.split(',').map(&:strip).map(&:to_i).reject(&:zero?)
    end
    
    def handle_error(error)
      Rails.logger.error("抽奖创建失败: #{error.message}")
      Rails.logger.error(error.backtrace.join("\n"))
      
      post_error_message(error.message) unless @editing
    end
    
    def success(message)
      OpenStruct.new(success?: true, message: message)
    end
    
    def failure(message)
      OpenStruct.new(success?: false, message: message)
    end
  end
end
