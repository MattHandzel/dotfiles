#!/bin/bash

# Enable debugging if DEBUG is set to 1
DEBUG=0

# Function to log debug messages
log_debug() {
    if [ "$DEBUG" -eq 1 ]; then
        echo "DEBUG: $1"
    fi
}

# Function to validate the format of the MAC-ID map file
validate_map_file() {
    local file="$1"
    while IFS= read -r line; do
        if [[ ! $line =~ ^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}=.+$ ]]; then
            echo "Invalid line in MAC-ID map file: $line"
            echo "Each line should be in the format: XX:XX:XX:XX:XX:XX=Name"
            exit 1
        fi
    done < "$file"
}

# Function to filter found users
filter_found_users() {
    grep -v "User: Unknown"
}

# Default options
MAP_FILE="mac-id-name-map.txt"
FILTER_USERS=0
QUIET_MODE=0

# Help function
print_help() {
    echo "Usage: $0 [options]"
    echo
    echo "Options:"
    echo "  -f FILE       Specify the MAC-ID to name map file (default: $MAP_FILE)"
    echo "  -d            Enable debug mode"
    echo "  -q            Quiet mode, only list found users (no IP/MAC info)"
    echo "  -h            Show this help message and exit"
    echo "  --filter      Filter out unknown users"
}

# Parse command line options
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -f|--file) MAP_FILE="$2"; shift ;;
        -d|--debug) DEBUG=1 ;;
        --filter) FILTER_USERS=1 ;;
        -q|--quiet) QUIET_MODE=1 ;;
        -h|--help) print_help; exit 0 ;;
        *) echo "Unknown parameter passed: $1"; print_help; exit 1 ;;
    esac
    shift
done

# Ensure the MAC-ID to name map file exists
if [[ ! -f "$MAP_FILE" ]]; then
    echo "MAC-ID to name map file ($MAP_FILE) not found!"
    exit 1
fi

# Validate the MAC-ID to name map file format
log_debug "Validating map file format"
validate_map_file "$MAP_FILE"

# Automatically detect the network range
DEFAULT_INTERFACE=$(ip route | grep default | awk '{print $5}')
log_debug "Default interface: $DEFAULT_INTERFACE"

NETWORK_RANGE=$(ip -o -f inet addr show $DEFAULT_INTERFACE | awk '/scope global/ {print $4}')
log_debug "Detected network range: $NETWORK_RANGE"

if [[ -z "$NETWORK_RANGE" ]]; then
    echo "Could not detect network range!"
    exit 1
fi

# Run nmap to detect devices on the network
log_debug "Running nmap scan on $NETWORK_RANGE"
NMAP_OUTPUT=$(sudo nmap -sn $NETWORK_RANGE)

# Initialize variables to store IP and MAC address
CURRENT_IP=""
CURRENT_MAC=""

# Parse nmap output and map MAC addresses to user names
OUTPUT=""
echo "$NMAP_OUTPUT" | while read -r line; do
    if [[ $line == *"Nmap scan report for"* ]]; then
        # Extract IP or hostname and IP
        if [[ $line =~ \(([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)\) ]]; then
            CURRENT_IP=${BASH_REMATCH[1]}
        else
            CURRENT_IP=$(echo $line | awk '{print $NF}')
        fi
        log_debug "Found IP: $CURRENT_IP"
    elif [[ $line == *"MAC Address:"* ]]; then
        CURRENT_MAC=$(echo $line | awk '{print $3}')
        USER=$(grep -i "$CURRENT_MAC" "$MAP_FILE" | awk -F "=" '{print $2}')
        log_debug "Found MAC: $CURRENT_MAC, User: ${USER:-Unknown}"
        if [ "$QUIET_MODE" -eq 1 ]; then
            if [ -n "$USER" ]; then
                echo "$USER"
            fi
        else
            OUTPUT="IP: $CURRENT_IP, MAC: $CURRENT_MAC, User: ${USER:-Unknown}"
            if [ "$FILTER_USERS" -eq 1 ]; then
                if [ "$USER" != "Unknown" ]; then
                    echo "$OUTPUT"
                fi
            else
                echo "$OUTPUT"
            fi
        fi
    fi
done
