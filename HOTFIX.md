# OpenProject will not boot — SettingsHelper

Restarting is not enough. The process is still loading git SHA
`bb7f2c81ad20`, which contains:

```ruby
include Admin::Settings::SettingsHelper
```

That constant does not exist in OpenProject 17. Version **1.0.2** already
removed it. Until that copy is what Bundler loads, the web and worker
units will keep exiting.

## Get the site up now (one line)

Edit the file OpenProject is **actually** loading:

```text
/opt/openproject/vendor/bundle/ruby/4.0.0/bundler/gems/openproject-mattermost-bb7f2c81ad20/app/controllers/mattermost/admin_settings_controller.rb
```

Delete this line (around line 5):

```ruby
include Admin::Settings::SettingsHelper
```

Leave the rest. Start OpenProject again. It should boot.

This vendor copy is overwritten the next time Bundler installs the gem.
Do the proper update after the site is up.

## Then install 1.0.2

This repository is 1.0.2 (`AdminSettingsController` has no SettingsHelper).

If `Gemfile.plugins` uses a **git** URL, push this tree to that remote,
then from the OpenProject checkout:

```bash
bundle update openproject-mattermost
# packaged installs:  openproject configure
```

After that, the path under `vendor/bundle/.../bundler/gems/` must show a
**different SHA** than `bb7f2c81ad20`. If the SHA is unchanged, Bundler
is still using the old clone — the helper include is still there.

If `Gemfile.plugins` uses **path:**, replace the directory with this tree
and run `bundle install` / `openproject configure`.
