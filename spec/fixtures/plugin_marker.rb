# frozen_string_literal: true

# Fixture for runner_spec.rb -- proves Runner#load_plugins actually requires
# the files listed under the `require:` config key, relative to root.
SCHEMA_REAPER_PLUGIN_LOADED = true unless defined?(SCHEMA_REAPER_PLUGIN_LOADED)
