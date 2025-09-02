#!/bin/bash

# Create a test image and simulate queueing it

# Get the app group container path on the simulator
APP_GROUP_ID="group.com.snapzify.app"
SIMULATOR_ID=$(xcrun simctl list devices | grep "iPhone 16 Pro" | grep -v "unavailable" | awk -F'[()]' '{print $2}' | head -1)

if [ -z "$SIMULATOR_ID" ]; then
    echo "Simulator not found"
    exit 1
fi

# Get the app group container path
CONTAINER_PATH=$(xcrun simctl get_app_container "$SIMULATOR_ID" "$APP_GROUP_ID" data 2>/dev/null)

if [ -z "$CONTAINER_PATH" ]; then
    echo "App group container not found, creating test queue in main app container"
    # Get main app container
    CONTAINER_PATH=$(xcrun simctl get_app_container "$SIMULATOR_ID" "com.snapzify.app" data)
    if [ -z "$CONTAINER_PATH" ]; then
        echo "App container not found"
        exit 1
    fi
fi

echo "Container path: $CONTAINER_PATH"

# Create QueuedMedia directory
QUEUE_DIR="$CONTAINER_PATH/Shared/AppGroup/QueuedMedia"
mkdir -p "$QUEUE_DIR"

# Create a simple test image
TEST_IMAGE="/tmp/test_queue_image.jpg"
# Use sips to create a simple test image
echo "Creating test image..."
# Create a simple solid color image using ImageMagick or sips
sips -z 100 100 /System/Library/Desktop\ Pictures/Solid\ Colors/Blue.png --out "$TEST_IMAGE" 2>/dev/null || {
    # Fallback: copy any system image
    cp /System/Library/Desktop\ Pictures/*.heic "$TEST_IMAGE" 2>/dev/null || {
        echo "Could not create test image"
        exit 1
    }
}

# Copy image to queue directory
IMAGE_NAME="test_$(date +%s).jpg"
cp "$TEST_IMAGE" "$QUEUE_DIR/$IMAGE_NAME"

# Create queue metadata
QUEUE_FILE="$CONTAINER_PATH/Shared/AppGroup/mediaQueue.json"
cat > "$QUEUE_FILE" << EOF
[
  {
    "id": "$(uuidgen)",
    "fileName": "$IMAGE_NAME",
    "isVideo": false,
    "queuedAt": "$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")",
    "source": "test_script"
  }
]
EOF

echo "Queue file created at: $QUEUE_FILE"
echo "Image saved as: $QUEUE_DIR/$IMAGE_NAME"
echo "Now relaunch the app to process the queue"