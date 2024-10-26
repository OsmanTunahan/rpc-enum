#!/bin/bash

# Author: Osman Tunahan ARIKAN 
# Github: https://github.com/OsmanTunahan

GREEN="\033[1;32m"
RESET="\033[0m"
RED="\033[1;31m"
BLUE="\033[1;34m"
YELLOW="\033[1;33m"
PURPLE="\033[1;35m"
TURQUOISE="\033[1;36m"
GRAY="\033[1;37m"

declare -r TMP_FILE1="/dev/shm/tmp_file1"
declare -r TMP_FILE2="/dev/shm/tmp_file2"
declare -r TMP_FILE3="/dev/shm/tmp_file3"

function handleExit() {
    echo -e "\n${YELLOW}[*]${RESET}${GRAY} Exiting...${RESET}"
    rm -f $TMP_FILE1 $TMP_FILE2 $TMP_FILE3
    tput cnorm
    exit 1
}

function displayHelp() {
    echo -e "\n${YELLOW}[*]${RESET}${GRAY} Usage: rpc-enum${RESET}"
    echo -e "\n\t${PURPLE}e)${RESET}${YELLOW} Enumeration Mode${RESET}"
    echo -e "\t\t${GRAY}DUsers${RED} (Domain Users)${RESET}"
    echo -e "\t\t${GRAY}DUsersInfo${RED} (Domain Users with Info)${RESET}"
    echo -e "\t\t${GRAY}DAUsers${RED} (Domain Admin Users)${RESET}"
    echo -e "\t\t${GRAY}DGroups${RED} (Domain Groups)${RESET}"
    echo -e "\t\t${GRAY}All${RED} (All Modes)${RESET}"
    echo -e "\n\t${PURPLE}i)${RESET}${YELLOW} Host IP Address${RESET}"
    echo -e "\n\t${PURPLE}h)${RESET}${YELLOW} Display this help panel${RESET}"
    exit 1
}

function printTable() {
    local delimiter="${1}"
    local data="$(removeEmptyLines "${2}")"
    
    if [[ -n "${delimiter}" && "$(isEmptyString "${data}")" == 'false' ]]; then
        local table=''
        local line_count=$(wc -l <<< "${data}")

        for (( i = 1; i <= line_count; i++ )); do
            local line=$(sed "${i}q;d" <<< "${data}")
            local column_count=$(awk -F "${delimiter}" '{print NF}' <<< "${line}")

            if [[ $i -eq 1 ]]; then
                table+=$(printf '%s#+' "$(repeatString '#+' "${column_count}")")
            fi
            table+="\n"
            
            for (( j = 1; j <= column_count; j++ )); do
                table+=$(printf '#| %s' "$(cut -d "${delimiter}" -f "${j}" <<< "${line}")")
            done
            table+="#|\n"
            
            if [[ $i -eq 1 || ( $line_count -gt 1 && $i -eq $line_count ) ]]; then
                table+=$(printf '%s#+' "$(repeatString '#+' "${column_count}")")
            fi
        done
        echo -e "${table}" | column -s '#' -t | awk '/^\+/{gsub(" ", "-", $0)}1'
    fi
}

function removeEmptyLines() {
    local content="${1}"
    echo -e "${content}" | sed '/^\s*$/d'
}

function repeatString() {
    local string="${1}"
    local repeat_count="${2}"
    [[ "${string}" != '' && "${repeat_count}" =~ ^[1-9][0-9]*$ ]] && printf "%${repeat_count}s" | tr ' ' "${string}"
}

function isEmptyString() {
    local string="${1}"
    [[ -z "$(trimString "${string}")" ]] && echo 'true' || echo 'false'
}

function trimString() {
    sed 's/^[[:blank:]]*//;s/[[:blank:]]*$//'
}

function extractDomainUsers() {
    echo -e "\n${YELLOW}[*]${RESET}${GRAY} Enumerating Domain Users...${RESET}\n"
    local users=$(rpcclient -U "" "${1}" -c "enumdomusers" -N | grep -oP '\[.*?\]' | grep -v 0x | tr -d '[]')

    echo "Users" > $TMP_FILE1
    for user in $users; do echo "$user" >> $TMP_FILE1; done
    echo -ne "${BLUE}"; printTable ' ' "$(cat $TMP_FILE1)"; echo -ne "${RESET}"
    rm -f $TMP_FILE1
}

function extractDomainAdminUsers() {
    echo -e "\n${YELLOW}[*]${RESET}${GRAY} Enumerating Domain Admin Users...${RESET}\n"
    local group_rid=$(rpcclient -U "" "${1}" -c "enumdomgroups" -N | grep "Domain Admins" | awk 'NF{print $NF}' | grep -oP '\[.*?\]' | tr -d '[]')
    local admin_users=$(rpcclient -U "" "${1}" -c "querygroupmem ${group_rid}" -N | awk '{print $1}' | grep -oP '\[.*?\]' | tr -d '[]')

    echo "DomainAdminUsers" > $TMP_FILE1
    for rid in $admin_users; do
        rpcclient -U "" "${1}" -c "queryuser ${rid}" -N | grep 'User Name' | awk 'NF{print $NF}' >> $TMP_FILE1
    done
    echo -ne "${BLUE}"; printTable ' ' "$(cat $TMP_FILE1)"; echo -ne "${RESET}"
    rm -f $TMP_FILE1
}

function startEnumeration() {
    tput civis
    nmap -p139 --open -T5 -v -n "${HOST_IP}" | grep open > /dev/null 2>&1 && port_status=$?

    if rpcclient -U "" "${HOST_IP}" -c "enumdomusers" -N > /dev/null 2>&1; then
        [[ $port_status == 0 ]] && {
            case "${ENUM_MODE}" in
                DUsers) extractDomainUsers "${HOST_IP}" ;;
                DAUsers) extractDomainAdminUsers "${HOST_IP}" ;;
                *) echo -e "\n${RED}[!] Invalid option${RESET}"; displayHelp ;;
            esac
        } || {
            echo -e "\n${RED}Port 139 is closed on ${HOST_IP}${RESET}"
            tput cnorm
            exit 0
        }
    else
        echo -e "\n${RED}[!] Access Denied${RESET}"
        tput cnorm
        exit 0
    fi
}

if [[ $UID -eq 0 ]]; then
    trap handleExit INT
    declare -i param_count=0
    while getopts ":e:i:h:" arg; do
        case $arg in
            e) ENUM_MODE=$OPTARG; ((param_count++)) ;;
            i) HOST_IP=$OPTARG; ((param_count++)) ;;
            h) displayHelp ;;
        esac
    done

    [[ $param_count -ne 2 ]] && displayHelp || startEnumeration
    tput cnorm
else
    echo -e "\n${RED}[*] Run the program as root${RESET}\n"
fi