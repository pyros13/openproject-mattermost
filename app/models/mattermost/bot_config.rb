# frozen_string_literal: true

module Mattermost
  module BotConfig
    module_function

    def settings
      Hash(Setting.plugin_openproject_mattermost).with_indifferent_access
    end

    def server_url
      settings[:server_url].presence
    end

    def bot_token
      settings[:bot_token].presence
    end

    def bot_name
      settings[:bot_name].presence || "OpenProject"
    end

    def ready?
      server_url.present? && bot_token.present?
    end

    def client
      OpenProject::Mattermost::Client.new(server_url: server_url, bot_token: bot_token)
    end
  end
end
