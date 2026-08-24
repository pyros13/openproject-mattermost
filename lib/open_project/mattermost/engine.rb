# frozen_string_literal: true

# OpenProject::Plugins lives in OpenProject core, not the 2013
# "openproject-plugins" gem.
require "open_project/plugins"

module OpenProject
  module Mattermost
    class Engine < ::Rails::Engine
      engine_name :openproject_mattermost

      include OpenProject::Plugins::ActsAsOpEngine

      def self.settings
        {
          default: {
            "server_url" => "",
            "bot_token" => "",
            "bot_name" => "OpenProject",
            "enabled" => true
          },
          partial: "mattermost/settings"
        }
      end

      register(
        "openproject-mattermost",
        author_url: "https://www.openproject.org/",
        bundled: false,
        requires_openproject: ">= 15.0.0",
        settings:
      ) do
        project_module :mattermost, dependencies: :work_package_tracking do
          permission :manage_mattermost,
                     { "mattermost/project_settings": %i[show update] },
                     permissible_on: :project,
                     require: :member
        end

        menu :admin_menu,
             :plugin_mattermost,
             { controller: "/mattermost/admin_settings", action: :show },
             caption: :label_mattermost,
             icon: "comment-discussion",
             if: ->(*) { User.current.admin? },
             last: true

        menu :project_menu,
             :mattermost,
             { controller: "/mattermost/project_settings", action: :show },
             caption: :label_mattermost,
             after: :settings,
             param: :project_id,
             icon: "comment-discussion",
             if: ->(project) {
               User.current.allowed_in_project?(:manage_mattermost, project)
             }
      end

      initializer "openproject_mattermost.notifications" do |app|
        app.config.after_initialize do
          OpenProject::Notifications.subscribe(
            OpenProject::Events::AGGREGATED_WORK_PACKAGE_JOURNAL_READY,
            &NotificationHandler.method(:aggregated_journal)
          )
          OpenProject::Notifications.subscribe(
            OpenProject::Events::ATTACHMENT_CREATED,
            &NotificationHandler.method(:attachment_created)
          )
        end
      end
    end
  end
end
