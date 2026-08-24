# frozen_string_literal: true

class AddJournalSnapshotToMattermostPosts < ActiveRecord::Migration[7.1]
  def change
    add_column :mattermost_work_package_posts, :last_notes, :text
    add_column :mattermost_work_package_posts, :last_details_json, :text
  end
end
