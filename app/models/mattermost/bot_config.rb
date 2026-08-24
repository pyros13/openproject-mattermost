# frozen_string_literal: true

module Mattermost
  module BotConfig
    module_function

    def server_url
      Setting.plugin_openproject_mattermost[:server_url].presence ||
        Setting.plugin_openproject_mattermost["server_url"]
    end

    def bot_token
      Setting.plugin_openproject_mattermost[:bot_token].presence ||
        Setting.plugin_openproject_mattermost["bot_token"]
    end

    def ready?
      server_url.present? && bot_token.present?
    end

    def client
      OpenProject::Mattermost::Client.new(server_url: server_url, bot_token: bot_token)
    end
  end
end
