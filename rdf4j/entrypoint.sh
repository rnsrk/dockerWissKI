#!/bin/bash
# Start rdf4j in the background
catalina.sh run &
sleep 5
# Create the default repository
curl -X PUT http://localhost:8080/rdf4j-server/repositories/default -H 'Content-Type: text/turtle' -T "/default_repository.ttl"
wait
