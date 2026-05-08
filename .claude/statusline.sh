#!/bin/bash
input=$(cat)

TOTAL=$(echo "$input" | jq -r '(.context_window.total_input_tokens // 0) + (.context_window.total_output_tokens // 0)')
CTX_PCT=$(echo "$input" | jq -r '.context_window.used_percentage // 0')
CTX_USED=$(echo "$input" | jq -r '((.context_window.context_window_size // 200000) * (.context_window.used_percentage // 0) / 100) | floor')

RESETS_AT=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')
if [ -n "$RESETS_AT" ]; then
  NOW=$(date +%s)
  SECS_LEFT=$(( RESETS_AT - NOW ))
  HOURS_LEFT=$(( SECS_LEFT / 3600 ))
  MINS_LEFT=$(( (SECS_LEFT % 3600) / 60 ))
else
  HOURS_LEFT=0
  MINS_LEFT=0
fi

MODEL=$(echo "$input" | jq -r '.model.display_name // "unknown"')
EFFORT=$(echo "$input" | jq -r '.thinking_effort // "normal"')

printf "Ctx:%s%% | Reset:%dh%02dm | %s | %s\n" "$CTX_PCT" "$HOURS_LEFT" "$MINS_LEFT" "$MODEL" "$EFFORT"

#printf "Total: %s | Ctx: %s | Ctx: %s%%\n" "$TOTAL" "$CTX_USED" "$CTX_PCT"
#printf "Reset: %dh %02dm | %s | %s\n" "$HOURS_LEFT" "$MINS_LEFT" "$MODEL" "$EFFORT"
