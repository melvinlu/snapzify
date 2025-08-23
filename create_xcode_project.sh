#!/bin/bash

# Create Xcode project for Snapzify
echo "Creating Xcode project for Snapzify..."

cd /Users/melvinlu/snapzify

# Create the Xcode project using xcodegen or manual method
cat > Package.swift << 'EOF'
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Snapzify",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "Snapzify", targets: ["Snapzify"])
    ],
    targets: [
        .target(
            name: "Snapzify",
            path: "Snapzify/Snapzify"
        ),
        .testTarget(
            name: "SnapzifyTests",
            dependencies: ["Snapzify"],
            path: "Snapzify/SnapzifyTests"
        )
    ]
)
EOF

echo "✅ Package.swift created"
echo ""
echo "Now follow these steps to open in Xcode:"
echo ""
echo "1. Open Xcode"
echo "2. Choose 'Create New Project' from the welcome screen"
echo "3. Select 'iOS' → 'App' → Next"
echo "4. Configure as follows:"
echo "   - Product Name: Snapzify"
echo "   - Team: Your Apple Developer Team"
echo "   - Organization Identifier: com.yourname"
echo "   - Interface: SwiftUI"
echo "   - Language: Swift"
echo "   - Use Core Data: NO"
echo "   - Include Tests: YES"
echo "5. Save to: /Users/melvinlu/snapzify (select the parent folder)"
echo "6. After project creates, you'll need to:"
echo "   - Delete the default generated files"
echo "   - Drag all the Swift files from Snapzify folder into Xcode"
echo "   - Add Share Extension target (File → New → Target → Share Extension)"
echo "   - Configure App Groups for both targets"