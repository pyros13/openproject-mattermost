# frozen_string_literal: true

require "spec_helper"
require "ostruct"
require_relative "../../../lib/open_project/mattermost/recipients"

RSpec.describe OpenProject::Mattermost::Recipients do
  it "collects assignee, author, accountable and watchers by login" do
    author = OpenStruct.new(id: 1, login: "Maya")
    assignee = OpenStruct.new(id: 2, login: "luca")
    responsible = OpenStruct.new(id: 3, login: "priya")
    watcher = OpenStruct.new(id: 4, login: "ops")
    wp = OpenStruct.new(
      author: author,
      assigned_to: assignee,
      responsible: responsible,
      watcher_users: [watcher],
      watchers: []
    )
    names = described_class.members(wp).map(&:username)
    expect(names).to contain_exactly("maya", "luca", "priya", "ops")
  end

  it "expands a group assignee into its users" do
    group = OpenStruct.new(id: 50, type: "Group", users: [
      OpenStruct.new(id: 2, login: "luca"),
      OpenStruct.new(id: 3, login: "priya")
    ])
    wp = OpenStruct.new(author: OpenStruct.new(id: 1, login: "maya"), assigned_to: group, watchers: [])
    expect(described_class.members(wp).map(&:username)).to contain_exactly("maya", "luca", "priya")
  end

  it "includes extra users (updater, previous DMs)" do
    wp = OpenStruct.new(author: OpenStruct.new(id: 1, login: "maya"), watchers: [])
    extra = OpenStruct.new(id: 9, login: "andrey")
    expect(described_class.members(wp, extra_users: [extra]).map(&:username)).to include("maya", "andrey")
  end

  it "includes all project members" do
    project = OpenStruct.new(
      principals: [
        OpenStruct.new(id: 10, login: "north"),
        OpenStruct.new(id: 11, login: "wind")
      ]
    )
    wp = OpenStruct.new(author: OpenStruct.new(id: 1, login: "maya"), project: project, watchers: [])
    expect(described_class.members(wp).map(&:username)).to include("maya", "north", "wind")
  end

  it "includes people the work package is shared with" do
    shared = OpenStruct.new(
      principal: OpenStruct.new(id: 20, login: "guest")
    )
    wp = OpenStruct.new(author: OpenStruct.new(id: 1, login: "maya"), members: [shared], watchers: [])
    expect(described_class.members(wp).map(&:username)).to include("maya", "guest")
  end

  it "falls back to the mail local-part" do
    user = OpenStruct.new(id: 9, login: nil, mail: "ops@example.com")
    expect(described_class.username_for(user)).to eq("ops")
  end
end
