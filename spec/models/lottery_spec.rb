# frozen_string_literal: true

require 'rails_helper'

describe DiscourseLottery::Lottery do
  let(:user) { Fabricate(:user) }
  let(:topic) { Fabricate(:topic, user: user) }
  
  describe 'validations' do
    it 'requires name' do
      lottery = DiscourseLottery::Lottery.new(topic: topic, user: user)
      expect(lottery).not_to be_valid
      expect(lottery.errors[:name]).to be_present
    end
    
    it 'requires prize_description' do
      lottery = DiscourseLottery::Lottery.new(topic: topic, user: user, name: 'Test')
      expect(lottery).not_to be_valid
      expect(lottery.errors[:prize_description]).to be_present
    end
    
    it 'validates draw_time is in future' do
      lottery = DiscourseLottery::Lottery.new(
        topic: topic,
        user: user,
        name: 'Test',
        prize_description: 'Prize',
        draw_time: 1.hour.ago
      )
      expect(lottery).not_to be_valid
      expect(lottery.errors[:draw_time]).to be_present
    end
    
    it 'validates winner_count is positive' do
      lottery = DiscourseLottery::Lottery.new(
        topic: topic,
        user: user,
        name: 'Test',
        prize_description: 'Prize',
        draw_time: 1.hour.from_now,
        winner_count: 0
      )
      expect(lottery).not_to be_valid
      expect(lottery.errors[:winner_count]).to be_present
    end
    
    it 'validates min_participants meets global requirement' do
      SiteSetting.lottery_min_participants_global = 5
      
      lottery = DiscourseLottery::Lottery.new(
        topic: topic,
        user: user,
        name: 'Test',
        prize_description: 'Prize',
        draw_time: 1.hour.from_now,
        min_participants: 3
      )
      expect(lottery).not_to be_valid
      expect(lottery.errors[:min_participants]).to be_present
    end
  end
  
  describe 'scopes' do
    let!(:running_lottery) do
      DiscourseLottery::Lottery.create!(
        topic: topic,
        user: user,
        name: 'Running',
        prize_description: 'Prize',
        draw_time: 1.hour.from_now,
        status: 'running'
      )
    end
    
    let!(:finished_lottery) do
      DiscourseLottery::Lottery.create!(
        topic: Fabricate(:topic),
        user: user,
        name: 'Finished',
        prize_description: 'Prize',
        draw_time: 1.hour.from_now,
        status: 'finished'
      )
    end
    
    it 'filters by status' do
      expect(DiscourseLottery::Lottery.running).to include(running_lottery)
      expect(DiscourseLottery::Lottery.running).not_to include(finished_lottery)
      
      expect(DiscourseLottery::Lottery.finished).to include(finished_lottery)
      expect(DiscourseLottery::Lottery.finished).not_to include(running_lottery)
    end
    
    it 'finds pending draws' do
      running_lottery.update!(draw_time: 1.hour.ago)
      expect(DiscourseLottery::Lottery.pending_draw).to include(running_lottery)
      expect(DiscourseLottery::Lottery.pending_draw).not_to include(finished_lottery)
    end
  end
  
  describe 'methods' do
    let(:lottery) do
      DiscourseLottery::Lottery.create!(
        topic: topic,
        user: user,
        name: 'Test',
        prize_description: 'Prize',
        draw_time: 1.hour.from_now,
        specific_floors: '8, 18, 28'
      )
    end
    
    it 'parses specific floors correctly' do
      expect(lottery.specific_floors_array).to eq([8, 18, 28])
    end
    
    it 'calculates actual winner count for specific floors' do
      lottery.update!(draw_method: 'specific')
      expect(lottery.actual_winner_count).to eq(3)
    end
    
    it 'calculates actual winner count for random draw' do
      lottery.update!(draw_method: 'random', winner_count: 5)
      expect(lottery.actual_winner_count).to eq(5)
    end
    
    it 'can be locked' do
      expect(lottery).not_to be_locked
      lottery.lock!
      expect(lottery).to be_locked
      expect(lottery.locked_at).to be_present
    end
    
    it 'can be finished with winners' do
      winners_data = [{ username: 'user1', floor: 2 }]
      lottery.finish_with_winners!(winners_data)
      
      expect(lottery.status).to eq('finished')
      expect(lottery.winners_data).to eq(winners_data)
    end
    
    it 'can be cancelled with reason' do
      reason = 'Not enough participants'
      lottery.cancel_with_reason!(reason)
      
      expect(lottery.status).to eq('cancelled')
      expect(lottery.cancellation_reason).to eq(reason)
    end
  end
end
