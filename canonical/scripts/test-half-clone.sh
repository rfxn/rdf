#!/usr/bin/env bash
#
# test-half-clone.sh - Test suite for half-clone-conversation.sh
#
# Creates mock conversations and verifies the half-clone behavior.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HALF_CLONE_SCRIPT="${SCRIPT_DIR}/half-clone-conversation.sh"

# Test directory (isolated from real Claude data)
TEST_DIR=$(mktemp -d)
TEST_CLAUDE_DIR="${TEST_DIR}/.claude"
TEST_PROJECTS_DIR="${TEST_CLAUDE_DIR}/projects"
TEST_PROJECT_PATH="/test/project"
TEST_PROJECT_DIRNAME="-test-project"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

log_test() { echo -e "${YELLOW}[TEST]${NC} $1"; ((++TESTS_RUN)) || true; }
log_pass() { echo -e "${GREEN}[PASS]${NC} $1"; ((++TESTS_PASSED)) || true; }
log_fail() { echo -e "${RED}[FAIL]${NC} $1"; ((++TESTS_FAILED)) || true; }

setup_test_env() {
    mkdir -p "${TEST_PROJECTS_DIR}/${TEST_PROJECT_DIRNAME}"
    mkdir -p "${TEST_CLAUDE_DIR}/todos"
    touch "${TEST_CLAUDE_DIR}/history.jsonl"
}

cleanup_test_env() {
    rm -rf "$TEST_DIR"
}

# Generate a mock message line
# Args: uuid, parent_uuid (or "null"), session_id, type (user/assistant), content
generate_message() {
    local uuid="$1"
    local parent_uuid="$2"
    local session_id="$3"
    local msg_type="$4"
    local content="$5"

    local parent_field
    if [ "$parent_uuid" = "null" ]; then
        parent_field='"parentUuid":null'
    else
        parent_field="\"parentUuid\":\"${parent_uuid}\""
    fi

    if [ "$msg_type" = "user" ]; then
        echo "{${parent_field},\"sessionId\":\"${session_id}\",\"type\":\"user\",\"message\":{\"role\":\"user\",\"content\":\"${content}\"},\"uuid\":\"${uuid}\",\"timestamp\":\"2025-01-01T00:00:00.000Z\"}"
    else
        echo "{${parent_field},\"sessionId\":\"${session_id}\",\"type\":\"assistant\",\"message\":{\"role\":\"assistant\",\"content\":[{\"type\":\"text\",\"text\":\"${content}\"}]},\"uuid\":\"${uuid}\",\"timestamp\":\"2025-01-01T00:00:00.000Z\"}"
    fi
}

# Create a test conversation with N messages
# Returns the session ID
create_test_conversation() {
    local num_messages="$1"
    local session_id
    session_id=$(uuidgen | tr '[:upper:]' '[:lower:]')
    local conv_file="${TEST_PROJECTS_DIR}/${TEST_PROJECT_DIRNAME}/${session_id}.jsonl"

    local prev_uuid="null"
    for i in $(seq 1 "$num_messages"); do
        local uuid
        uuid=$(uuidgen | tr '[:upper:]' '[:lower:]')
        local msg_type
        if [ $((i % 2)) -eq 1 ]; then
            msg_type="user"
            generate_message "$uuid" "$prev_uuid" "$session_id" "user" "User message $i"
        else
            msg_type="assistant"
            generate_message "$uuid" "$prev_uuid" "$session_id" "assistant" "Assistant response $i"
        fi
        prev_uuid="$uuid"
    done > "$conv_file"

    echo "$session_id"
}

run_half_clone() {
    local session_id="$1"
    # Override HOME to use test directory
    HOME="$TEST_DIR" "$HALF_CLONE_SCRIPT" "$session_id" "$TEST_PROJECT_PATH" 2>&1
}

count_messages() {
    local file="$1"
    wc -l < "$file" | tr -d ' '
}

