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
    expect(result.thread_details).to be_empty
    expect(result.author_name).to eq("Maya Chen")
  end

  it "on a later comment folded into the same journal, threads only the new notes" do
    j = journal(
      details: {
        "project" => [nil, 14],
        "status_id" => [nil, 1],
        "subject" => [nil, "Test OP New"]
      },
      notes: "Some Comments<br>",
      initial: true,
      user: OpenStruct.new(name: "Maya Chen")
    )
    snapshot = {
      notes: "",
      details: {
        "project" => [nil, 14],
        "status_id" => [nil, 1],
        "subject" => [nil, "Test OP New"]
      }
    }
    result = classifier.call(j, snapshot: snapshot)
    expect(result.opened?).to eq(false)
    expect(result.notes).to eq("Some Comments")
    expect(result.thread_details).to be_empty
  end

  it "on a status change folded into the same journal, bumps and threads the named status" do
    j = journal(
      details: { "status_id" => [nil, 2], "subject" => [nil, "Test OP New"] },
      initial: true
    )
    snapshot = {
      notes: "",
      details: { "status_id" => [nil, 1], "subject" => [nil, "Test OP New"] }
    }
    result = classifier.call(j, snapshot: snapshot)
    expect(result.opened?).to eq(false)
    expect(result.bump?).to eq(true)
    expect(result.thread_details["status_id"]).to eq([1, 2])
  end

  it "treats attachments_N as a file, not a field diff" do
    result = classifier.call(
      journal(details: { "attachments_23" => [nil, "bill_c_r_example.PNG"] })
    )
    expect(result.thread_details).to be_empty
    expect(result.attachments.map { |a| a.filename }).to eq(["bill_c_r_example.PNG"])
    expect(result.thread?).to eq(true)
  end

  it "applies a live status delta when the journal omitted the change" do
    result = classifier.call(journal(details: {}, notes: nil))
    expect(result.bump?).to eq(false)
    merged = described_class.apply_live_card_delta(result, { "status_id" => [1, 9] })
    expect(merged.bump?).to eq(true)
    expect(merged.thread_details["status_id"]).to eq([1, 9])
  end
end

RSpec.describe OpenProject::Mattermost::Formatter do
  let(:formatter) { described_class.new(url_helpers: nil) }

  it "renders opened by on the initial journal" do
    classified = OpenStruct.new(
      opened?: true,
      author_name: "Maya Chen",
      notes: nil,
      thread_details: {},
      attachments: [],
      removed_filenames: []
    )
    expect(formatter.thread_message(nil, classified)).to eq("Opened by **Maya Chen**")
  end

  it "prefixes the OpenProject user on comments" do
    classified = OpenStruct.new(
      opened?: false,
      author_name: "Maya Chen",
      notes: described_class.plain_text("Some Comments<br>"),
      thread_details: {},
      attachments: [],
      removed_filenames: []
    )
    expect(formatter.thread_message(nil, classified)).to eq("**Maya Chen**\nSome Comments")
  end

  it "formats a field change under the user who made it" do
    classified = OpenStruct.new(
      opened?: false,
      author_name: "Luca Voss",
      notes: nil,
      thread_details: { "subject" => ["Old", "New title"] },
      attachments: [],
      removed_filenames: []
    )
    expect(formatter.thread_message(nil, classified)).to eq("**Luca Voss**\n**Subject**  Old → New title")
  end

  it "uses the OpenProject status color hex on the card" do
    wp = OpenStruct.new(
      id: 12,
      subject: "Paint",
      type: OpenStruct.new(name: "Task"),
      status: OpenStruct.new(name: "In progress", color: OpenStruct.new(hexcode: "#F49D1A")),
      assigned_to: nil,
      priority: OpenStruct.new(name: "Normal"),
      due_date: nil,
      done_ratio: 0,
      project: OpenStruct.new(name: "Kitewell")
    )
    payload = formatter.card_payload(wp, bumped_at: Time.at(0))
    expect(payload[:props][:attachments].first[:color]).to eq("#F49D1A")
  end
end
