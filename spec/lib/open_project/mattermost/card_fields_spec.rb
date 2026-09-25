# frozen_string_literal: true

require "spec_helper"
require "ostruct"
require_relative "../../../lib/open_project/mattermost/card_fields"

RSpec.describe OpenProject::Mattermost::CardFields do
  let(:config) do
    {
      "default" => %w[status assignee],
      "by_type" => { "4" => %w[priority custom_field_7] }
    }
  end

  it "uses the workflow override for that type" do
    wp = OpenStruct.new(type_id: 4)
    expect(described_class.keys_for(wp, config: config)).to eq(%w[priority custom_field_7])
  end

  it "falls back to the default fields" do
    wp = OpenStruct.new(type_id: 9)
    expect(described_class.keys_for(wp, config: config)).to eq(%w[status assignee])
  end

  it "maps journal keys onto field keys" do
    expect(described_class.field_for_detail("status_id")).to eq("status")
    expect(described_class.field_for_detail("custom_fields_7")).to eq("custom_field_7")
  end

  it "hides a field the workflow did not select" do
    wp = OpenStruct.new(type_id: 4)
    expect(described_class.detail_allowed?(wp, "priority_id", config: config)).to be true
    expect(described_class.detail_allowed?(wp, "status_id", config: config)).to be false
  end

  it "keeps unknown journal keys" do
    wp = OpenStruct.new(type_id: 4)
    expect(described_class.detail_allowed?(wp, "lock_version", config: config)).to be true
  end

  it "stores a type override only when it does not use the default" do
    raw = {
      "default" => { "fields" => %w[status] },
      "3" => { "use_default" => "1", "fields" => %w[assignee] },
      "4" => { "use_default" => "0", "fields" => ["", "priority"] }
    }
    expect(described_class.normalize(raw)).to eq(
      "default" => ["status"],
      "by_type" => { "4" => ["priority"] }
    )
  end

  it "shows yes or no for boolean custom fields and keeps plain numbers" do
    expect(described_class.format_stored_value(OpenStruct.new(field_format: "bool"), "1")).to eq("Yes")
    expect(described_class.format_stored_value(OpenStruct.new(field_format: "bool"), "0")).to eq("No")
    expect(described_class.format_stored_value(OpenStruct.new(field_format: "int"), "8")).to eq("8")
    expect(described_class.format_stored_value(OpenStruct.new(field_format: "list"), "Night work")).to eq("Night work")
  end
end