get_new_session_from_output() {
    local output="$1"
    echo "$output" | grep "New session:" | awk '{print $3}'
}

# Test 1: 6 messages (3 user, 3 assistant) -> 3 clean user msgs, skip 1, keep 2
# Starts at user message 2 (line 3), keeps lines 3-6 = 4 messages + 1 reference = 5
test_even_messages() {
    log_test "6 messages (3 clean user): should keep 4 lines + 1 reference = 5"

    local session_id
    session_id=$(create_test_conversation 6)
    local output
    output=$(run_half_clone "$session_id")

    local new_session
    new_session=$(get_new_session_from_output "$output")
    local new_file="${TEST_PROJECTS_DIR}/${TEST_PROJECT_DIRNAME}/${new_session}.jsonl"

    if [ ! -f "$new_file" ]; then
        log_fail "Output file not created"
        return
    fi

    local count
    count=$(count_messages "$new_file")
    if [ "$count" -eq 5 ]; then
        log_pass "Kept 5 messages (4 + reference)"
    else
        log_fail "Expected 5 messages, got $count"
    fi
}

# Test 2: 7 messages (4 user, 3 assistant) -> 4 clean user msgs, skip 2, keep 2
# Starts at user message 3 (line 5), keeps lines 5-7 = 3 messages + 1 reference = 4
test_odd_messages() {
    log_test "7 messages (4 clean user): should keep 3 lines + 1 reference = 4"

    local session_id
    session_id=$(create_test_conversation 7)
    local output
    output=$(run_half_clone "$session_id")

    local new_session
    new_session=$(get_new_session_from_output "$output")
    local new_file="${TEST_PROJECTS_DIR}/${TEST_PROJECT_DIRNAME}/${new_session}.jsonl"

    local count
    count=$(count_messages "$new_file")
    if [ "$count" -eq 4 ]; then
        log_pass "Kept 4 messages (3 + reference)"
    else
        log_fail "Expected 4 messages, got $count"
    fi
}

# Test 3: 4 messages (2 user, 2 assistant) -> 2 clean user msgs, skip 1, keep 1
# Starts at user message 2 (line 3), keeps lines 3-4 = 2 messages + 1 reference = 3
test_minimum_messages() {
    log_test "4 messages (2 clean user): should keep 2 lines + 1 reference = 3"

    local session_id
    session_id=$(create_test_conversation 4)
    local output
    output=$(run_half_clone "$session_id")

    local new_session
    new_session=$(get_new_session_from_output "$output")
    local new_file="${TEST_PROJECTS_DIR}/${TEST_PROJECT_DIRNAME}/${new_session}.jsonl"

    local count
    count=$(count_messages "$new_file")
    if [ "$count" -eq 3 ]; then
        log_pass "Kept 3 messages (2 + reference)"
    else
        log_fail "Expected 3 messages, got $count"
    fi
}

# Test 4: 2 messages (1 user, 1 assistant) -> only 1 clean user msg, should error
test_single_message_error() {
    log_test "2 messages (1 clean user): should error"

    local session_id
    session_id=$(create_test_conversation 2)
    local output
    if output=$(run_half_clone "$session_id" 2>&1); then
        log_fail "Should have failed but succeeded"
    else
        if echo "$output" | grep -q "fewer than 2 clean user messages"; then
            log_pass "Correctly errored for single clean user message"
        else
            log_fail "Wrong error message: $output"
        fi
    fi
}

# Test 5: First kept message has null parentUuid
test_parent_uuid_nullified() {
    log_test "First kept message should have null parentUuid"

    local session_id
    session_id=$(create_test_conversation 6)
    local output
    output=$(run_half_clone "$session_id")

    local new_session
    new_session=$(get_new_session_from_output "$output")
    local new_file="${TEST_PROJECTS_DIR}/${TEST_PROJECT_DIRNAME}/${new_session}.jsonl"

    local first_line
    first_line=$(head -1 "$new_file")

    if echo "$first_line" | grep -q '"parentUuid":null'; then
        log_pass "First message has null parentUuid"
    else
        log_fail "First message does not have null parentUuid"
        echo "First line: $first_line"
    fi
}

