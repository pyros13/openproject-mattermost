# frozen_string_literal: true

module OpenProject
  module Mattermost
    # Splits an OpenProject journal into:
    #   * card  — fields that rewrite the root Mattermost post and bump it
    #   * thread — comments, files, and every other change, posted as replies
    class Classifier
      CARD_KEYS = %w[
        status status_id
        type type_id
        priority priority_id
        assigned_to assigned_to_id
        responsible responsible_id
        subject
        start_date due_date date
        done_ratio percentage_done estimated_hours remaining_hours duration
        schedule_manually
      ].freeze

      THREAD_KEYS = %w[
        description
        category_id category
        version_id version
        parent_id parent
        subject_html
      ].freeze

      Result = Struct.new(
        :card_details,
        :thread_details,
        :notes,
        :attachments,
        :bump?,
        :thread?,
        keyword_init: true
      )

      def initialize(settings:)
        @settings = settings
      end

      def call(journal)
        details = Hash(journal.try(:details) || journal.try(:get_changes) || {})
        card = {}
        thread = {}

        details.each do |key, change|
          key_s = key.to_s
          if attachment_key?(key_s)
            thread[key_s] = change
          elsif card_key?(key_s)
            card[key_s] = change
          else
            thread[key_s] = change
          end
        end

        notes = journal.try(:notes).to_s
        attachments = Array(journal.try(:attachable) ? [] : nil)
        attachments = journal_attachments(journal)

        bump = @settings.bump_on_status && card.any?
        thread_wanted =
          (@settings.thread_comments && notes.present?) ||
          (@settings.thread_files && attachments.any?) ||
          (@settings.thread_other && thread.any?)

        Result.new(
          card_details: card,
          thread_details: thread,
          notes: notes.presence,
          attachments: attachments,
          bump?: bump,
          thread?: thread_wanted
        )
      end

      def self.card_key?(key)
        k = key.to_s
        return true if CARD_KEYS.include?(k)
        return true if k.end_with?("_id") && CARD_KEYS.include?(k.delete_suffix("_id"))

        false
      end

      def self.attachment_key?(key)
        key.to_s.match?(/\Aattachments?(_\d+)?\z/) || key.to_s.start_with?("attachments_")
      end

      def card_key?(key) = self.class.card_key?(key)
      def attachment_key?(key) = self.class.attachment_key?(key)

      private

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
