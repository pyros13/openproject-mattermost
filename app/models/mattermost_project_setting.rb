# frozen_string_literal: true

class MattermostProjectSetting < ApplicationRecord
  belongs_to :project

  NOTIFY_MODES = %w[group users both].freeze

  validates :project_id, uniqueness: true
  validates :notify_mode, inclusion: { in: NOTIFY_MODES }, allow_blank: true
  validates :channel_id,
            presence: { message: "is required when informing the project channel" },
            if: -> { enabled? && notify_group? }

  before_validation :normalize_channel_id
  before_validation :normalize_notify_mode

  def bump_on_status = self[:bump_on_status]
  def pin_on_bump = self[:pin_on_bump]
  def thread_comments = self[:thread_comments]
  def thread_files = self[:thread_files]
  def thread_other = self[:thread_other]

  def notify_mode
    return "group" unless has_attribute?(:notify_mode)

    self[:notify_mode].presence || "group"
  end

  def notify_group?
    %w[group both].include?(notify_mode)
  end

  def notify_users?
    %w[users both].include?(notify_mode)
  end

  def self.for_project(project)
    return if project.nil?

    find_by(project: project)
  end

  private

  def normalize_notify_mode
    return unless has_attribute?(:notify_mode)

    self.notify_mode = "group" if notify_mode.blank?
  end

  def normalize_channel_id
    raw = channel_id.to_s.strip
    raw = raw.split("/").last.to_s if raw.include?("/")
    self.channel_id = raw.presence
  end
end
