#!/bin/bash

echo "📁 Adding Swift files to Snapzify project..."

# Copy all Swift files to the main Snapzify folder for easy adding
echo "Copying Swift files..."

# Copy all the implementation files
cp Snapzify/Snapzify/Utils/Theme.swift Snapzify/
cp Snapzify/Snapzify/Models/DataModels.swift Snapzify/
cp Snapzify/Snapzify/Services/*.swift Snapzify/
cp Snapzify/Snapzify/Views/*.swift Snapzify/
cp Snapzify/Snapzify/ViewModels/*.swift Snapzify/
cp Snapzify/Snapzify/Resources/SnapzifyConfig.json Snapzify/

echo "✅ Files copied to Snapzify/ folder"
echo ""
echo "📋 NEXT STEPS IN XCODE:"
echo "======================"
echo "1. The project should now be open in Xcode"
echo "2. In the project navigator, right-click on 'Snapzify' folder"
echo "3. Choose 'Add Files to Snapzify'"
echo "4. Select ALL .swift files from the Snapzify folder:"
echo "   - Theme.swift"
echo "   - DataModels.swift" 
echo "   - All Service files"
echo "   - All View files"
echo "   - All ViewModel files"
echo "5. Also add SnapzifyConfig.json as a resource"
echo "6. Make sure to select 'Copy items if needed'"
echo "7. Build the project (⌘B)"
echo ""
echo "🔧 If you get build errors:"
echo "- Check that all files are added to the target"
echo "- Add missing imports if needed"
echo "- Set Development Team in project settings"