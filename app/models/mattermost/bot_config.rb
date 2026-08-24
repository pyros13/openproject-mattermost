# frozen_string_literal: true

module Mattermost
  module BotConfig
    module_function

    # Plugin id is "openproject-mattermost". OpenProject stores that as
    # plugin_openproject-mattermost (hyphen) and/or plugin_openproject_mattermost.
    SETTING_KEYS = [
      "plugin_openproject_mattermost",
      "plugin_openproject-mattermost"
    ].freeze

    def settings
      Hash(raw_settings).with_indifferent_access
    end

    def raw_settings
      SETTING_KEYS.each do |key|
        val = begin
          Setting[key]
        rescue StandardError
          nil
        end
        return val if val.present?
      end
      if Setting.respond_to?(:plugin_openproject_mattermost)
        val = Setting.plugin_openproject_mattermost
        return val if val.present?
      end
      {}
    end

    def write!(hash)
      payload = Hash(hash).stringify_keys
      SETTING_KEYS.each do |key|
        Setting[key] = payload
      rescue StandardError
        nil
      end
      if Setting.respond_to?(:plugin_openproject_mattermost=)
        Setting.plugin_openproject_mattermost = payload
      end
      payload
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

    def debug_keys
      SETTING_KEYS.map do |key|
        val = begin
          Setting[key]
        rescue StandardError
          nil
        end
        "#{key}=#{val.present? ? 'set' : 'empty'}"
      end.join(",")
    end

    def client
      OpenProject::Mattermost::Client.new(server_url: server_url, bot_token: bot_token)
    end
  end
end
