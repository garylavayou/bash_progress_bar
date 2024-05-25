#!/bin/bash
# https://github.com/pollev/bash_progress_bar - See license at end of file

# Constants
CODE_SAVE_CURSOR="\033[s"
CODE_RESTORE_CURSOR="\033[u"
CODE_CURSOR_IN_SCROLL_AREA="\033[1A"
COLOR_FG="\e[30m"
COLOR_BG="\e[42m"
COLOR_BG_BLOCKED="\e[43m"
RESTORE_FG="\e[39m"
RESTORE_BG="\e[49m"

# Initialize internal used variables
function _load_variables() {
    PROGRESS_BLOCKED="false"
    TRAPPING_ENABLED="false"
    ETA_ENABLED="false"
    TRAP_SET="false"
    PERCENT_SCALE=2

    CURRENT_NR_LINES=0
    PROGRESS_TITLE=""
    PROGRESS_TOTAL=100
    PROGRESS_START=0
    BLOCKED_START=0
}

# shellcheck disable=SC2120
setup_scroll_area() {
    # If trapping is enabled, we will want to activate it whenever we setup the scroll area and remove it when we break the scroll area
    if [ "$TRAPPING_ENABLED" = "true" ]; then
        trap_on_interrupt
    fi

    # Handle first parameter: alternative progress bar title
    [ -n "$1" ] && PROGRESS_TITLE="$1" || PROGRESS_TITLE="Progress"

    # Handle second parameter : alternative total count
    [ -n "$2" ] && PROGRESS_TOTAL=$2 || PROGRESS_TOTAL=100

    lines=$(tput lines)
    CURRENT_NR_LINES=$lines
    lines=$((lines - 1))
    # Scroll down a bit to avoid visual glitch when the screen area shrinks by one row
    echo -en "\n"

    # Save cursor
    echo -en "$CODE_SAVE_CURSOR"
    # Set scroll region (this will place the cursor in the top left)
    echo -en "\033[0;${lines}r"

    # Restore cursor but ensure its inside the scrolling area
    echo -en "$CODE_RESTORE_CURSOR"
    echo -en "$CODE_CURSOR_IN_SCROLL_AREA"

    # Store start timestamp to compute ETA
    if [ "$ETA_ENABLED" = "true" ]; then
        PROGRESS_START=$(date +%s)
    fi

    # Start empty progress bar
    draw_progress_bar 0
}

function create_progress_bar() {
    local _short='N:tp:'
    local _longs='trap,eta,size:,precision:'
    local _parsed
    _parsed=$(getopt --options=$_short --longoptions=$_longs --name "$0" -- "$@")
    eval set -- "$_parsed"
    _load_variables
    declare -i _num_total_tasks
    while true; do
        case $1 in
        -N | --size) _num_total_tasks=$2 && shift ;;
        -p | --precision) PERCENT_SCALE=$2 && shift ;;
        -t | --eta) ETA_ENABLED=true ;;
        --trap) TRAPPING_ENABLED=true ;;
        --)
            shift && break # break the while loop
            ;;
        esac
        shift
    done
    local _progress_bar_title="$1"
    setup_scroll_area "$_progress_bar_title" "$_num_total_tasks" 1>&2
}

destroy_scroll_area() {
    lines=$(tput lines)
    # Save cursor
    echo -en "$CODE_SAVE_CURSOR" 1>&2
    # Set scroll region (this will place the cursor in the top left)
    echo -en "\033[0;${lines}r" 1>&2

    # Restore cursor but ensure its inside the scrolling area
    echo -en "$CODE_RESTORE_CURSOR" 1>&2
    echo -en "$CODE_CURSOR_IN_SCROLL_AREA" 1>&2

    # We are done so clear the scroll bar
    _clear_progress_bar 1>&2

    # Scroll down a bit to avoid visual glitch when the screen area grows by one row
    echo -en "\n\n" 1>&2

    # Reset title for next usage
    PROGRESS_TITLE=""

    # Once the scroll area is cleared, we want to remove any trap previously set. Otherwise, ctrl+c will exit our shell
    if [ "$TRAP_SET" = "true" ]; then
        trap - EXIT
    fi
}

format_eta() {
    local T=$1
    local D=$((T / 60 / 60 / 24))
    local H=$((T / 60 / 60 % 24))
    local M=$((T / 60 % 60))
    local S=$((T % 60))
    [[ $D -eq 0 && $H -eq 0 && $M -eq 0 && $S -eq 0 ]] && echo "--:--:--" && return
    [ $D -gt 0 ] && printf '%d days, ' $D
    printf 'ETA: %d:%02.f:%02.f' $H $M $S
}

function _float_devide() {
    local x=$1 y=$2 res_var=${3:-'_float_res'} scale=${PERCENT_SCALE:-2} int_scale
    ((int_scale = 10 * 10 ** scale, a = x / y, b = x % y * int_scale / y))
    printf -v "$res_var" "%.${scale}f" "$a.$b"
}

