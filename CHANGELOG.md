# Changelog

## 1.0.0 — 2026-08-24

- Post each work package as a single Mattermost status card via a bot account.
- Status, dates, assignee, type, priority and % complete rewrite the same post (`PUT /posts/{id}`) so `update_at` changes and the card UPs.
- Optional pin after bump.
- Comments, files, description, watchers, versions and other journal changes are posted as thread replies (`root_id`).
- Attachments are uploaded with the bot token and attached to the thread post.
## 1.0.0 — 2026-08-24

- Post each work package as a single Mattermost status card via a bot account.
- Status, dates, assignee, type, priority and % complete rewrite the same post (`PUT /posts/{id}`) so `update_at` changes and the card UPs.
- Optional pin after bump.
- Comments, files, description, watchers, versions and other journal changes are posted as thread replies (`root_id`).
- Attachments are uploaded with the bot token and attached to the thread post.
- **One bot, many channels:** global server URL + bot token; **channel ID is per OpenProject project**.
- Per-project routing flags; channel id required when the project module is enabled.

