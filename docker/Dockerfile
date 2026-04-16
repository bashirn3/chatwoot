# ===========================================================================
# Stage 1: GEMS — only rebuilds when Gemfile/Gemfile.lock change
# ===========================================================================
FROM node:24-alpine AS node
FROM ruby:3.4.4-alpine3.21 AS gems

ENV BUNDLER_VERSION=2.5.16
ENV BUNDLE_PATH="/gems"

RUN apk update && apk add --no-cache \
  build-base musl ruby-full ruby-dev gcc make musl-dev \
  openssl openssl-dev g++ linux-headers xz vips \
  postgresql-dev git tar curl \
  && gem install bundler -v "$BUNDLER_VERSION"

WORKDIR /app
COPY Gemfile Gemfile.lock ./
RUN bundle config set --local force_ruby_platform true \
  && bundle config set without 'development test' \
  && bundle install -j 4 -r 3

# ===========================================================================
# Stage 2: FRONTEND — extends gems so Ruby version matches compiled gems
# ===========================================================================
FROM gems AS frontend

ARG NODE_OPTIONS="--max-old-space-size=4096 --openssl-legacy-provider"
ENV NODE_OPTIONS=${NODE_OPTIONS}

COPY --from=node /usr/local/bin/node /usr/local/bin/
COPY --from=node /usr/local/lib/node_modules /usr/local/lib/node_modules
RUN ln -s /usr/local/lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm \
  && npm install -g pnpm@10.2.0

ENV PNPM_HOME="/root/.local/share/pnpm"
ENV PATH="$PNPM_HOME:$PATH"

WORKDIR /app
COPY package.json pnpm-lock.yaml ./
RUN pnpm i

COPY . /app

RUN mkdir -p /app/log \
  && SECRET_KEY_BASE=precompile_placeholder RAILS_ENV=production \
     RAILS_LOG_TO_STDOUT=enabled bundle exec rake assets:precompile \
  && rm -rf tmp/cache spec .git

# ===========================================================================
# Stage 3: FINAL — lightweight runtime image
# ===========================================================================
FROM ruby:3.4.4-alpine3.21

ARG RAILS_ENV=production
ENV RAILS_ENV=${RAILS_ENV}
ENV BUNDLE_PATH="/gems"
ENV BUNDLE_WITHOUT="development:test"
ENV BUNDLE_FORCE_RUBY_PLATFORM=1
ENV BUNDLER_VERSION=2.5.16
ENV EXECJS_RUNTIME="Disabled"
ENV RAILS_SERVE_STATIC_FILES=true

RUN apk update && apk add --no-cache \
  build-base openssl tzdata postgresql-client imagemagick git vips \
  && gem install bundler -v "$BUNDLER_VERSION"

COPY --from=node /usr/local/bin/node /usr/local/bin/
COPY --from=node /usr/local/lib/node_modules /usr/local/lib/node_modules
RUN ln -s /usr/local/lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm \
  && npm install -g pnpm@10.2.0

ENV PNPM_HOME="/root/.local/share/pnpm"
ENV PATH="$PNPM_HOME:$PATH"

COPY --from=gems /gems/ /gems/
COPY --from=frontend /app /app

RUN git rev-parse HEAD > /app/.git_sha 2>/dev/null || echo "unknown" > /app/.git_sha

RUN rm -rf /gems/ruby/3.4.0/cache/*.gem \
  && find /gems/ruby/3.4.0/gems/ \( -name "*.c" -o -name "*.o" \) -delete

WORKDIR /app
RUN mkdir -p /app/log

EXPOSE 3000
