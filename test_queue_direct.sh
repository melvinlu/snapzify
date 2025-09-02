#!/bin/bash

# Direct test of queue processing by creating files in app container

# Get the app container path on the simulator
SIMULATOR_ID=$(xcrun simctl list devices | grep "iPhone 16 Pro" | grep -v "unavailable" | awk -F'[()]' '{print $2}' | head -1)

if [ -z "$SIMULATOR_ID" ]; then
    echo "Simulator not found"
    exit 1
fi

# Get main app container
CONTAINER_PATH=$(xcrun simctl get_app_container "$SIMULATOR_ID" "com.snapzify.app" data)

if [ -z "$CONTAINER_PATH" ]; then
    echo "App container not found"
    exit 1
fi

echo "App container path: $CONTAINER_PATH"

# Try to find the app group container path
APP_GROUP_PATH="/Users/melvinlu/Library/Developer/CoreSimulator/Devices/$SIMULATOR_ID/data/Containers/Shared/AppGroup"

# Find any existing app group directories
if [ -d "$APP_GROUP_PATH" ]; then
    echo "Checking for app group containers in: $APP_GROUP_PATH"
    ls -la "$APP_GROUP_PATH" 2>/dev/null
    
    # Find the correct one by checking for our app's identifier in the metadata
    for dir in "$APP_GROUP_PATH"/*; do
        if [ -d "$dir" ]; then
            METADATA_FILE="$dir/.com.apple.mobile_container_metadata.plist"
            if [ -f "$METADATA_FILE" ]; then
                if grep -q "group.com.snapzify.app" "$METADATA_FILE" 2>/dev/null; then
                    echo "Found app group container: $dir"
                    GROUP_CONTAINER="$dir"
                    break
                fi
            fi
        fi
    done
fi

# If we found the group container, use it; otherwise fall back to app container
if [ -n "$GROUP_CONTAINER" ]; then
    TARGET_PATH="$GROUP_CONTAINER"
    echo "Using app group container: $TARGET_PATH"
else
    TARGET_PATH="$CONTAINER_PATH"
    echo "App group not found, using app container: $TARGET_PATH"
fi

# Create QueuedMedia directory
QUEUE_DIR="$TARGET_PATH/QueuedMedia"
mkdir -p "$QUEUE_DIR"

# Create a simple test image using system resources
TEST_IMAGE="/tmp/test_queue_$(date +%s).jpg"

# Create a simple blue image with text
cat > /tmp/create_test_image.swift << 'EOF'
import Cocoa

let size = CGSize(width: 400, height: 300)
let image = NSImage(size: size)
image.lockFocus()

// Fill with blue
NSColor.blue.setFill()
NSRect(origin: .zero, size: size).fill()

// Add some Chinese text
let text = "测试队列"
let attributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 48),
    .foregroundColor: NSColor.white
]
let textSize = text.size(withAttributes: attributes)
let textRect = NSRect(
    x: (size.width - textSize.width) / 2,
    y: (size.height - textSize.height) / 2,
    width: textSize.width,
    height: textSize.height
)
text.draw(in: textRect, withAttributes: attributes)

image.unlockFocus()

// Save as JPEG
if let tiffData = image.tiffRepresentation,
   let bitmap = NSBitmapImageRep(data: tiffData),
   let jpegData = bitmap.representation(using: .jpeg, properties: [:]) {
    try? jpegData.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
}
EOF

swift /tmp/create_test_image.swift "$TEST_IMAGE" 2>/dev/null || {
    # Fallback: create a simple image with ImageMagick if available
    which convert > /dev/null && convert -size 400x300 xc:blue -pointsize 48 -fill white -gravity center -annotate +0+0 "测试" "$TEST_IMAGE" 2>/dev/null || {
        # Final fallback: copy any existing image
        cp /System/Library/Desktop\ Pictures/Solid\ Colors/Blue.png "$TEST_IMAGE" 2>/dev/null || {
            echo "Warning: Could not create test image with Chinese text"
            # Create an empty file as last resort
            touch "$TEST_IMAGE"
        }
    }
}

# Copy image to queue directory
IMAGE_NAME="queued_$(date +%s).jpg"
cp "$TEST_IMAGE" "$QUEUE_DIR/$IMAGE_NAME"

# Create queue metadata
QUEUE_FILE="$TARGET_PATH/mediaQueue.json"
QUEUE_ID=$(uuidgen)
QUEUE_DATE=$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")

cat > "$QUEUE_FILE" << EOF
[
  {
    "id": "$QUEUE_ID",
    "fileName": "$IMAGE_NAME",
    "isVideo": false,
    "queuedAt": "$QUEUE_DATE",
    "source": "test_script"
  }
]
EOF

echo "✅ Queue setup complete!"
echo "Queue file: $QUEUE_FILE"
echo "Image file: $QUEUE_DIR/$IMAGE_NAME"
echo ""
echo "Contents of queue file:"
cat "$QUEUE_FILE"
echo ""
echo "Now terminate and relaunch the app to test queue processing"

# Clean up
rm -f "$TEST_IMAGE" /tmp/create_test_image.swift 2>/dev/null