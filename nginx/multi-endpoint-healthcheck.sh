#!/bin/bash

# Multi-endpoint healthcheck script
# Usage: ./multi-endpoint-healthcheck.sh <port>

PORT=${1:-8081}
HOST="localhost"

# Diverse endpoints array với các error types mới
ENDPOINTS=("/" "/api" "/random" "/status" "/health" "/notfound" "/forbidden" "/ratelimit" "/timeout" "/badgateway" "/unavailable" "/slowapi")

echo "=== Multi-endpoint healthcheck bắt đầu cho port $PORT ==="

SUCCESS_COUNT=0
TOTAL_CALLS=4  # Tăng từ 3 lên 4 để test nhiều hơn

# Gọi 4 endpoints random
for ((i=1; i<=TOTAL_CALLS; i++)); do
    # Random chọn endpoint
    ENDPOINT_INDEX=$((RANDOM % ${#ENDPOINTS[@]}))
    ENDPOINT=${ENDPOINTS[$ENDPOINT_INDEX]}
    
    echo "[$i/$TOTAL_CALLS] Testing endpoint: $ENDPOINT"
    
    # Gọi với timeout và silent mode
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 6 "http://$HOST:$PORT$ENDPOINT" 2>/dev/null)
    CURL_EXIT=$?
    
    # Kiểm tra kết quả - accept cả success và controlled errors
    if [ $CURL_EXIT -eq 0 ] && [ "$HTTP_CODE" != "000" ]; then
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
        # Phân loại status codes
        if [[ "$HTTP_CODE" =~ ^2[0-9][0-9]$ ]]; then
            echo "  ✓ $ENDPOINT → HTTP $HTTP_CODE (SUCCESS)"
        elif [[ "$HTTP_CODE" =~ ^4[0-9][0-9]$ ]]; then
            echo "  ⚠ $ENDPOINT → HTTP $HTTP_CODE (CLIENT ERROR - expected)"
        elif [[ "$HTTP_CODE" =~ ^5[0-9][0-9]$ ]]; then
            echo "  ⚠ $ENDPOINT → HTTP $HTTP_CODE (SERVER ERROR - expected)"
        else
            echo "  ✓ $ENDPOINT → HTTP $HTTP_CODE (RESPONSE)"
        fi
    else
        echo "  ✗ $ENDPOINT → HTTP $HTTP_CODE (FAILED, curl exit: $CURL_EXIT)"
    fi
    
    # Delay nhỏ giữa các request
    [ $i -lt $TOTAL_CALLS ] && sleep 0.2
done

echo "=== Kết quả: $SUCCESS_COUNT/$TOTAL_CALLS endpoints phản hồi thành công ==="

# Healthcheck pass nếu có ít nhất 1 endpoint thành công
if [ $SUCCESS_COUNT -gt 0 ]; then
    echo "✓ HEALTHCHECK PASSED"
    exit 0
else
    echo "✗ HEALTHCHECK FAILED - Không có endpoint nào phản hồi"
    exit 1
fi