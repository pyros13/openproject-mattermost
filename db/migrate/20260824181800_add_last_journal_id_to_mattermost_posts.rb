# frozen_string_literal: true

class AddLastJournalIdToMattermostPosts < ActiveRecord::Migration[7.1]
  def change
    add_column :mattermost_work_package_posts, :last_journal_id, :bigint
  end
end