function _percent() {
    local _float_res # _float_res is updated by _float_devide()
    _float_devide "$(($1 * 100))" "$2"
    local res_var=${3:-'_percent_res'}
    printf -v "$res_var" '%s%%' "$_float_res"
}

draw_progress_bar() {
    eta=""
    if [[ "$ETA_ENABLED" = "true" && $1 -gt 0 ]]; then
        if [ "$PROGRESS_BLOCKED" = "true" ]; then
            blocked_duration=$(($(date +%s) - BLOCKED_START))
            PROGRESS_START=$((PROGRESS_START + blocked_duration))
        fi
        running_time=$(($(date +%s) - PROGRESS_START))
        total_time=$((PROGRESS_TOTAL * running_time / $1))
        eta=$(format_eta $((total_time - running_time)))
    fi

    # compute percentage as
    _percent "$1" "$PROGRESS_TOTAL" percentage
    extra=$2 # supplying extra message showing in progress bar

    lines=$(tput lines)
    lines=$((lines))

    # Check if the window has been resized. If so, reset the scroll area
    if [ "$lines" -ne "$CURRENT_NR_LINES" ]; then
        setup_scroll_area 1>&2
    fi

    # Save cursor
    echo -en "$CODE_SAVE_CURSOR" 1>&2

    # Move cursor position to last row
    echo -en "\033[${lines};0f" 1>&2

    # Clear progress bar
    tput el

    # Draw progress bar
    PROGRESS_BLOCKED="false"
    print_bar_text "$percentage" "$extra" "$eta" 1>&2

    # Restore cursor position
    echo -en "$CODE_RESTORE_CURSOR" 1>&2
}

block_progress_bar() {
    percentage=$1
    lines=$(tput lines)
    lines=$((lines))
    # Save cursor
    echo -en "$CODE_SAVE_CURSOR" 1>&2

    # Move cursor position to last row
    echo -en "\033[${lines};0f" 1>&2

    # Clear progress bar
    tput el

    # Draw progress bar
    PROGRESS_BLOCKED="true"
    BLOCKED_START=$(date +%s)
    print_bar_text "$percentage" 1>&2

    # Restore cursor position
    echo -en "$CODE_RESTORE_CURSOR" 1>&2
}

clear_progress_bar() {
    lines=$(tput lines)
    lines=$((lines))
    # Save cursor
    echo -en "$CODE_SAVE_CURSOR"

    # Move cursor position to last row
    echo -en "\033[${lines};0f"

    # clear progress bar
    tput el

    # Restore cursor position
    echo -en "$CODE_RESTORE_CURSOR"
}

print_bar_text() {
    local percentage=$1
    local extra=$2
    [ -n "$extra" ] && extra=" ($extra)"
    local eta=$3
    if [ -n "$eta" ]; then
        [ -n "$extra" ] && extra="$extra "
        extra="$extra$eta"
    fi
    local cols
    cols=$(tput cols)
    # hard coded width includes space between fields (3), progress delimiter "[", "]"
    # we intentionally allocated two more columns in case the ETA hour field overflow
    bar_size=$((cols - ${#percentage} - ${#PROGRESS_TITLE} - ${#extra} - 7))

    local color="${COLOR_FG}${COLOR_BG}"
    if [ "$PROGRESS_BLOCKED" = "true" ]; then
        color="${COLOR_FG}${COLOR_BG_BLOCKED}"
    fi

    # Prepare progress bar
    local _n_percent_minor_digits=$((PERCENT_SCALE + 2))          # decimal mark, digits + "%"
    local _progress=${percentage[*]::-${_n_percent_minor_digits}} #* quote does not allow after '::'
    complete_size=$(((bar_size * _progress) / 100))
    remainder_size=$((bar_size - complete_size))
    progress_bar=$(
        echo -ne "["
        echo -en "${color}"
        printf_new "#" $complete_size
        echo -en "${RESTORE_FG}${RESTORE_BG}"
        printf_new "." $remainder_size
        echo -ne "]"
    )

    # Print progress bar
    echo -ne "$PROGRESS_TITLE ${percentage} ${progress_bar} ${extra}" 
}

enable_trapping() {
    TRAPPING_ENABLED="true"
}

trap_on_interrupt() {
    # If this function is called, we setup an interrupt handler to cleanup the progress bar
    TRAP_SET="true"
    trap cleanup_on_interrupt EXIT
}

cleanup_on_interrupt() {
    destroy_scroll_area
    exit
}

printf_new() {
    str=$1
    num=$2
    v=$(printf "%-${num}s" "$str")
    echo -ne "${v// /$str}"
}

# SPDX-License-Identifier: MIT
#
# Copyright (c) 2018--2020 Polle Vanhoof
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
