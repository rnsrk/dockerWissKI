#!/bin/bash
# eclipse/rdf4j-workbench runs as uid 100 (tomcat) but ships /var/rdf4j as uid 101.
# Named volumes keep that mismatch, so rdf4j-server cannot create its log dir.
set -euo pipefail
mkdir -p /var/rdf4j/server/logs /var/rdf4j/server/repositories
chown -R tomcat:nogroup /var/rdf4j
exec setpriv --reuid=tomcat --regid=nogroup --init-groups -- catalina.sh run
