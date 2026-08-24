# frozen_string_literal: true

require "spec_helper"
require "ostruct"
require_relative "../../../lib/open_project/mattermost/formatter"
require_relative "../../../lib/open_project/mattermost/classifier"

RSpec.describe OpenProject::Mattermost::Classifier do
  let(:settings) do
    OpenStruct.new(
      bump_on_status: true,
      thread_comments: true,
      thread_files: true,
      thread_other: true
    )
  end
  let(:classifier) { described_class.new(settings: settings) }

  def journal(details:, notes: nil, initial: false, user: nil)
    OpenStruct.new(
      details: details,
      notes: notes,
      journable: nil,
      created_at: Time.now,
      initial?: initial,
      version: initial ? 1 : 2,
      user: user
    )
  end

  it "bumps the card and threads a status change" do
    result = classifier.call(journal(details: { "status_id" => [1, 2] }))
    expect(result.bump?).to eq(true)
    expect(result.thread?).to eq(true)
    expect(result.card_details).to have_key("status_id")
    expect(result.thread_details).to have_key("status_id")
  end

  it "threads comments without bumping" do
    result = classifier.call(journal(details: {}, notes: "Looks good"))
    expect(result.bump?).to eq(false)
    expect(result.thread?).to eq(true)
    expect(result.notes).to eq("Looks good")
  end

  it "strips html from comments" do
    result = classifier.call(journal(details: {}, notes: "Some Comments<br>"))
    expect(result.notes).to eq("Some Comments")
  end

  it "bumps and threads when a journal has both status and a comment" do
    result = classifier.call(journal(details: { "status_id" => [1, 3] }, notes: "Moving to QA"))
    expect(result.bump?).to eq(true)
    expect(result.thread?).to eq(true)
  end

  it "threads description diffs" do
    result = classifier.call(journal(details: { "description" => %w[old new] }))
    expect(result.bump?).to eq(false)
    expect(result.thread?).to eq(true)
    expect(result.thread_details).to have_key("description")
  end

  it "does not thread author/project/ignore_non_working_days noise" do
    result = classifier.call(
      journal(details: {
                "project" => [nil, 14],
                "author" => [nil, 3],
                "ignore_non_working_days" => [nil, false],
                "status_id" => [1, 2]
              })
    )
    expect(result.thread_details.keys).to eq(["status_id"])
    expect(result.card_details).to have_key("status_id")
  end

  it "on create only marks opened, does not dump every attribute" do
    user = OpenStruct.new(name: "Maya Chen")
    result = classifier.call(
      journal(
        details: {
          "project" => [nil, 14],
          "author" => [nil, 3],
          "ignore_non_working_days" => [nil, false],
          "status_id" => [nil, 1],
          "subject" => [nil, "Test OP New"]
        },
        initial: true,
        user: user
      )
    )
    expect(result.opened?).to eq(true)
    expect(result.thread?).to eq(true)
    expect(result.bump?).to eq(false)
    expect(result.thread_details).to be_empty
    expect(result.author_name).to eq("Maya Chen")
  end

  it "does not bump when bump_on_status is off" do
    settings.bump_on_status = false
    result = classifier.call(journal(details: { "assigned_to_id" => [nil, 9] }))
    expect(result.bump?).to eq(false)
    expect(result.thread?).to eq(true)
  end
end

RSpec.describe OpenProject::Mattermost::Formatter do
  let(:formatter) { described_class.new(url_helpers: nil) }

  it "renders opened by on the initial journal" do
    classified = OpenStruct.new(opened?: true, author_name: "Maya Chen", notes: nil, thread_details: {}, attachments: [])
    expect(formatter.thread_message(nil, classified)).to eq("Opened by **Maya Chen**")
  end

  it "strips html from notes and skips empty thread details" do
    classified = OpenStruct.new(
      opened?: false,
      notes: described_class.plain_text("Some Comments<br>"),
      thread_details: {},
      attachments: []
    )
    expect(formatter.thread_message(nil, classified)).to eq("Some Comments")
  end

  it "formats a status change as names when records exist, else the raw values" do
    classified = OpenStruct.new(
      opened?: false,
      notes: nil,
      thread_details: { "subject" => ["Old", "New title"] },
      attachments: []
    )
    expect(formatter.thread_message(nil, classified)).to eq("**Subject**  Old → New title")
  end
end
