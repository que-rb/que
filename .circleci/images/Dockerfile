FROM ubuntu:16.04

RUN echo 'deb http://apt.postgresql.org/pub/repos/apt/ xenial-pgdg main' > /etc/apt/sources.list.d/pgdg.list

RUN apt-get update
RUN apt-get install -y git ssh tar gzip ca-certificates
RUN apt-get install -y --allow-unauthenticated \
  postgresql-9.6 postgresql-contrib-9.6 \
  postgresql-9.5 postgresql-contrib-9.5 \
  postgresql-9.4 postgresql-contrib-9.4

EXPOSE 5432
EXPOSE 5433
EXPOSE 5434
