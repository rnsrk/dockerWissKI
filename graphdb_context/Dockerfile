FROM openjdk:11-slim-buster

MAINTAINER Robert Nasarek "r.nasarek@gnm.de"

# Silence debconf messages
RUN echo 'debconf debconf/frontend select Noninteractive' | debconf-set-selections

# Install.
RUN \
  sed -i 's/# \(.*multiverse$\)/\1/g' /etc/apt/sources.list && \
  apt-get -qq update && \
  apt-get -y install unzip && \
  rm -rf /var/lib/apt/lists/*

# Install GraphDB-Free and clean up
COPY ./graphdb.zip /tmp/graphdb.zip

RUN \
  unzip /tmp/graphdb.zip -d /tmp && \
  mv /tmp/graphdb-* /graphdb && \
  rm /tmp/graphdb.zip

# Set GraphDB Max and Min Heap size
ENV GDB_HEAP_SIZE="4G"

EXPOSE 7200
CMD ["/graphdb/bin/graphdb"]