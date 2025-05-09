#!/bin/bash

countdown() {
    for i in {5..1}; do
        echo -n "$i.."
        sleep 1
    done
    echo
}

prompt() {
    local text="$1"
    local output="$2"
    local input=""

    echo -ne "$text\n> "
    read -r input
    [[ -z "$input" ]] && return 1

    printf -v "$output" '%s' "$input"
    return 0
}

prompt_with_default() {
    local text="$1"
    local default="$2"
    local output="$3"
    local input=""

    echo -ne "$text\n> "
    read -r input
    [[ -z "$input" ]] && input="$default"

    printf -v "$output" '%s' "$input"
    return 0
}

prompt_select() {
    local text="$1"
    local output="$2"
    shift 2
    local options=("$@")
    local input=""

    PS3="> "
    echo -e "$text"
    select input in "${options[@]}"; do break; done
    [[ -z "$input" ]] && return 1

    printf -v "$output" '%s' "$input"
    return 0
}

prompt_password() {
    local text="$1"
    local output="$2"
    local input1=""
    local input2=""

    echo -ne "$text\n> "
    read -rs input1; echo
    [[ -z "$input1" ]] && return 1

    echo -ne "confirm> "
    read -rs input2; echo
    [[ "$input1" != "$input2" ]] && return 1

    printf -v "$output" '%s' "$input1"
    return 0
}

prompt_password_with_default() {
    local text="$1"
    local default="$2"
    local output="$3"
    local input1=""
    local input2=""

    echo -ne "$text\n> "
    read -rs input1; echo
    if [[ -n "$input1" ]]; then
        echo -ne "confirm> "
        read -rs input2; echo
        [[ "$input1" != "$input2" ]] && return 1
    else
        input1="$default"
    fi

    printf -v "$output" '%s' "$input1"
    return 0
}
