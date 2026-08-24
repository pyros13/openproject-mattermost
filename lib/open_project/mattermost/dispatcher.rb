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
        live_delta = live_card_delta(mapping, work_package)
        if live_delta.any?
          classified = Classifier.apply_live_card_delta(classified, live_delta)
        end
        stale_card = card_stale?(mapping, work_package)

        self.class.log(
          "classify WP ##{work_package.id} journal=#{journal.id} " \
          "status=#{work_package.try(:status_id)} bump=#{classified.bump?} " \
          "thread=#{classified.thread?} stale_card=#{stale_card} " \
          "snapshot=#{snapshot ? 'yes' : 'no'} " \
          "journal_keys=#{Hash(journal.try(:details)).keys.take(16).join(',')}"
        )

        card_missing = mapping.new_record? || mapping.post_id.blank?
        unless card_missing || classified.bump? || classified.thread? || stale_card
          self.class.log("skip WP ##{work_package.id}: no new payload journal=#{journal.id}")
          persist_snapshot(mapping, journal, work_package, write_card: false)
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
        elsif classified.bump? || stale_card
          payload = formatter.card_payload(work_package)
          client.update_post(
            post_id: mapping.post_id,
            message: payload[:message],
            props: payload[:props]
          )
          mapping.update!(last_bumped_at: Time.current)
          client.pin_post(mapping.post_id) if setting.pin_on_bump
          self.class.log("bumped WP ##{work_package.id} post=#{mapping.post_id} status=#{work_package.status&.name}")
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

        persist_snapshot(mapping, journal, work_package, write_card: card_missing || classified.bump? || stale_card)
      rescue StandardError => e
        self.class.log_error("journal #{journal.try(:id)}", e)
      end

      def sync_attachment(attachment)
        # Files ride with the work-package journal (attachments_N details).
        # Posting here as well duplicated the file in the thread.
        self.class.log("skip attachment #{attachment.try(:id)}: files go with the work package journal")
        nil
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

      def persist_snapshot(mapping, journal, work_package = nil, write_card: true)
        return unless mapping.persisted?

        attrs = {}
        attrs[:last_journal_id] = journal.id if mapping.has_attribute?(:last_journal_id) && journal.id
        if mapping.has_attribute?(:last_notes)
          attrs[:last_notes] = journal.try(:notes).to_s
        end
        if mapping.has_attribute?(:last_details_json)
          attrs[:last_details_json] = Hash(journal.try(:details) || journal.try(:get_changes)).to_json
        end
        wp = work_package || journal.try(:journable)
        if write_card && mapping.has_attribute?(:last_card_json) && wp
          attrs[:last_card_json] = card_state(wp).to_json
        end
        mapping.update_columns(attrs) if attrs.any?
      rescue StandardError => e
        self.class.log_error("persist snapshot WP mapping #{mapping.id}", e)
      end

      def card_state(work_package)
        {
          "status_id" => work_package.try(:status_id),
          "assigned_to_id" => work_package.try(:assigned_to_id),
          "responsible_id" => work_package.try(:responsible_id),
          "subject" => work_package.try(:subject),
          "due_date" => work_package.try(:due_date)&.to_s,
          "start_date" => work_package.try(:start_date)&.to_s,
          "done_ratio" => work_package.try(:done_ratio),
          "type_id" => work_package.try(:type_id),
          "priority_id" => work_package.try(:priority_id)
        }
      end

      def live_card_delta(mapping, work_package)
        return {} unless mapping.persisted? && mapping.post_id.present?
        return {} unless mapping.has_attribute?(:last_card_json)

        previous = parse_details(mapping.last_card_json)
        return {} if previous.blank?

        delta = {}
        card_state(work_package).each do |key, value|
          old = previous[key]
          next if old.to_s == value.to_s

          delta[key] = [old, value]
        end
        delta
      end

      def card_stale?(mapping, work_package)
        return false unless mapping.persisted? && mapping.post_id.present?
        return false unless mapping.has_attribute?(:last_card_json)

        previous = parse_details(mapping.last_card_json)
        return true if previous.blank?

        live_card_delta(mapping, work_package).any?
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
