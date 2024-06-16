#!/usr/bin/env bash

# shellcheck disable=SC1091,SC2155,SC2154
# Not following: (error message here)
# Declare and assign separately to avoid masking return values.
# var is referenced but not assigned.

source ./gitmagic.sh -T -s slug_id_test
 
testLogNotArchived() {
    local expected_message="LOGS WERE NOT AVAILABLE - navigate to https://codemagic.io/app/slug_id_test/build/5fabc6414c483700143f4f92 to see the logs."
    trigger_build "successful"> /dev/null
    local actual_message=$(get_build_status "not_archived")
    assertEquals "Message for logs not available did not match" "$expected_message" "$actual_message"
}

testLogsUrl() {
    local expected_url="https://bitrise_test_url.com"
    get_build_status "archived" > /dev/null
    local actual_url="${log_url}"
    assertEquals "log url did not match" "$expected_url" "$actual_url"
}

. ./tests/shunit2