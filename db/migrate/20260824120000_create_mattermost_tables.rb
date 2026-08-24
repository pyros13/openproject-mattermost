# frozen_string_literal: true

class CreateMattermostTables < ActiveRecord::Migration[7.1]
  def change
    create_table :mattermost_work_package_posts do |t|
      t.references :work_package, null: false, foreign_key: true, index: { unique: true }
      t.string :post_id, null: false
      t.string :root_id, null: false
      t.string :channel_id, null: false
      t.datetime :last_bumped_at
      t.timestamps
    end

    create_table :mattermost_project_settings do |t|
      t.references :project, null: false, foreign_key: true, index: { unique: true }
      t.boolean :enabled, null: false, default: false
      t.string :channel_id
      t.string :channel_name
      t.boolean :bump_on_status, null: false, default: true
      t.boolean :pin_on_bump, null: false, default: false
      t.boolean :thread_comments, null: false, default: true
      t.boolean :thread_files, null: false, default: true
      t.boolean :thread_other, null: false, default: true
      t.timestamps
    end
  end
end
