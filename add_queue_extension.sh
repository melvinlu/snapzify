#!/bin/bash

# Script to add QueueActionExtension to Xcode project

PROJECT_FILE="Snapzify.xcodeproj/project.pbxproj"
TEMP_FILE="${PROJECT_FILE}.temp"

# Backup original project file
cp "$PROJECT_FILE" "${PROJECT_FILE}.backup"

echo "Adding QueueActionExtension to Xcode project..."

# Read the current project file
PROJECT_CONTENT=$(cat "$PROJECT_FILE")

# Generate unique IDs for the new extension
QUEUE_EXT_ID=$(uuidgen | tr -d '-' | cut -c 1-24)
QUEUE_VIEW_ID=$(uuidgen | tr -d '-' | cut -c 1-24)
QUEUE_INFO_ID=$(uuidgen | tr -d '-' | cut -c 1-24)
QUEUE_STORYBOARD_ID=$(uuidgen | tr -d '-' | cut -c 1-24)
QUEUE_BUILD_ID=$(uuidgen | tr -d '-' | cut -c 1-24)
QUEUE_SOURCE_BUILD_ID=$(uuidgen | tr -d '-' | cut -c 1-24)
QUEUE_RESOURCE_BUILD_ID=$(uuidgen | tr -d '-' | cut -c 1-24)
QUEUE_PROXY_ID=$(uuidgen | tr -d '-' | cut -c 1-24)
QUEUE_EMBED_ID=$(uuidgen | tr -d '-' | cut -c 1-24)
QUEUE_GROUP_ID=$(uuidgen | tr -d '-' | cut -c 1-24)
QUEUE_STORYBOARD_REF_ID=$(uuidgen | tr -d '-' | cut -c 1-24)

# Find where to insert the new extension references
# We'll add them after the ActionExtension references

