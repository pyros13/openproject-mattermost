# frozen_string_literal: true

require_relative "lib/open_project/mattermost/version"

Gem::Specification.new do |s|
  s.name        = "openproject-mattermost"
  s.version     = OpenProject::Mattermost::VERSION
  s.authors     = ["Andrey Iurov"]
  s.email       = ["openproject-mattermost@local"]
  s.homepage    = "https://github.com/openproject/openproject-mattermost"
  s.summary     = "Mattermost bot for OpenProject work packages"
  s.description = <<~DESC
    Posts each work package as a single Mattermost status card. Status, dates,
    assignee and progress rewrite that same post (timestamp changes so it UPs).
    Comments, files and other journal changes are pushed as thread replies.
  DESC
  s.license = "GPL-3.0"

  s.files = Dir["{app,config,db,lib,spec}/**/*"] + %w[README.md CHANGELOG.md LICENSE Gemfile.plugins.example]

  s.required_ruby_version = ">= 3.2.0"

  s.add_dependency "openproject-plugins", "~> 1.0"
end
