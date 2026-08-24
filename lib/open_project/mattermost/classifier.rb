# frozen_string_literal: true

module OpenProject
  module Mattermost
    # Splits an OpenProject journal into:
    #   * card  — fields that rewrite the root Mattermost post and bump it
    #   * thread — human-readable changelog, comments, files
    #
    # OpenProject may fold later comments/status into the same journal id
    # (aggregation window). Pass +snapshot+ of what we already posted so we
    # only emit the delta — never skip the journal just because the id matches.
    class Classifier
      CARD_KEYS = %w[
        status status_id
        type type_id
        priority priority_id
        assigned_to assigned_to_id
        responsible responsible_id
        subject
        start_date due_date date
        done_ratio percentage_done
      ].freeze

      NOISE_KEYS = %w[
        author author_id
        project project_id
        ignore_non_working_days
        schedule_manually
        lock_version
        created_at updated_at
        derived_start_date derived_due_date derived_done_ratio derived_estimated_hours
        cause
        duration
        estimated_hours remaining_hours
        subject_html
        journal_id
      ].freeze

      Result = Struct.new(
        :card_details,
        :thread_details,
        :notes,
        :attachments,
        :bump?,
        :thread?,
        :opened?,
        :author_name,
        keyword_init: true
      )

      def initialize(settings:)
        @settings = settings
      end

      def call(journal, snapshot: nil)
        details = stringify_keys(journal.try(:details) || journal.try(:get_changes) || {})
        notes_full = Formatter.plain_text(journal.try(:notes).to_s)
        initial = snapshot.nil? && initial_journal?(journal)

        if snapshot
          details = detail_delta(stringify_keys(snapshot[:details]), details)
          notes_full = note_delta(snapshot[:notes], notes_full).to_s
          initial = false
        end

        card = {}
        thread = {}

        details.each do |key, change|
          key_s = key.to_s
          next if noise_key?(key_s)
          next if noop_change?(change)

          if attachment_key?(key_s)
            thread[key_s] = change if @settings.thread_files
          elsif card_key?(key_s)
            card[key_s] = change
            thread[key_s] = change unless initial
          elsif @settings.thread_other && !initial
            thread[key_s] = change
          end
        end

        notes = @settings.thread_comments ? notes_full.presence : nil
        attachments = @settings.thread_files ? journal_attachments(journal) : []

        bump = !initial && @settings.bump_on_status && card.any?
        opened = initial
        thread_wanted =
          opened ||
          notes.present? ||
          attachments.any? ||
          thread.any?

        Result.new(
          card_details: card,
          thread_details: thread,
          notes: notes.presence,
          attachments: attachments,
          bump?: bump,
          thread?: thread_wanted,
          opened?: opened,
          author_name: person_name(journal.try(:user))
        )
      end

      def self.card_key?(key)
        k = key.to_s
        return true if CARD_KEYS.include?(k)
        return true if k.end_with?("_id") && CARD_KEYS.include?(k.delete_suffix("_id"))

        false
      end

      def self.noise_key?(key)
        k = key.to_s
        return true if NOISE_KEYS.include?(k)
        return true if k.start_with?("derived_")
        return true if k.match?(/\Acause/)

        false
      end

      def self.attachment_key?(key)
        key.to_s.match?(/\Aattachments?(_\d+)?\z/) || key.to_s.start_with?("attachments_")
      end

      def card_key?(key) = self.class.card_key?(key)
      def noise_key?(key) = self.class.noise_key?(key)
      def attachment_key?(key) = self.class.attachment_key?(key)

      private

      def initial_journal?(journal)
        return true if journal.respond_to?(:initial?) && journal.initial?
        return true if journal.respond_to?(:version) && journal.version.to_i < 2

        false
      end

      def stringify_keys(hash)
        Hash(hash).each_with_object({}) do |(key, value), out|
          out[key.to_s] = value
        end
      end

      def detail_delta(previous, current)
        delta = {}
        current.each do |key, change|
          old_change = previous[key]
          next if old_change == change

          old_to = old_change.nil? ? Array(change).first : Array(old_change).last
          new_to = Array(change).last
          next if old_to.to_s == new_to.to_s

          delta[key] = [old_to, new_to]
        end
        delta
      end

      def note_delta(previous, current)
        current = Formatter.plain_text(current.to_s)
        previous = Formatter.plain_text(previous.to_s)
        return if current.blank?
        return if current == previous

        if previous.present? && current.start_with?(previous)
          extra = current[previous.length..].to_s.sub(/\A[\s\n]+/, "")
          return extra.presence
        end

        current
      end

      def noop_change?(change)
        from, to = Array(change)
        blankish(from) && blankish(to) || from.to_s == to.to_s
      end

      def blankish(value)
        value.nil? || value == "" || value == false || value == "f" || value == "false"
      end

      def person_name(user)
        return "Someone" unless user

        user.try(:name).presence ||
          [user.try(:firstname), user.try(:lastname)].compact.join(" ").strip.presence ||
          user.to_s
      end

      def journal_attachments(journal)
        journable = journal.try(:journable)
        return [] unless journable.respond_to?(:attachments)

        stamped = journal.try(:created_at) || journal.try(:updated_at)
        journable.attachments.select do |att|
          next true if stamped.nil?

          att.created_at && (att.created_at - stamped).abs < 5
        end
      rescue StandardError
        []
      end
    end
  end
end
