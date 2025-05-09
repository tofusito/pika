#!/bin/bash

# Script to add copyright header to Swift files

HEADER_FILE="Source_Headers/header.txt"
FILES=$(find Pika -name "*.swift")

for file in $FILES; do
  if ! grep -q "Copyright © 2023-2024 Manuel Gutiérrez" "$file"; then
    echo "Adding header to $file"
    TEMP_FILE=$(mktemp)
    cat "$HEADER_FILE" > "$TEMP_FILE"
    echo "" >> "$TEMP_FILE"
    echo "" >> "$TEMP_FILE"
    cat "$file" >> "$TEMP_FILE"
    mv "$TEMP_FILE" "$file"
  else
    echo "Header already exists in $file"
  fi
done

echo "Done!" 