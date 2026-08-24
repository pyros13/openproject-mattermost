# frozen_string_literal: true

module Mattermost
  # Global bot connection (server URL + one token). Channel ID is per project.
  # Mirrors OpenProject's GitHub integration admin controller — no
  # Admin::Settings::SettingsHelper (that constant does not exist in core).
  class AdminSettingsController < ::ApplicationController
    layout "admin"

    menu_item :plugin_mattermost

    before_action :require_admin

    def show
      @settings = plugin_settings
    end

    def update
      Setting.plugin_openproject_mattermost = plugin_settings.merge(settings_params)
      flash[:notice] = I18n.t(:notice_successful_update)
      redirect_to mattermost_admin_settings_path
    end

    private

    def plugin_settings
      Hash(Setting.plugin_openproject_mattermost).with_indifferent_access
    end

    def settings_params
      params.require(:settings).permit(:server_url, :bot_token, :bot_name).to_h
    end
  end
end
