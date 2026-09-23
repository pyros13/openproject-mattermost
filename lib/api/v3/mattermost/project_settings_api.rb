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
                  requires :notify_mode,
                           type: String,
                           values: MattermostProjectSetting::NOTIFY_MODES,
                           desc: "group, users, or both"
                end
                patch do
                  setting = MattermostProjectSetting.find_or_initialize_by(project: @project)
                  setting.notify_mode = params[:notify_mode]
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
