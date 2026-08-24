# frozen_string_literal: true

module Mattermost
  class AdminSettingsController < ::ApplicationController
    layout "admin"

    menu_item :plugin_mattermost

    before_action :require_admin

    def show
      @settings = plugin_settings
    end

    def update
      merged = plugin_settings.merge(settings_params)
      merged["bot_token"] = plugin_settings[:bot_token] if merged["bot_token"].blank?
      Mattermost::BotConfig.write!(merged)
      flash[:notice] = I18n.t(:notice_successful_update)
      redirect_to mattermost_admin_settings_path
    end

    def test
      me = OpenProject::Mattermost::Dispatcher.new.test_bot
      name = me["username"] || me["nickname"] || me["id"]
      flash[:notice] = I18n.t(:notice_mattermost_bot_ok, name: name)
    rescue OpenProject::Mattermost::Client::Error => e
      flash[:error] = e.message
    rescue StandardError => e
      flash[:error] = "#{e.class}: #{e.message}"
    ensure
      redirect_to mattermost_admin_settings_path
    end

    private

    def plugin_settings
      Mattermost::BotConfig.settings
    end

    def settings_params
      params.require(:settings).permit(:server_url, :bot_token, :bot_name).to_h.stringify_keys
    end
  end
end
