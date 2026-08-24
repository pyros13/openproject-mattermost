# frozen_string_literal: true

# OpenProject::Plugins lives in OpenProject core, not the 2013
# "openproject-plugins" gem.
require "open_project/plugins"

module OpenProject
  module Mattermost
    class Engine < ::Rails::Engine
      engine_name :openproject_mattermost

      include OpenProject::Plugins::ActsAsOpEngine

      config.eager_load_paths += %W[
        #{config.root}/app/workers
        #{config.root}/app/services
        #{config.root}/lib
      ]

      def self.settings
        {
          default: {
            "server_url" => "",
            "bot_token" => "",
            "bot_name" => "OpenProject"
          },
          partial: "settings/mattermost"
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
                     {
                       "mattermost/project_settings": %i[show update test]
                     },
                     permissible_on: :project,
                     require: :member
        end

        menu :admin_menu,
             :plugin_mattermost,
             { controller: "/mattermost/admin_settings", action: :show },
             caption: :label_mattermost,
             icon: "comment-discussion",
             parent: :admin_integrations,
             if: ->(*) { User.current.admin? }

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
          OpenProject::Mattermost::Engine.subscribe_mattermost_notifications!
          msg = "[mattermost] #{OpenProject::Mattermost::VERSION} subscribed " \
                "aggregated_work_package_journal_ready, journal_created, attachment_created"
          Rails.logger.info(msg) if defined?(Rails) && Rails.logger
          warn(msg)
        end
      end

      config.to_prepare do
        unless WorkPackage.reflect_on_association(:mattermost_work_package_post)
          WorkPackage.has_one :mattermost_work_package_post,
                              class_name: "MattermostWorkPackagePost",
                              dependent: :delete,
                              inverse_of: :work_package
        end
        unless Project.reflect_on_association(:mattermost_project_setting)
          Project.has_one :mattermost_project_setting,
                          class_name: "MattermostProjectSetting",
                          dependent: :delete,
                          inverse_of: :project
        end
      end

      def self.subscribe_mattermost_notifications!
        OpenProject::Notifications.subscribe(
          OpenProject::Events::AGGREGATED_WORK_PACKAGE_JOURNAL_READY
        ) do |payload|
          NotificationHandler.aggregated_journal(payload)
        end
        OpenProject::Notifications.subscribe(
          OpenProject::Events::JOURNAL_CREATED
        ) do |payload|
          NotificationHandler.journal_created(payload)
        end
        OpenProject::Notifications.subscribe(
          OpenProject::Events::ATTACHMENT_CREATED
        ) do |payload|
          NotificationHandler.attachment_created(payload)
        end
      end
    end
  end
end