# Test 6: [HALF-CLONE <timestamp>] tag is present
test_half_clone_tag() {
    log_test "[HALF-CLONE <timestamp>] tag should be in first user message"

    local session_id
    session_id=$(create_test_conversation 6)
    local output
    output=$(run_half_clone "$session_id")

    local new_session
    new_session=$(get_new_session_from_output "$output")
    local new_file="${TEST_PROJECTS_DIR}/${TEST_PROJECT_DIRNAME}/${new_session}.jsonl"

    # Match pattern like [HALF-CLONE Jan 7 14:30]
    if grep -qE '\[HALF-CLONE [A-Z][a-z]+ [0-9]+ [0-9]+:[0-9]+\]' "$new_file"; then
        log_pass "[HALF-CLONE <timestamp>] tag found"
    else
        log_fail "[HALF-CLONE <timestamp>] tag not found"
        cat "$new_file"
    fi
}

# Test 7: Session IDs are remapped
test_session_id_remapped() {
    log_test "Session IDs should be remapped to new ID"

    local session_id
    session_id=$(create_test_conversation 4)
    local output
    output=$(run_half_clone "$session_id")

    local new_session
    new_session=$(get_new_session_from_output "$output")
    local new_file="${TEST_PROJECTS_DIR}/${TEST_PROJECT_DIRNAME}/${new_session}.jsonl"

    # Check that old session ID is not in the new file
    if grep -q "\"sessionId\":\"${session_id}\"" "$new_file"; then
        log_fail "Old session ID still present"
    elif grep -q "\"sessionId\":\"${new_session}\"" "$new_file"; then
        log_pass "Session ID correctly remapped"
    else
        log_fail "New session ID not found"
    fi
}

# Test 8: History entry is added
test_history_entry() {
    log_test "History entry should be added"

    local session_id
    session_id=$(create_test_conversation 4)

    local history_before
    history_before=$(wc -l < "${TEST_CLAUDE_DIR}/history.jsonl" | tr -d ' ')

    run_half_clone "$session_id" > /dev/null

    local history_after
    history_after=$(wc -l < "${TEST_CLAUDE_DIR}/history.jsonl" | tr -d ' ')

    if [ "$history_after" -gt "$history_before" ]; then
        # Match pattern like [HALF-CLONE Jan 7 14:30]
        if grep -qE '\[HALF-CLONE [A-Z][a-z]+ [0-9]+ [0-9]+:[0-9]+\]' "${TEST_CLAUDE_DIR}/history.jsonl"; then
            log_pass "History entry added with [HALF-CLONE <timestamp>] tag"
        else
            log_fail "History entry added but missing [HALF-CLONE <timestamp>] tag"
        fi
    else
        log_fail "No history entry added"
    fi
}

