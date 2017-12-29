# Usage cheat sheet:
# sudo docker build .circleci/images -t chanks/que-circleci:0.0.x
# sudo docker push chanks/que-circleci:0.0.x

FROM ubuntu:16.04

RUN apt-get update
RUN apt-get install -y wget ca-certificates

RUN echo 'deb http://apt.postgresql.org/pub/repos/apt/ xenial-pgdg main' > \
  /etc/apt/sources.list.d/pgdg.list

RUN wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add -

RUN apt-get update
RUN apt-get install -y git ssh tar gzip build-essential \
  openssl libreadline6 libreadline6-dev curl zlib1g zlib1g-dev libssl-dev \
  libyaml-dev libsqlite3-dev sqlite3 libxml2-dev libxslt-dev autoconf \
  libc6-dev ncurses-dev automake libtool bison subversion pkg-config

RUN apt-get install -y \
  libpq-dev postgresql-common \
  postgresql-10  postgresql-contrib-10 \
  postgresql-9.6 postgresql-contrib-9.6 \
  postgresql-9.5 postgresql-contrib-9.5

# Set up RVM and Rubies.

RUN gpg --keyserver hkp://keys.gnupg.net --recv-keys D39DC0E3
RUN curl -sSL https://get.rvm.io | bash -s head
ENV PATH /usr/local/rvm/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

RUN /bin/bash -l -c "rvm reload"
RUN /bin/bash -l -c "rvm requirements"

RUN /bin/bash -l -c "rvm install 2.2"
RUN /bin/bash -l -c "rvm 2.2 do gem install bundler --no-ri --no-rdoc"

RUN /bin/bash -l -c "rvm install 2.3"
RUN /bin/bash -l -c "rvm 2.3 do gem install bundler --no-ri --no-rdoc"

RUN /bin/bash -l -c "rvm install 2.4"
RUN /bin/bash -l -c "rvm 2.4 do gem install bundler --no-ri --no-rdoc"

RUN /bin/bash -l -c "rvm install 2.5"
RUN /bin/bash -l -c "rvm 2.5 do gem install bundler --no-ri --no-rdoc"

RUN /bin/bash -l -c "rvm install ruby-head"
RUN /bin/bash -l -c "rvm ruby-head do gem install bundler --no-ri --no-rdoc"

RUN /bin/bash -l -c "rvm install jruby"
RUN /bin/bash -l -c "rvm jruby do gem install bundler --no-ri --no-rdoc"

# No such file or directory - clang # >:(
# RUN /bin/bash -l -c "rvm install rbx"
# RUN /bin/bash -l -c "rvm rbx do gem install bundler --no-ri --no-rdoc"
