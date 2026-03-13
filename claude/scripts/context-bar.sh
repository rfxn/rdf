#!/bin/bash

# Color theme: gray, orange, blue, teal, green, lavender, rose, gold, slate, cyan
# Preview colors with: bash scripts/color-preview.sh
COLOR="blue"

# Color codes
C_RESET='\033[0m'
C_GRAY='\033[38;5;245m'  # explicit gray for default text
C_BAR_EMPTY='\033[38;5;238m'
C_WARN='\033[38;5;178m'   # yellow-orange for warning thresholds
C_ALERT='\033[38;5;167m'  # red for alert thresholds
case "$COLOR" in
    orange)   C_ACCENT='\033[38;5;173m' ;;
    blue)     C_ACCENT='\033[38;5;74m' ;;
    teal)     C_ACCENT='\033[38;5;66m' ;;
    green)    C_ACCENT='\033[38;5;71m' ;;
    lavender) C_ACCENT='\033[38;5;139m' ;;
    rose)     C_ACCENT='\033[38;5;132m' ;;
    gold)     C_ACCENT='\033[38;5;136m' ;;
    slate)    C_ACCENT='\033[38;5;60m' ;;
    cyan)     C_ACCENT='\033[38;5;37m' ;;
    *)        C_ACCENT="$C_GRAY" ;;  # gray: all same color
esac

input=$(cat)

# Extract model, directory, and cwd
model=$(echo "$input" | jq -r '.model.display_name // .model.id // "?"')
cwd=$(echo "$input" | jq -r '.cwd // empty')
dir=$(basename "$cwd" 2>/dev/null || echo "?")

# Get git branch, uncommitted file count, and sync status
branch=""
git_status=""
if [[ -n "$cwd" && -d "$cwd" ]]; then
    branch=$(git -C "$cwd" branch --show-current 2>/dev/null)
    if [[ -n "$branch" ]]; then
        # Count uncommitted files
        file_count=$(git -C "$cwd" --no-optional-locks status --porcelain -uall 2>/dev/null | wc -l | tr -d ' ')

        # Check sync status with upstream
        sync_status=""
        upstream=$(git -C "$cwd" rev-parse --abbrev-ref @{upstream} 2>/dev/null)
        if [[ -n "$upstream" ]]; then
            # Get last fetch time
            fetch_head="$cwd/.git/FETCH_HEAD"
            fetch_ago=""
            if [[ -f "$fetch_head" ]]; then
                fetch_time=$(stat -c %Y "$fetch_head" 2>/dev/null || stat -f %m "$fetch_head" 2>/dev/null)
                if [[ -n "$fetch_time" ]]; then
                    now=$(date +%s)
                    diff=$((now - fetch_time))
                    if [[ $diff -lt 60 ]]; then
                        fetch_ago="<1m ago"
                    elif [[ $diff -lt 3600 ]]; then
                        fetch_ago="$((diff / 60))m ago"
                    elif [[ $diff -lt 86400 ]]; then
                        fetch_ago="$((diff / 3600))h ago"
                    else
                        fetch_ago="$((diff / 86400))d ago"
                    fi
                fi
            fi

            counts=$(git -C "$cwd" rev-list --left-right --count HEAD...@{upstream} 2>/dev/null)
            ahead=$(echo "$counts" | cut -f1)
            behind=$(echo "$counts" | cut -f2)
            if [[ "$ahead" -eq 0 && "$behind" -eq 0 ]]; then
                if [[ -n "$fetch_ago" ]]; then
                    sync_status="synced ${fetch_ago}"
                else
                    sync_status="synced"
                fi
            elif [[ "$ahead" -gt 0 && "$behind" -eq 0 ]]; then
                sync_status="${ahead} ahead"
            elif [[ "$ahead" -eq 0 && "$behind" -gt 0 ]]; then
                sync_status="${behind} behind"
            else
                sync_status="${ahead} ahead, ${behind} behind"
            fi
        else
            sync_status="no upstream"
        fi

        # Build git status string
        if [[ "$file_count" -eq 0 ]]; then
            git_status="(0 files uncommitted, ${sync_status})"
        elif [[ "$file_count" -eq 1 ]]; then
            # Show the actual filename when only one file is uncommitted
            single_file=$(git -C "$cwd" --no-optional-locks status --porcelain -uall 2>/dev/null | head -1 | sed 's/^...//')
            git_status="(${single_file} uncommitted, ${sync_status})"
        else
            git_status="(${file_count} files uncommitted, ${sync_status})"
        fi
    fi
