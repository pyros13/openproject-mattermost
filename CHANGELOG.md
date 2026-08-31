# Changelog

## 1.2.0 — 2026-08-31

- Per-project **Inform**: project channel, private DMs to task members, or both.
- DMs use each member's OpenProject username as the Mattermost username (assignee, accountable, author, watchers). Same status card + thread as the channel.

## 1.1.6 — 2026-08-24

- Status card follows the **live work package**, not only journal diffs. "On Hold" (and other statuses that OpenProject folds into an existing journal) was skipped as `no new payload` and Mattermost kept the old status.

## 1.1.5 — 2026-08-24

- Card accent uses the work package **status color** from OpenProject (Administration → Work packages → Status).
- Thread replies start with the OpenProject user who commented or changed the work package.
- Files post once: `attachments_N` is a file, not a field diff, and the extra `ATTACHMENT_CREATED` post is skipped.

## 1.1.4 — 2026-08-24

- Comments and status changes inside OpenProject's journal aggregation window were skipped (`journal N already processed`). The create journal is reused, so we now post the **delta** (new comment text, new status names) instead of ignoring the same id.

## 1.1.3 — 2026-08-24

- Allow deleting work packages: `mattermost_work_package_posts` (and project settings) now cascade on delete. Bulk delete was hitting `PG::ForeignKeyViolation`.

## 1.1.2 — 2026-08-24

- Fix SyntaxError in `Formatter.plain_text` (broken quote after HTML entity decode). Comments now use `CGI.unescapeHTML`.

## 1.1.1 — 2026-08-24

- Human-readable thread replies: **Opened by Name**, **Status** New → In progress, comments as the comment text.
- Drop noise fields (`project`, `author`, `ignore_non_working_days`, derived dates, …) and raw ids. Status/type/assignee/priority resolve to names.
- Strip HTML (`<br>`, tags) from comments.
- Deduplicate the same journal (create event + aggregated event) via `last_journal_id`.

## 1.1.0 — 2026-08-24

- Actually post: work-package journals are handled on the same worker event outgoing webhooks use (`aggregated_work_package_journal_ready`), not a second silent job hop.
- Every skip is logged with `[mattermost]` (disabled, blank channel, missing bot token, not a work package). Look in web and worker journals.
- Check bot token (Administration) and Send a test post (project Mattermost) so a dead token or wrong channel id is visible immediately.
- Empty token on save no longer wipes the stored token.
- Reads plugin settings from both hyphen and underscore keys.

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
