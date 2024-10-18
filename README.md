# Flutter Runner Script

This script automates the process of building and running Flutter apps for iOS and Android platforms, handling various platform-specific tasks and configurations.

## Features

- Run or build Flutter apps for iOS and Android
- Automatically handle iOS-specific file issues
- Exclude platform-specific dependencies
- Modify specific files before building or running
- Clean up and restore original state after execution
- Support for additional Flutter flags

## Prerequisites

- Flutter SDK installed and in PATH
- `yq` command-line YAML processor installed and in PATH
- For iOS: Xcode and CocoaPods
- For Android: Android SDK

## Installation

To install the `flutter-runner` script as a system-wide command:

1. Ensure you have Flutter and `yq` installed and available in your PATH. The installation script will check for these dependencies.

2. Ensure you're in the directory containing the `flutter-runner` script and the `install.sh` script.

3. Make the installation script executable:
   ```
   chmod +x install.sh
   ```

4. Run the installation script:
   ```
   sudo ./install.sh
   ```

   This script will:
   - Check for the presence of `flutter` and `yq`
   - Install the `flutter-runner` command in `/usr/local/bin`
   - Install the man page (if available) in the appropriate directory

If the installation script detects that `flutter` or `yq` is missing, it will provide instructions on how to install them.

## Usage

After installation, you can use the script from any directory:

```
flutter-runner [-r platform] [-b platform] [-e extra_flags]
```

### Options

- `-r platform`: Run the app on the specified platform (ios or android)
- `-b platform`: Build the app for the specified platform (ios or android)
- `-e extra_flags`: Specify additional flags to pass to the Flutter command

### Examples

1. Run the app on iOS:
   ```
   flutter-runner -r ios
   ```

2. Build the app for Android:
   ```
   flutter-runner -b android
   ```

3. Run the app on Android with additional flags:
   ```
   flutter-runner -r android -e "--flavor production"
   ```

## Configuration

The script relies on the `pubspec.yaml` file for configuration. Add the following sections to your `pubspec.yaml`:

```yaml
ios_ignored_files:
  - path/to/file1
  - path/to/file2

ios_ignored_dependencies:
  dependency_name: ^version

android_ignored_dependencies:
  dependency_name: ^version

ios_files_to_modify:
  path/to/file:
    - "content to comment/uncomment"

android_files_to_modify:
  path/to/file:
    - "content to comment/uncomment"
```

## Documentation

After installation, you can access the full documentation by running:

```
man flutter-runner
```

## Troubleshooting

If you encounter any issues:

1. Ensure all prerequisites (Flutter, yq) are correctly installed and in your PATH
2. Check that your `pubspec.yaml` is correctly configured
3. Run the script with `set -x` at the beginning for verbose output

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

