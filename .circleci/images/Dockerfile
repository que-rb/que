FROM ubuntu:16.04

RUN echo 'deb http://apt.postgresql.org/pub/repos/apt/ xenial-pgdg main' > \
  /etc/apt/sources.list.d/pgdg.list

RUN apt-get update
RUN apt-get install -y git ssh tar gzip ca-certificates build-essential \
  openssl libreadline6 libreadline6-dev curl zlib1g zlib1g-dev libssl-dev \
  libyaml-dev libsqlite3-dev sqlite3 libxml2-dev libxslt-dev autoconf \
  libc6-dev ncurses-dev automake libtool bison subversion pkg-config

# TODO: Next time we're updating this image, move that Postgres SSL certificate
# stuff and the pg_hba.conf configuration from the config.yml in here.

RUN apt-get install -y --allow-unauthenticated \
  libpq-dev postgresql-common \
  postgresql-9.6 postgresql-contrib-9.6 \
  postgresql-9.5 postgresql-contrib-9.5 \
  postgresql-9.4 postgresql-contrib-9.4

RUN curl -L https://get.rvm.io | bash -s stable
ENV PATH /usr/local/rvm/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

RUN /bin/bash -l -c "rvm requirements"

RUN /bin/bash -l -c "rvm install 2.2"
RUN /bin/bash -l -c "rvm 2.2 do gem install bundler --no-ri --no-rdoc"

RUN /bin/bash -l -c "rvm install 2.3"
RUN /bin/bash -l -c "rvm 2.3 do gem install bundler --no-ri --no-rdoc"

RUN /bin/bash -l -c "rvm install 2.4"
RUN /bin/bash -l -c "rvm 2.4 do gem install bundler --no-ri --no-rdoc"
