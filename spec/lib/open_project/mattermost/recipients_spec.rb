# frozen_string_literal: true

require "spec_helper"
require "ostruct"
require_relative "../../../lib/open_project/mattermost/recipients"

RSpec.describe OpenProject::Mattermost::Recipients do
  it "collects assignee, author, accountable and watchers by login" do
    author = OpenStruct.new(id: 1, login: "Maya")
    assignee = OpenStruct.new(id: 2, login: "luca")
    responsible = OpenStruct.new(id: 3, login: "priya")
    watcher = OpenStruct.new(id: 2, login: "luca")
    wp = OpenStruct.new(
      author: author,
      assigned_to: assignee,
      responsible: responsible,
      watchers: [watcher]
    )
    names = described_class.members(wp).map(&:username)
    expect(names).to contain_exactly("maya", "luca", "priya")
  end

  it "falls back to the mail local-part" do
    user = OpenStruct.new(id: 9, login: nil, mail: "ops@example.com")
    expect(described_class.username_for(user)).to eq("ops")
  end
end
