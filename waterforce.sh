#!/bin/bash

set -e

declare -A FAN_MODES=(
    [0]="balance"
    [1]="custom"
    [2]="default"
    [4]="max"
    [5]="performance"
    [6]="quiet"
    [7]="off"
)

print_fan_modes() {
    for i in $(printf '%s\n' "${!FAN_MODES[@]}" | sort -n); do
        echo "  $i - ${FAN_MODES[$i]}"
    done
}

show_help() {
    echo ""
    echo "Usage: waterforce [COMMAND]"
    echo ""
    echo "Commands:"
    echo "  --help             Display this message"
    echo "  mode <mode_num>    Set the radiator fan mode"
    echo "  speed <speed_rpm>  Set the radiator fan speed in RPM (forces custom mode)"
    echo "  sync               Send CPU temperature in a loop"
    echo "  install <mode_num> Install systemd temperature sync service configured to start in specified fan mode"
    echo ""
    echo "Supported Modes:"

    print_fan_modes

    echo ""
    echo "Examples:"
    echo "  waterforce mode 1"
    echo "  waterforce speed 1500"
    echo "  waterforce sync"
    echo "  waterforce install 6"
}

if [ $# -eq 0 ] || [ "$1" = "--help" ]; then
    show_help
    exit 0
fi

if [ $1 != "install" ]; then
    HWMON_DIR=""

    for dir in /sys/class/hwmon/hwmon*; do
        if [ -f "$dir/name" ] && [ "$(cat "$dir/name")" = "waterforce" ]; then
            HWMON_DIR="$dir"
            break
        fi
    done

    if [ -z "$HWMON_DIR" ]; then
        echo "Error: Gigabyte Waterforce device was not found. Ensure that the driver is loaded"
        exit 1
    fi

    echo "Found Waterforce device at: $HWMON_DIR"
fi

case "$1" in
    mode)
        mode_num="$2"
        
        if [[ "$mode_num" =~ ^[0-7]$ ]]; then
            echo "$mode_num" | sudo tee "$HWMON_DIR/pwm1_enable" > /dev/null
            echo "Radiator fans mode set to $mode_num"
        else
            echo "Error: Invalid mode. Supported modes are:"
            print_fan_modes
            exit 1
        fi
        ;;
    speed)
        speed_num="$2"
        
        if [ -z "$speed_num" ] || ! [[ "$speed_num" =~ ^[0-9]+$ ]]; then
            echo "Error: Fan speed must be a valid number (RPM)."
            exit 1
        fi
        
        if [ "$speed_num" -lt 750 ] || [ "$speed_num" -gt 3200 ]; then
            echo "Error: Fan speed out of bounds. Must be between 750 and 3200 RPM."
            exit 1
        fi

        echo 1 | sudo tee "$HWMON_DIR/pwm1_enable" > /dev/null
        echo "$speed_num" | sudo tee "$HWMON_DIR/fan1_target"
        echo "Radiator fans mode set to 1"
        echo "Radiator fans speed set to: ${speed_num} RPM"
        ;;
    sync)
        echo "Starting CPU Temperature syncing loop..."
        fail_count=0

        while true; do
            cpu_temp=$(sensors | grep -E -i '(Package id 0|Tctl|Core 0)' | head -n 1 | awk -F ':' '{print $2}' | tr -d '+°C ' | cut -d. -f1 || true)
            if [ -z "$cpu_temp" ]; then
                echo "Error: Could not read CPU temperature"
                ((fail_count++))
                sleep 3
                continue
            fi
            
            if [[ "$cpu_temp" =~ ^[0-9]+$ ]]; then
                echo "$cpu_temp" | sudo tee "$HWMON_DIR/temp2_input" > /dev/null
                fail_count=0
            fi

            if [ "$fail_count" -ge 5 ]; then
                echo "Error: Failure threshold reached. Exiting..."
                exit 1
            fi
                
            sleep 3
        done
        ;;
    install)
        mode_num="$2"
        echo "${FAN_NAMES[$mode_num]}"
        if ! [[ "$mode_num" =~ ^[0-7]$ ]] || [ -z "${FAN_MODES[$mode_num]}" ]; then
            echo "Error: You must provide a valid startup fan mode (0-2, 4-7)."
            print_fan_modes
            exit 1
        fi

        script_path="/usr/local/bin/waterforce"
        if [ "$(realpath "$0")" != "$script_path" ]; then
            echo "Copying script to: $script_path..."
            sudo cp "$(realpath "$0")" "$script_path"
            sudo chmod +x "$script_path"
        fi

        echo "Generating systemd service file..."
        cat << EOF | sudo tee /etc/systemd/system/waterforce-temp-sync.service > /dev/null
[Unit]
Description=Gigabyte Waterforce Temperature Sync Daemon
After=multi-user.target

[Service]
Type=simple
Environment="WATERFORCE_MODE=$mode_num"
ExecStartPre=$script_path mode \${WATERFORCE_MODE}
ExecStart=$script_path sync
Restart=always
RestartSec=5
User=root

[Install]
WantedBy=multi-user.target
EOF

        echo "Reloading systemd and enabling TEMP sync service..."
        sudo systemctl daemon-reload
        sudo systemctl enable waterforce-temp-sync.service
        sudo systemctl restart waterforce-temp-sync.service

        echo ""
        echo "Waterforce TEMP sync service installed and started."
        echo "Default boot mode set to: ${FAN_MODES[$mode_num]} ($mode_num)"
        ;;
    *)
        echo "Error: Unknown command '$1'."
        show_help
        exit 1
        ;;
esac
