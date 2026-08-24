# frozen_string_literal: true

class CascadeMattermostForeignKeys < ActiveRecord::Migration[7.1]
  def up
    if foreign_key_exists?(:mattermost_work_package_posts, :work_packages)
      remove_foreign_key :mattermost_work_package_posts, :work_packages
    end
    add_foreign_key :mattermost_work_package_posts, :work_packages, on_delete: :cascade

    if foreign_key_exists?(:mattermost_project_settings, :projects)
      remove_foreign_key :mattermost_project_settings, :projects
    end
    add_foreign_key :mattermost_project_settings, :projects, on_delete: :cascade
  end

  def down
    if foreign_key_exists?(:mattermost_work_package_posts, :work_packages)
      remove_foreign_key :mattermost_work_package_posts, :work_packages
    end
    add_foreign_key :mattermost_work_package_posts, :work_packages

    if foreign_key_exists?(:mattermost_project_settings, :projects)
      remove_foreign_key :mattermost_project_settings, :projects
    end
    add_foreign_key :mattermost_project_settings, :projects
  end
end
