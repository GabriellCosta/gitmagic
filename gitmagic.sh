#!/usr/bin/env bash
# shellcheck disable=SC2155
# disbales "Declare and assign separately to avoid masking return values."
# shellcheck disable=SC2120
# disables "foo references arguments, but none are ever passed."

VERSION="0.9.2"
APP_NAME="GitMagic"
STATUS_POLLING_INTERVAL=30

build_id=""
build_slug=""
build_url=""
build_status=0
current_build_status_text=""
exit_code=""
log_url=""
build_artifacts_slugs=()

function usage() {
    echo ""
    echo "Usage: gitmagic.sh [-d] [-e] [-h] [-T] [-v]  -a token -s project_slug -w workflow [-b branch|-t tag|-c commit]"
    echo 
    echo "  -a, --access-token         <string>    CodeMagic access token"
    echo "  -b, --branch               <string>    Git branch"
    echo "  -c, --commit               <string>    Git commit hash "
    echo "  -d, --debug                            Debug mode enabled"
    echo "      --download-artifacts   <string>    List of build artifact names to download in the form of name1,name2" 
    echo "  -e, --env                  <string>    List of environment variables in the form of key1:value1,key2:value2"
    echo "  -h, --help                             Print this help text"
    echo "  -p, --poll                  <string>   Polling interval (in seconds) to get the build status."
    echo "      --stream                           Stream build logs"
    echo "  -s, --slug                  <string>   CodeMagic project slug"
    echo "  -T, --test                             Test mode enabled"
    echo "  -t, --tag                   <string>   Git tag"
    echo "  -v, --version                          App version"
    echo "  -w, --workflow              <string>   CodeMagic workflow"
    echo 
}

# parsing space separated options
while [ $# -gt 0 ]; do
    key="$1"
    case $key in
    -v|--version)
        echo "$APP_NAME version $VERSION"
        exit 0
    ;;
    -w|--workflow)
        WORKFLOW="$2"
        shift;shift
    ;;
    -c|--commit)
        COMMIT="$2"
        shift;shift
    ;;
    -t|--tag)
        TAG="$2"
        shift;shift
    ;;
    -b|--branch)
        BRANCH="$2"
        shift;shift
    ;;
    -a|--access-token)
        ACCESS_TOKEN="$2"
        shift;shift
    ;;
    -s|--slug)
        PROJECT_SLUG="$2"
        shift;shift
    ;;
    -e|--env)
        ENV_STRING="$2"
        shift;shift
    ;;
    -h|--help)
        usage
        exit 0 
    ;;
    -T|--test)
        TESTING_ENABLED="true"
        shift
    ;;
    -d|--debug)
        DEBUG="true"
        shift
    ;;
    --stream)
        STREAM="true"
        shift
    ;;
    -p|--poll)
        STATUS_POLLING_INTERVAL="$2"
        shift;shift
    ;;
    --download-artifacts)
        BUILD_ARTIFACTS="$2"
        shift;shift
    ;;
    *) 
        echo "Invalid option '$1'"
        usage
        exit 1
    ;;
    esac
done

# Create temp directory if debugging mode enabled
if [ "$DEBUG" == "true" ]; then  
    [ -d gitrise_temp ] && rm -r gitrise_temp 
    mkdir -p gitrise_temp
fi

# Create build_artifacts directory when downloading build artifacts
if [ -n "$BUILD_ARTIFACTS" ]; then  
    [ -d build_artifacts ] && rm -r build_artifacts
    mkdir -p build_artifacts
fi

function validate_input() {
    if [ -z "$WORKFLOW" ] || [ -z "$ACCESS_TOKEN" ] || [ -z "$PROJECT_SLUG" ]; then
        printf "\e[31m ERROR: Missing arguments(s). All these args must be passed: --workflow,--slug,--access-token \e[0m\n"
        usage
        exit 1
    fi

    local count=0
    [[ -n "$TAG" ]] &&  ((count++))
    [[ -n "$COMMIT" ]] &&  ((count++))
    [[ -n "$BRANCH" ]] &&  ((count++))

    if [[  $count -gt 1 ]]; then
        printf "\n\e[33m Warning: Too many building arguments passed. Only one of these is needed: --commit, --tag, --branch \e[0m\n"
    elif [[  $count == 0 ]]; then
        printf "\e[31m ERROR: Missing build argument. Pass one of these: --commit, --tag, --branch\e[0m\n"
        usage
        exit 1
    fi

    if [[ $STATUS_POLLING_INTERVAL -lt 10 ]]; then
        printf "\e[31m ERROR: polling interval is too short. The minimum acceptable value is 10, but received %s.\e[0m\n" "$STATUS_POLLING_INTERVAL"
        exit 1
    fi
}

