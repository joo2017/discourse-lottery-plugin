# Discourse 抽奖插件

一个功能完整的 Discourse 抽奖插件，支持随机抽奖和指定楼层抽奖，具有完善的管理功能和用户友好的界面。

## 功能特性

### 🎯 核心功能
- **双模式抽奖**：支持随机抽奖和指定楼层抽奖
- **智能判断**：系统根据用户输入自动判断抽奖方式
- **精准调度**：使用 Sidekiq 实现精准的定时开奖
- **公平机制**：严格的参与者资格验证和防作弊机制
- **实时更新**：基于 MessageBus 的实时状态同步

### ⚙️ 管理功能
- **全局设置**：管理员可配置最低参与人数、锁定延迟等
- **用户组排除**：可排除特定用户组参与抽奖
- **分类限制**：可限制抽奖功能到特定分类
- **后悔期机制**：可配置的帖子锁定延迟时间
- **统计面板**：完整的抽奖统计信息

### 🎨 用户体验
- **表单验证**：前端实时验证和后端最终验证
- **响应式设计**：完美适配各种屏幕尺寸
- **多语言支持**：完整的中英文国际化
- **优雅动画**：平滑的状态转换和加载效果
- **无障碍设计**：符合无障碍标准的界面设计

## 安装方法

### 1. 使用 Git 安装（推荐）

在 Discourse 容器的 `app.yml` 文件中添加：

```yaml
hooks:
  after_code:
    - exec:
        cd: $home/plugins
        cmd:
          - git clone https://github.com/your-username/discourse-lottery-plugin.git
```

### 2. 手动安装

1. 下载插件文件到 `/var/discourse/plugins/discourse-lottery-plugin/`
2. 重建容器：`./launcher rebuild app`

## 配置说明

### 管理员设置

进入 **管理后台** → **设置** → **插件**，配置以下选项：

| 设置项 | 说明 | 默认值 |
|--------|------|--------|
| `lottery_enabled` | 启用抽奖功能 | `true` |
| `lottery_min_participants_global` | 全局最低参与人数 | `5` |
| `lottery_post_lock_delay_minutes` | 帖子锁定延迟（分钟） | `30` |
| `lottery_excluded_groups` | 排除的用户组 | `staff|moderators` |
| `lottery_categories` | 允许抽奖的分类 | 空（所有分类） |
| `lottery_max_concurrent` | 最大同时进行抽奖数 | `10` |
| `lottery_max_winner_count` | 单次最大获奖人数 | `20` |

### 表单模板配置

插件提供完整的表单模板，用户创建新主题时会自动显示抽奖表单。表单包含以下字段：

- **活动名称**（必填）：抽奖活动的标题
- **奖品说明**（必填）：详细的奖品描述
- **奖品图片**（可选）：奖品的展示图片
- **开奖时间**（必填）：自动开奖的具体时间
- **获奖人数**（必填）：随机抽奖时的获奖者数量
- **指定楼层**（可选）：指定中奖楼层，会覆盖随机抽奖
- **参与门槛**（必填）：最少参与人数要求
- **后备策略**（必填）：人数不足时的处理方式
- **补充说明**（可选）：额外的活动说明

## 使用流程

### 创建抽奖

1. 在允许的分类中点击"新建主题"
2. 填写抽奖表单的各个字段
3. 系统会进行前端实时验证
4. 发布后系统自动调度开奖任务

### 参与抽奖

1. 用户在抽奖主题下回复即可参与
2. 每个用户只能参与一次（取最早回复）
3. 楼主和被排除用户组无法参与
4. 删除或隐藏的回复不计入参与

### 自动开奖

1. 系统在预设时间自动执行开奖
2. 检查参与人数是否满足要求
3. 根据后备策略决定继续或取消
4. 自动发布开奖结果和私信通知

## 技术架构

### 后端技术栈

- **Rails Engine**：模块化架构设计
- **ActiveRecord**：数据模型和关系管理
- **Sidekiq**：定时任务和后台作业
- **MessageBus**：实时消息推送

### 前端技术栈

- **Glimmer Components**：现代化的组件系统
- **Ember.js**：响应式的数据绑定
- **SCSS**：模块化的样式管理
- **ES6+**：现代 JavaScript 特性

### 数据模型

```
lotteries (抽奖表)
├── topic_id (关联主题)
├── user_id (创建用户)
├── name (活动名称)
├── prize_description (奖品说明)
├── draw_time (开奖时间)
├── status (状态：running/finished/cancelled)
└── winners_data (中奖者数据)

lottery_participants (参与者表)
├── lottery_id (关联抽奖)
├── user_id (参与用户)
├── post_id (参与帖子)
├── floor_number (楼层号)
└── is_winner (是否中奖)
```

## 安全机制

### 数据验证
- 前端实时验证用户输入
- 后端最终验证所有参数
- 防止 SQL 注入和 XSS 攻击
- CSRF 令牌保护

### 权限控制
- 基于用户组的访问控制
- 管理员可覆盖所有限制
- 严格的编辑权限检查
- 自动锁定机制防篡改

### 防作弊机制
- 每用户仅一次参与机会
- 严格的楼层号验证
- 随机种子确保公平性
- 完整的操作日志记录

## 性能优化

### 数据库优化
- 合理的索引设计
- 预加载关联数据
- 查询结果缓存
- 分页加载大数据集

### 前端优化
- 组件懒加载
- 图片压缩和 CDN
- CSS/JS 代码分割
- 浏览器缓存策略

### 后台任务
- 异步处理耗时操作
- 任务队列负载均衡
- 失败重试机制
- 优雅降级处理

## 故障排除

### 常见问题

**Q: 抽奖创建失败**
A: 检查是否满足全局最低参与人数要求，验证开奖时间格式是否正确。

**Q: 定时开奖不执行**
A: 确认 Sidekiq 服务正常运行，检查系统时区设置是否正确。

**Q: 前端显示异常**
A: 清除浏览器缓存，检查是否有 JavaScript 错误。

### 日志查看

```bash
# 查看 Rails 日志
tail -f /var/discourse/shared/standalone/log/rails/production.log

# 查看 Sidekiq 日志
tail -f /var/discourse/shared/standalone/log/rails/sidekiq.log
```

## 开发指南

### 本地开发环境

1. 克隆 Discourse 开发环境
2. 将插件链接到 plugins 目录
3. 运行数据库迁移
4. 启动开发服务器

### 测试

```bash
# 运行所有测试
bundle exec rspec plugins/discourse-lottery-plugin/spec

# 运行特定测试
bundle exec rspec plugins/discourse-lottery-plugin/spec/models/lottery_spec.rb
```

### 贡献代码

1. Fork 本项目
2. 创建功能分支
3. 提交代码变更
4. 发起 Pull Request

## 版本历史

### v1.0.0 (2025-01-01)
- 初始版本发布
- 基础抽奖功能
- 管理员配置面板
- 完整的国际化支持

## 许可证

本项目采用 MIT 许可证 - 详见 [LICENSE](LICENSE) 文件。

## 支持

- **问题报告**：[GitHub Issues](https://github.com/your-username/discourse-lottery-plugin/issues)
- **功能请求**：[GitHub Discussions](https://github.com/your-username/discourse-lottery-plugin/discussions)
- **社区支持**：[Discourse Meta](https://meta.discourse.org)

## 致谢

感谢 Discourse 团队提供优秀的插件系统和开发文档，使得这个插件的开发成为可能。
