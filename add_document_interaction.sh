#!/bin/bash

# Add DocumentInteractionView.swift to Xcode project

PBXPROJ="Snapzify.xcodeproj/project.pbxproj"

# Generate a unique ID for the file reference
FILE_REF_ID="3D9B1A1F1234567890123461"
BUILD_FILE_ID="3D9B1A1F1234567890123462"

# Check if file already exists in project
if grep -q "DocumentInteractionView.swift" "$PBXPROJ"; then
    echo "DocumentInteractionView.swift already exists in project"
    exit 0
fi

# Create a temporary backup
cp "$PBXPROJ" "$PBXPROJ.backup"

# Add file reference to PBXFileReference section
# Find the line with QueueDocumentView.swift and add after it
sed -i '' "/QueueDocumentView.swift.*PBXFileReference/a\\
		${FILE_REF_ID} /* DocumentInteractionView.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = \"Components/DocumentInteractionView.swift\"; sourceTree = \"<group>\"; };
" "$PBXPROJ"

# Add to PBXBuildFile section (find QueueDocumentView.swift in Sources and add after)
sed -i '' "/QueueDocumentView.swift in Sources/a\\
		${BUILD_FILE_ID} /* DocumentInteractionView.swift in Sources */ = {isa = PBXBuildFile; fileRef = ${FILE_REF_ID} /* DocumentInteractionView.swift */; };
" "$PBXPROJ"

# Add to Views group children list - need to find the Components folder
# First check if Components folder exists
if ! grep -q "Components" "$PBXPROJ"; then
    echo "Creating Components folder in Views group..."
    
    # Generate ID for Components folder
    COMPONENTS_ID="3D9B1A1F1234567890123463"
    
    # Find Views group and add Components folder
    sed -i '' "/3D9B1A171234567890123456.*Views.*= {/,/};/{ 
        /children = (/a\\
				${COMPONENTS_ID} /* Components */,
    }" "$PBXPROJ"
    
    # Add Components group definition after Views group
    sed -i '' "/3D9B1A171234567890123456.*Views.*= {/,/};/a\\
		${COMPONENTS_ID} /* Components */ = {\\
			isa = PBXGroup;\\
			children = (\\
				${FILE_REF_ID} /* DocumentInteractionView.swift */,\\
			);\\
			path = Components;\\
			sourceTree = \"<group>\";\\
		};
" "$PBXPROJ"
else
    # Components folder exists, add file to it
    sed -i '' "/${COMPONENTS_ID}.*Components.*= {/,/};/{ 
        /children = (/a\\
				${FILE_REF_ID} /* DocumentInteractionView.swift */,
    }" "$PBXPROJ"
fi

# Add to build phase
sed -i '' "/QueueDocumentView.swift in Sources/a\\
				${BUILD_FILE_ID} /* DocumentInteractionView.swift in Sources */,
" "$PBXPROJ"

echo "Added DocumentInteractionView.swift to Xcode project"
echo "Please rebuild the project in Xcode"