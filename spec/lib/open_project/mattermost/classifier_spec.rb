# frozen_string_literal: true

require "spec_helper"
require "ostruct"
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

  def journal(details:, notes: nil)
    OpenStruct.new(details: details, notes: notes, journable: nil, created_at: Time.now)
  end

  it "bumps the root card on status change" do
    result = classifier.call(journal(details: { "status_id" => [1, 2] }))
    expect(result.bump?).to eq(true)
    expect(result.thread?).to eq(false)
    expect(result.card_details).to have_key("status_id")
  end

  it "threads comments without bumping" do
    result = classifier.call(journal(details: {}, notes: "Looks good"))
    expect(result.bump?).to eq(false)
    expect(result.thread?).to eq(true)
    expect(result.notes).to eq("Looks good")
  end

  it "bumps and threads when a journal has both status and a comment" do
    result = classifier.call(journal(details: { "status_id" => [1, 3] }, notes: "Moving to QA"))
    expect(result.bump?).to eq(true)
    expect(result.thread?).to eq(true)
  end

  it "threads description and watcher diffs as other changes" do
    result = classifier.call(journal(details: { "description" => %w[old new] }))
    expect(result.bump?).to eq(false)
    expect(result.thread?).to eq(true)
    expect(result.thread_details).to have_key("description")
  end

  it "does not bump when bump_on_status is off" do
    settings.bump_on_status = false
    result = classifier.call(journal(details: { "assigned_to_id" => [nil, 9] }))
    expect(result.bump?).to eq(false)
  end
end
