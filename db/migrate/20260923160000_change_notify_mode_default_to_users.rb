# frozen_string_literal: true

class ChangeNotifyModeDefaultToUsers < ActiveRecord::Migration[7.1]
  def up
    change_column_default :mattermost_project_settings, :notify_mode, "users"
  end

  def down
    change_column_default :mattermost_project_settings, :notify_mode, "group"
  end
end
