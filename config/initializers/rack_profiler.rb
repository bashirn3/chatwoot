# frozen_string_literal: true

# Disabled: mini-profiler causes 500s on the includes.js resource.
# Re-enable by setting ENABLE_MINI_PROFILER=true in .env
if Rails.env.development? && ENV['ENABLE_MINI_PROFILER'] == 'true'
  require 'rack-mini-profiler'

  # initialization is skipped so trigger it
  Rack::MiniProfilerRails.initialize!(Rails.application)
end
