import { withPluginApi } from "discourse/lib/plugin-api";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";

function initializeLotteryPlugin(api) {
  // 在主题视图中插入抽奖卡片
  api.includePostAttributes("lottery_info");
  
  // 装饰帖子以显示抽奖信息
  api.decorateWidget("post:before", (dec) => {
    const post = dec.getModel();
    if (post && post.get("firstPost") && post.get("topic.lottery_info")) {
      return dec.widget.attach("lottery-card", {
        topicId: post.get("topic.id"),
        lotteryInfo: post.get("topic.lottery_info")
      });
    }
  });
  
  // 为新建主题表单添加验证
  api.modifyClass("controller:composer", {
    pluginId: "discourse-lottery-plugin",
    
    _validateLotteryFields() {
      const model = this.model;
      if (!model || !model.metaData || !model.metaData.is_lottery) {
        return true;
      }
      
      const fields = model.metaData;
      const errors = [];
      
      // 验证必填字段
      if (!fields.lottery_name?.trim()) {
        errors.push("活动名称不能为空");
      }
      
      if (!fields.lottery_prize?.trim()) {
        errors.push("奖品说明不能为空");
      }
      
      if (!fields.lottery_draw_time) {
        errors.push("开奖时间不能为空");
      } else {
        const drawTime = new Date(fields.lottery_draw_time);
        if (drawTime <= new Date()) {
          errors.push("开奖时间必须是未来时间");
        }
      }
      
      // 验证获奖人数
      const winnerCount = parseInt(fields.lottery_winner_count);
      if (!winnerCount || winnerCount < 1) {
        errors.push("获奖人数必须大于0");
      }
      
      // 验证最小参与人数
      const minParticipants = parseInt(fields.lottery_min_participants);
      const globalMin = this.siteSettings.lottery_min_participants_global || 5;
      if (!minParticipants || minParticipants < globalMin) {
        errors.push(`最少参与人数不能低于 ${globalMin} 人`);
      }
      
      // 验证指定楼层格式
      if (fields.lottery_specific_floors?.trim()) {
        try {
          const floors = fields.lottery_specific_floors
            .split(",")
            .map(f => parseInt(f.trim()))
            .filter(f => f > 0);
          
          if (floors.length === 0) {
            errors.push("指定楼层格式无效");
          } else if (floors.some(f => f <= 1)) {
            errors.push("楼层号必须大于1");
          } else if (floors.length !== new Set(floors).size) {
            errors.push("楼层号不能重复");
          }
        } catch (e) {
          errors.push("楼层号格式错误");
        }
      }
      
      if (errors.length > 0) {
        this.dialog.alert(errors.join("\n"));
        return false;
      }
      
      return true;
    },
    
    save(opts = {}) {
      if (!this._validateLotteryFields()) {
        return Promise.resolve();
      }
      return this._super(opts);
    }
  });
  
  // 添加抽奖统计信息到管理员面板
  api.modifyClass("route:admin-dashboard", {
    pluginId: "discourse-lottery-plugin",
    
    async setupController(controller, model) {
      this._super(controller, model);
      
      try {
        const lotteryStats = await ajax("/lottery/stats");
        controller.set("lotteryStats", lotteryStats);
      } catch (error) {
        console.error("获取抽奖统计失败:", error);
      }
    }
  });
  
  // 为管理员添加快捷操作按钮
  api.addPostAdminMenuButton((attrs) => {
    const post = attrs.post;
    if (post && post.firstPost && post.topic?.lottery_info) {
      return {
        action: "manageLottery",
        icon: "gift",
        label: "lottery.admin.manage",
        condition: attrs.canManage
      };
    }
  });
  
  // 处理管理员抽奖操作
  api.modifyClass("controller:topic", {
    pluginId: "discourse-lottery-plugin",
    
    actions: {
      async manageLottery() {
        const topic = this.model;
        const lotteryInfo = topic.lottery_info;
        
        if (!lotteryInfo) return;
        
        // 这里可以打开管理对话框或跳转到管理页面
        this.router.transitionTo("admin.plugins.lottery", lotteryInfo.id);
      }
    }
  });
  
  // 实时更新抽奖状态
  api.onAppEvent("topic:current-post-changed", (data) => {
    const topic = data.topic;
    if (topic?.lottery_info) {
      // 订阅抽奖状态更新
      const messageBus = api.container.lookup("service:message-bus");
      messageBus.subscribe(`/lottery/${topic.lottery_info.id}`, (message) => {
        if (message.type === "lottery_completed") {
          // 更新页面显示
          topic.set("lottery_info.status", message.status);
          topic.set("lottery_info.winners_data", message.winners);
          
          // 触发重新渲染
          api.appEvents.trigger("post-stream:refresh");
        }
      });
    }
  });
  
  // 添加抽奖相关的路由
  api.addRoute("admin.plugins.lottery", {
    path: "/admin/plugins/lottery/:id",
    model(params) {
      return ajax(`/lottery/${params.id}`);
    }
  });
}

export default {
  name: "lottery-plugin",
  
  initialize(container) {
    const siteSettings = container.lookup("service:site-settings");
    
    if (!siteSettings.lottery_enabled) {
      return;
    }
    
    withPluginApi("1.8.0", initializeLotteryPlugin);
  }
};