# map environment variables to objects codemagic will accept. 
# ENV_STRING is passed as argument
function process_env_vars() {
    local env_string=""
    local result=""
    input_length=$(grep -c . <<< "$1")
    if [[ $input_length -gt 1 ]]; then
        while read -r line
        do
            env_string+=$line
        done <<< "$1"
    else
        env_string="$1"
    fi
    IFS=',' read -r -a env_array <<< "$env_string"
    for i in "${env_array[@]}"
    do
        # shellcheck disable=SC2162
        # disables "read without -r will mangle backslashes"
        IFS=':' read -a array_from_pair <<< "$i"
        key="${array_from_pair[0]}"
        value="${array_from_pair[1]}"
        # shellcheck disable=SC2089
        # disables "Quotes/backslashes will be treated literally. Use an array."
        result+="{\"mapped_to\":\"$key\",\"value\":\"$value\",\"is_expand\":true},"
    done
    echo "[${result/%,}]"
}

function generate_build_payload() {
    local environments=$(process_env_vars "$ENV_STRING")   
    cat << EOF
{
    "appId": "$PROJECT_SLUG",
    "branch": "$BRANCH",
    "commit_hash": "$COMMIT",
    "tag": "$TAG",
    "workflowId" : "$WORKFLOW",
    "environment": { "variables" : "$environments" }
}
EOF
}

function trigger_build() {
    local response=""
    if [ -z "${TESTING_ENABLED}" ]; then 
        local command="curl --silent -X POST https://api.codemagic.io/builds \
                --data '$(generate_build_payload)' \
                --header 'Content-Type: application/json' --header 'x-auth-token: $ACCESS_TOKEN'"
        response=$(eval "${command}")
    else
        response=$(<./testdata/"$1"_build_trigger_response.json)
    fi
    [ "$DEBUG" == "true" ] && log "${command%'--data'*}" "$response" "trigger_build.log"
    
    #status_code=$(echo $response | grep HTTP | awk '{print $2}')
    #echo "status code: $status_code"
    status=$(echo "$response" | jq ".buildId" | sed 's/"//g' )
    if [[ -z "$status" ]]; then
        #msg=$(echo "$response" | jq ".buildId" | sed 's/"//g')
        printf "%s" "ERROR: $response"
        exit 1
    else 
        build_id=$status
        build_url="https://codemagic.io/app/$PROJECT_SLUG/build/$build_id"
        build_slug=$PROJECT_SLUG
    fi
    printf "\nHold on... We're about to liftoff! 🚀\n \nBuild Id: %s\n" "${build_id}"
}

function process_build() {
    local status_counter=0
    while [ "${build_status}" = 0 ]; do
        # Parameter is a test json file name and is only passed for testing. 
        check_build_status "$1"
        if [[ "$STREAM" == "true" ]] && [[ "$current_build_status_text" != "on-hold" ]]; then stream_logs; fi
        if [[ $TESTING_ENABLED == true ]] && [[ "${FUNCNAME[1]}" != "testFailureUponReceivingHTMLREsponse" ]]; then break; fi
        sleep "$STATUS_POLLING_INTERVAL"
    done
    if [ "$build_status" = 1 ]; then exit_code=0; else exit_code=1; fi
} 

function check_build_status() {
    local response=""
    local retry=3
    if [ -z "${TESTING_ENABLED}" ]; then
        local command="curl --silent -X GET -w \"status_code:%{http_code}\" https://api.codemagic.io/builds/$build_id \
            --header 'Content-Type: application/json' --header 'x-auth-token: $ACCESS_TOKEN'"
        response=$(eval "${command}")
    else
        response=$(< ./testdata/"$1")
    fi
    [ "$DEBUG" == "true" ] && log "${command%%'--header'*}" "$response" "get_build_status.log"

    if [[ "$response" != *"<!DOCTYPE html>"* ]]; then
        handle_status_response "${response%'status_code'*}"
    else
        if [[ $status_counter -lt $retry ]]; then
            build_status=0
            ((status_counter++))
        else
            echo "ERROR: Invalid response received from CodeMagic API"
            build_status="null" 
        fi
    fi
}

function handle_status_response() {
    local response="$1"
    local build_status_text=$(echo "$response" | jq ".build .status" | sed 's/"//g')
    if [ "$build_status_text" != "$current_build_status_text" ]; then
        echo "Build $build_status_text"
        current_build_status_text="${build_status_text}"
    fi
    build_status=$(echo "$response" | jq ".build .status")
}

function contains_in_array() {
    local array=$1
    if [[ "${array[*]}" =~ (^|[^[:alpha:]])$2([^[:alpha:]]|$) ]]; then
        echo "true"
    else
        echo "false"
    fi
}

