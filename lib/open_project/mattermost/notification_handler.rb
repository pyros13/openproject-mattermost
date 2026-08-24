# frozen_string_literal: true

module OpenProject
  module Mattermost
    class NotificationHandler
      class << self
        def aggregated_journal(payload)
          journal = payload[:journal] || payload["journal"]
          return unless journal
          return unless journal.journable_type.to_s == "WorkPackage"

          Mattermost::SyncJournalJob.perform_later(journal.id)
        end

        def attachment_created(payload)
          attachment = payload[:attachment] || payload["attachment"] || payload
          return unless attachment
          return unless attachment.try(:container_type).to_s == "WorkPackage"

          Mattermost::SyncAttachmentJob.perform_later(attachment.id)
        end
      end
    end
  end
end
