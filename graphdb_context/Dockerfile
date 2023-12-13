FROM openjdk:22-slim-bullseye

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
  mv /tmp/graphdb-* /opt/graphdb && \
  rm /tmp/graphdb.zip

EXPOSE 7200
CMD ["/opt/graphdb/bin/graphdb"]