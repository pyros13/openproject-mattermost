# Changelog

## 1.0.2 — 2026-08-24

- Boot fix for OpenProject 17 / Rails 8.1: drop `include Admin::Settings::SettingsHelper` (that constant is not in core). Admin settings now match the GitHub integration controller (`layout "admin"`, `menu_item`, `require_admin`).
- Plugin settings partial path is `settings/mattermost` so Administration → Plugins → Configure renders.
- HOTFIX.md: restarting git SHA `bb7f2c81ad20` is not an update — delete the include in the vendor copy to boot, then rebundle 1.0.2.

## 1.0.1 — 2026-08-24

- Drop the 2013 `openproject-plugins` gemspec dependency. It pinned `rails ~> 3.2.9` and Bundler refused the plugin on OpenProject (Rails 8.1). Plugin APIs (`OpenProject::Plugins::ActsAsOpEngine`) come from OpenProject core. No Rails dependency either.

## 1.0.0 — 2026-08-24

- Post each work package as a single Mattermost status card via a bot account.
- Status, dates, assignee, type, priority and % complete rewrite the same post (`PUT /posts/{id}`) so `update_at` changes and the card UPs.
- Optional pin after bump.
- Comments, files, description, watchers, versions and other journal changes are posted as thread replies (`root_id`).
- Attachments are uploaded with the bot token and attached to the thread post.
- **One bot, many channels:** global server URL + bot token; **channel ID is per OpenProject project**.
- Per-project routing flags; channel id required when the project module is enabled.
