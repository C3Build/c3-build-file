#!/bin/sh

mkdir -p "scripts"

echo "Building..."
c3c build --trust=full

if [ $? -ne 0 ]; then
    echo "Build failed"
    exit 1
fi

DEST_PATH="$HOME/c3build"

mkdir -p "$DEST_PATH"
cp "build/c3build" "$DEST_PATH/"

PROFILE_FILE="$HOME/.profile"

if [ ! -f "$PROFILE_FILE" ]; then
    touch "$PROFILE_FILE"
fi

if ! grep -q "PATH.*$DEST_PATH" "$PROFILE_FILE" 2>/dev/null; then
    echo "export PATH=\"\$PATH:$DEST_PATH\"" >> "$PROFILE_FILE"
    echo "Added $DEST_PATH to $PROFILE_FILE"
else
    echo "PATH already contains $DEST_PATH in $PROFILE_FILE"
fi

echo "Installed to $DEST_PATH"

echo "Rebuilding with c3build"
build/c3build install
