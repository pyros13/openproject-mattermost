# frozen_string_literal: true

module Mattermost
  class SyncJournalJob < ApplicationJob
    queue_as :default

    def perform(journal_id)
      journal = Journal.find_by(id: journal_id)
      return unless journal

      work_package = journal.journable
      return unless work_package.is_a?(WorkPackage)

      project = work_package.project
      setting = MattermostProjectSetting.for_project(project)
      return unless setting&.enabled?
      return if setting.channel_id.blank?
      return unless Mattermost::BotConfig.ready?

      classified = OpenProject::Mattermost::Classifier.new(settings: setting).call(journal)
      client = Mattermost::BotConfig.client
      formatter = OpenProject::Mattermost::Formatter.new
      mapping = MattermostWorkPackagePost.find_or_initialize_by(work_package: work_package)
      # New cards go to this project's channel. Existing cards stay on the
      # channel they were created in so the thread is not orphaned.
      target_channel = mapping.channel_id.presence || setting.channel_id

      if mapping.new_record? || mapping.post_id.blank?
        payload = formatter.card_payload(work_package)
        created = client.create_post(
          channel_id: setting.channel_id,
          message: payload[:message],
          props: payload[:props]
        )
        mapping.post_id = created["id"]
        mapping.root_id = created["id"]
        mapping.channel_id = setting.channel_id
        mapping.last_bumped_at = Time.current
        mapping.save!
        client.pin_post(mapping.post_id) if setting.pin_on_bump?
      elsif classified.bump?
        payload = formatter.card_payload(work_package)
        client.update_post(
          post_id: mapping.post_id,
          message: payload[:message],
          props: payload[:props]
        )
        mapping.update!(last_bumped_at: Time.current)
        client.pin_post(mapping.post_id) if setting.pin_on_bump?
      end

      return unless classified.thread?
      return if mapping.post_id.blank?

      file_ids = upload_attachments(client, target_channel, classified.attachments)
      text = formatter.thread_message(journal, classified)
      client.create_post(
        channel_id: target_channel,
        message: text,
        root_id: mapping.root_id.presence || mapping.post_id,
        file_ids: file_ids
      )
    rescue OpenProject::Mattermost::Client::Error => e
      Rails.logger.error("[mattermost] journal #{journal_id}: #{e.message}")
    end

    private

    def upload_attachments(client, channel_id, attachments)
      attachments.filter_map do |att|
        file = att.try(:file) || att.try(:diskfile)
        next unless file

        io = file.respond_to?(:download) ? StringIO.new(file.download) : File.open(file.path, "rb")
        filename = att.try(:filename) || File.basename(file.try(:path).to_s)
        response = client.upload_file(
          channel_id: channel_id,
          filename: filename,
          io: io,
          content_type: att.try(:content_type) || "application/octet-stream"
        )
        client.file_ids_from_upload(response).first
      rescue StandardError => e
        Rails.logger.error("[mattermost] upload #{att.id}: #{e.message}")
        nil
      ensure
        io.close if io.respond_to?(:close)
      end
    end
  end
end
