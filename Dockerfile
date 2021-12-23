FROM ruby:2.7.5-slim-buster@sha256:4cbbe2fba099026b243200aa8663f56476950cc64ccd91d7aaccddca31e445b5 AS base

# Install libpq-dev in our base layer, as it's needed in all environments
RUN apt-get update \
  && apt-get install -y libpq-dev \
  && rm -rf /var/lib/apt/lists/*

ENV RUBY_BUNDLER_VERSION 2.3.1
RUN gem install bundler -v $RUBY_BUNDLER_VERSION

ENV BUNDLE_PATH /usr/local/bundle

ENV RUBYOPT=-W:deprecated

FROM base AS dev-environment

# Install build-essential and git, as we'd need them for building gems that have native code components
RUN apt-get update \
  && apt-get install -y build-essential git \
  && rm -rf /var/lib/apt/lists/*
