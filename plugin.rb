# frozen_string_literal: true

# name: discourse-lottery-plugin
# about: 高级抽奖插件，支持随机抽奖和指定楼层抽奖
# version: 1.0.0
# authors: 论坛管理员
# url: https://github.com/discourse/discourse-lottery-plugin
# required_version: 3.3.0
# transpile_js: true

gem 'sidekiq-mini_scheduler', '0.16.1', require: false

enabled_site_setting :lottery_enabled

register_asset 'stylesheets/lottery.scss'
register_asset 'javascripts/components/lottery-card.gjs'
register_asset 'javascripts/components/lottery-admin-panel.gjs'

after_initialize do
  module ::DiscourseLottery
    PLUGIN_NAME = "discourse-lottery-plugin"
    
    class Engine < ::Rails::Engine
      engine_name PLUGIN_NAME
      isolate_namespace DiscourseLottery
    end
  end
  
  # 加载模型
  require_dependency File.expand_path('../app/models/lottery', __FILE__)
  require_dependency File.expand_path('../app/models/lottery_participant', __FILE__)
  
  # 加载服务
  require_dependency File.expand_path('../app/services/lottery_creator', __FILE__)
  require_dependency File.expand_path('../app/services/lottery_manager', __FILE__)
  require_dependency File.expand_path('../app/services/lottery_validator', __FILE__)
  
  # 加载控制器
  require_dependency File.expand_path('../app/controllers/lottery_controller', __FILE__)
  
  # 加载作业
  require_dependency File.expand_path('../app/jobs/execute_lottery_draw', __FILE__)
  require_dependency File.expand_path('../app/jobs/lock_lottery_post', __FILE__)
  
  # 加载序列化器
  require_dependency File.expand_path('../app/serializers/lottery_serializer', __FILE__)
  
  # 注册路由
  Discourse::Application.routes.append do
    mount ::DiscourseLottery::Engine, at: "/lottery"
  end
  
  # 扩展Topic序列化器
  add_to_serializer(:topic_view, :lottery_info) do
    if object.topic.custom_fields['is_lottery'] == 'true'
      lottery = ::DiscourseLottery::Lottery.find_by(topic_id: object.topic.id)
      if lottery
        ::DiscourseLottery::LotterySerializer.new(lottery, root: false)
      end
    end
  end
  
  # 监听主题创建事件
  DiscourseEvent.on(:topic_created) do |topic, opts, user|
    if topic.custom_fields['is_lottery'] == 'true'
      ::DiscourseLottery::LotteryCreator.new(topic, user).call
    end
  end
  
  # 监听帖子编辑事件
  DiscourseEvent.on(:post_edited) do |post, topic_changed, user|
    if post.post_number == 1 && post.topic.custom_fields['is_lottery'] == 'true'
      lottery = ::DiscourseLottery::Lottery.find_by(topic_id: post.topic_id)
      if lottery && lottery.status == 'running' && !lottery.locked?
        ::DiscourseLottery::LotteryCreator.new(post.topic, user, editing: true).call
      end
    end
  end
  
  # 注册自定义字段
  Topic.register_custom_field_type('is_lottery', :boolean)
  Topic.register_custom_field_type('lottery_name', :string)
  Topic.register_custom_field_type('lottery_prize', :string)
  Topic.register_custom_field_type('lottery_prize_image', :string)
  Topic.register_custom_field_type('lottery_draw_time', :string)
  Topic.register_custom_field_type('lottery_winner_count', :integer)
  Topic.register_custom_field_type('lottery_specific_floors', :string)
  Topic.register_custom_field_type('lottery_min_participants', :integer)
  Topic.register_custom_field_type('lottery_backup_strategy', :string)
  Topic.register_custom_field_type('lottery_description', :text)
  
  # 预加载自定义字段
  Topic.preload_custom_fields << 'is_lottery'
  Topic.preload_custom_fields << 'lottery_name'
  Topic.preload_custom_fields << 'lottery_prize'
  Topic.preload_custom_fields << 'lottery_draw_time'
  Topic.preload_custom_fields << 'lottery_status'
  
  # 添加全局设置到客户端
  add_to_serializer(:site, :lottery_min_participants_global) do
    SiteSetting.lottery_min_participants_global
  end
end
