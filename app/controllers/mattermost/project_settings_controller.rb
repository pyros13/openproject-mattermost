# frozen_string_literal: true

module Mattermost
  class ProjectSettingsController < ::ApplicationController
    before_action :find_project_by_project_id
    before_action :authorize

    def show
      @setting = MattermostProjectSetting.find_or_initialize_by(project: @project)
      @setting.enabled = true if @setting.new_record?
    end

    def update
      @setting = MattermostProjectSetting.find_or_initialize_by(project: @project)
      if @setting.update(setting_params)
        flash[:notice] = I18n.t(:notice_successful_update)
        redirect_to project_mattermost_settings_path(@project)
      else
        render :show, status: :unprocessable_entity
      end
    end

    def test
      @setting = MattermostProjectSetting.find_or_initialize_by(project: @project)
      created = OpenProject::Mattermost::Dispatcher.new.test_channel(@setting)
      flash[:notice] = I18n.t(:notice_mattermost_test_posted, post_id: created["id"])
    rescue OpenProject::Mattermost::Client::Error => e
      flash[:error] = e.message
    rescue StandardError => e
      flash[:error] = "#{e.class}: #{e.message}"
    ensure
      redirect_to project_mattermost_settings_path(@project)
    end

    private

    def setting_params
      permitted = params.require(:mattermost_project_setting).permit(
        :enabled,
        :channel_id,
        :channel_name,
        :bump_on_status,
        :pin_on_bump,
        :thread_comments,
        :thread_files,
        :thread_other
      )
      %w[enabled bump_on_status pin_on_bump thread_comments thread_files thread_other].each do |key|
        value = permitted[key]
        permitted[key] = Array(value).last if value.is_a?(Array)
      end
      permitted
    end
  end
end
