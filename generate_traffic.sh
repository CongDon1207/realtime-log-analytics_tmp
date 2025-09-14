#!/bin/bash

# Generate diverse traffic with response times
for i in {1..50}; do
# Random endpoints (chỉ các endpoint thực sự cần thiết)
endpoints=("/" "/api" "/oops")
endpoint=${endpoints[$((RANDOM % ${#endpoints[@]}))]}

# Random delays between requests
sleep_time=$(awk "BEGIN {printf \"%.2f\", rand()*2}")

# Make request
curl -s "http://localhost:8081$endpoint" > /dev/null &

echo "Request $i to $endpoint"
sleep $sleep_time
done

wait
echo "Traffic generation completed"