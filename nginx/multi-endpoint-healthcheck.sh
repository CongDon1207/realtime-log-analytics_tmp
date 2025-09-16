#!/bin/bash

# Multi-endpoint healthcheck script
# Usage: ./multi-endpoint-healthcheck.sh <port>

PORT=${1:-8081}
HOST="localhost"

# Common endpoints simulate normal traffic (mostly 2xx)
COMMON_ENDPOINTS=("/" "/" "/status" "/status" "/health" "/health" "/api")
# Edge endpoints introduce controlled errors for monitoring coverage
EDGE_ENDPOINTS=("/random" "/notfound" "/forbidden" "/ratelimit" "/timeout" "/badgateway" "/unavailable" "/slowapi")

echo "=== Multi-endpoint healthcheck bat dau cho port $PORT ==="

SUCCESS_COUNT=0
TOTAL_CALLS=6

for ((i=1; i<=TOTAL_CALLS; i++)); do
    if (( RANDOM % 10 < 7 )); then
        ENDPOINT=${COMMON_ENDPOINTS[RANDOM % ${#COMMON_ENDPOINTS[@]}]}
    else
        ENDPOINT=${EDGE_ENDPOINTS[RANDOM % ${#EDGE_ENDPOINTS[@]}]}
    fi

    echo "[$i/$TOTAL_CALLS] Testing endpoint: $ENDPOINT"

    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 6 "http://$HOST:$PORT$ENDPOINT" 2>/dev/null)
    CURL_EXIT=$?

    if [ $CURL_EXIT -eq 0 ] && [ "$HTTP_CODE" != "000" ]; then
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
        if [[ "$HTTP_CODE" =~ ^2[0-9][0-9]$ ]]; then
            echo "  OK $ENDPOINT -> HTTP $HTTP_CODE (SUCCESS)"
        elif [[ "$HTTP_CODE" =~ ^4[0-9][0-9]$ ]]; then
            echo "  WARN $ENDPOINT -> HTTP $HTTP_CODE (CLIENT ERROR expected)"
        elif [[ "$HTTP_CODE" =~ ^5[0-9][0-9]$ ]]; then
            echo "  WARN $ENDPOINT -> HTTP $HTTP_CODE (SERVER ERROR expected)"
        else
            echo "  OK $ENDPOINT -> HTTP $HTTP_CODE (RESPONSE)"
        fi
    else
        echo "  FAIL $ENDPOINT -> HTTP $HTTP_CODE (curl exit: $CURL_EXIT)"
    fi

    [ $i -lt $TOTAL_CALLS ] && sleep 0.2
done

echo "=== Ket qua: $SUCCESS_COUNT/$TOTAL_CALLS endpoints phan hoi thanh cong ==="

if [ $SUCCESS_COUNT -gt 0 ]; then
    echo "OK HEALTHCHECK PASSED"
    exit 0
else
    echo "FAIL HEALTHCHECK FAILED - Khong co endpoint nao phan hoi"
    exit 1
fi
