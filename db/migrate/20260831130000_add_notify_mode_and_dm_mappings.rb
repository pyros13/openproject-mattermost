# frozen_string_literal: true

class AddNotifyModeAndDmMappings < ActiveRecord::Migration[7.1]
  def change
    add_column :mattermost_project_settings, :notify_mode, :string, null: false, default: "group"

    add_column :mattermost_work_package_posts, :target_kind, :string, null: false, default: "group"
    add_column :mattermost_work_package_posts, :mattermost_username, :string
    add_column :mattermost_work_package_posts, :op_user_id, :bigint

    if index_exists?(:mattermost_work_package_posts, :work_package_id, unique: true)
      remove_index :mattermost_work_package_posts, :work_package_id
    end
    unless index_exists?(:mattermost_work_package_posts, :work_package_id)
      add_index :mattermost_work_package_posts, :work_package_id
    end
    unless index_exists?(:mattermost_work_package_posts, %i[work_package_id channel_id], name: "index_mm_wp_posts_on_wp_and_channel")
      add_index :mattermost_work_package_posts,
                %i[work_package_id channel_id],
                unique: true,
                name: "index_mm_wp_posts_on_wp_and_channel"
    end
  end
end
