#!/bin/bash

echo "🚀 Setting up Snapzify Xcode Project"
echo "======================================"

cd /Users/melvinlu/snapzify

# Create a simple Package.swift for now
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
        )
    ]
)
EOF

echo "✅ Created Package.swift"

# Move all Swift files to a flatter structure temporarily
echo "📁 Organizing files..."

# Create a simple main file structure
mkdir -p Sources/Snapzify
mkdir -p Sources/ShareExtension

# Copy all Swift files to Sources
find Snapzify -name "*.swift" -exec cp {} Sources/Snapzify/ \;
cp Snapzify/ShareExtension/ShareViewController.swift Sources/ShareExtension/

echo "✅ Files organized"

echo ""
echo "📋 NEXT STEPS:"
echo "=============="
echo "1. Open Xcode"
echo "2. Create new project: File → New → Project"
echo "3. Choose iOS → App"
echo "4. Settings:"
echo "   - Product Name: Snapzify"
echo "   - Interface: SwiftUI"
echo "   - Language: Swift"  
echo "   - Use Core Data: NO"
echo "   - Include Tests: YES"
echo "5. Save to: $(pwd) (this folder)"
echo "6. After project creates:"
echo "   - Delete default ContentView.swift and SnapzifyApp.swift"
echo "   - Drag Sources/Snapzify/*.swift into your project"
echo "   - Add Share Extension target: File → New → Target → Share Extension"
echo "   - Add Sources/ShareExtension/ShareViewController.swift to extension"
echo "   - Configure App Groups capability for both targets"
echo ""
echo "🔧 Alternative: Use 'swift package generate-xcodeproj' to create from Package.swift"