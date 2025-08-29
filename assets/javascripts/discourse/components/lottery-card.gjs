import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { service } from "@ember/service";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import DButton from "discourse/components/d-button";
import UserLink from "discourse/components/user-link";
import { htmlSafe } from "@ember/template";
import I18n from "I18n";

export default class LotteryCard extends Component {
  @service messageBus;
  @service currentUser;
  
  @tracked lottery = null;
  @tracked participants = [];
  @tracked loading = true;
  @tracked timeRemaining = "";
  @tracked showParticipants = false;
  
  constructor() {
    super(...arguments);
    this.loadLotteryData();
    this.startTimeUpdater();
    this.subscribeToUpdates();
  }
  
  willDestroy() {
    super.willDestroy();
    this.cleanup();
  }
  
  @action
  async loadLotteryData() {
    try {
      const response = await ajax(`/lottery/${this.args.topicId}`);
      this.lottery = response;
      this.loading = false;
    } catch (error) {
      console.error("加载抽奖数据失败:", error);
      this.loading = false;
    }
  }
  
  @action
  async toggleParticipants() {
    if (!this.showParticipants && this.participants.length === 0) {
      await this.loadParticipants();
    }
    this.showParticipants = !this.showParticipants;
  }
  
  @action
  async loadParticipants() {
    try {
      const response = await ajax(`/lottery/${this.lottery.id}/participants`);
      this.participants = response.participants || [];
    } catch (error) {
      popupAjaxError(error);
    }
  }
  
  @action
  async cancelLottery() {
    if (!confirm(I18n.t("lottery.confirm_cancel"))) {
      return;
    }
    
    try {
      await ajax(`/lottery/${this.lottery.id}/cancel`, { type: "POST" });
      this.lottery.status = "cancelled";
      this.lottery.can_cancel = false;
    } catch (error) {
      popupAjaxError(error);
    }
  }
  
  startTimeUpdater() {
    this.timeUpdateInterval = setInterval(() => {
      this.updateTimeRemaining();
    }, 1000);
  }
  
  updateTimeRemaining() {
    if (!this.lottery || this.lottery.status !== "running") {
      this.timeRemaining = "";
      return;
    }
    
    const drawTime = new Date(this.lottery.draw_time);
    const now = new Date();
    const timeDiff = drawTime - now;
    
    if (timeDiff <= 0) {
      this.timeRemaining = I18n.t("lottery.drawing_now");
      return;
    }
    
    const days = Math.floor(timeDiff / (1000 * 60 * 60 * 24));
    const hours = Math.floor((timeDiff % (1000 * 60 * 60 * 24)) / (1000 * 60 * 60));
    const minutes = Math.floor((timeDiff % (1000 * 60 * 60)) / (1000 * 60));
    const seconds = Math.floor((timeDiff % (1000 * 60)) / 1000);
    
    let timeStr = "";
    if (days > 0) timeStr += `${days}天 `;
    if (hours > 0) timeStr += `${hours}小时 `;
    if (minutes > 0) timeStr += `${minutes}分钟 `;
    if (seconds > 0) timeStr += `${seconds}秒`;
    
    this.timeRemaining = timeStr || "即将开奖";
  }
  
  subscribeToUpdates() {
    if (this.lottery?.id) {
      this.messageBus.subscribe(`/lottery/${this.lottery.id}`, (data) => {
        if (data.type === "lottery_completed") {
          this.lottery.status = data.status;
          this.lottery.winners_data = data.winners;
          this.timeRemaining = "";
        }
      });
    }
  }
  
  cleanup() {
    if (this.timeUpdateInterval) {
      clearInterval(this.timeUpdateInterval);
    }
    if (this.lottery?.id) {
      this.messageBus.unsubscribe(`/lottery/${this.lottery.id}`);
    }
  }
  
  get statusClass() {
    const status = this.lottery?.status || "unknown";
    return `lottery-status lottery-status-${status}`;
  }
  
  get statusText() {
    const status = this.lottery?.status || "unknown";
    return I18n.t(`lottery.status.${status}`);
  }
  
  get canShowParticipants() {
    return this.lottery && ["running", "finished", "cancelled"].includes(this.lottery.status);
  }
  
  get winnersList() {
    if (!this.lottery?.winners_data) return [];
    
    return this.lottery.winners_data.map(winner => ({
      username: winner.username,
      floor: winner.floor_number,
      avatar_template: winner.avatar_template
    }));
  }

