# frozen_string_literal: true

class CreateLotteries < ActiveRecord::Migration[7.0]
  def up
    create_table :lotteries do |t|
      t.references :topic, null: false, foreign_key: true, index: true
      t.references :user, null: false, foreign_key: true, index: true
      t.string :name, null: false, limit: 255
      t.text :prize_description, null: false
      t.string :prize_image_url, limit: 500
      t.datetime :draw_time, null: false, index: true
      t.integer :winner_count, null: false, default: 1
      t.text :specific_floors
      t.integer :min_participants, null: false, default: 1
      t.string :backup_strategy, null: false, default: 'continue'
      t.text :description
      t.string :draw_method, null: false, default: 'random'
      t.string :status, null: false, default: 'running', index: true
      t.boolean :locked, null: false, default: false
      t.datetime :locked_at
      t.json :winners_data
      t.text :cancellation_reason
      t.timestamps null: false
    end

    add_index :lotteries, [:status, :draw_time], name: 'idx_lotteries_status_draw_time'
    add_index :lotteries, [:topic_id, :status], name: 'idx_lotteries_topic_status'
  end

  def down
    drop_table :lotteries
  end
end
