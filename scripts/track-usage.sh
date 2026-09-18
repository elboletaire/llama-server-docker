#!/bin/bash
# Track model usage - Record timestamp for a specific model
# Usage: ./scripts/track-usage.sh <alias>

set -e

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

alias="${1:-}"

if [ -z "$alias" ]; then
    echo "Usage: $0 <alias>"
    echo ""
    echo "Available aliases:"
    echo "  qwen35-9b   - Qwen3.5 9B Q8_0 (fast agent)"
    echo "  gemma4-26b  - Gemma 4 26B-A4B Q4_K_M (quality agent)"
    echo "  qwen35-35b  - Qwen3.5 35B-A3B Q4_K_XL (max quality, GPU+RAM split)"
    exit 1
fi

# Record current timestamp
current_time=$(date +%s)
mkdir -p "$PROJECT_DIR/.model_last_used"
echo "${current_time}" > "$PROJECT_DIR/.model_last_used/${alias}"

echo "Recorded usage for model: ${alias}"
echo "Timestamp: ${current_time} ($(date -d @${current_time}))"
echo ""

# Show last used times
echo "All model usage times:"
echo "======================"
for model in qwen35-9b gemma4-26b qwen35-35b; do
    if [ -f "$PROJECT_DIR/.model_last_used/${model}" ]; then
        last_used=$(cat "$PROJECT_DIR/.model_last_used/${model}")
        idle_seconds=$(($(date +%s) - last_used))
        idle_minutes=$((idle_seconds / 60))
        
        if [ $idle_seconds -lt 60 ]; then
            idle_str="${idle_seconds}s"
        else
            idle_str="${idle_minutes}m"
        fi
        
        echo "  ${model}: last used ${idle_str} ago"
    else
        echo "  ${model}: never used"
    fi
done