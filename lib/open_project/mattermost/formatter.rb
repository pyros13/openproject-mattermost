# frozen_string_literal: true

module OpenProject
  module Mattermost
    # Builds Mattermost attachment payloads for the root status card
    # and markdown for thread replies. Thread lines use names, never raw ids.
    class Formatter
      LABELS = {
        "status_id" => "Status",
        "status" => "Status",
        "type_id" => "Type",
        "type" => "Type",
        "priority_id" => "Priority",
        "priority" => "Priority",
        "assigned_to_id" => "Assignee",
        "assigned_to" => "Assignee",
        "responsible_id" => "Accountable",
        "responsible" => "Accountable",
        "subject" => "Subject",
        "start_date" => "Start date",
        "due_date" => "Due date",
        "date" => "Date",
        "done_ratio" => "% Complete",
        "percentage_done" => "% Complete",
        "description" => "Description",
        "category_id" => "Category",
        "category" => "Category",
        "version_id" => "Version",
        "version" => "Version",
        "parent_id" => "Parent",
        "parent" => "Parent",
        "story_points" => "Story points"
      }.freeze

      ID_MODELS = {
        "status_id" => %w[Status],
        "type_id" => %w[Type],
        "priority_id" => %w[IssuePriority Priority],
        "assigned_to_id" => %w[Principal User],
        "responsible_id" => %w[Principal User],
        "category_id" => %w[Category],
        "version_id" => %w[Version],
        "project_id" => %w[Project],
        "parent_id" => %w[WorkPackage]
      }.freeze

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
        author = classified.author_name.presence || "Someone"
        if classified.opened?
          return "Opened by **#{author}**"
        end

        parts = []
        parts << classified.notes if classified.notes.present?

        classified.thread_details.each do |key, change|
          next if Classifier.attachment_key?(key)
          line = format_detail(key, change)
          parts << line if line.present?
        end

        Array(classified.try(:removed_filenames)).each do |name|
          parts << "Removed **#{name}**"
        end

        classified.attachments.each do |att|
          name = att.try(:filename) || att.try(:name) || "file"
          parts << "Attached **#{name}**"
        end

        return if parts.empty?

        "**#{author}**\n#{parts.join("\n")}"
      end

      def self.plain_text(html)
        require "cgi"
        s = html.to_s.dup
        s.gsub!(%r{<\s*br\s*/?\s*>}i, "\n")
        s.gsub!(%r{<\s*/p\s*>}i, "\n")
        s.gsub!(%r{<\s*li[^>]*>}i, "* ")
        s.gsub!(/<[^>]+>/, "")
        s = CGI.unescapeHTML(s)
        s.gsub!("\u00a0", " ")
        s.gsub!(/[ \t]+\n/, "\n")
        s.gsub!(/\n{3,}/, "\n\n")
        s.strip
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
        hex = extract_status_hex(status)
        return hex if hex

        name = status&.name.to_s.downcase
        return "#5b8c7a" if name.match?(/closed|done|resolved/)
        return "#c48a4a" if name.match?(/progress|active/)
        return "#a78a5a" if name.match?(/wait|hold|blocked/)

        "#3aa0c8"
      end

      def extract_status_hex(status)
        return if status.nil?

        color = status.try(:color)
        candidates = [
          (color if color.is_a?(String)),
          color.try(:hexcode),
          color.try(:hex),
          status.try(:hexcode),
          status.try(:hex),
          status.try(:color_code)
        ]
        candidates.each do |value|
          normalized = normalize_hex(value)
          return normalized if normalized
        end
        nil
      end

      def normalize_hex(value)
        s = value.to_s.strip
        s = s.delete_prefix("#")
        return if s.empty?
        return "##{s}#{s}" if s.match?(/\A[0-9A-Fa-f]{3}\z/)
        return "##{s}" if s.match?(/\A[0-9A-Fa-f]{6}\z/)

        nil
      end

      def format_detail(key, change)
        key_s = key.to_s
        from, to = Array(change)
        from_s = human_value(key_s, from)
        to_s = human_value(key_s, to)
        return if from_s == to_s

        if key_s == "description"
          return "**Description** updated" if from_s == "—"
          return "**Description**  #{from_s} → #{to_s}"
        end

        "**#{human_key(key_s)}**  #{from_s} → #{to_s}"
      end

      def human_key(key)
        return LABELS[key] if LABELS[key]
        if key.match?(/\Acustom_field[s]?_(\d+)\z/)
          id = Regexp.last_match(1)
          name = lookup_record(%w[CustomField], id)&.try(:name)
          return name if name.present?
        end

        key.sub(/_id\z/, "").tr("_", " ").capitalize
      end

      def human_value(key, value)
        return "—" if value.nil? || value == ""
        return "Yes" if value == true || value == "t" || value == "true"
        return "No" if value == false || value == "f" || value == "false"

        if %w[done_ratio percentage_done].include?(key)
          return "#{value}%"
        end

        if ID_MODELS[key]
          rec = lookup_record(ID_MODELS[key], value)
          if rec
            return "##{rec.id} #{rec.subject}" if rec.respond_to?(:subject) && rec.try(:subject)
            return rec.try(:name).presence || rec.to_s
          end
        end

        if key.match?(/_id\z/) && value.to_s.match?(/\A\d+\z/)
          return value.to_s
        end

        text = self.class.plain_text(value.to_s)
        text = "#{text[0, 180]}…" if text.length > 180
        text.presence || "—"
      end

      def lookup_record(class_names, id)
        Array(class_names).each do |name|
          klass = name.constantize
          rec = klass.find_by(id: id)
          return rec if rec
        rescue NameError, StandardError
          next
        end
        nil
      end

      def work_package_url(work_package)
        @url_helpers.work_package_url(work_package)
      rescue StandardError
        "/work_packages/#{work_package.id}"
      end
    end
  end
end