# Add file references in PBXFileReference section
sed -i '' "/ActionExtension.appex.*productType/a\\
		${QUEUE_EXT_ID} /* QueueActionExtension.appex */ = {isa = PBXFileReference; explicitFileType = \"wrapper.app-extension\"; includeInIndex = 0; path = QueueActionExtension.appex; sourceTree = BUILT_PRODUCTS_DIR; };\\
" "$PROJECT_FILE"

sed -i '' "/ActionViewController.swift.*lastKnownFileType/a\\
		${QUEUE_VIEW_ID} /* QueueActionViewController.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = QueueActionViewController.swift; sourceTree = \"<group>\"; };\\
		${QUEUE_INFO_ID} /* Info.plist */ = {isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = \"<group>\"; };\\
		${QUEUE_STORYBOARD_REF_ID} /* MainInterface.storyboard */ = {isa = PBXFileReference; lastKnownFileType = file.storyboard; path = MainInterface.storyboard; sourceTree = \"<group>\"; };\\
" "$PROJECT_FILE"

# Add to PBXBuildFile section
sed -i '' "/ActionViewController.swift in Sources/a\\
		${QUEUE_SOURCE_BUILD_ID} /* QueueActionViewController.swift in Sources */ = {isa = PBXBuildFile; fileRef = ${QUEUE_VIEW_ID} /* QueueActionViewController.swift */; };\\
		${QUEUE_RESOURCE_BUILD_ID} /* MainInterface.storyboard in Resources */ = {isa = PBXBuildFile; fileRef = ${QUEUE_STORYBOARD_REF_ID} /* MainInterface.storyboard */; };\\
" "$PROJECT_FILE"

# Add embed build phase
sed -i '' "/ActionExtension.appex in Embed App Extensions/a\\
		${QUEUE_EMBED_ID} /* QueueActionExtension.appex in Embed App Extensions */ = {isa = PBXBuildFile; fileRef = ${QUEUE_EXT_ID} /* QueueActionExtension.appex */; settings = {ATTRIBUTES = (RemoveHeadersOnCopy, ); }; };\\
" "$PROJECT_FILE"

# Add group in PBXGroup section
sed -i '' "/ActionExtension =/,/};/a\\
		${QUEUE_GROUP_ID} /* QueueActionExtension */ = {\\
			isa = PBXGroup;\\
			children = (\\
				${QUEUE_VIEW_ID} /* QueueActionViewController.swift */,\\
				${QUEUE_STORYBOARD_REF_ID} /* MainInterface.storyboard */,\\
				${QUEUE_INFO_ID} /* Info.plist */,\\
			);\\
			path = QueueActionExtension;\\
			sourceTree = \"<group>\";\\
		};\\
" "$PROJECT_FILE"

# Add to main project children
sed -i '' "/ActionExtension,$/a\\
				${QUEUE_GROUP_ID} /* QueueActionExtension */,\\
" "$PROJECT_FILE"

# Add to products group
sed -i '' "/ActionExtension.appex.*\\/,$/a\\
				${QUEUE_EXT_ID} /* QueueActionExtension.appex */,\\
" "$PROJECT_FILE"

# Add native target
sed -i '' "/End PBXNativeTarget section/i\\
		${QUEUE_BUILD_ID} /* QueueActionExtension */ = {\\
			isa = PBXNativeTarget;\\
			buildConfigurationList = ${QUEUE_BUILD_ID}01 /* Build configuration list for PBXNativeTarget \"QueueActionExtension\" */;\\
			buildPhases = (\\
				${QUEUE_BUILD_ID}02 /* Sources */,\\
				${QUEUE_BUILD_ID}03 /* Frameworks */,\\
				${QUEUE_BUILD_ID}04 /* Resources */,\\
			);\\
			buildRules = (\\
			);\\
			dependencies = (\\
			);\\
			name = QueueActionExtension;\\
			productName = QueueActionExtension;\\
			productReference = ${QUEUE_EXT_ID} /* QueueActionExtension.appex */;\\
			productType = \"com.apple.product-type.app-extension\";\\
		};\\
" "$PROJECT_FILE"

# Add build phases
sed -i '' "/End PBXSourcesBuildPhase section/i\\
		${QUEUE_BUILD_ID}02 /* Sources */ = {\\
			isa = PBXSourcesBuildPhase;\\
			buildActionMask = 2147483647;\\
			files = (\\
				${QUEUE_SOURCE_BUILD_ID} /* QueueActionViewController.swift in Sources */,\\
			);\\
			runOnlyForDeploymentPostprocessing = 0;\\
		};\\
" "$PROJECT_FILE"

sed -i '' "/End PBXFrameworksBuildPhase section/i\\
		${QUEUE_BUILD_ID}03 /* Frameworks */ = {\\
			isa = PBXFrameworksBuildPhase;\\
			buildActionMask = 2147483647;\\
			files = (\\
			);\\
			runOnlyForDeploymentPostprocessing = 0;\\
		};\\
" "$PROJECT_FILE"

sed -i '' "/End PBXResourcesBuildPhase section/i\\
		${QUEUE_BUILD_ID}04 /* Resources */ = {\\
			isa = PBXResourcesBuildPhase;\\
			buildActionMask = 2147483647;\\
			files = (\\
				${QUEUE_RESOURCE_BUILD_ID} /* MainInterface.storyboard in Resources */,\\
			);\\
			runOnlyForDeploymentPostprocessing = 0;\\
		};\\
" "$PROJECT_FILE"

# Add to embed app extensions
sed -i '' "/ActionExtension.appex.*\\/,$/a\\
				${QUEUE_EXT_ID} /* QueueActionExtension.appex */,\\
" "$PROJECT_FILE"

# Add container proxy
sed -i '' "/End PBXContainerItemProxy section/i\\
		${QUEUE_PROXY_ID} /* PBXContainerItemProxy */ = {\\
			isa = PBXContainerItemProxy;\\
			containerPortal = 3D9B1A3D1234567890123456 /* Project object */;\\
			proxyType = 1;\\
			remoteGlobalIDString = ${QUEUE_BUILD_ID};\\
			remoteInfo = QueueActionExtension;\\
		};\\
" "$PROJECT_FILE"

# Add target dependency
sed -i '' "/End PBXTargetDependency section/i\\
		${QUEUE_BUILD_ID}05 /* PBXTargetDependency */ = {\\
			isa = PBXTargetDependency;\\
			target = ${QUEUE_BUILD_ID} /* QueueActionExtension */;\\
			targetProxy = ${QUEUE_PROXY_ID} /* PBXContainerItemProxy */;\\
		};\\
" "$PROJECT_FILE"

# Add to project targets
sed -i '' "/targets = (/,/);/s/);/				${QUEUE_BUILD_ID} \/* QueueActionExtension *\/,\\
			);/" "$PROJECT_FILE"

# Add build configurations
sed -i '' "/End XCBuildConfiguration section/i\\
		${QUEUE_BUILD_ID}06 /* Debug */ = {\\
			isa = XCBuildConfiguration;\\
			buildSettings = {\\
				ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;\\
				CODE_SIGN_STYLE = Automatic;\\
				CURRENT_PROJECT_VERSION = 1;\\
				DEVELOPMENT_TEAM = \"\";\\
				GENERATE_INFOPLIST_FILE = NO;\\
				INFOPLIST_FILE = QueueActionExtension/Info.plist;\\
				INFOPLIST_KEY_CFBundleDisplayName = \"Add to Snapzify Queue\";\\
				INFOPLIST_KEY_NSHumanReadableCopyright = \"\";\\
				IPHONEOS_DEPLOYMENT_TARGET = 16.0;\\
				LD_RUNPATH_SEARCH_PATHS = (\\
					\"\$(inherited)\",\\
					\"@executable_path/Frameworks\",\\
					\"@executable_path/../../Frameworks\",\\
				);\\
				MARKETING_VERSION = 1.0;\\
				PRODUCT_BUNDLE_IDENTIFIER = com.snapzify.app.QueueActionExtension;\\
				PRODUCT_NAME = \"\$(TARGET_NAME)\";\\
				SKIP_INSTALL = YES;\\
				SWIFT_EMIT_LOC_STRINGS = YES;\\
				SWIFT_VERSION = 5.0;\\
				TARGETED_DEVICE_FAMILY = \"1,2\";\\
			};\\
			name = Debug;\\
		};\\
		${QUEUE_BUILD_ID}07 /* Release */ = {\\
			isa = XCBuildConfiguration;\\
			buildSettings = {\\
				ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;\\
				CODE_SIGN_STYLE = Automatic;\\
				CURRENT_PROJECT_VERSION = 1;\\
				DEVELOPMENT_TEAM = \"\";\\
				GENERATE_INFOPLIST_FILE = NO;\\
				INFOPLIST_FILE = QueueActionExtension/Info.plist;\\
				INFOPLIST_KEY_CFBundleDisplayName = \"Add to Snapzify Queue\";\\
				INFOPLIST_KEY_NSHumanReadableCopyright = \"\";\\
				IPHONEOS_DEPLOYMENT_TARGET = 16.0;\\
				LD_RUNPATH_SEARCH_PATHS = (\\
					\"\$(inherited)\",\\
					\"@executable_path/Frameworks\",\\
					\"@executable_path/../../Frameworks\",\\
				);\\
				MARKETING_VERSION = 1.0;\\
				PRODUCT_BUNDLE_IDENTIFIER = com.snapzify.app.QueueActionExtension;\\
				PRODUCT_NAME = \"\$(TARGET_NAME)\";\\
				SKIP_INSTALL = YES;\\
				SWIFT_EMIT_LOC_STRINGS = YES;\\
				SWIFT_VERSION = 5.0;\\
				TARGETED_DEVICE_FAMILY = \"1,2\";\\
			};\\
			name = Release;\\
		};\\
" "$PROJECT_FILE"

sed -i '' "/End XCConfigurationList section/i\\
		${QUEUE_BUILD_ID}01 /* Build configuration list for PBXNativeTarget \"QueueActionExtension\" */ = {\\
			isa = XCConfigurationList;\\
			buildConfigurations = (\\
				${QUEUE_BUILD_ID}06 /* Debug */,\\
				${QUEUE_BUILD_ID}07 /* Release */,\\
			);\\
			defaultConfigurationIsVisible = 0;\\
			defaultConfigurationName = Release;\\
		};\\
" "$PROJECT_FILE"

echo "QueueActionExtension has been added to the Xcode project."
echo "Please open Xcode and verify the extension has been added correctly."
echo "You may need to:"
echo "1. Set the development team for the new extension target"
echo "2. Ensure the bundle identifier is correct (com.snapzify.app.QueueActionExtension)"
echo "3. Build and test the new extension"