# Be sure to restart your server when you modify this file.
#
# OAuth flows (notably Google sign-in) stash the full auth hash in the session
# before finalising the login. With accumulated consents (e.g. Drive scope from
# Captain's Google Drive integration) that payload exceeds the 4KB cookie jar
# limit and Rails raises CookieOverflow. Backing the session with Redis keeps
# cookies small (only a session id) and makes arbitrarily large flash payloads
# safe.

require 'action_dispatch/middleware/session/cache_store'
require Rails.root.join('lib/redis/config').to_s

session_cache = ActiveSupport::Cache::RedisCacheStore.new(
  **Redis::Config.app,
  namespace: 'chatwoot_sessions',
  expires_in: 14.days
)

Rails.application.config.session_store(
  :cache_store,
  cache: session_cache,
  key: '_chatwoot_session',
  same_site: :lax,
  expire_after: 14.days
)