# Test 9: Double tagging - half-clone a conversation that already has a tag
test_double_tagging() {
    log_test "Double tagging: half-cloning already-tagged conversation should have both tags"

    # Create a 6-message conversation where the THIRD user message (which will be
    # the first kept after half-clone) already has a tag. This simulates:
    # 1. A conversation that was previously half-cloned
    # 2. Then continued with more messages
    # 3. Now being half-cloned again
    local session_id
    session_id=$(uuidgen | tr '[:upper:]' '[:lower:]')
    local conv_file="${TEST_PROJECTS_DIR}/${TEST_PROJECT_DIRNAME}/${session_id}.jsonl"

    local uuid1 uuid2 uuid3 uuid4 uuid5 uuid6
    uuid1=$(uuidgen | tr '[:upper:]' '[:lower:]')
    uuid2=$(uuidgen | tr '[:upper:]' '[:lower:]')
    uuid3=$(uuidgen | tr '[:upper:]' '[:lower:]')
    uuid4=$(uuidgen | tr '[:upper:]' '[:lower:]')
    uuid5=$(uuidgen | tr '[:upper:]' '[:lower:]')
    uuid6=$(uuidgen | tr '[:upper:]' '[:lower:]')

    # 6 messages = 3 user messages. Half-clone skips 1, keeps 2.
    # So messages 3-6 are kept, and message 3 (2nd user msg) becomes first.
    # Put the existing tag on message 3 (the 2nd user message).
    {
        echo "{\"parentUuid\":null,\"sessionId\":\"${session_id}\",\"type\":\"user\",\"message\":{\"role\":\"user\",\"content\":\"User message 1\"},\"uuid\":\"${uuid1}\",\"timestamp\":\"2025-01-01T00:00:00.000Z\"}"
        echo "{\"parentUuid\":\"${uuid1}\",\"sessionId\":\"${session_id}\",\"type\":\"assistant\",\"message\":{\"role\":\"assistant\",\"content\":[{\"type\":\"text\",\"text\":\"Response 1\"}]},\"uuid\":\"${uuid2}\",\"timestamp\":\"2025-01-01T00:00:00.000Z\"}"
        echo "{\"parentUuid\":\"${uuid2}\",\"sessionId\":\"${session_id}\",\"type\":\"user\",\"message\":{\"role\":\"user\",\"content\":\"[HALF-CLONE Jan 1 12:00] User message 2\"},\"uuid\":\"${uuid3}\",\"timestamp\":\"2025-01-01T00:00:00.000Z\"}"
        echo "{\"parentUuid\":\"${uuid3}\",\"sessionId\":\"${session_id}\",\"type\":\"assistant\",\"message\":{\"role\":\"assistant\",\"content\":[{\"type\":\"text\",\"text\":\"Response 2\"}]},\"uuid\":\"${uuid4}\",\"timestamp\":\"2025-01-01T00:00:00.000Z\"}"
        echo "{\"parentUuid\":\"${uuid4}\",\"sessionId\":\"${session_id}\",\"type\":\"user\",\"message\":{\"role\":\"user\",\"content\":\"User message 3\"},\"uuid\":\"${uuid5}\",\"timestamp\":\"2025-01-01T00:00:00.000Z\"}"
        echo "{\"parentUuid\":\"${uuid5}\",\"sessionId\":\"${session_id}\",\"type\":\"assistant\",\"message\":{\"role\":\"assistant\",\"content\":[{\"type\":\"text\",\"text\":\"Response 3\"}]},\"uuid\":\"${uuid6}\",\"timestamp\":\"2025-01-01T00:00:00.000Z\"}"
    } > "$conv_file"

    local output
    output=$(run_half_clone "$session_id")

    local new_session
    new_session=$(get_new_session_from_output "$output")
    local new_file="${TEST_PROJECTS_DIR}/${TEST_PROJECT_DIRNAME}/${new_session}.jsonl"

    # Should have two [HALF-CLONE ...] tags - the new one prepended to the existing one
    local first_user_line
    first_user_line=$(grep '"type":"user"' "$new_file" | head -1)

    # Count occurrences of [HALF-CLONE pattern
    local tag_count
    tag_count=$(echo "$first_user_line" | grep -oE '\[HALF-CLONE [A-Z][a-z]+ [0-9]+ [0-9]+:[0-9]+\]' | wc -l | tr -d ' ')

    if [ "$tag_count" -eq 2 ]; then
        log_pass "Double tagging works - found 2 [HALF-CLONE] tags"
    else
        log_fail "Expected 2 [HALF-CLONE] tags, found $tag_count"
        echo "First user line: $first_user_line"
    fi
}

