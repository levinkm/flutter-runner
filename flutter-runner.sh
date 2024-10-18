#!/bin/bash

set -e  # Exit immediately if a command exits with a non-zero status

# Define temporary folder for iOS-specific ignored files
TEMP_FOLDER="./temp_folder"

# Function to read ignored file paths for iOS from pubspec.yaml
get_ignored_files_for_ios() {
    echo "Reading ignored file paths for iOS from pubspec.yaml..."
    if [ ! -f pubspec.yaml ]; then
        echo "Error: pubspec.yaml not found in the current directory."
        exit 1
    fi
    IGNORED_FILES=$(yq '.ios_ignored_files[]' pubspec.yaml 2>/dev/null)
    if [ -z "$IGNORED_FILES" ]; then
        echo "Warning: No iOS ignored files found in pubspec.yaml. Proceeding without moving files."
        return
    fi
    FILES_TO_MOVE=($IGNORED_FILES)
}

# Function to move files to a temporary folder
move_files() {
    if [ ${#FILES_TO_MOVE[@]} -eq 0 ]; then
        echo "No files to move. Skipping..."
        return
    fi
    echo "Moving iOS problematic files to $TEMP_FOLDER..."
    mkdir -p "$TEMP_FOLDER"
    for file in "${FILES_TO_MOVE[@]}"; do
        if [ -f "$file" ]; then
            mv "$file" "$TEMP_FOLDER/"
            echo "Moved $file to $TEMP_FOLDER"
        else
            echo "Warning: File $file not found, skipping..."
        fi
    done
}

# Function to restore files after the iOS build or app termination
restore_files() {
    if [ ! -d "$TEMP_FOLDER" ]; then
        echo "No files to restore. Skipping..."
        return
    fi
    echo "Restoring files from $TEMP_FOLDER..."
    for file in "${FILES_TO_MOVE[@]}"; do
        local basename=$(basename "$file")
        if [ -f "$TEMP_FOLDER/$basename" ]; then
            mv "$TEMP_FOLDER/$basename" "$(dirname "$file")/"
            echo "Restored $file"
        else
            echo "Warning: File $basename not found in $TEMP_FOLDER, skipping..."
        fi
    done
    rmdir "$TEMP_FOLDER" 2>/dev/null || true
}

# Function to delete symlinks and Podfile.lock
clean_up() {
    echo "Cleaning up..."
    rm -rf ios/.symlinks
    rm -f ios/Podfile.lock
}

# Function to select a device
select_device() {
    local platform=$1
    local devices

    if [ "$platform" == "ios" ]; then
        devices=$(flutter devices | grep -E 'ios|iphone|ipad')
    elif [ "$platform" == "android" ]; then
        devices=$(flutter devices | grep -E 'android')
    else
        echo "Error: Invalid platform specified."
        exit 1
    fi

    if [ -z "$devices" ]; then
        echo "No $platform devices found. Make sure a device is connected or an emulator/simulator is running."
        exit 1
    fi

    echo "Available $platform devices:"
    echo "$devices" | nl -w2 -s') '

    local device_count=$(echo "$devices" | wc -l)
    if [ "$device_count" -eq 1 ]; then
        echo "Only one device available. Automatically selecting it."
        DEVICE_ID=$(echo "$devices" | awk -F '•' '{print $2}' | xargs)
    else
        while true; do
            read -p "Enter the number of the device you want to use: " device_number
            if [[ "$device_number" =~ ^[0-9]+$ ]] && [ "$device_number" -ge 1 ] && [ "$device_number" -le "$device_count" ]; then
                DEVICE_ID=$(echo "$devices" | sed -n "${device_number}p" | awk -F '•' '{print $2}' | xargs)
                break
            else
                echo "Invalid selection. Please enter a number between 1 and $device_count."
            fi
        done
    fi

    echo "Selected device ID: $DEVICE_ID"
}

exclude_dependencies() {
    local platform=$1
    local pubspec_file="pubspec.yaml"
    local temp_pubspec="pubspec_temp.yaml"

    echo "Excluding $platform-specific dependencies..."
    ignored_deps=$(yq '.["'"$platform"'_ignored_dependencies"]' "$pubspec_file" 2>/dev/null)

    if [ "$ignored_deps" == "null" ] || [ -z "$ignored_deps" ]; then
        echo "No ignored dependencies found for $platform. Proceeding without changes."
        return
    fi

    # Read ignored dependencies into an array
    deps_array=()
    while IFS= read -r dep; do
        deps_array+=("$dep")
    done < <(echo "$ignored_deps" | yq -r 'keys | .[]')

    # Show the ignored dependencies
    echo "Ignored dependencies for $platform:"
    for dep in "${deps_array[@]}"; do
        version=$(yq -r ".${platform}_ignored_dependencies[\"$dep\"]" "$pubspec_file")
        echo "  - $dep: $version"
    done

    # Create a new temporary pubspec without the ignored dependencies
    {
        while IFS= read -r line; do
            if echo "$line" | grep -q -E "(${deps_array[*]// /|})"; then
                echo "# Removed dependency: $line"
            else
                echo "$line"
            fi
        done
    } < "$pubspec_file" > "$temp_pubspec"

    mv "$temp_pubspec" "$pubspec_file"
    echo "Dependencies excluded. Updated pubspec.yaml"
}

# Function to restore original pubspec.yaml
restore_pubspec() {
    if [ -f "pubspec.yaml.bak" ]; then
        mv "pubspec.yaml.bak" "pubspec.yaml"
        echo "Restored original pubspec.yaml"
    fi
}

# Modified function to comment/uncomment specific elements in files
modify_files() {
    local platform=$1
    local action=$2  # "comment" or "uncomment"

    echo "Reading $platform files to modify from pubspec.yaml..."
    if [ ! -f pubspec.yaml ]; then
        echo "Error: pubspec.yaml not found in the current directory."
        return 1
    fi

    # Read the files to modify
    FILES_TO_MODIFY=$(yq e ".${platform}_files_to_modify | select(. != null)" pubspec.yaml)
    if [ -z "$FILES_TO_MODIFY" ]; then
        echo "No files to modify found for $platform in pubspec.yaml. Skipping modification."
        return 0
    fi

    # Iterate over each file
    echo "$FILES_TO_MODIFY" | yq e 'to_entries[]' -o json | jq -c '.' | while read -r entry; do
        local file
        file=$(echo "$entry" | jq -r '.key')
        local contents
        contents=$(echo "$entry" | jq -r '.value[]')

        if [ ! -f "$file" ]; then
            echo "Warning: File $file not found, skipping..."
            continue
        fi
        echo "Modifying file: $file"
        
        # Create a temporary file
        local temp_file
        temp_file=$(mktemp)
        cp "$file" "$temp_file"
        
        # Process each content item
        echo "$contents" | while IFS= read -r content; do
            # Remove leading/trailing whitespace and quotes
            content=$(echo "$content" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/^["'"'"']\(.*\)["'"'"']$/\1/')

            # Skip empty lines
            if [ -z "$content" ]; then
                continue
            fi
            
            echo "Processing content: $content"
            
            # Handle multi-line entries
            if [[ "$content" == "|"* ]]; then
                # Extract the multi-line content
                multi_line_content=$(echo "$content" | sed 's/^|//; s/^[[:space:]]*//')
                escaped_content=$(printf '%s\n' "$multi_line_content" | sed 's/[\/&]/\\&/g')
                
                if [ "$action" = "comment" ]; then
                    sed -i.bak "/^[[:space:]]*${escaped_content}/{
                        :a
                        N
                        /);[[:space:]]*$/!ba
                        s/^/\/\/ /
                    }" "$temp_file"
                elif [ "$action" = "uncomment" ]; then
                    sed -i.bak "/^[[:space:]]*\/\/ ${escaped_content}/{
                        :a
                        N
                        /);[[:space:]]*$/!ba
                        s/^\/\/ //
                    }" "$temp_file"
                fi
            else
                escaped_content=$(printf '%s\n' "$content" | sed 's/[\/&]/\\&/g')
                
                if [ "$action" = "comment" ]; then
                    sed -i.bak "s/^[[:space:]]*${escaped_content}/\/\/ &/" "$temp_file"
                elif [ "$action" = "uncomment" ]; then
                    sed -i.bak "s/^[[:space:]]*\/\/ *${escaped_content}/${escaped_content}/" "$temp_file"
                fi
            fi
        done
        
        # Replace the original file with the modified one
        mv "$temp_file" "$file"
    done
    
    # Clean up temporary files
    find . -name "*.bak" -type f -delete
    echo "File modification complete for $platform."
    return 0
}




