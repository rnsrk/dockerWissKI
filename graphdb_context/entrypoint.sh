#!/bin/bash
# Start GraphDB in the background
bash /opt/graphdb/bin/graphdb &
sleep 5
# Create the default repository
curl -X POST http://graphdb:7200/rest/repositories -H 'Content-Type: multipart/form-data' -F config=@/default_repository.ttl
wait
