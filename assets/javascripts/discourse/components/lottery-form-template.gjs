import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { service } from "@ember/service";
import DButton from "discourse/components/d-button";
import TextField from "discourse/components/text-field";
import Textarea from "discourse/components/textarea";
import ComboBox from "discourse/components/combo-box";
import DateTimeInput from "discourse/components/date-time-input";
import UppyImageUploader from "discourse/components/uppy-image-uploader";
import I18n from "I18n";

export default class LotteryFormTemplate extends Component {
  @service site;
  @service siteSettings;
  
  @tracked lotteryName = "";
  @tracked prizeDescription = "";
  @tracked prizeImageUrl = "";
  @tracked drawTime = null;
  @tracked winnerCount = 1;
  @tracked specificFloors = "";
  @tracked minParticipants = this.siteSettings.lottery_min_participants_global || 5;
  @tracked backupStrategy = "continue";
  @tracked description = "";
  
  @tracked errors = {};
  @tracked isSubmitting = false;
  @tracked showSpecificFloors = false;
  
  backupStrategyOptions = [
    { id: "continue", name: I18n.t("lottery.backup_strategy.continue") },
    { id: "cancel", name: I18n.t("lottery.backup_strategy.cancel") }
  ];
  
  get globalMinParticipants() {
    return this.site.lottery_min_participants_global || 5;
  }
  
  get canSubmit() {
    return !this.isSubmitting && 
           this.lotteryName.length > 0 && 
           this.prizeDescription.length > 0 &&
           this.drawTime &&
           this.minParticipants >= this.globalMinParticipants &&
           this.winnerCount > 0 &&
           Object.keys(this.errors).length === 0;
  }
  
  @action
  validateField(field, value) {
    delete this.errors[field];
    
    switch (field) {
      case "lotteryName":
        if (!value || value.trim().length === 0) {
          this.errors[field] = I18n.t("lottery.errors.name_required");
        } else if (value.length > 255) {
          this.errors[field] = I18n.t("lottery.errors.name_too_long");
        }
        break;
        
      case "prizeDescription":
        if (!value || value.trim().length === 0) {
          this.errors[field] = I18n.t("lottery.errors.prize_required");
        }
        break;
        
      case "drawTime":
        if (!value) {
          this.errors[field] = I18n.t("lottery.errors.draw_time_required");
        } else if (new Date(value) <= new Date()) {
          this.errors[field] = I18n.t("lottery.errors.draw_time_must_be_future");
        }
        break;
        
      case "winnerCount":
        const count = parseInt(value);
        if (!count || count < 1) {
          this.errors[field] = I18n.t("lottery.errors.winner_count_invalid");
        } else if (count > this.siteSettings.lottery_max_winner_count) {
          this.errors[field] = I18n.t("lottery.errors.winner_count_too_high", 
                                   { max: this.siteSettings.lottery_max_winner_count });
        }
        break;
        
      case "minParticipants":
        const min = parseInt(value);
        if (!min || min < 1) {
          this.errors[field] = I18n.t("lottery.errors.min_participants_invalid");
        } else if (min < this.globalMinParticipants) {
          this.errors[field] = I18n.t("lottery.errors.min_participants_too_low", 
                                    { min: this.globalMinParticipants });
        }
        break;
        
      case "specificFloors":
        if (this.showSpecificFloors && value.trim()) {
          try {
            const floors = value.split(",").map(f => parseInt(f.trim())).filter(f => f > 0);
            if (floors.length === 0) {
              this.errors[field] = I18n.t("lottery.errors.specific_floors_invalid");
            } else if (floors.some(f => f <= 1)) {
              this.errors[field] = I18n.t("lottery.errors.invalid_floor_numbers");
            } else if (floors.length !== new Set(floors).size) {
              this.errors[field] = I18n.t("lottery.errors.duplicate_floor_numbers");
            }
          } catch (e) {
            this.errors[field] = I18n.t("lottery.errors.floor_format_invalid");
          }
        }
        break;
    }
    
    // 触发重新渲染
    this.errors = { ...this.errors };
  }
  
