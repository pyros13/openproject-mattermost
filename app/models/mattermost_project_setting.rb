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
    return "users" unless has_attribute?(:notify_mode)

    self[:notify_mode].presence || "users"
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

  # Create the row at project creation. enabled is on so copy/create
  # does not leave posting off.
  def self.ensure_for_project!(project)
    return if project.nil?

    setting = find_or_initialize_by(project: project)
    return setting unless setting.new_record?

    setting.notify_mode = "users"
    setting.enabled = true
    setting.save!
    setting
  end

  # Module was just turned on (including a copied project). Force posting on.
  def self.activate!(project)
    return if project.nil?

    setting = find_or_initialize_by(project: project)
    setting.notify_mode = "users" if setting.notify_mode.blank?
    setting.enabled = true
    setting.save! if setting.new_record? || setting.changed?
    setting
  end

  private

  def normalize_notify_mode
    return unless has_attribute?(:notify_mode)

    self.notify_mode = "users" if notify_mode.blank?
  end

  def normalize_channel_id
    raw = channel_id.to_s.strip
    raw = raw.split("/").last.to_s if raw.include?("/")
    self.channel_id = raw.presence
  end
end
