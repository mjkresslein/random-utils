#!/bin/bash

# Check if both source and target directory paths are provided
if [ -z "$1" ] || [ -z "$2" ]; then
    echo "Error: Both source and target directory paths must be provided."
    echo "Usage: $0 /path/to/source /path/to/target"
    exit 1
fi

# Check if the provided source path is a valid directory
if [ ! -d "$1" ]; then
    echo "Error: The source path '$1' is not a valid directory."
    exit 1
fi

SOURCE_DIR="$1"
TARGET_DIR="$2"

echo "Processing .csv files from: $SOURCE_DIR"
echo "Saving cleaned files to: $TARGET_DIR"

# Create the target directory if it doesn't exist
mkdir -p "$TARGET_DIR"

# Loop through all .csv files recursively, starting from SOURCE_DIR
find "$SOURCE_DIR" -type f -name "*.csv" -print0 | while IFS= read -r -d $'\0' file; do
    echo "Processing file: $file"

    # Construct the output path for the cleaned file
    # This replaces the SOURCE_DIR prefix with the TARGET_DIR prefix
    output_file="${file/$SOURCE_DIR/$TARGET_DIR}"

    # Create the directory structure in the target folder
    # This command creates parent directories as needed
    mkdir -p "$(dirname "$output_file")"

    # Use 'tr' to delete all characters outside of the standard ASCII range.
    # LC_ALL=C is crucial for handling files as raw bytes.
    LC_ALL=C tr -dc '\0-\177' < "$file" > "$output_file"
done

echo "Done. All .csv files have been cleaned and saved to '$TARGET_DIR'."
