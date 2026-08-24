# frozen_string_literal: true

module Mattermost
  class SyncJournalJob < ApplicationJob
    queue_with_priority :notification

    def perform(journal_id)
      journal = Journal.find_by(id: journal_id)
      unless journal
        OpenProject::Mattermost::Dispatcher.log("job skip: journal #{journal_id} gone")
        return
      end

      OpenProject::Mattermost::Dispatcher.new.sync_journal(journal)
    end
  end
end
