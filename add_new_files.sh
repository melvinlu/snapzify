#!/bin/bash

# This script adds the new refactored files to the Xcode project

PROJECT_PATH="Snapzify.xcodeproj/project.pbxproj"

# Function to add a file to the Xcode project
add_file_to_xcode() {
    local file_path=$1
    local file_name=$(basename "$file_path")
    local group_name=$2
    
    echo "Adding $file_name to $group_name..."
    
    # This is a simplified approach - in production you'd use a tool like xcodeproj or pbxproj
    # For now, we'll just list what needs to be added
    echo "  - $file_path"
}

echo "Files that need to be added to the Xcode project:"
echo "================================================"

# Services
echo -e "\nServices Group:"
add_file_to_xcode "Snapzify/Services/MediaStorageService.swift" "Services"
add_file_to_xcode "Snapzify/Services/VideoFrameProcessor.swift" "Services"
add_file_to_xcode "Snapzify/Services/MediaProcessingService.swift" "Services"
add_file_to_xcode "Snapzify/Services/PhotoLibraryService.swift" "Services"
add_file_to_xcode "Snapzify/Services/KeychainService.swift" "Services"

# Utils
echo -e "\nUtils Group:"
add_file_to_xcode "Snapzify/Utils/LRUCache.swift" "Utils"
add_file_to_xcode "Snapzify/Utils/ErrorHandling.swift" "Utils"
add_file_to_xcode "Snapzify/Utils/PaginatedDocumentLoader.swift" "Utils"
add_file_to_xcode "Snapzify/Utils/ConcurrentProcessing.swift" "Utils"

# Constants
echo -e "\nConstants Group:"
add_file_to_xcode "Snapzify/Constants/Constants.swift" "Constants"

# Views/Components
echo -e "\nViews/Components Group:"
add_file_to_xcode "Snapzify/Views/Components/SharedPopupComponents.swift" "Views/Components"
add_file_to_xcode "Snapzify/Views/Components/MediaNavigationBar.swift" "Views/Components"
add_file_to_xcode "Snapzify/Views/Components/BaseMediaDocumentView.swift" "Views/Components"

# Protocols
echo -e "\nProtocols Group:"
add_file_to_xcode "Snapzify/Protocols/ServiceProtocols.swift" "Protocols"

# DependencyInjection
echo -e "\nDependencyInjection Group:"
add_file_to_xcode "Snapzify/DependencyInjection/DependencyContainer.swift" "DependencyInjection"

# Tests
echo -e "\nTests Group:"
add_file_to_xcode "SnapzifyTests/TestInfrastructure.swift" "SnapzifyTests"

echo -e "\n================================================"
echo "To add these files to Xcode:"
echo "1. Open Snapzify.xcodeproj in Xcode"
echo "2. Right-click on the appropriate group in the project navigator"
echo "3. Select 'Add Files to Snapzify...'"
echo "4. Navigate to and select the files listed above"
echo "5. Make sure 'Copy items if needed' is unchecked (files are already in place)"
echo "6. Make sure the target membership is set to 'Snapzify' (and 'SnapzifyTests' for test files)"