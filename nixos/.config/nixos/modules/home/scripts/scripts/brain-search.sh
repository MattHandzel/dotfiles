#!/usr/bin/env bash

# brain-search.sh: Search the Second Brain from the CLI
# Usage: ./brain-search.sh "query" [top_k]

QUERY="$1"
TOP_K="${2:-5}"
API_URL="http://matts-server:47772/search"

if [ -z "$QUERY" ]; then
    echo "Usage: $0 \"search query\" [top_k]"
    exit 1
fi

# Make the request and format with jq
# Using a 120s timeout since the server is currently on CPU
# We use --data-urlencode to safely handle multi-line strings and quotes in the query
JSON_PAYLOAD=$(jq -n --arg q "$QUERY" --arg k "$TOP_K" '{query: $q, top_k: ($k|tonumber), rerank: false}')

RESPONSE=$(curl -s -X POST "$API_URL" \
     -H "Content-Type: application/json" \
     -d "$JSON_PAYLOAD" \
     --max-time 120)

# Check if response is an error or valid array
if echo "$RESPONSE" | jq -e 'if type == "array" then true else false end' > /dev/null 2>&1; then
    echo "$RESPONSE" | jq -r '.[] | "[\((.score * 1000 | round) / 1000)] \(.rel_path)\n\(.text | gsub("\\n"; " ") | .[0:500])...\n"'
else
    echo "API Error or Unexpected Response:"
    echo "$RESPONSE" | jq .
fi