# Function to handle errors and cleanup
cleanup_and_exit() {
    echo "An error occurred. Cleaning up..."
    restore_files
    restore_pubspec
    modify_files "ios" "uncomment"
    modify_files "android" "uncomment"
    exit 1
}

# Set up trap to call cleanup_and_exit on any error
trap cleanup_and_exit ERR

# Function to restore original files
restore_modified_files() {
    local platform=$1
    echo "Restoring original files for $platform..."
 modify_files "$platform" "uncomment"
}

# Function to handle Android run
run_android() {
    echo "Running app on Android with extra flags: $EXTRA_FLAGS"
    cp pubspec.yaml pubspec.yaml.bak
    exclude_dependencies "android"
    modify_files "android" "comment"
    trap 'restore_pubspec; restore_modified_files android' EXIT
    select_device "android"
    flutter pub get
    flutter run -d "$DEVICE_ID" $EXTRA_FLAGS
}

# Function to handle iOS run
run_ios() {
    echo "Running app on iOS with extra flags: $EXTRA_FLAGS"
    clean_up
    move_files
    modify_files "ios" "comment"
    trap 'restore_files; restore_pubspec; restore_modified_files ios' EXIT

    cp pubspec.yaml pubspec.yaml.bak
    exclude_dependencies "ios"

    select_device "ios"
    flutter pub get
    flutter run -d "$DEVICE_ID" $EXTRA_FLAGS
}