function get_build_status() {
    local log_is_archived=false
    local counter=0
    local retry=4
    local polling_interval=15
    local response=""
    local finished_build=("canceled" "finished" "failed" "skipped" "timeout")
    while ! "$log_is_archived"  && [[ "$counter" -lt "$retry" ]]; do
        if [ -z "${TESTING_ENABLED}" ] ; then
            sleep "$polling_interval"
            local command="curl --silent -X GET https://api.codemagic.io/builds/$build_id \
                --header 'Content-Type: application/json' --header 'x-auth-token: $ACCESS_TOKEN'"
            response=$(eval "$command")

        else
            response="$(< ./testdata/"$1"_log_info_response.json)"
        fi
        [ "$DEBUG" == "true" ] && log "${command%'--header'*}" "$response" "get_log_info.log"

        log_is_archived=$(contains_in_array "${finished_build[0]}" "$response")
        ((counter++))
    done
    #log_url=$(echo "$response" | jq ".expiring_raw_log_url" | sed 's/"//g')
    if ! "$log_is_archived"; then
        echo "LOGS WERE NOT AVAILABLE - navigate to $build_url to see the logs."
        exit ${exit_code}
    else
        print_logs "$log_url"
    fi
}

function print_logs() {
    local url="$1"
    local logs=$(curl --silent -X GET "$url")

    echo "================================================================================"
    echo "============================== CodeMagic Logs Start =============================="
    echo "$logs"
    echo "================================================================================"
    echo "==============================  CodeMagic Logs End  =============================="

}

function build_status_message() {
    local status="$1"
    case "$status" in
        "0")
            echo "Build TIMED OUT based on mobile trigger internal setting"
            ;;
        "1")
            echo "Build Successful 🎉"
            ;;
        "2")
            echo "Build Failed 🚨"
            ;;
        "3")
            echo "Build Aborted 💥"
            ;;
        *)
            echo "Invalid build status 🤔"
            exit 1
            ;;
    esac
}

function get_build_artifacts() {
    local build_artifacts_names=()
    local artifact_slug=""
    local response=""
    if [ -z "${TESTING_ENABLED}" ]; then 
        local command="curl --silent -X GET https://api.bitrise.io/v0.1/apps/$PROJECT_SLUG/builds/$build_slug/artifacts \
                            --header 'Accept: application/json' --header 'Authorization: $ACCESS_TOKEN'"
        response=$(eval "${command}") 
    else
        response=$(<./testdata/build_artifacts_response.json)
    fi
    
    [ "$DEBUG" == "true" ] && log "${command%%'--header'*}" "$response" "get_all_artifacts.log"
        
    IFS=',' read -r -a build_artifacts_names <<< "$BUILD_ARTIFACTS"

    for name in "${build_artifacts_names[@]}"
    do
        artifact_slug=$(echo "$response" | jq --arg artifact_name "$name" '.data[] | select(.title | contains($artifact_name)) | .slug' | sed 's/"//g')
        
        [ -n "$artifact_slug" ] && build_artifacts_slugs+=("${artifact_slug}")
    done

    if [[ ${#build_artifacts_slugs[@]} == 0 ]]; then
        printf "%b" "\e[31m ERROR: Invalid download artifacts arguments(s). Make sure artifact names are correct and are passed in the format of --download-artifacts name1,name2 \e[0m\n"
        exit 1
    fi
}

function download_single_artifact() {
    local artifact_slug="$1"
    local response=""
    if [ -z "${TESTING_ENABLED}" ]; then 
        local command="curl --silent -X GET https://api.bitrise.io/v0.1/apps/$PROJECT_SLUG/builds/$build_slug/artifacts/$artifact_slug \
                            --header 'Accept: application/json' --header 'Authorization: $ACCESS_TOKEN'"
        response=$(eval "${command}") 
    else
        response=$(<./testdata/single_artifact_response.json)
    fi

    [ "$DEBUG" == "true" ] && log "${command%%'--header'*}" "$response" "get_single_artifact.log"

    artifact_url=$(echo "$response" | jq ".data.expiring_download_url" | sed 's/"//g')
    artifact_title=$(echo "$response" | jq ".data.title" | sed 's/"//g')
    printf "%b" "Downloading build artifact $artifact_title\n"
    curl -X GET "$artifact_url" --output "./build_artifacts/$artifact_title"
    exit_code=$?
}

function download_build_artifacts() {
    get_build_artifacts  
    for slug in "${build_artifacts_slugs[@]}"
    do
        download_single_artifact "$slug"
    done
}

function log() {
    local request="$1"
    local response="$2"
    local log_file="$3"

    secured_request=${request/\/'apps'\/*\//\/'apps'\/'[REDACTED]'\/}
    printf "%b" "\n[$(TZ="EST6EDT" date +'%T')] REQUEST: ${secured_request}\n[$(TZ="EST6EDT" date +'%T')] RESPONSE: $response\n" >> ./gitrise_temp/"$log_file"
}

# No function execution when the script is sourced 
# shellcheck disable=SC2119
# disables "use foo "$@" if function's $1 should mean script's $1."
if [ "$0" = "${BASH_SOURCE[0]}" ] && [ -z "${TESTING_ENABLED}" ]; then
    validate_input
    trigger_build
    process_build
    [ -z "$STREAM" ] && get_build_status 
    build_status_message "$build_status"
    [ -n "$BUILD_ARTIFACTS" ] && download_build_artifacts
    exit ${exit_code}
fi