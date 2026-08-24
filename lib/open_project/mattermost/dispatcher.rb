# frozen_string_literal: true

require "json"

module OpenProject
  module Mattermost
    # Posts / bumps / threads a work package to Mattermost.
    # Called from notification handlers (already on the worker for aggregated
    # journals) and from the Settings "Send test" button.
    class Dispatcher
      PREFIX = "[mattermost]"

      def self.log(message)
        if defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger
          Rails.logger.info("#{PREFIX} #{message}")
        end
        warn("#{PREFIX} #{message}")
      end

      def self.log_error(message, error = nil)
        text = error ? "#{message}: #{error.class}: #{error.message}" : message
        if defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger
          Rails.logger.error("#{PREFIX} #{text}")
          Rails.logger.error(error.backtrace.first(12).join("\n")) if error&.backtrace
        end
        warn("#{PREFIX} #{text}")
      end

      def sync_journal(journal)
        work_package = journal.try(:journable)
        unless work_package.is_a?(WorkPackage)
          self.class.log("skip journal=#{journal.try(:id)}: not a work package (#{journal.try(:journable_type)})")
          return
        end

        project = work_package.project
        setting = ::MattermostProjectSetting.for_project(project)
        unless setting
          self.class.log("skip WP ##{work_package.id}: no Mattermost row for project #{project&.id} (#{project&.name})")
          return
        end
        unless setting.enabled?
          self.class.log("skip WP ##{work_package.id}: Mattermost disabled on #{project&.name}")
          return
        end
        if setting.channel_id.blank?
          self.class.log("skip WP ##{work_package.id}: channel id blank on #{project&.name}")
          return
        end
        unless ::Mattermost::BotConfig.ready?
          self.class.log("skip WP ##{work_package.id}: bot not ready server=#{::Mattermost::BotConfig.server_url.present?} token=#{::Mattermost::BotConfig.bot_token.present?} keys=#{::Mattermost::BotConfig.debug_keys}")
          return
        end

        client = ::Mattermost::BotConfig.client
        formatter = Formatter.new
        mapping = ::MattermostWorkPackagePost.find_or_initialize_by(work_package: work_package)
        target_channel = mapping.channel_id.presence || setting.channel_id

        if mapping.has_attribute?(:last_journal_id) &&
           mapping.last_journal_id.present? &&
           journal.id &&
           journal.id < mapping.last_journal_id
          self.class.log("skip WP ##{work_package.id}: older journal #{journal.id} < #{mapping.last_journal_id}")
          return
        end

        snapshot = snapshot_for(mapping, journal)
        classified = Classifier.new(settings: setting).call(journal, snapshot: snapshot)

        card_missing = mapping.new_record? || mapping.post_id.blank?
        unless card_missing || classified.bump? || classified.thread?
          self.class.log("skip WP ##{work_package.id}: no new payload journal=#{journal.id}")
          return
        end

        if card_missing
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
          mapping.last_journal_id = journal.id if mapping.has_attribute?(:last_journal_id) && journal.id
          mapping.save!
          client.pin_post(mapping.post_id) if setting.pin_on_bump
          self.class.log("created card WP ##{work_package.id} post=#{mapping.post_id} channel=#{setting.channel_id}")
        elsif classified.bump?
          payload = formatter.card_payload(work_package)
          client.update_post(
            post_id: mapping.post_id,
            message: payload[:message],
            props: payload[:props]
          )
          mapping.update!(last_bumped_at: Time.current)
          client.pin_post(mapping.post_id) if setting.pin_on_bump
          self.class.log("bumped WP ##{work_package.id} post=#{mapping.post_id}")
        else
          self.class.log("no bump WP ##{work_package.id} thread=#{classified.thread?} notes=#{classified.notes.present?} opened=#{classified.opened?}")
        end

        if classified.thread? && mapping.post_id.present?
          text = formatter.thread_message(journal, classified)
          if text.present?
            file_ids = upload_attachments(client, target_channel, classified.attachments)
            client.create_post(
              channel_id: target_channel,
              message: text,
              root_id: mapping.root_id.presence || mapping.post_id,
              file_ids: file_ids
            )
            self.class.log("thread WP ##{work_package.id}: #{text.lines.first.to_s.strip}")
          end
        end

        persist_snapshot(mapping, journal)
      rescue StandardError => e
        self.class.log_error("journal #{journal.try(:id)}", e)
      end

      def sync_attachment(attachment)
        return unless attachment
        return unless attachment.container.is_a?(WorkPackage)

        setting = ::MattermostProjectSetting.for_project(attachment.container.project)
        unless setting&.enabled? && setting.thread_files && setting.channel_id.present?
          self.class.log("skip attachment #{attachment.id}: project not posting files")
          return
        end
        unless ::Mattermost::BotConfig.ready?
          self.class.log("skip attachment #{attachment.id}: bot not ready")
          return
        end

        mapping = ::MattermostWorkPackagePost.find_by(work_package: attachment.container)
        if mapping.blank? || mapping.post_id.blank?
          self.class.log("skip attachment #{attachment.id}: no root card yet")
          return
        end

        client = ::Mattermost::BotConfig.client
        channel_id = mapping.channel_id.presence || setting.channel_id
        file_ids = upload_attachments(client, channel_id, [attachment])
        client.create_post(
          channel_id: channel_id,
          message: "Attached **#{attachment.filename}**",
          root_id: mapping.root_id.presence || mapping.post_id,
          file_ids: file_ids
        )
        self.class.log("attached #{attachment.filename} on WP ##{attachment.container.id}")
      rescue StandardError => e
        self.class.log_error("attachment #{attachment.try(:id)}", e)
      end

      def test_bot
        unless ::Mattermost::BotConfig.ready?
          raise Client::Error, "Server URL or bot token is blank (keys=#{::Mattermost::BotConfig.debug_keys})"
        end

        ::Mattermost::BotConfig.client.me
      end

      def test_channel(setting)
        raise Client::Error, "Enable Mattermost and set a Channel ID first" if setting.channel_id.blank?

        me = test_bot
        name = me["username"] || me["nickname"] || "bot"
        ::Mattermost::BotConfig.client.create_post(
          channel_id: setting.channel_id,
          message: "OpenProject Mattermost plugin is connected as **#{name}**. This project will post status cards in this channel.",
          props: { from_bot: "true" }
        )
      end

      private

      def snapshot_for(mapping, journal)
        return unless mapping.persisted? && mapping.post_id.present?
        return unless mapping.has_attribute?(:last_journal_id)
        return unless journal.id && mapping.last_journal_id
        return unless journal.id == mapping.last_journal_id

        details = if mapping.has_attribute?(:last_details_json) && mapping.last_details_json.present?
          parse_details(mapping.last_details_json)
        else
          # Row from before 1.1.4: we already posted this journal once.
          # Treat current details as already shipped so only new notes go out.
          Hash(journal.try(:details) || journal.try(:get_changes))
        end
        notes = mapping.has_attribute?(:last_notes) ? mapping.last_notes : nil
        { notes: notes, details: details }
      end

      def persist_snapshot(mapping, journal)
        return unless mapping.persisted?

        attrs = {}
        attrs[:last_journal_id] = journal.id if mapping.has_attribute?(:last_journal_id) && journal.id
        if mapping.has_attribute?(:last_notes)
          attrs[:last_notes] = journal.try(:notes).to_s
        end
        if mapping.has_attribute?(:last_details_json)
          attrs[:last_details_json] = Hash(journal.try(:details) || journal.try(:get_changes)).to_json
        end
        mapping.update_columns(attrs) if attrs.any?
      rescue StandardError => e
        self.class.log_error("persist snapshot WP mapping #{mapping.id}", e)
      end

      def parse_details(json)
        raw = JSON.parse(json.to_s)
        raw.each_with_object({}) { |(key, value), out| out[key.to_s] = value }
      rescue JSON::ParserError, TypeError
        {}
      end

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
          self.class.log_error("upload #{att.try(:id)}", e)
          nil
        ensure
          io.close if defined?(io) && io.respond_to?(:close)
        end
      end
    end
  end
end