  @action
  updateLotteryName(value) {
    this.lotteryName = value;
    this.validateField("lotteryName", value);
  }
  
  @action
  updatePrizeDescription(value) {
    this.prizeDescription = value;
    this.validateField("prizeDescription", value);
  }
  
  @action
  updateDrawTime(value) {
    this.drawTime = value;
    this.validateField("drawTime", value);
  }
  
  @action
  updateWinnerCount(value) {
    this.winnerCount = parseInt(value) || 1;
    this.validateField("winnerCount", value);
  }
  
  @action
  updateMinParticipants(value) {
    this.minParticipants = parseInt(value) || 1;
    this.validateField("minParticipants", value);
  }
  
  @action
  updateSpecificFloors(value) {
    this.specificFloors = value;
    this.validateField("specificFloors", value);
    
    // 自动更新获奖人数
    if (value.trim()) {
      try {
        const floors = value.split(",").map(f => parseInt(f.trim())).filter(f => f > 0);
        if (floors.length > 0) {
          this.winnerCount = floors.length;
        }
      } catch (e) {
        // 忽略解析错误
      }
    }
  }
  
  @action
  toggleSpecificFloors() {
    this.showSpecificFloors = !this.showSpecificFloors;
    if (!this.showSpecificFloors) {
      this.specificFloors = "";
      delete this.errors.specificFloors;
    }
  }
  
  @action
  handleImageUpload(upload) {
    this.prizeImageUrl = upload.url;
  }
  
  @action
  handleImageRemove() {
    this.prizeImageUrl = "";
  }
  
  @action
  submitForm() {
    if (!this.canSubmit) return;
    
    this.isSubmitting = true;
    
    // 构建表单数据
    const formData = {
      is_lottery: true,
      lottery_name: this.lotteryName,
      lottery_prize: this.prizeDescription,
      lottery_prize_image: this.prizeImageUrl,
      lottery_draw_time: this.drawTime,
      lottery_winner_count: this.winnerCount,
      lottery_specific_floors: this.showSpecificFloors ? this.specificFloors : "",
      lottery_min_participants: this.minParticipants,
      lottery_backup_strategy: this.backupStrategy,
      lottery_description: this.description
    };
    
    // 调用父组件的提交方法
    this.args.onSubmit?.(formData);
  }

  <template>
    <div class="lottery-form-template">
      <div class="form-section">
        <h3>{{I18n "lottery.form.title"}}</h3>
        <p class="form-description">{{I18n "lottery.form.description"}}</p>
      </div>
      
