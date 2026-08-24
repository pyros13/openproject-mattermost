# frozen_string_literal: true

module Mattermost
  class AdminSettingsController < ApplicationController
    include Admin::Settings::SettingsHelper

    before_action :require_admin

    def show
      @settings = Setting.plugin_openproject_mattermost
    end

    def update
      Setting.plugin_openproject_mattermost = settings_params
      flash[:notice] = I18n.t(:notice_successful_update)
      redirect_to action: :show
    end

    private

    def settings_params
      params.require(:settings).permit(:server_url, :bot_token, :bot_name, :enabled).to_h
    end
  end
end
