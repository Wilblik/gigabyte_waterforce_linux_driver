#!/bin/bash

set -e

show_help() {
    echo ""
    echo "Usage: waterforce [COMMAND]"
    echo ""
    echo "Commands:"
    echo "  --help             Display this message"
    echo "  mode <mode_num>    Set the radiator fan mode (0 - balance, 1 - custom, 2 - default, 4 - max, 5 - performance, 6 - quiet, 7 - off)"
    echo "  speed <speed_rpm>  Set the radiator fan speed in RPM (requires custom mode)"
    echo ""
    echo "Examples:"
    echo "  waterforce mode 1"
    echo "  waterforce speed 1500"
}

if [ $# -eq 0 ] || [ "$1" = "--help" ]; then
    show_help
    exit 0
fi

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

case "$1" in
    mode)
        mode_num="$2"
        
        if [[ "$mode_num" =~ ^[0-7]$ ]]; then
            echo "$mode_num" | sudo tee "$HWMON_DIR/pwm1_enable" > /dev/null
            echo "Radiator fans mode set to $mode_num"
        else
            echo "Error: Invalid mode. Supported modes are:"
            echo "    0 - balance"
            echo "    1 - custom"
            echo "    2 - default"
            echo "    4 - max"
            echo "    5 - performance"
            echo "    6 - quiet"
            echo "    7 - off"
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
    *)
        echo "Error: Unknown command '$1'."
        show_help
        exit 1
        ;;
esac
