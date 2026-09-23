# frozen_string_literal: true

class ChangeEnabledDefaultToTrue < ActiveRecord::Migration[7.1]
  def up
    change_column_default :mattermost_project_settings, :enabled, true
  end

  def down
    change_column_default :mattermost_project_settings, :enabled, false
  end
end
