#!/usr/bin/env bash

# shellcheck disable=SC1091,SC2155
# Not following: (error message here)
# Declare and assign separately to avoid masking return values.

testMissingWorkflow() {
    local expected_message="ERROR: Missing arguments(s). All these args must be passed: --workflow,--slug,--access-token"
    local actual_message=$(./gitmagic.sh -b "test-branch" -s "test-slug" -a "test-token")
    assertContains "Output message does not match." "${actual_message}" "${expected_message}"
}

testMissingProjectSlug() {
    local expected_message="ERROR: Missing arguments(s). All these args must be passed: --workflow,--slug,--access-token"
    local actual_message=$(./gitmagic.sh -b "test-branch" -w "workflow" -a "test-token")
    assertContains "Output message does not match." "${actual_message}" "${expected_message}"
}

testMissingRequiredOptions() {
    local expected_message="ERROR: Missing arguments(s). All these args must be passed: --workflow,--slug,--access-token"
    local actual_message=$(./gitmagic.sh)
    assertContains "Output message does not match." "${actual_message}" "${expected_message}"
}

testMissingCheckoutOptions() {
    local expected_message="ERROR: Missing build argument. Pass one of these: --commit, --tag, --branch"
    local actual_message=$(./gitmagic.sh -s "test-slug" -a "test-token" -w "test-workflow")
    assertContains "Output message does not match." "${actual_message}" "${expected_message}"
}

testInvalidCheckoutOption() {
    local expected_message="ERROR: Missing build argument. Pass one of these: --commit, --tag, --branch"
    local actual_message=$(./gitmagic.sh -s "test-slug" -a "test-token" -w "test-workflow" -t "")
    assertContains "Output message does not match." "${actual_message}" "${expected_message}"
}

testPassingTooCheckoutOptions() {
    source ./gitmagic.sh -T -d -s "test-slug" -a "test-token" -w "test-workflow" -b "test-branch" -t "test-tag"
    local expected_message="Warning: Too many building arguments passed. Only one of these is needed: --commit, --tag, --branch"
    local actual_message=$(validate_input)
    assertContains "Output message does not match." "${actual_message}" "${expected_message}"
}

testPassingAllCheckoutOptions() {
    source ./gitmagic.sh -T -d -s "test-slug" -a "test-token" -w "test-workflow" -b "test-branch" -t "test-tag" -c "test-commit"
    local expected_message="Warning: Too many building arguments passed. Only one of these is needed: --commit, --tag, --branch"
    local actual_message=$(validate_input)
    assertContains "Output message does not match." "${actual_message}" "${expected_message}"
}

testTooShortPollingInterval() {
    source ./gitmagic.sh -T -d -s "test-slug" -a "test-token" -w "test-workflow" -b "test-branch" -p 7
    local expected_message="ERROR: polling interval is too short. The minimum acceptable value is 10, but received 7."
    local actual_message=$(validate_input)
    assertContains "Output message does not match." "${actual_message}" "${expected_message}"
}

testAcceptablePollingInterval() {
    source ./gitmagic.sh -T -d -s "test-slug" -a "test-token" -w "test-workflow" -b "test-branch" -p 10
    local not_expected_message="ERROR: polling interval is too short. The minimum acceptable value is 10, but received 10."
    local actual_message=$(validate_input)
    assertNotContains "Output message does not match." "${actual_message}" "${not_expected_message}"
}
. ./tests/shunit2