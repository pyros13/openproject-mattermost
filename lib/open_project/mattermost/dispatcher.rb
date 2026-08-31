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

      Destination = Struct.new(:kind, :channel_id, :username, :op_user_id, keyword_init: true)

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
        unless setting.notify_group? || setting.notify_users?
          self.class.log("skip WP ##{work_package.id}: notify mode is blank")
          return
        end
        unless ::Mattermost::BotConfig.ready?
          self.class.log("skip WP ##{work_package.id}: bot not ready server=#{::Mattermost::BotConfig.server_url.present?} token=#{::Mattermost::BotConfig.bot_token.present?} keys=#{::Mattermost::BotConfig.debug_keys}")
          return
        end

        client = ::Mattermost::BotConfig.client
        formatter = Formatter.new
        dests = destinations_for(setting, work_package, client)
        if dests.empty?
          self.class.log("skip WP ##{work_package.id}: no destinations (mode=#{setting.notify_mode})")
          return
        end

        primary = primary_mapping(work_package, dests)
        if primary &&
           primary.has_attribute?(:last_journal_id) &&
           primary.last_journal_id.present? &&
           journal.id &&
           journal.id < primary.last_journal_id &&
           dests.all? { |dest| existing_mapping(work_package, dest)&.last_journal_id.to_i >= journal.id.to_i }
          self.class.log("skip WP ##{work_package.id}: older journal #{journal.id} < #{primary.last_journal_id}")
          return
        end

        snapshot = snapshot_for(primary, journal)
        classified = Classifier.new(settings: setting).call(journal, snapshot: snapshot)

        dests.each do |dest|
          deliver(journal, work_package, setting, client, formatter, classified, dest)
        end
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

      def test_channel(setting, op_user = nil)
        client = ::Mattermost::BotConfig.client
        me = test_bot
        name = me["username"] || me["nickname"] || "bot"
        self.class.log("test mode=#{setting.notify_mode} group=#{setting.notify_group?} users=#{setting.notify_users?} user=#{op_user.try(:login)}")
        posted = nil
        notes = []
        if setting.notify_group?
          raise Client::Error, "Enable Mattermost and set a Channel ID first" if setting.channel_id.blank?

          posted = client.create_post(
            channel_id: setting.channel_id,
            message: "OpenProject Mattermost plugin is connected as **#{name}**. This project will post status cards in this channel.",
            props: { from_bot: "true" }
          )
          notes << "channel post #{posted['id']}"
        end
        if setting.notify_users?
          begin
            dm = test_dm(op_user)
            posted = { "id" => dm["id"] }
            notes << "DM @#{dm['username']} post #{dm['id']}"
          rescue StandardError => e
            self.class.log_error("unknown MM user #{op_user.try(:login)} / #{op_user.try(:mail)} — continuing", e)
            notes << "DM skipped (no Mattermost user for #{op_user.try(:login)} / #{op_user.try(:mail)})"
            posted ||= { "id" => "skipped-dm" }
          end
        end
        if posted.nil?
          raise Client::Error, "Inform is set to #{setting.notify_mode.inspect} — nothing to send. Save Inform as channel, DMs, or both."
        end
        posted["_summary"] = notes.join("; ")
        posted
      end

      def test_dm(op_user = nil)
        op_user ||= (defined?(User) && User.respond_to?(:current) ? User.current : nil)
        raise Client::Error, "No logged-in OpenProject user to DM" if op_user.nil? || op_user.try(:anonymous?)

        client = ::Mattermost::BotConfig.client
        me = test_bot
        bot_name = me["username"] || "bot"
        username = Recipients.username_for(op_user)
        email = op_user.try(:mail).to_s.strip.presence
        raise Client::Error, "Your OpenProject account has no login and no email" if username.blank? && email.blank?

        self.class.log("test DM lookup login=#{username} email=#{email}")
        dm = client.open_direct(username: username, email: email)
        posted = client.create_post(
          channel_id: dm["id"],
          message: "Test DM from OpenProject. This is **#{bot_name}**. Open Direct Messages with this bot — task cards will land here when Inform is per-user or both.\nLooked up OpenProject **#{op_user.try(:name) || username}** as Mattermost **@#{dm['_resolved_username']}**.",
          props: { from_bot: "true" }
        )
        self.class.log("test DM ok mm=@#{dm['_resolved_username']} channel=#{dm['id']} post=#{posted['id']}")
        {
          "id" => posted["id"],
          "channel_id" => dm["id"],
          "username" => dm["_resolved_username"],
          "email" => email,
          "login" => username
        }
      end

      private

      def destinations_for(setting, work_package, client)
        list = []
        if setting.notify_group?
          if setting.channel_id.present?
            list << Destination.new(kind: "group", channel_id: setting.channel_id)
          else
            self.class.log("skip group for WP ##{work_package.id}: channel id blank")
          end
        end
        if setting.notify_users?
          members = Recipients.members(work_package)
          self.class.log("task members WP ##{work_package.id}: #{members.map(&:username).join(',')}")
          members.each do |member|
            channel_id = dm_channel_for(client, member, work_package)
            next if channel_id.blank?

            list << Destination.new(
              kind: "dm",
              channel_id: channel_id,
              username: member.username,
              op_user_id: member.user.try(:id)
            )
          end
        end
        list
      end

      def dm_channel_for(client, member, work_package)
        dm = client.open_direct(
          username: member.username,
          email: member.user.try(:mail)
        )
        channel_id = dm["id"] || dm[:id]
        if channel_id.blank?
          self.class.log(
            "unknown MM user @#{member.username} email=#{member.user.try(:mail)} " \
            "WP ##{work_package.id} — no channel id, continuing with others"
          )
          return nil
        end
        channel_id
      rescue StandardError => e
        self.class.log_error(
          "unknown MM user @#{member.username} email=#{member.user.try(:mail)} " \
          "WP ##{work_package.id} — continuing with others",
          e
        )
        nil
      end

      def existing_mapping(work_package, dest)
        scope = ::MattermostWorkPackagePost.where(work_package: work_package)
        if dest.channel_id.present?
          found = scope.find_by(channel_id: dest.channel_id)
          return found if found
        end
        return scope.find_by(work_package: work_package) if dest.kind == "group" && scope.count <= 1

        nil
      end

      def mapping_for(work_package, dest)
        mapping = existing_mapping(work_package, dest)
        mapping ||= ::MattermostWorkPackagePost.new(work_package: work_package)
        mapping.channel_id = dest.channel_id
        if mapping.has_attribute?(:target_kind)
          mapping.target_kind = dest.kind
        end
        if mapping.has_attribute?(:mattermost_username)
          mapping.mattermost_username = dest.username
        end
        if mapping.has_attribute?(:op_user_id)
          mapping.op_user_id = dest.op_user_id
        end
        mapping
      end

      def primary_mapping(work_package, dests)
        dests.filter_map { |dest| existing_mapping(work_package, dest) }
             .max_by { |row| row.try(:last_journal_id).to_i }
      end

      def deliver(journal, work_package, setting, client, formatter, classified, dest)
        mapping = mapping_for(work_package, dest)
        this = classified
        live_delta = live_card_delta(mapping, work_package)
        this = Classifier.apply_live_card_delta(this, live_delta) if live_delta.any?
        stale_card = card_stale?(mapping, work_package)
        card_missing = mapping.new_record? || mapping.post_id.blank?
        label = dest.kind == "dm" ? "DM @#{dest.username}" : "channel #{dest.channel_id}"

        self.class.log(
          "classify WP ##{work_package.id} #{label} journal=#{journal.id} " \
          "status=#{work_package.try(:status_id)} bump=#{this.bump?} " \
          "thread=#{this.thread?} stale_card=#{stale_card} card_missing=#{card_missing}"
        )

        unless card_missing || this.bump? || this.thread? || stale_card
          self.class.log("skip WP ##{work_package.id} #{label}: no new payload journal=#{journal.id}")
          persist_snapshot(mapping, journal, work_package, write_card: false) if mapping.persisted?
          return
        end

        if card_missing
          payload = formatter.card_payload(work_package)
          created = client.create_post(
            channel_id: dest.channel_id,
            message: payload[:message],
            props: payload[:props]
          )
          mapping.post_id = created["id"]
          mapping.root_id = created["id"]
          mapping.channel_id = dest.channel_id
          mapping.last_bumped_at = Time.current
          mapping.last_journal_id = journal.id if mapping.has_attribute?(:last_journal_id) && journal.id
          mapping.save!
          client.pin_post(mapping.post_id) if setting.pin_on_bump && dest.kind == "group"
          self.class.log("created card WP ##{work_package.id} #{label} post=#{mapping.post_id}")
        elsif this.bump? || stale_card
          payload = formatter.card_payload(work_package)
          client.update_post(
            post_id: mapping.post_id,
            message: payload[:message],
            props: payload[:props]
          )
          mapping.update!(last_bumped_at: Time.current)
          client.pin_post(mapping.post_id) if setting.pin_on_bump && dest.kind == "group"
          self.class.log("bumped WP ##{work_package.id} #{label} status=#{work_package.status&.name}")
        else
          self.class.log("no bump WP ##{work_package.id} #{label} thread=#{this.thread?}")
        end

        if this.thread? && mapping.post_id.present?
          text = formatter.thread_message(journal, this)
          if text.present?
            file_ids = upload_attachments(client, dest.channel_id, this.attachments)
            client.create_post(
              channel_id: dest.channel_id,
              message: text,
              root_id: mapping.root_id.presence || mapping.post_id,
              file_ids: file_ids
            )
            self.class.log("thread WP ##{work_package.id} #{label}: #{text.lines.first.to_s.strip}")
          end
        end

        persist_snapshot(mapping, journal, work_package, write_card: card_missing || this.bump? || stale_card)
      rescue StandardError => e
        self.class.log_error("deliver WP ##{work_package.id} #{dest.kind} #{dest.username}", e)
      end

      def snapshot_for(mapping, journal)
        return unless mapping
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
