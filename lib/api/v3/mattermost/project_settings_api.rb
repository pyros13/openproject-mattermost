# frozen_string_literal: true

module API
  module V3
    module Mattermost
      # PATCH /api/v3/mattermost/projects/:id/settings
      # Body: { "notify_mode": "users" | "group" | "both" }
      class ProjectSettingsAPI < ::API::OpenProjectAPI
        resources :mattermost do
          resources :projects do
            route_param :id, type: String do
              resource :settings do
                after_validation do
                  @project = Project.visible.find_by(id: params[:id]) ||
                             Project.visible.find_by(identifier: params[:id])
                  raise API::Errors::NotFound if @project.nil?

                  allowed = User.current.admin? ||
                            User.current.allowed_in_project?(:manage_mattermost, @project)
                  raise API::Errors::Unauthorized unless allowed
                end

                get do
                  setting = MattermostProjectSetting.find_or_initialize_by(project: @project)
                  status 200
                  setting_payload(setting)
                end

                params do
                  optional :notify_mode,
                           type: String,
                           values: MattermostProjectSetting::NOTIFY_MODES,
                           desc: "group, users, or both"
                  optional :enabled,
                           type: Boolean,
                           desc: "Turn Mattermost posting on or off"
                end
                patch do
                  attrs = declared(params, include_missing: false)
                  if !attrs.key?(:notify_mode) && !attrs.key?(:enabled)
                    error!({ message: "Provide notify_mode and/or enabled" }, 400)
                  end

                  setting = MattermostProjectSetting.find_or_initialize_by(project: @project)
                  setting.notify_mode = attrs[:notify_mode] if attrs.key?(:notify_mode)
                  setting.enabled = attrs[:enabled] if attrs.key?(:enabled)
                  unless setting.save
                    message = setting.errors.full_messages.join(", ")
                    error!({ message: message }, 422)
                  end
                  status 200
                  setting_payload(setting)
                end
              end
            end
          end
        end

        helpers do
          def setting_payload(setting)
            {
              project_id: setting.project_id,
              notify_mode: setting.notify_mode,
              enabled: setting.enabled?,
              channel_id: setting.channel_id
            }
          end
        end
      end
    end
  end
end
