# openproject-mattermost

OpenProject plugin that talks to Mattermost **as a bot**.

Each work package gets **one status card**. When status, dates, assignee, type,
priority or % complete change, the plugin **rewrites that same post**. Mattermost
sets a new `update_at`, the attachment `ts` changes, and the card **UPs**
(Threads sorts by last update; optional pin keeps it on the channel pin bar).

Comments, files, description edits, watchers, versions and other journal
changes are **not** new channel messages. They are posted as **thread replies**
on the original card (`root_id`).

```
OpenProject journal
        │
        ▼
   Classifier
        │
        ├─ card fields  →  PUT /api/v4/posts/{id}     (same message, new time)
        └─ notes/files  →  POST /api/v4/posts         (root_id = status card)
                              + multipart file upload
```

This is not an incoming webhook. Webhooks cannot edit posts. The bot token needs
`create_post`, `edit_post`, and `upload_file`. Pin is optional.

## Requirements

- OpenProject 15 or 16
- Mattermost 8+ with bot accounts enabled
- A bot invited to the project channel

## Install

Place the gem next to your OpenProject checkout:

```text
openproject/
plugins/openproject-mattermost/   ← this repository
```

In `openproject/Gemfile.plugins`:

```ruby
group :opf_plugins do
  gem "openproject-mattermost", path: "../plugins/openproject-mattermost"
end
```

Then:

```bash
bundle install
bundle exec rake db:migrate
# restart OpenProject
```

Packaged installations can use a custom Gemfile as described in the
[OpenProject plugin docs](https://www.openproject.org/docs/installation-and-operations/configuration/plugins/).

## Mattermost bot

1. System Console → Integrations → Bot Accounts → create **OpenProject**.
2. Copy the bot token (this is **global** — one token for the whole instance).
3. Invite **that same bot** to every project channel it should post in.
4. Channel menu → View Info → copy the **Channel ID**. Paste it on the OpenProject **project**, not in admin.

## Configure

**Administration → Integrations → Mattermost** (once)

| Setting | Scope | Purpose |
| --- | --- | --- |
| Server URL | Global | `https://chat.example.com` (no `/api/v4`) |
| Bot token | Global | The one bot account |
| Bot name | Global | Display name on posts |

**Project → Mattermost** (per project)

| Setting | Default | Purpose |
| --- | --- | --- |
| Enabled | off | Master switch for this project |
| **Channel ID** | — | **This project's Mattermost channel.** Required when enabled. |
| Channel name | — | Human label only |
| Bump on status | on | Rewrite the root card and UP it |
| Pin after bump | off | Pin the card in the channel |
| Thread comments | on | Journal notes → thread |
| Thread files | on | Attachments → thread |
| Thread other | on | Remaining field diffs → thread |

One bot, many channels: Kitewell can post to `#kitewell-release` while Northwind posts to `#northwind-ops`. Both use the same token. Channel ID is never stored on the bot — only on the project.

If you change a project's channel ID later, **new** work packages post to the new channel. Existing cards stay where they were created so their threads stay intact.


## Routing

| Journal | Mattermost |
| --- | --- |
| Work package created | New root status card |
| Status, type, priority, assignee, subject, dates, % complete | `PUT` same post · `update_at` changes · UP |
| Comment / notes | Thread reply |
| Attachment | Upload file as bot, thread reply with `file_ids` |
| Description, watchers, version, parent, time logs, custom fields | Thread reply with the diff |

A single aggregated journal that contains both a status change and a comment
does **both**: the card is rewritten and bumped, then the comment is posted in
the thread.

## Why not post a new message?

A new message would sit at the bottom of the channel but it would **break the
thread**. Mattermost threads are keyed by the root post id. The mapping table
`mattermost_work_package_posts` stores `work_package_id → post_id` so every
later event hits the same root.

Channel history itself is ordered by `create_at`. Editing does not move the
original row in the channel. What UPs:

1. `update_at` on the post — Threads / followed threads sort by this.
2. Attachment `ts` — the card footer shows the new time.
3. Optional pin — the card stays on the pin bar at the top of the channel.

Do not delete-and-recreate the root. That orphans every reply.

## Development

```bash
bundle exec rspec spec/lib/open_project/mattermost/classifier_spec.rb
```

The classifier is a plain Ruby object and does not need a running OpenProject.

## License

GPL-3.0, same as OpenProject.
