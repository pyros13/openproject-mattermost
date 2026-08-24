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
    OpenProject plugin — requires OpenProject core. Channel ID is per project;
    one bot token is shared.
  DESC
  s.license = "GPL-3.0"

  s.files = Dir["{app,config,db,lib,spec}/**/*"] + %w[README.md CHANGELOG.md LICENSE Gemfile.plugins.example]

  s.required_ruby_version = ">= 3.2.0"

  # OpenProject core already ships Rails and OpenProject::Plugins
  # (ActsAsOpEngine). Do not depend on the 2013 RubyGems gem
  # "openproject-plugins" (~> 1.0) — it pins rails ~> 3.2.9 and Bundler
  # will refuse this plugin on current OpenProject (Rails 8.1).
  # Do not depend on rails either. Only list gems that are not in core.
  # This plugin uses stdlib Net::HTTP only.
end
