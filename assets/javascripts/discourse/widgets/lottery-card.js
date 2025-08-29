import { createWidget } from "discourse/widgets/widget";
import { h } from "virtual-dom";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import I18n from "I18n";

export default createWidget("lottery-card", {
  tagName: "div.lottery-card",
  
  buildKey: (attrs) => `lottery-card-${attrs.topicId}`,
  
  defaultState() {
    return {
      loading: true,
      lottery: null,
      timeRemaining: "",
      showParticipants: false,
      participants: []
    };
  },
  
  didMount() {
    this.loadLotteryData();
    this.startTimer();
  },
  
  willReopenWidget() {
    this.startTimer();
  },
  
  willRemoveWidget() {
    this.stopTimer();
  },
  
  async loadLotteryData() {
    try {
      const response = await ajax(`/lottery/${this.attrs.topicId}`);
      this.state.lottery = response;
      this.state.loading = false;
      this.scheduleRerender();
    } catch (error) {
      console.error("加载抽奖数据失败:", error);
      this.state.loading = false;
      this.scheduleRerender();
    }
  },
  
  startTimer() {
    if (this.state.lottery?.status === "running") {
      this.timer = setInterval(() => {
        this.updateTimeRemaining();
        this.scheduleRerender();
      }, 1000);
    }
  },
  
  stopTimer() {
    if (this.timer) {
      clearInterval(this.timer);
      this.timer = null;
    }
  },
  
  updateTimeRemaining() {
    if (!this.state.lottery || this.state.lottery.status !== "running") {
      this.state.timeRemaining = "";
      return;
    }
    
    const drawTime = new Date(this.state.lottery.draw_time);
    const now = new Date();
    const timeDiff = drawTime - now;
    
    if (timeDiff <= 0) {
      this.state.timeRemaining = I18n.t("lottery.drawing_now");
      this.stopTimer();
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
    
    this.state.timeRemaining = timeStr || "即将开奖";
  },
  
  async toggleParticipants() {
    if (!this.state.showParticipants && this.state.participants.length === 0) {
      await this.loadParticipants();
    }
    this.state.showParticipants = !this.state.showParticipants;
    this.scheduleRerender();
  },
  
  async loadParticipants() {
    try {
      const response = await ajax(`/lottery/${this.state.lottery.id}/participants`);
      this.state.participants = response.participants || [];
    } catch (error) {
      popupAjaxError(error);
    }
  },
  
  async cancelLottery() {
    if (!confirm(I18n.t("lottery.confirm_cancel"))) {
      return;
    }
    
    try {
      await ajax(`/lottery/${this.state.lottery.id}/cancel`, { type: "POST" });
      this.state.lottery.status = "cancelled";
      this.state.lottery.can_cancel = false;
      this.scheduleRerender();
    } catch (error) {
      popupAjaxError(error);
    }
  },
  
  buildLoadingState() {
    return h("div.lottery-loading", [
      h("div.spinner"),
      h("span", I18n.t("lottery.loading"))
    ]);
  },
  
  buildErrorState() {
    return h("div.lottery-error", [
      h("span", I18n.t("lottery.load_error"))
    ]);
  },
  
  buildStatusBadge(status) {
    const statusClass = `lottery-status lottery-status-${status}`;
    return h(`span.${statusClass}`, I18n.t(`lottery.status.${status}`));
  },
  
  buildHeader() {
    const { lottery } = this.state;
    
    return h("div.lottery-header", [
      h("div.lottery-title", [
        h("h3", `🎁 ${lottery.name}`),
        this.buildStatusBadge(lottery.status)
      ]),
      lottery.locked && h("div.lottery-locked", [
        h("span.lock-icon", "🔒"),
        h("span", I18n.t("lottery.locked"))
      ])
    ]);
  },
  
  buildPrizeInfo() {
    const { lottery } = this.state;
    
    return [
      h("div.lottery-prize", [
        h("strong", I18n.t("lottery.prize") + ": "),
        lottery.prize_description
      ]),
      lottery.prize_image_url && h("div.lottery-prize-image", [
        h("img", { attributes: { src: lottery.prize_image_url, alt: "奖品图片" } })
      ])
    ];
  },
  
  buildLotteryInfo() {
    const { lottery } = this.state;
    
    const drawMethodText = lottery.draw_method === "random" 
      ? `${I18n.t("lottery.method.random")} (${lottery.winner_count}${I18n.t("lottery.winners")})`
      : `${I18n.t("lottery.method.specific")} (${lottery.specific_floors_display})`;
    
    const info = [
      h("div.lottery-detail", [
        h("strong", I18n.t("lottery.draw_method") + ": "),
        drawMethodText
      ]),
      h("div.lottery-detail", [
        h("strong", I18n.t("lottery.min_participants") + ": "),
        `${lottery.min_participants}${I18n.t("lottery.people")}`
      ]),
      h("div.lottery-detail", [
        h("strong", I18n.t("lottery.current_participants") + ": "),
        `${lottery.effective_participants_count}${I18n.t("lottery.people")}`
      ])
    ];
    
    if (lottery.status === "running") {
      info.push(h("div.lottery-detail.lottery-time", [
        h("strong", I18n.t("lottery.time_remaining") + ": "),
        h("span.time-countdown", this.state.timeRemaining)
      ]));
    }
    
    if (lottery.description) {
      info.push(h("div.lottery-description", [
        h("strong", I18n.t("lottery.description") + ": "),
        h("div.description-content", { innerHTML: lottery.description })
      ]));
    }
    
    return h("div.lottery-info", info);
  },
  
  buildWinnersList() {
    const { lottery } = this.state;
    
    if (lottery.status !== "finished" || !lottery.winners_data) {
      return null;
    }
    
    const winners = lottery.winners_data.map(winner => 
      h("div.winner-item", [
        h("a.username", { attributes: { href: `/u/${winner.username}` } }, `@${winner.username}`),
        h("span.winner-floor", `(${winner.floor_number}楼)`)
      ])
    );
    
    return h("div.lottery-winners", [
      h("h4", "🏆 " + I18n.t("lottery.congratulations")),
      h("div.winners-list", winners)
    ]);
  },
  
  buildCancelledMessage() {
    const { lottery } = this.state;
    
    if (lottery.status !== "cancelled") {
      return null;
    }
    
    return h("div.lottery-cancelled", [
      h("span.cancel-icon", "❌"),
      h("span", I18n.t("lottery.cancelled_message"))
    ]);
  },
  
  buildActions() {
    const { lottery } = this.state;
    const actions = [];
    
    if (["running", "finished", "cancelled"].includes(lottery.status)) {
      actions.push(this.attach("button", {
        className: "btn-default lottery-participants-btn",
        action: "toggleParticipants",
        icon: "users",
        label: this.state.showParticipants ? "lottery.hide_participants" : "lottery.show_participants"
      }));
    }
    
    if (lottery.can_cancel) {
      actions.push(this.attach("button", {
        className: "btn-danger lottery-cancel-btn",
        action: "cancelLottery",
        icon: "times",
        label: "lottery.cancel_lottery"
      }));
    }
    
    return actions.length > 0 ? h("div.lottery-actions", actions) : null;
  },
  
  buildParticipantsList() {
    if (!this.state.showParticipants) {
      return null;
    }
    
    const { participants } = this.state;
    
    if (participants.length === 0) {
      return h("div.lottery-participants-list", [
        h("h4", I18n.t("lottery.participants_list") + ` (${participants.length})`),
        h("div.no-participants", I18n.t("lottery.no_participants"))
      ]);
    }
    
    const participantItems = participants.map(participant => {
      const classes = participant.is_winner ? "participant-item is-winner" : "participant-item";
      
      return h(`div.${classes}`, [
        h("a.username", { 
          attributes: { href: `/u/${participant.username}` } 
        }, `@${participant.username}`),
        h("span.participant-floor", `${participant.floor_number}楼`),
        participant.is_winner && h("span.winner-badge", "🏆")
      ]);
    });
    
    return h("div.lottery-participants-list", [
      h("h4", I18n.t("lottery.participants_list") + ` (${participants.length})`),
      h("div.participants-grid", participantItems)
    ]);
  },
  
  html() {
    if (this.state.loading) {
      return this.buildLoadingState();
    }
    
    if (!this.state.lottery) {
      return this.buildErrorState();
    }
    
    const content = [
      this.buildHeader(),
      h("div.lottery-content", [
        ...this.buildPrizeInfo(),
        this.buildLotteryInfo(),
        this.buildWinnersList(),
        this.buildCancelledMessage()
      ].filter(Boolean)),
      this.buildActions(),
      this.buildParticipantsList()
    ].filter(Boolean);
    
    return content;
  },
  
  toggleParticipants() {
    this.toggleParticipants();
  },
  
  cancelLottery() {
    this.cancelLottery();
  }
});
