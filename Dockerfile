FROM ruby:3.2.2-slim-buster@sha256:005f0892d160a4f80f8f89116ec15fddc81f296cd4083db9d59accaed125e270 AS base

# Install libpq-dev in our base layer, as it's needed in all environments
RUN apt-get update \
  && apt-get install -y libpq-dev \
  && rm -rf /var/lib/apt/lists/*

ENV RUBY_BUNDLER_VERSION 2.4.22
RUN gem install bundler -v $RUBY_BUNDLER_VERSION

ENV BUNDLE_PATH /usr/local/bundle

ENV RUBYOPT=-W:deprecated

FROM base AS dev-environment

# Install build-essential and git, as we'd need them for building gems that have native code components
RUN apt-get update \
  && apt-get install -y build-essential git \
  && rm -rf /var/lib/apt/lists/*
