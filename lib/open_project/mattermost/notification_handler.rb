# frozen_string_literal: true

module OpenProject
  module Mattermost
    class NotificationHandler
      class << self
        def aggregated_journal(payload)
          journal = extract_journal(payload)
          Dispatcher.log("event aggregated_journal journal=#{journal.try(:id)} type=#{journal.try(:journable_type)}")
          return unless journal

          # Already running inside Journals::CompletedJob on the worker —
          # post now so we do not depend on a second job class being queued.
          Dispatcher.new.sync_journal(journal)
        rescue StandardError => e
          Dispatcher.log_error("aggregated_journal", e)
        end

        def journal_created(payload)
          journal = extract_journal(payload)
          Dispatcher.log("event journal_created journal=#{journal.try(:id)} type=#{journal.try(:journable_type)}")
          return unless journal
          return unless journal.try(:journable_type).to_s == "WorkPackage"

          # Web request — queue so we do not block the save. Aggregated
          # event (worker) will post even if this job never runs.
          ::Mattermost::SyncJournalJob.perform_later(journal.id)
          Dispatcher.log("enqueued SyncJournalJob journal=#{journal.id}")
        rescue StandardError => e
          Dispatcher.log_error("journal_created enqueue", e)
          Dispatcher.new.sync_journal(journal) if journal
        end

        def attachment_created(payload)
          attachment = extract_attachment(payload)
          Dispatcher.log("event attachment_created id=#{attachment.try(:id)}")
          return unless attachment
          return unless attachment.try(:id)

          ::Mattermost::SyncAttachmentJob.perform_later(attachment.id)
        rescue StandardError => e
          Dispatcher.log_error("attachment_created", e)
        end

        def extract_journal(payload)
          return payload if payload.is_a?(Journal)
          return unless payload.respond_to?(:[])

          payload[:journal] || payload["journal"] || payload[:journable] || payload["journable"]
        end

        def extract_attachment(payload)
          return payload if payload.is_a?(Attachment)
          return payload unless payload.respond_to?(:[])

          payload[:attachment] || payload["attachment"] || payload
        end
      end
    end
  end
end
