# frozen_string_literal: true

module Mattermost
  class SyncAttachmentJob < ApplicationJob
    queue_as :default

    def perform(attachment_id)
      attachment = Attachment.find_by(id: attachment_id)
      return unless attachment
      return unless attachment.container.is_a?(WorkPackage)

      setting = MattermostProjectSetting.for_project(attachment.container.project)
      return unless setting&.enabled? && setting.thread_files? && setting.channel_id.present?
      return unless Mattermost::BotConfig.ready?

      mapping = MattermostWorkPackagePost.find_by(work_package: attachment.container)
      return if mapping.blank? || mapping.post_id.blank?

      client = Mattermost::BotConfig.client
      channel_id = mapping.channel_id.presence || setting.channel_id
      file_ids = []
      file = attachment.file
      if file
        io = file.respond_to?(:download) ? StringIO.new(file.download) : File.open(file.path, "rb")
        response = client.upload_file(
          channel_id: channel_id,
          filename: attachment.filename,
          io: io,
          content_type: attachment.content_type.presence || "application/octet-stream"
        )
        file_ids = client.file_ids_from_upload(response)
      end

      client.create_post(
        channel_id: channel_id,
        message: "Attached **#{attachment.filename}**",
        root_id: mapping.root_id.presence || mapping.post_id,
        file_ids: file_ids
      )
    rescue OpenProject::Mattermost::Client::Error => e
      Rails.logger.error("[mattermost] attachment #{attachment_id}: #{e.message}")
    ensure
      io&.close if defined?(io) && io.respond_to?(:close)
    end
  end
end
