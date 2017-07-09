FROM ubuntu:16.04

RUN echo 'deb http://apt.postgresql.org/pub/repos/apt/ xenial-pgdg main' > \
  /etc/apt/sources.list.d/pgdg.list

RUN apt-get update
RUN apt-get install -y git ssh tar gzip ca-certificates build-essential \
  openssl libreadline6 libreadline6-dev curl zlib1g zlib1g-dev libssl-dev \
  libyaml-dev libsqlite3-dev sqlite3 libxml2-dev libxslt-dev autoconf \
  libc6-dev ncurses-dev automake libtool bison subversion pkg-config

RUN apt-get install -y --allow-unauthenticated \
  libpq-dev postgresql-common \
  postgresql-9.6 postgresql-contrib-9.6 \
  postgresql-9.5 postgresql-contrib-9.5 \
  postgresql-9.4 postgresql-contrib-9.4

# Fix Postgres SSL certificate error. Not sure why this is necessary.
# See https://github.com/nimiq/docker-postgresql93/issues/2
RUN mkdir /etc/ssl/private-copy
RUN mv /etc/ssl/private/* /etc/ssl/private-copy/
RUN rm -r /etc/ssl/private
RUN mv /etc/ssl/private-copy /etc/ssl/private
RUN chmod -R 0700 /etc/ssl/private
RUN chown -R postgres /etc/ssl/private

# Make Postgres just trust all connections - this is only used for testing.
RUN for PG_VERSION in 9.4 9.5 9.6; do echo "host all all 127.0.0.1/32 trust" > /etc/postgresql/$PG_VERSION/main/pg_hba.conf && echo "local all all trust" >> /etc/postgresql/$PG_VERSION/main/pg_hba.conf; done

# Set up RVM and Rubies.

RUN curl -L https://get.rvm.io | bash -s stable
ENV PATH /usr/local/rvm/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

RUN /bin/bash -l -c "rvm reload"
RUN /bin/bash -l -c "rvm requirements"

RUN /bin/bash -l -c "rvm install 2.2"
RUN /bin/bash -l -c "rvm 2.2 do gem install bundler --no-ri --no-rdoc"

RUN /bin/bash -l -c "rvm install 2.3"
RUN /bin/bash -l -c "rvm 2.3 do gem install bundler --no-ri --no-rdoc"

RUN /bin/bash -l -c "rvm install 2.4"
RUN /bin/bash -l -c "rvm 2.4 do gem install bundler --no-ri --no-rdoc"

RUN /bin/bash -l -c "rvm install jruby"
RUN /bin/bash -l -c "rvm jruby do gem install bundler --no-ri --no-rdoc"

# No such file or directory - clang # >:(
# RUN /bin/bash -l -c "rvm install rbx"
# RUN /bin/bash -l -c "rvm rbx do gem install bundler --no-ri --no-rdoc"