# Function to handle Android build
build_android() {
    echo "Building app for Android with extra flags: $EXTRA_FLAGS"
    cp pubspec.yaml pubspec.yaml.bak
    exclude_dependencies "android"
    modify_files "android" "comment"
    trap 'restore_pubspec; restore_modified_files android' EXIT
    flutter pub get
    flutter build appbundle $EXTRA_FLAGS
}

# Function to handle iOS build
build_ios() {
    echo "Building app for iOS with extra flags: $EXTRA_FLAGS"

    clean_up
    get_ignored_files_for_ios
    move_files
    modify_files "ios" "comment"
    trap 'restore_files; restore_pubspec; restore_modified_files ios' EXIT

    cp pubspec.yaml pubspec.yaml.bak
    exclude_dependencies "ios"

    echo "Running pub upgrade..."
    flutter pub upgrade

    echo "Cleaning and getting packages..."
    flutter clean
    flutter pub get

    echo "Deintegrating and reinstalling pods..."
    (cd ios && pod deintegrate && pod install) || { echo "Error: Pod install failed!"; exit 1; }

    echo "Building IPA..."
    flutter build ipa $EXTRA_FLAGS
}

# Function to display help information
display_help() {
    echo "Usage: $0 [-r <platform>] [-b <platform>] [--no-reverse] [--reverse-only] [additional flutter flags]"
    echo
    echo "Options:"
    echo "  -r <platform>    Run the app on the specified platform (ios or android)"
    echo "  -b <platform>    Build the app for the specified platform (ios or android)"
    echo "  --no-reverse     Do not reverse the changes made to files and pubspec.yaml"
    echo "  --reverse-only   Only reverse changes from a previous run (do not build or run)"
    echo "  -h, --help       Display this help message"
    echo
    echo "Any additional flags provided will be passed directly to the flutter command."
    echo
    echo "Examples:"
    echo "  $0 -r ios"
    echo "  $0 -b android --release"
    echo "  $0 -b ios --no-tree-shake-icons --no-reverse"
    echo "  $0 --reverse-only"
    exit 0
}

# Function to reverse changes
reverse_changes() {
    echo "Reversing changes..."
    restore_files
    restore_pubspec
    modify_files "ios" "uncomment"
    modify_files "android" "uncomment"
    echo "Changes reversed."
}

# Main script logic
main() {
    local ACTION=""
    local PLATFORM=""
    local EXTRA_FLAGS=""
    local NO_REVERSE=false
    local REVERSE_ONLY=false

    # Parse options
    while [[ $# -gt 0 ]]; do
        case $1 in
            -r|--run)
                ACTION="run"
                PLATFORM="$2"
                shift 2
                ;;
            -b|--build)
                ACTION="build"
                PLATFORM="$2"
                shift 2
                ;;
            --no-reverse)
                NO_REVERSE=true
                shift
                ;;
            --reverse-only)
                REVERSE_ONLY=true
                shift
                ;;
            -h|--help)
                display_help
                ;;
            *)
                EXTRA_FLAGS="$EXTRA_FLAGS $1"
                shift
                ;;
        esac
    done

    # Handle reverse-only action
    if $REVERSE_ONLY; then
        reverse_changes
        exit 0
    fi

    # Validate inputs
    if [[ -z "$ACTION" || -z "$PLATFORM" ]]; then
        echo "Error: Both action (-r or -b) and platform (ios or android) must be specified."
        display_help
    fi

    if [[ "$PLATFORM" != "ios" && "$PLATFORM" != "android" ]]; then
        echo "Error: Invalid platform. Use 'ios' or 'android'."
        display_help
    fi

    # Execute the appropriate function
    if [[ "$ACTION" == "run" ]]; then
        if [[ "$PLATFORM" == "ios" ]]; then
            get_ignored_files_for_ios
            run_ios
        else
            run_android
        fi
    elif [[ "$ACTION" == "build" ]]; then
        if [[ "$PLATFORM" == "ios" ]]; then
            get_ignored_files_for_ios
            build_ios
        else
            build_android
        fi
    fi

    # Reverse changes if not disabled
    if ! $NO_REVERSE; then
        reverse_changes
    fi
}

# Call the main function with all provided arguments
main "$@"