fi

# Get transcript path for context calculation and last message feature
transcript_path=$(echo "$input" | jq -r '.transcript_path // empty')

# Get context window size from JSON (accurate), but calculate tokens from transcript
# (more accurate than total_input_tokens which excludes system prompt/tools/memory)
# See: github.com/anthropics/claude-code/issues/13652
max_context=$(echo "$input" | jq -r '.context_window.context_window_size // 200000')
max_k=$((max_context / 1000))

# Calculate context bar from transcript
if [[ -n "$transcript_path" && -f "$transcript_path" ]]; then
    context_metrics=$(jq -rs '
        map(select(.message.usage and .isSidechain != true and .isApiErrorMessage != true)) |
        last |
        if . then
            {
                total: ((.message.usage.input_tokens // 0) +
                        (.message.usage.cache_read_input_tokens // 0) +
                        (.message.usage.cache_creation_input_tokens // 0)),
                cache_read: (.message.usage.cache_read_input_tokens // 0),
                cache_create: (.message.usage.cache_creation_input_tokens // 0),
                input: (.message.usage.input_tokens // 0)
            }
        else { total: 0, cache_read: 0, cache_create: 0, input: 0 } end |
        "\(.total) \(.cache_read) \(.cache_create) \(.input)"
    ' < "$transcript_path")
    read -r context_length cache_read cache_create uncached_input <<< "$context_metrics"

    # Cache hit rate: cache_read / (cache_read + cache_create + uncached_input)
    cache_total=$((cache_read + cache_create + uncached_input))
    if [[ "$cache_total" -gt 0 ]]; then
        cache_hit_pct=$((cache_read * 100 / cache_total))
    else
        cache_hit_pct=0
    fi

    # 20k baseline: includes system prompt (~3k), tools (~15k), memory (~300),
    # plus ~2k for git status, env block, XML framing, and other dynamic context
    baseline=20000
    bar_width=10

    if [[ "$context_length" -gt 0 ]]; then
        pct=$((context_length * 100 / max_context))
        pct_prefix=""
    else
        # At conversation start, ~20k baseline is already loaded
        pct=$((baseline * 100 / max_context))
        pct_prefix="~"
    fi

    [[ $pct -gt 100 ]] && pct=100

    bar=""
    for ((i=0; i<bar_width; i++)); do
        bar_start=$((i * 10))
        progress=$((pct - bar_start))
        if [[ $progress -ge 8 ]]; then
            bar+="${C_ACCENT}█${C_RESET}"
        elif [[ $progress -ge 3 ]]; then
            bar+="${C_ACCENT}▄${C_RESET}"
        else
            bar+="${C_BAR_EMPTY}░${C_RESET}"
        fi
    done

    # Color context % by threshold: >80% red, >60% yellow, else gray
    if [[ $pct -gt 80 ]]; then
        pct_color="$C_ALERT"
    elif [[ $pct -gt 60 ]]; then
        pct_color="$C_WARN"
    else
        pct_color="$C_GRAY"
    fi

    # Color cache % by threshold: <35% red, <60% yellow, else gray
    if [[ $cache_hit_pct -lt 35 ]]; then
        cache_color="$C_ALERT"
    elif [[ $cache_hit_pct -lt 60 ]]; then
        cache_color="$C_WARN"
    else
        cache_color="$C_GRAY"
    fi

    # Session cost and burn rate from JSON input (cost.total_cost_usd)
    cost_usd=$(echo "$input" | jq -r '.cost.total_cost_usd // empty')
    cost_label=""
    if [[ -n "$cost_usd" ]]; then
        cost_fmt=$(printf '$%.2f' "$cost_usd")

        # Count turns (assistant messages with usage, excluding sidechain)
        turn_count=$(jq -s '[.[] | select(.message.usage and .isSidechain != true and .isApiErrorMessage != true)] | length' < "$transcript_path")

        if [[ "$turn_count" -gt 0 ]]; then
            per_turn=$(awk "BEGIN { printf \"%.2f\", $cost_usd / $turn_count }")

            # Color $/turn by threshold: >$0.50 red, >$0.25 yellow, else gray
            per_turn_alert=$(awk "BEGIN { print ($per_turn > 0.50) ? \"alert\" : ($per_turn > 0.25) ? \"warn\" : \"ok\" }")
            if [[ "$per_turn_alert" == "alert" ]]; then
                rate_color="$C_ALERT"
            elif [[ "$per_turn_alert" == "warn" ]]; then
                rate_color="$C_WARN"
            else
                rate_color="$C_GRAY"
            fi
            cost_label=" ${C_GRAY}${cost_fmt} ${rate_color}\$${per_turn}/t"
        else
            cost_label=" ${C_GRAY}${cost_fmt}"
        fi
    fi

    # Compact format: ██░░ 40%/200k | ⚡83% $1.42 $0.12/t
    ctx="${bar} ${pct_color}${pct_prefix}${pct}%/${max_k}k${C_GRAY} | ${cache_color}⚡${cache_hit_pct}%${cost_label}"
else
    # Transcript not available yet - show baseline estimate
    baseline=20000
    bar_width=10
    pct=$((baseline * 100 / max_context))
    [[ $pct -gt 100 ]] && pct=100

    bar=""
    for ((i=0; i<bar_width; i++)); do
        bar_start=$((i * 10))
        progress=$((pct - bar_start))
        if [[ $progress -ge 8 ]]; then
            bar+="${C_ACCENT}█${C_RESET}"
        elif [[ $progress -ge 3 ]]; then
            bar+="${C_ACCENT}▄${C_RESET}"
        else
            bar+="${C_BAR_EMPTY}░${C_RESET}"
        fi
    done

    ctx="${bar} ${C_GRAY}~${pct}%/${max_k}k"
fi

# Read project health cache
health_indicator=""
if [[ -n "$cwd" ]]; then
    project_name=$(basename "$cwd" 2>/dev/null)
    cache_file="/tmp/rfxn-health-${project_name}.cache"
    if [[ -f "$cache_file" ]]; then
        health_rating=$(cut -d'|' -f1 < "$cache_file")
        case "$health_rating" in
            GREEN)  health_indicator=" | H:${health_rating}" ;;
            YELLOW)
                health_detail=$(cut -d'|' -f5 < "$cache_file" 2>/dev/null)
                health_indicator=" | H:${health_rating}${health_detail:+ ${health_detail}}" ;;
            RED)
                health_detail=$(cut -d'|' -f5 < "$cache_file" 2>/dev/null)
                health_indicator=" | H:${health_rating}${health_detail:+ ${health_detail}}" ;;
        esac
    fi
fi

# Build output: Model | Dir | Branch (uncommitted) | Health | Context
output="${C_ACCENT}${model}${C_GRAY} | 📁${dir}"
[[ -n "$branch" ]] && output+=" | 🔀${branch} ${git_status}"
[[ -n "$health_indicator" ]] && output+="${health_indicator}"
output+=" | ${ctx}${C_RESET}"

printf '%b\n' "$output"

# Get user's last message (text only, not tool results, skip unhelpful messages)
if [[ -n "$transcript_path" && -f "$transcript_path" ]]; then
    # Calculate visible length (without ANSI codes) - 10 chars for bar + content
    plain_output="${model} | 📁${dir}"
    [[ -n "$branch" ]] && plain_output+=" | 🔀${branch} ${git_status}"
    cost_plain=""
    [[ -n "$cost_usd" ]] && cost_plain=" $(printf '$%.2f' "$cost_usd") \$0.00/t"
    plain_output+=" | xxxxxxxxxx ${pct}%/${max_k}k | ⚡${cache_hit_pct:-0}%${cost_plain}"
    max_len=${#plain_output}
    last_user_msg=$(jq -rs '
        # Messages to skip (not useful as context)
        def is_unhelpful:
            startswith("[Request interrupted") or
            startswith("[Request cancelled") or
            . == "";

        [.[] | select(.type == "user") |
         select(.message.content | type == "string" or
                (type == "array" and any(.[]; .type == "text")))] |
        reverse |
        map(.message.content |
            if type == "string" then .
            else [.[] | select(.type == "text") | .text] | join(" ") end |
            gsub("\n"; " ") | gsub("  +"; " ")) |
        map(select(is_unhelpful | not)) |
        first // ""
    ' < "$transcript_path" 2>/dev/null)

    if [[ -n "$last_user_msg" ]]; then
        if [[ ${#last_user_msg} -gt $max_len ]]; then
            echo "💬 ${last_user_msg:0:$((max_len - 3))}..."
        else
            echo "💬 ${last_user_msg}"
        fi
    fi
fi
