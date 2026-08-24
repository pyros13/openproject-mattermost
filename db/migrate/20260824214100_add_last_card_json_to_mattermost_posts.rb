# frozen_string_literal: true

class AddLastCardJsonToMattermostPosts < ActiveRecord::Migration[7.1]
  def change
    add_column :mattermost_work_package_posts, :last_card_json, :text
  end
end
