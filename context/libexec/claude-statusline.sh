#!/bin/bash
# Session-info status line: [model] effort:<level> | $cost | <time-remaining> <pct>% | <pct>% (used/total)
# No PS1-derived content (no user/host/path).

input=$(cat)

# Compact "k"/"M" formatter: rounds to nearest k, or shows whole/decimal M
# for values >= 1,000,000 (e.g. 1000000 -> "1M").
format_k() {
    awk -v n="$1" 'BEGIN {
        if (n >= 1000000) {
            v = n / 1000000
            if (v == int(v)) printf "%dM", v
            else printf "%.1fM", v
        } else {
            printf "%dk", int((n + 500) / 1000)
        }
    }'
}

model=$(echo "$input" | jq -r '.model.display_name // empty')
effort=$(echo "$input" | jq -r '.effort.level // empty')
used_pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
total_input=$(echo "$input" | jq -r '.context_window.total_input_tokens // empty')
window_size=$(echo "$input" | jq -r '.context_window.context_window_size // empty')
cost=$(echo "$input" | jq -r '.cost.total_cost_usd // empty')
five_hour_pct=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
five_hour_resets_at=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')

RESET=$'\033[0m'
GREEN=$'\033[32m'
YELLOW=$'\033[33m'
RED=$'\033[31m'

# Segment 1: model + optional effort
segment="[$model]"
if [ -n "$effort" ]; then
    segment="$segment effort:$effort"
fi

# Segment 2: context usage (percentage + token counts), colored by usage
if [ -n "$used_pct" ] && [ "$used_pct" != "null" ] \
    && [ -n "$total_input" ] && [ "$total_input" != "null" ] \
    && [ -n "$window_size" ] && [ "$window_size" != "null" ]; then
    pct_int=$(awk -v p="$used_pct" 'BEGIN{printf "%d", p+0.5}')
    used_k=$(format_k "$total_input")
    window_k=$(format_k "$window_size")

    if awk -v p="$used_pct" 'BEGIN{exit !(p>=85)}'; then
        color="$RED"
    elif awk -v p="$used_pct" 'BEGIN{exit !(p>=60)}'; then
        color="$YELLOW"
    else
        color="$GREEN"
    fi

    ctx_segment="${color}${pct_int}% (${used_k}/${window_k})${RESET}"
else
    ctx_segment="–"
fi

output="$segment"

# Segment: session cost (omitted if absent)
if [ -n "$cost" ] && [ "$cost" != "null" ]; then
    cost_fmt=$(awk -v c="$cost" 'BEGIN{printf "%.2f", c}')
    output="$output | \$$cost_fmt"
fi

# Segment: 5-hour rate-limit usage (omitted if absent)
if [ -n "$five_hour_pct" ] && [ "$five_hour_pct" != "null" ]; then
    five_hour_int=$(awk -v p="$five_hour_pct" 'BEGIN{printf "%d", p+0.5}')
    if [ -n "$five_hour_resets_at" ] && [ "$five_hour_resets_at" != "null" ]; then
        now=$(date +%s)
        label=$(awk -v resets="$five_hour_resets_at" -v now="$now" 'BEGIN {
            rem_min = int((resets - now) / 60 + 0.5)
            if (rem_min < 0) rem_min = 0
            h = int(rem_min / 60)
            m = rem_min % 60
            if (h > 0) printf "%dh%dm", h, m
            else printf "%dm", m
        }')
    else
        label="5h"
    fi

    output="$output | ${label} ${five_hour_int}%"
fi

# Segment: context usage (percentage + token counts), colored by usage
output="$output | $ctx_segment"

printf '%s' "$output"
