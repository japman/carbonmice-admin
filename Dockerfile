# syntax=docker/dockerfile:1
# Multi-stage image for carbonmice-admin (Rails 8.1, Ruby 4.0).
#
# Targets:
#   development — used by docker-compose.yml for local dev (source is bind-mounted,
#                 all gem groups installed). Default CMD is overridden by compose.
#   production  — slim runtime for deploy (Plan 4b). Assets precompiled, non-root.
#
# The app shares the carbonmice Postgres and owns ONLY the `admin` schema. The
# entrypoint runs `db:migrate`, which is enhanced (lib/tasks/admin_schema.rake) to
# create the admin schema first — it NEVER migrates the Go-owned `public` schema.

ARG RUBY_VERSION=4.0.0
# PEA build.yml passes PROXY_IMAGE_PREFIX=docker-registry-mirror.pea.co.th/library
# (runners cannot reach docker.io). Default keeps local builds working.
ARG PROXY_IMAGE_PREFIX=docker.io/library

########################  base  ########################
FROM ${PROXY_IMAGE_PREFIX}/ruby:${RUBY_VERSION}-slim AS base
WORKDIR /rails

# Runtime packages: libpq for pg, postgresql-client for pg_isready, tzdata, curl for healthchecks.
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y curl libpq5 postgresql-client tzdata && \
    rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*

ENV TZ="Asia/Bangkok" \
    BUNDLE_PATH="/usr/local/bundle"

########################  build (gem toolchain)  ########################
FROM base AS build
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
      build-essential git libpq-dev pkg-config libyaml-dev libffi-dev && \
    rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*
COPY Gemfile Gemfile.lock ./

########################  development  ########################
FROM build AS development
ENV RAILS_ENV="development"
RUN bundle install
COPY . .
EXPOSE 3000
# Compose overrides this; the default mirrors `bin/dev` (foreman: web + tailwind watch).
CMD ["bin/dev"]

########################  production build  ########################
FROM build AS build_prod
ENV RAILS_ENV="production" \
    BUNDLE_DEPLOYMENT="1" \
    BUNDLE_WITHOUT="development:test"
RUN bundle install && \
    rm -rf ~/.bundle "${BUNDLE_PATH}/ruby"/*/cache
COPY . .
# tailwindcss-rails builds CSS during assets:precompile; no real secret needed here.
RUN SECRET_KEY_BASE_DUMMY=1 ./bin/rails assets:precompile

########################  production runtime  ########################
FROM base AS production
ENV RAILS_ENV="production" \
    BUNDLE_DEPLOYMENT="1" \
    BUNDLE_WITHOUT="development:test"

COPY --from=build_prod "${BUNDLE_PATH}" "${BUNDLE_PATH}"
COPY --from=build_prod /rails /rails

# Run as an unprivileged user; own the dirs Rails writes to at runtime.
RUN groupadd --system --gid 1000 rails && \
    useradd rails --uid 1000 --gid 1000 --create-home --shell /bin/bash && \
    chown -R rails:rails /rails/log /rails/tmp /rails/storage 2>/dev/null || true
USER 1000:1000

ENTRYPOINT ["/rails/bin/docker-entrypoint"]
EXPOSE 3000
# Puma serves directly. Front with Thruster once `bin/thrust` is binstubbed if desired.
CMD ["./bin/rails", "server", "-b", "0.0.0.0", "-p", "3000"]