      <div class="form-group">
        <label class="form-label required">{{I18n "lottery.form.lottery_name"}}</label>
        <TextField 
          @value={{this.lotteryName}}
          @input={{this.updateLotteryName}}
          @placeholder={{I18n "lottery.form.lottery_name_placeholder"}}
          class={{if this.errors.lotteryName "error"}}
        />
        {{#if this.errors.lotteryName}}
          <div class="form-error">{{this.errors.lotteryName}}</div>
        {{/if}}
      </div>
      
      <div class="form-group">
        <label class="form-label required">{{I18n "lottery.form.prize_description"}}</label>
        <Textarea 
          @value={{this.prizeDescription}}
          @input={{this.updatePrizeDescription}}
          @placeholder={{I18n "lottery.form.prize_description_placeholder"}}
          class={{if this.errors.prizeDescription "error"}}
        />
        {{#if this.errors.prizeDescription}}
          <div class="form-error">{{this.errors.prizeDescription}}</div>
        {{/if}}
      </div>
      
      <div class="form-group">
        <label class="form-label">{{I18n "lottery.form.prize_image"}}</label>
        <UppyImageUploader
          @id="lottery-prize-image"
          @imageUrl={{this.prizeImageUrl}}
          @onUpload={{this.handleImageUpload}}
          @onRemove={{this.handleImageRemove}}
        />
      </div>
      
      <div class="form-group">
        <label class="form-label required">{{I18n "lottery.form.draw_time"}}</label>
        <DateTimeInput 
          @date={{this.drawTime}}
          @onChange={{this.updateDrawTime}}
          class={{if this.errors.drawTime "error"}}
        />
        {{#if this.errors.drawTime}}
          <div class="form-error">{{this.errors.drawTime}}</div>
        {{/if}}
      </div>
      
      <div class="form-row">
        <div class="form-group half">
          <label class="form-label required">{{I18n "lottery.form.winner_count"}}</label>
          <TextField 
            @value={{this.winnerCount}}
            @input={{this.updateWinnerCount}}
            @type="number"
            @min="1"
            @max={{this.siteSettings.lottery_max_winner_count}}
            class={{if this.errors.winnerCount "error"}}
            disabled={{this.showSpecificFloors}}
          />
          <div class="form-hint">{{I18n "lottery.form.winner_count_hint"}}</div>
          {{#if this.errors.winnerCount}}
            <div class="form-error">{{this.errors.winnerCount}}</div>
          {{/if}}
        </div>
        
        <div class="form-group half">
          <label class="form-label required">{{I18n "lottery.form.min_participants"}}</label>
          <TextField 
            @value={{this.minParticipants}}
            @input={{this.updateMinParticipants}}
            @type="number"
            @min={{this.globalMinParticipants}}
            class={{if this.errors.minParticipants "error"}}
          />
          <div class="form-hint">{{I18n "lottery.form.min_participants_hint" min=this.globalMinParticipants}}</div>
          {{#if this.errors.minParticipants}}
            <div class="form-error">{{this.errors.minParticipants}}</div>
          {{/if}}
        </div>
      </div>
      
      <div class="form-group">
        <div class="form-checkbox">
          <input 
            type="checkbox" 
            id="specific-floors-toggle"
            checked={{this.showSpecificFloors}}
            {{on "change" this.toggleSpecificFloors}}
          />
          <label for="specific-floors-toggle">
            {{I18n "lottery.form.use_specific_floors"}}
          </label>
        </div>
        <div class="form-hint">{{I18n "lottery.form.specific_floors_hint"}}</div>
      </div>
      
      {{#if this.showSpecificFloors}}
        <div class="form-group">
          <label class="form-label">{{I18n "lottery.form.specific_floors"}}</label>
          <TextField 
            @value={{this.specificFloors}}
            @input={{this.updateSpecificFloors}}
            @placeholder={{I18n "lottery.form.specific_floors_placeholder"}}
            class={{if this.errors.specificFloors "error"}}
          />
          <div class="form-hint">{{I18n "lottery.form.specific_floors_description"}}</div>
          {{#if this.errors.specificFloors}}
            <div class="form-error">{{this.errors.specificFloors}}</div>
          {{/if}}
        </div>
      {{/if}}
      
      <div class="form-group">
        <label class="form-label required">{{I18n "lottery.form.backup_strategy"}}</label>
        <ComboBox 
          @value={{this.backupStrategy}}
          @content={{this.backupStrategyOptions}}
          @onChange={{fn (mut this.backupStrategy)}}
        />
        <div class="form-hint">{{I18n "lottery.form.backup_strategy_hint"}}</div>
      </div>
      
      <div class="form-group">
        <label class="form-label">{{I18n "lottery.form.additional_description"}}</label>
        <Textarea 
          @value={{this.description}}
          @input={{fn (mut this.description)}}
          @placeholder={{I18n "lottery.form.additional_description_placeholder"}}
        />
      </div>
      
      <div class="form-actions">
        <DButton 
          @class="btn-primary lottery-submit-btn"
          @action={{this.submitForm}}
          @disabled={{not this.canSubmit}}
          @isLoading={{this.isSubmitting}}
          @icon="gift"
          @label="lottery.form.create_lottery"
        />
      </div>
    </div>
  </template>
}
