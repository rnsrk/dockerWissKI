#!/bin/bash
# Start rdf4j in the background
catalina.sh run &

while true; do
  response=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/rdf4j-server/protocol)
  if [ "$response" -eq 200 ]; then
    echo "RDF4J has started ..."
    break
  else
    echo "RDF4J has not yet started (received wrong status code $response) ..."
    sleep 1
  fi
done

# Create the default repository
curl -X PUT http://localhost:8080/rdf4j-server/repositories/default -H 'Content-Type: text/turtle' -T "/default_repository.ttl"
wait
