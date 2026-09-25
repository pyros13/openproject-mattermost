# frozen_string_literal: true

module OpenProject
  module Mattermost
    # Which attributes appear on the Mattermost card and in thread field lines.
    # Workflows in OpenProject are per work package type, so each type can
    # override the global default.
    class CardFields
      BUILTIN = [
        ["status", "Status"],
        ["assignee", "Assignee"],
        ["accountable", "Accountable"],
        ["priority", "Priority"],
        ["type", "Type"],
        ["author", "Author"],
        ["start_date", "Start date"],
        ["due_date", "Due date"],
        ["done_ratio", "% Complete"],
        ["category", "Category"],
        ["version", "Version"],
        ["parent", "Parent"],
        ["project", "Project"],
        ["story_points", "Story points"],
        ["estimated_hours", "Estimated time"],
        ["remaining_hours", "Remaining time"],
        ["description", "Description"]
      ].freeze

      DEFAULT_KEYS = %w[status assignee priority due_date done_ratio type].freeze

      DETAIL_KEYS = {
        "status_id" => "status",
        "status" => "status",
        "assigned_to_id" => "assignee",
        "assigned_to" => "assignee",
        "responsible_id" => "accountable",
        "responsible" => "accountable",
        "priority_id" => "priority",
        "priority" => "priority",
        "type_id" => "type",
        "author_id" => "author",
        "author" => "author",
        "start_date" => "start_date",
        "due_date" => "due_date",
        "done_ratio" => "done_ratio",
        "percentage_done" => "done_ratio",
        "category_id" => "category",
        "category" => "category",
        "version_id" => "version",
        "version" => "version",
        "parent_id" => "parent",
        "parent" => "parent",
        "project_id" => "project",
        "project" => "project",
        "story_points" => "story_points",
        "estimated_hours" => "estimated_hours",
        "remaining_hours" => "remaining_hours",
        "description" => "description"
      }.freeze

      def self.config
        raw = {}
        if defined?(::Mattermost::BotConfig)
          stored = ::Mattermost::BotConfig.settings[:card_fields]
          raw = stored.to_h if stored.respond_to?(:to_h)
        end
        raw = raw.stringify_keys if raw.respond_to?(:stringify_keys)
        default = if raw.key?("default")
                    Array(raw["default"]).map(&:to_s).reject(&:blank?)
                  else
                    DEFAULT_KEYS
                  end
        by_type = {}
        Hash(raw["by_type"]).each do |type_id, keys|
          by_type[type_id.to_s] = Array(keys).map(&:to_s).reject(&:blank?)
        end
        { "default" => default, "by_type" => by_type }
      end

      def self.normalize(raw)
        raw = raw.to_unsafe_h if raw.respond_to?(:to_unsafe_h)
        raw = raw.to_h if raw.respond_to?(:to_h)
        default = DEFAULT_KEYS
        by_type = {}
        Hash(raw).each do |id, body|
          body = {} unless body.respond_to?(:[])
          fields = Array(body["fields"] || body[:fields]).map(&:to_s).reject(&:blank?).uniq
          if id.to_s == "default"
            default = fields
          elsif (body["use_default"] || body[:use_default]).to_s == "1"
            next
          else
            by_type[id.to_s] = fields
          end
        end
        { "default" => default, "by_type" => by_type }
      end

      def self.keys_for(work_package, config: nil)
        stored = config || self.config
        type_id = work_package.try(:type_id).to_s
        by_type = stored["by_type"] || {}
        if type_id.present? && by_type.key?(type_id)
          Array(by_type[type_id])
        elsif stored.key?("default")
          Array(stored["default"])
        else
          DEFAULT_KEYS
        end
      end

      def self.field_for_detail(journal_key)
        key = journal_key.to_s
        return DETAIL_KEYS[key] if DETAIL_KEYS[key]
        if key =~ /\Acustom_fields?_(\d+)\z/
          return "custom_field_#{Regexp.last_match(1)}"
        end

        nil
      end

      def self.detail_allowed?(work_package, journal_key, config: nil)
        field = field_for_detail(journal_key)
        return true if field.nil?

        keys_for(work_package, config: config).include?(field)
      end

      def self.workflows
        types = load_types
        [default_workflow] + types.map { |type| workflow_for(type) }
      end

      def self.default_workflow
        stored = config
        {
          id: "default",
          name: "Default (every workflow)",
          use_default: false,
          fields: field_options(nil),
          selected: stored["default"]
        }
      end

      def self.workflow_for(type)
        stored = config
        id = type.id.to_s
        override = stored["by_type"].key?(id)
        {
          id: id,
          name: type.try(:name).to_s,
          use_default: !override,
          fields: field_options(type),
          selected: override ? stored["by_type"][id] : stored["default"]
        }
      end

      def self.field_options(type)
        options = BUILTIN.map { |key, label| { key: key, label: label } }
        custom_fields_for(type).each do |field|
          options << { key: "custom_field_#{field.id}", label: field.try(:name).to_s }
        end
        options
      end

      def self.load_types
        return [] unless defined?(::Type)

        ::Type.order(:position, :name).to_a
      rescue StandardError
        []
      end

      def self.custom_fields_for(type)
        if type && type.respond_to?(:custom_fields)
          return Array(type.custom_fields)
        end
        return [] unless type.nil?
        return [] unless defined?(::WorkPackageCustomField)

        ::WorkPackageCustomField.order(:position, :name).to_a
      rescue StandardError
        []
      end

      def self.entries(work_package, config: nil)
        keys_for(work_package, config: config).filter_map do |key|
          title, value = pair(work_package, key)
          next if title.blank?

          { title: title, value: value.to_s.presence || "—" }
        end
      end

      def self.pair(work_package, key)
        case key
        when "status" then ["Status", work_package.try(:status).try(:name)]
        when "assignee" then ["Assignee", work_package.try(:assigned_to).try(:name) || "Unassigned"]
        when "accountable" then ["Accountable", work_package.try(:responsible).try(:name) || "—"]
        when "priority" then ["Priority", work_package.try(:priority).try(:name)]
        when "type" then ["Type", work_package.try(:type).try(:name)]
        when "author" then ["Author", work_package.try(:author).try(:name)]
        when "start_date" then ["Start date", work_package.try(:start_date)]
        when "due_date" then ["Due", work_package.try(:due_date)]
        when "done_ratio" then ["% Complete", percent(work_package)]
        when "category" then ["Category", work_package.try(:category).try(:name)]
        when "version" then ["Version", work_package.try(:version).try(:name)]
        when "parent" then ["Parent", parent_label(work_package)]
        when "project" then ["Project", work_package.try(:project).try(:name)]
        when "story_points" then ["Story points", work_package.try(:story_points)]
        when "estimated_hours" then ["Estimated time", work_package.try(:estimated_hours)]
        when "remaining_hours" then ["Remaining time", work_package.try(:remaining_hours)]
        when "description"
          text = Formatter.plain_text(work_package.try(:description))
          text = "#{text[0, 180]}…" if text.length > 180
          ["Description", text]
        else
          custom_pair(work_package, key)
        end
      end

      def self.custom_pair(work_package, key)
        return unless key =~ /\Acustom_field_(\d+)\z/

        field = find_custom_field(Regexp.last_match(1))
        label = field.try(:name).presence || "Custom field #{Regexp.last_match(1)}"
        [label, custom_value(work_package, field, Regexp.last_match(1))]
      end

      def self.find_custom_field(id)
        if defined?(::CustomField)
          ::CustomField.find_by(id: id)
        end
      rescue StandardError
        nil
      end

      def self.custom_value(work_package, field, id)
        value = nil
        if field && work_package.respond_to?(:custom_value_for)
          raw = work_package.custom_value_for(field)
          value = raw.respond_to?(:typed_value) ? (raw.typed_value || raw.try(:value)) : raw.try(:value)
        end
        if value.nil? && work_package.respond_to?(:custom_field_values)
          Array(work_package.custom_field_values).each do |row|
            next unless row.try(:custom_field_id).to_s == id.to_s

            value = row.try(:typed_value) || row.try(:value)
            break
          end
        end
        return "—" if value.nil? || value == ""
        return value.join(", ") if value.is_a?(Array)

        Formatter.plain_text(value.to_s)
      rescue StandardError
        "—"
      end

      def self.percent(work_package)
        if work_package.respond_to?(:done_ratio) && !work_package.done_ratio.nil?
          "#{work_package.done_ratio}%"
        elsif work_package.respond_to?(:percentage_done) && !work_package.percentage_done.nil?
          "#{work_package.percentage_done}%"
        else
          "—"
        end
      end

      def self.parent_label(work_package)
        parent = work_package.try(:parent)
        return "—" if parent.nil?

        "##{parent.id} #{parent.try(:subject)}"
      end
    end
  end
end
