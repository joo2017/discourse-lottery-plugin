# frozen_string_literal: true

class CreateLotteryParticipants < ActiveRecord::Migration[7.0]
  def up
    create_table :lottery_participants do |t|
      t.references :lottery, null: false, foreign_key: true, index: true
      t.references :user, null: false, foreign_key: true, index: true
      t.references :post, null: false, foreign_key: true, index: true
      t.integer :floor_number, null: false
      t.boolean :is_winner, null: false, default: false
      t.datetime :participated_at, null: false
      t.timestamps null: false
    end

    add_index :lottery_participants, [:lottery_id, :user_id], 
              name: 'idx_lottery_participants_lottery_user', unique: true
    add_index :lottery_participants, [:lottery_id, :is_winner], 
              name: 'idx_lottery_participants_lottery_winner'
    add_index :lottery_participants, [:lottery_id, :floor_number], 
              name: 'idx_lottery_participants_lottery_floor'
  end

  def down
    drop_table :lottery_participants
  end
end
