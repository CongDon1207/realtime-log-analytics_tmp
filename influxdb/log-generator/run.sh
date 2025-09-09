#!/bin/bash
# Script wrapper để chạy log_generator mà không cần export manual

# Load environment từ .env.influx
source ../.env.influx

# Chạy log generator với parameters mặc định hoặc từ args
py -3.9 log_generator.py \
    --url "$INFLUX_URL" \
    --org "$ORG_NAME" \
    --bucket "$BUCKET_NAME" \
    --token "$INFLUX_TOKEN" \
    --duration "${1:-20}" \
    --qps "${2:-80}" \
    --hosts "${3:-3}" \
    --window "${4:-10}" \
    --envtag "${5:-dev}"