  <template>
    <div class="lottery-card">
      {{#if this.loading}}
        <div class="lottery-loading">
          <div class="spinner"></div>
          <span>{{I18n "lottery.loading"}}</span>
        </div>
      {{else if this.lottery}}
        <div class="lottery-header">
          <div class="lottery-title">
            <h3>🎁 {{this.lottery.name}}</h3>
            <span class={{this.statusClass}}>{{this.statusText}}</span>
          </div>
          
          {{#if this.lottery.locked}}
            <div class="lottery-locked">
              <span class="lock-icon">🔒</span>
              <span>{{I18n "lottery.locked"}}</span>
            </div>
          {{/if}}
        </div>
        
        <div class="lottery-content">
          <div class="lottery-prize">
            <strong>{{I18n "lottery.prize"}}:</strong> 
            {{this.lottery.prize_description}}
          </div>
          
          {{#if this.lottery.prize_image_url}}
            <div class="lottery-prize-image">
              <img src={{this.lottery.prize_image_url}} alt="奖品图片" />
            </div>
          {{/if}}
          
          <div class="lottery-info">
            <div class="lottery-detail">
              <strong>{{I18n "lottery.draw_method"}}:</strong>
              {{#if (eq this.lottery.draw_method "random")}}
                {{I18n "lottery.method.random"}} ({{this.lottery.winner_count}}{{I18n "lottery.winners"}})
              {{else}}
                {{I18n "lottery.method.specific"}} ({{this.lottery.specific_floors_display}})
              {{/if}}
            </div>
            
            <div class="lottery-detail">
              <strong>{{I18n "lottery.min_participants"}}:</strong> 
              {{this.lottery.min_participants}}{{I18n "lottery.people"}}
            </div>
            
            <div class="lottery-detail">
              <strong>{{I18n "lottery.current_participants"}}:</strong> 
              {{this.lottery.effective_participants_count}}{{I18n "lottery.people"}}
            </div>
            
            {{#if (eq this.lottery.status "running")}}
              <div class="lottery-detail lottery-time">
                <strong>{{I18n "lottery.time_remaining"}}:</strong>
                <span class="time-countdown">{{this.timeRemaining}}</span>
              </div>
            {{/if}}
            
            {{#if this.lottery.description}}
              <div class="lottery-description">
                <strong>{{I18n "lottery.description"}}:</strong>
                <div class="description-content">
                  {{htmlSafe this.lottery.description}}
                </div>
              </div>
            {{/if}}
          </div>
          
          {{#if (eq this.lottery.status "finished")}}
            <div class="lottery-winners">
              <h4>🏆 {{I18n "lottery.congratulations"}}</h4>
              <div class="winners-list">
                {{#each this.winnersList as |winner|}}
                  <div class="winner-item">
                    <UserLink @user={{winner}} />
                    <span class="winner-floor">({{winner.floor}}楼)</span>
                  </div>
                {{/each}}
              </div>
            </div>
          {{/if}}
          
          {{#if (eq this.lottery.status "cancelled")}}
            <div class="lottery-cancelled">
              <span class="cancel-icon">❌</span>
              <span>{{I18n "lottery.cancelled_message"}}</span>
            </div>
          {{/if}}
        </div>
        
        <div class="lottery-actions">
          {{#if this.canShowParticipants}}
            <DButton 
              @class="btn-default lottery-participants-btn"
              @action={{this.toggleParticipants}}
              @icon="users"
              @label={{if this.showParticipants "lottery.hide_participants" "lottery.show_participants"}}
            />
          {{/if}}
          
          {{#if this.lottery.can_cancel}}
            <DButton 
              @class="btn-danger lottery-cancel-btn"
              @action={{this.cancelLottery}}
              @icon="times"
              @label="lottery.cancel_lottery"
            />
          {{/if}}
        </div>
        
        {{#if this.showParticipants}}
          <div class="lottery-participants-list">
            <h4>{{I18n "lottery.participants_list"}} ({{this.participants.length}})</h4>
            {{#if this.participants.length}}
              <div class="participants-grid">
                {{#each this.participants as |participant|}}
                  <div class="participant-item {{if participant.is_winner 'is-winner'}}">
                    <UserLink @user={{participant}} />
                    <span class="participant-floor">{{participant.floor_number}}楼</span>
                    {{#if participant.is_winner}}
                      <span class="winner-badge">🏆</span>
                    {{/if}}
                  </div>
                {{/each}}
              </div>
            {{else}}
              <div class="no-participants">
                {{I18n "lottery.no_participants"}}
              </div>
            {{/if}}
          </div>
        {{/if}}
        
      {{else}}
        <div class="lottery-error">
          <span>{{I18n "lottery.load_error"}}</span>
        </div>
      {{/if}}
    </div>
  </template>
}