# Test 10: Thinking blocks should be stripped from assistant messages
test_thinking_blocks_stripped() {
    log_test "Thinking blocks should be stripped from cloned conversation"

    # Create a conversation with thinking blocks in assistant messages
    local session_id
    session_id=$(uuidgen | tr '[:upper:]' '[:lower:]')
    local conv_file="${TEST_PROJECTS_DIR}/${TEST_PROJECT_DIRNAME}/${session_id}.jsonl"

    local uuid1 uuid2 uuid3 uuid4
    uuid1=$(uuidgen | tr '[:upper:]' '[:lower:]')
    uuid2=$(uuidgen | tr '[:upper:]' '[:lower:]')
    uuid3=$(uuidgen | tr '[:upper:]' '[:lower:]')
    uuid4=$(uuidgen | tr '[:upper:]' '[:lower:]')

    {
        echo "{\"parentUuid\":null,\"sessionId\":\"${session_id}\",\"type\":\"user\",\"message\":{\"role\":\"user\",\"content\":\"First question\"},\"uuid\":\"${uuid1}\",\"timestamp\":\"2025-01-01T00:00:00.000Z\"}"
        echo "{\"parentUuid\":\"${uuid1}\",\"sessionId\":\"${session_id}\",\"type\":\"assistant\",\"message\":{\"role\":\"assistant\",\"content\":[{\"type\":\"thinking\",\"thinking\":\"Let me think about this...\"},{\"type\":\"text\",\"text\":\"Response 1\"}]},\"uuid\":\"${uuid2}\",\"timestamp\":\"2025-01-01T00:00:00.000Z\"}"
        echo "{\"parentUuid\":\"${uuid2}\",\"sessionId\":\"${session_id}\",\"type\":\"user\",\"message\":{\"role\":\"user\",\"content\":\"Second question\"},\"uuid\":\"${uuid3}\",\"timestamp\":\"2025-01-01T00:00:00.000Z\"}"
        echo "{\"parentUuid\":\"${uuid3}\",\"sessionId\":\"${session_id}\",\"type\":\"assistant\",\"message\":{\"role\":\"assistant\",\"content\":[{\"type\":\"thinking\",\"thinking\":\"Thinking again...\"},{\"type\":\"text\",\"text\":\"Response 2\"}]},\"uuid\":\"${uuid4}\",\"timestamp\":\"2025-01-01T00:00:00.000Z\"}"
    } > "$conv_file"

    local output
    output=$(run_half_clone "$session_id")

    local new_session
    new_session=$(get_new_session_from_output "$output")
    local new_file="${TEST_PROJECTS_DIR}/${TEST_PROJECT_DIRNAME}/${new_session}.jsonl"

    # Check that no thinking blocks remain
    local thinking_count
    thinking_count=$(grep -c '"type":"thinking"' "$new_file" 2>/dev/null || true)
    thinking_count=${thinking_count:-0}

    if [ "$thinking_count" -eq 0 ]; then
        # Also verify text blocks are preserved
        if grep -q '"type":"text"' "$new_file"; then
            log_pass "Thinking blocks stripped, text blocks preserved"
        else
            log_fail "Thinking blocks stripped but text blocks also missing"
        fi
    else
        log_fail "Found $thinking_count thinking blocks (expected 0)"
    fi
}

# Main
main() {
    echo "================================"
    echo "Half-Clone Conversation Tests"
    echo "================================"
    echo ""

    if [ ! -f "$HALF_CLONE_SCRIPT" ]; then
        echo "Error: half-clone-conversation.sh not found at $HALF_CLONE_SCRIPT"
        exit 1
    fi

    setup_test_env
    trap cleanup_test_env EXIT

    test_even_messages
    test_odd_messages
    test_minimum_messages
    test_single_message_error
    test_parent_uuid_nullified
    test_half_clone_tag
    test_session_id_remapped
    test_history_entry
    test_double_tagging
    test_thinking_blocks_stripped

    echo ""
    echo "================================"
    echo "Results: $TESTS_PASSED/$TESTS_RUN passed"
    if [ "$TESTS_FAILED" -gt 0 ]; then
        echo -e "${RED}$TESTS_FAILED tests failed${NC}"
        exit 1
    else
        echo -e "${GREEN}All tests passed!${NC}"
    fi
}

main "$@"
