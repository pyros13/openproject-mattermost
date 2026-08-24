# frozen_string_literal: true

module Mattermost
  class SyncAttachmentJob < ApplicationJob
    queue_with_priority :notification

    def perform(attachment_id)
      attachment = Attachment.find_by(id: attachment_id)
      unless attachment
        OpenProject::Mattermost::Dispatcher.log("job skip: attachment #{attachment_id} gone")
        return
      end

      OpenProject::Mattermost::Dispatcher.new.sync_attachment(attachment)
    end
  end
end
