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

# Extract all hook-input fields in one jq pass. Newline-delimited, not @tsv: tab is
# IFS-whitespace and would collapse consecutive empty fields (shifting the parse).
{
    IFS= read -r model
    IFS= read -r cwd
    IFS= read -r transcript_path
    IFS= read -r max_context
    IFS= read -r cost_usd
} < <(printf '%s' "$input" | jq -r '
    .model.display_name // .model.id // "?",
    .cwd // "",
    .transcript_path // "",
    (.context_window.context_window_size // 200000 | tostring),
    (.cost.total_cost_usd // "" | tostring)')
dir=$(basename "$cwd" 2>/dev/null || echo "?")

# Get git branch, uncommitted file count, and sync status
branch=""
git_status=""
if [[ -n "$cwd" && -d "$cwd" ]]; then
    branch=$(git -C "$cwd" branch --show-current 2>/dev/null)
    if [[ -n "$branch" ]]; then
        # Count uncommitted tracked changes (staged + unstaged modified/deleted)
        # Excludes untracked files — those aren't "pending" work
        file_count=$(git -C "$cwd" --no-optional-locks status --porcelain -uno 2>/dev/null | wc -l | tr -d ' ')

        # Check sync status with current branch's upstream
        sync_status=""
        upstream=$(git -C "$cwd" rev-parse --abbrev-ref @{upstream} 2>/dev/null)
        if [[ -n "$upstream" ]]; then
            counts=$(git -C "$cwd" rev-list --left-right --count HEAD...@{upstream} 2>/dev/null)
            ahead=$(echo "$counts" | cut -f1)
            behind=$(echo "$counts" | cut -f2)

            # Sync time: use the push time of the current branch (last reflog entry
            # for the remote tracking ref), not FETCH_HEAD which is a global timestamp
            remote_ref="refs/remotes/${upstream}"
            sync_ago=""
            push_time=$(git -C "$cwd" reflog show "$remote_ref" --format='%ct' -1 2>/dev/null)
            if [[ -n "$push_time" ]]; then
                now=$(date +%s)
                diff=$((now - push_time))
                if [[ $diff -lt 60 ]]; then
                    sync_ago="<1m ago"
                elif [[ $diff -lt 3600 ]]; then
                    sync_ago="$((diff / 60))m ago"
                elif [[ $diff -lt 86400 ]]; then
                    sync_ago="$((diff / 3600))h ago"
                else
                    sync_ago="$((diff / 86400))d ago"
                fi
            fi

            if [[ "$ahead" -eq 0 && "$behind" -eq 0 ]]; then
                if [[ -n "$sync_ago" ]]; then
                    sync_status="synced ${sync_ago}"
                else
                    sync_status="synced"
                fi
            elif [[ "$ahead" -gt 0 && "$behind" -eq 0 ]]; then
                sync_status="${ahead} ahead"
            elif [[ "$ahead" -eq 0 && "$behind" -gt 0 ]]; then
                sync_status="${behind} behind"
            else
                sync_status="${ahead}↑ ${behind}↓"
            fi
        else
            sync_status="no upstream"
        fi

        # Build git status string: compact format
        # 0 pending: just sync status (e.g. "synced 12m ago", "2 ahead")
        # N pending: "N pending · sync" (e.g. "5 pending · synced 12m ago")
        if [[ "$file_count" -eq 0 ]]; then
            git_status="${sync_status}"
        else
            git_status="${file_count} pending · ${sync_status}"
        fi
    fi
fi

# Context window size (extracted above); tokens are computed from the transcript
# (more accurate than total_input_tokens which excludes system prompt/tools/memory).
# See: github.com/anthropics/claude-code/issues/13652
max_k=$((max_context / 1000))

# Calculate context bar from transcript
if [[ -n "$transcript_path" && -f "$transcript_path" ]]; then
    # Single pass over the transcript: token totals AND turn count share one filter
    # (was two separate slurps). Last-message extraction stays separate below so its
    # tolerated-failure semantics stay decoupled from the metrics.
    context_metrics=$(jq -rs '
        map(select(.message.usage and .isSidechain != true and .isApiErrorMessage != true)) as $u |
        ($u | last | .message.usage) as $g |
        (($g.input_tokens // 0) + ($g.cache_read_input_tokens // 0) + ($g.cache_creation_input_tokens // 0)) as $total |
        "\($total) \($g.cache_read_input_tokens // 0) \($g.cache_creation_input_tokens // 0) \($g.input_tokens // 0) \($u | length)"
    ' < "$transcript_path")
    read -r context_length cache_read cache_create uncached_input turn_count <<< "$context_metrics"

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

    # Session cost and windowed burn rate (last 5 turns); cost_usd extracted above
    cost_label=""
    if [[ -n "$cost_usd" ]]; then
        cost_fmt=$(printf '$%.2f' "$cost_usd")

        # turn_count comes from the single metrics pass above
        if [[ "$turn_count" -gt 0 ]]; then
            # Track cumulative cost at each turn for windowed average
            # Prefer XDG_RUNTIME_DIR (user-private tmpfs) over world-readable /tmp
            _cache_dir="${XDG_RUNTIME_DIR:-/tmp}"
            cost_cache="${_cache_dir}/claude-cost-$(printf '%s' "$transcript_path" | { md5sum 2>/dev/null || md5 -q 2>/dev/null; } | cut -c1-8).hist"
            last_recorded=0
            if [[ -f "$cost_cache" ]]; then
                last_recorded=$(tail -1 "$cost_cache" | cut -d' ' -f1)
                [[ -z "$last_recorded" ]] && last_recorded=0
            fi
            [[ "$turn_count" -gt "$last_recorded" ]] && echo "$turn_count $cost_usd" >> "$cost_cache"

            # Windowed avg: take last 6 entries to get a 5-turn delta window
            # (cost_at_N - cost_at_N-5) / 5 = avg marginal cost over last 5 turns
            per_turn=""
            if [[ -f "$cost_cache" ]]; then
                window=$(tail -6 "$cost_cache")
                w_first=$(echo "$window" | head -1)
                w_last=$(echo "$window" | tail -1)
                w_delta=$((${w_last%% *} - ${w_first%% *}))
                if [[ "$w_delta" -gt 0 ]]; then
                    per_turn=$(awk "BEGIN { printf \"%.2f\", (${w_last##* } - ${w_first##* }) / $w_delta }")
                fi
            fi
            # Fallback to cumulative if window has only 1 entry
            [[ -z "$per_turn" ]] && per_turn=$(awk "BEGIN { printf \"%.2f\", $cost_usd / $turn_count }")

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
    cache_file="${XDG_RUNTIME_DIR:-/tmp}/rfxn-health-${project_name}.cache"
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
