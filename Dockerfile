FROM ruby:3.1.1-slim-buster@sha256:2ada3e4fe7b1703c9333ad4eb9fc12c1d4d60bce0f981281b2151057e928d9ad AS base

# Install libpq-dev in our base layer, as it's needed in all environments
RUN apt-get update \
  && apt-get install -y libpq-dev \
  && rm -rf /var/lib/apt/lists/*

ENV RUBY_BUNDLER_VERSION 2.3.7
RUN gem install bundler -v $RUBY_BUNDLER_VERSION

ENV BUNDLE_PATH /usr/local/bundle

ENV RUBYOPT=-W:deprecated

FROM base AS dev-environment

# Install build-essential and git, as we'd need them for building gems that have native code components
RUN apt-get update \
  && apt-get install -y build-essential git \
  && rm -rf /var/lib/apt/lists/*
