# frozen_string_literal: true

module OpenProject
  module Mattermost
    # Builds Mattermost attachment payloads for the root status card
    # and markdown for thread replies.
    class Formatter
      def initialize(url_helpers: OpenProject::StaticRouting::StaticUrlHelpers.new)
        @url_helpers = url_helpers
      end

      def card_payload(work_package, bumped_at: Time.current)
        color = status_color(work_package.status)
        {
          message: heading(work_package),
          props: {
            from_bot: "true",
            op_work_package_id: work_package.id.to_s,
            op_bumped_at: bumped_at.to_i.to_s,
            attachments: [
              {
                fallback: heading(work_package),
                color: color,
                title: "##{work_package.id} #{work_package.subject}",
                title_link: work_package_url(work_package),
                fields: card_fields(work_package),
                footer: "#{work_package.project&.name} · updated",
                ts: bumped_at.to_i
              }
            ]
          }
        }
      end

      def thread_message(journal, classified)
        parts = []
        author = journal.try(:user).to_s
        parts << classified.notes if classified.notes.present?

        classified.thread_details.each do |key, change|
          parts << format_detail(key, change)
        end

        classified.attachments.each do |att|
          name = att.try(:filename) || att.try(:name) || "file"
          parts << "Attached **#{name}**"
        end

        return "_#{author} updated this work package_" if parts.empty?

        parts.join("\n")
      end

      def created_message(work_package)
        author = work_package.author.to_s
        "#{author} created this work package"
      end

      private

      def heading(work_package)
        type = work_package.type&.name || "Work package"
        "#{type} ##{work_package.id}  #{work_package.subject}"
      end

      def card_fields(work_package)
        [
          field("Status", work_package.status&.name),
          field("Assignee", work_package.assigned_to&.name || "Unassigned"),
          field("Priority", work_package.priority&.name),
          field("Due", work_package.due_date&.to_s || "—"),
          field("% Complete", percent(work_package)),
          field("Type", work_package.type&.name)
        ]
      end

      def field(title, value)
        { title: title, value: value.to_s, short: true }
      end

      def percent(work_package)
        if work_package.respond_to?(:done_ratio) && work_package.done_ratio
          "#{work_package.done_ratio}%"
        elsif work_package.respond_to?(:percentage_done) && work_package.percentage_done
          "#{work_package.percentage_done}%"
        else
          "—"
        end
      end

      def status_color(status)
        name = status&.name.to_s.downcase
        return "#5b8c7a" if name.match?(/closed|done|resolved/)
        return "#c48a4a" if name.match?(/progress|active/)
        return "#a78a5a" if name.match?(/wait|hold|blocked/)

        "#3aa0c8"
      end

      def format_detail(key, change)
        from, to = Array(change)
        "**#{human_key(key)}**  #{from.presence || '—'} → #{to.presence || '—'}"
      end

      def human_key(key)
        key.to_s.sub(/_id\z/, "").tr("_", " ").capitalize
      end

      def work_package_url(work_package)
        @url_helpers.work_package_url(work_package)
      rescue StandardError
        "/work_packages/#{work_package.id}"
      end
    end
  end
end
