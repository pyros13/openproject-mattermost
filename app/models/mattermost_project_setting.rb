# frozen_string_literal: true

class MattermostProjectSetting < ApplicationRecord
  belongs_to :project

  validates :project_id, uniqueness: true
  validates :channel_id,
            presence: { message: "is required when Mattermost is enabled for this project" },
            if: :enabled?

  before_validation :normalize_channel_id

  def bump_on_status = self[:bump_on_status]
  def pin_on_bump = self[:pin_on_bump]
  def thread_comments = self[:thread_comments]
  def thread_files = self[:thread_files]
  def thread_other = self[:thread_other]

  # Look up the setting that actually posts for this project.
  # Channel id is always per-project — never read from the global bot config.
  def self.for_project(project)
    return if project.nil?

    find_by(project: project)
  end

  private

  def normalize_channel_id
    raw = channel_id.to_s.strip
    # Accept a pasted Mattermost URL and keep the last path segment if it
    # looks like an id; otherwise store the stripped value.
    raw = raw.split("/").last.to_s if raw.include?("/")
    self.channel_id = raw.presence
  end
end
