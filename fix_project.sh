#!/bin/bash

echo "Fixing Xcode project build issues..."

# Add missing build phases to the project file
cd /Users/melvinlu/snapzify

# Create the corrected project.pbxproj with proper build phases
cat > Snapzify.xcodeproj/project.pbxproj << 'PBXEOF'
// !$*UTF8*$!
{
	archiveVersion = 1;
	classes = {
	};
	objectVersion = 56;
	objects = {

/* Begin PBXBuildFile section */
		A10001 /* SnapzifyApp.swift in Sources */ = {isa = PBXBuildFile; fileRef = A10002; };
		A10003 /* Theme.swift in Sources */ = {isa = PBXBuildFile; fileRef = A10004; };
		A10005 /* DataModels.swift in Sources */ = {isa = PBXBuildFile; fileRef = A10006; };
		A10007 /* ServiceProtocols.swift in Sources */ = {isa = PBXBuildFile; fileRef = A10008; };
		A10009 /* OCRServiceImpl.swift in Sources */ = {isa = PBXBuildFile; fileRef = A10010; };
		A10011 /* ScriptConversionServiceImpl.swift in Sources */ = {isa = PBXBuildFile; fileRef = A10012; };
		A10013 /* SentenceSegmentationServiceImpl.swift in Sources */ = {isa = PBXBuildFile; fileRef = A10014; };
		A10015 /* PinyinServiceImpl.swift in Sources */ = {isa = PBXBuildFile; fileRef = A10016; };
		A10017 /* TranslationServiceOpenAI.swift in Sources */ = {isa = PBXBuildFile; fileRef = A10018; };
		A10019 /* TTSServiceOpenAI.swift in Sources */ = {isa = PBXBuildFile; fileRef = A10020; };
		A10021 /* ConfigServiceImpl.swift in Sources */ = {isa = PBXBuildFile; fileRef = A10022; };
		A10023 /* PlecoLinkServiceImpl.swift in Sources */ = {isa = PBXBuildFile; fileRef = A10024; };
		A10025 /* HomeView.swift in Sources */ = {isa = PBXBuildFile; fileRef = A10026; };
		A10027 /* DocumentView.swift in Sources */ = {isa = PBXBuildFile; fileRef = A10028; };
		A10029 /* SentenceRowView.swift in Sources */ = {isa = PBXBuildFile; fileRef = A10030; };
		A10031 /* SettingsView.swift in Sources */ = {isa = PBXBuildFile; fileRef = A10032; };
		A10033 /* HomeViewModel.swift in Sources */ = {isa = PBXBuildFile; fileRef = A10034; };
		A10035 /* DocumentViewModel.swift in Sources */ = {isa = PBXBuildFile; fileRef = A10036; };
		A10037 /* SentenceViewModel.swift in Sources */ = {isa = PBXBuildFile; fileRef = A10038; };
		A10039 /* SettingsViewModel.swift in Sources */ = {isa = PBXBuildFile; fileRef = A10040; };
		A10041 /* SnapzifyConfig.json in Resources */ = {isa = PBXBuildFile; fileRef = A10042; };
		A10043 /* ShareViewController.swift in Sources */ = {isa = PBXBuildFile; fileRef = A10044; };
/* End PBXBuildFile section */

/* Begin PBXFileReference section */
		A10001 /* Snapzify.app */ = {isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = Snapzify.app; sourceTree = BUILT_PRODUCTS_DIR; };
		A10002 /* SnapzifyApp.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = SnapzifyApp.swift; sourceTree = "<group>"; };
		A10004 /* Theme.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = Theme.swift; sourceTree = "<group>"; };
		A10006 /* DataModels.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = DataModels.swift; sourceTree = "<group>"; };
		A10008 /* ServiceProtocols.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = ServiceProtocols.swift; sourceTree = "<group>"; };
		A10010 /* OCRServiceImpl.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = OCRServiceImpl.swift; sourceTree = "<group>"; };
		A10012 /* ScriptConversionServiceImpl.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = ScriptConversionServiceImpl.swift; sourceTree = "<group>"; };
		A10014 /* SentenceSegmentationServiceImpl.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = SentenceSegmentationServiceImpl.swift; sourceTree = "<group>"; };
		A10016 /* PinyinServiceImpl.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = PinyinServiceImpl.swift; sourceTree = "<group>"; };
		A10018 /* TranslationServiceOpenAI.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = TranslationServiceOpenAI.swift; sourceTree = "<group>"; };
		A10020 /* TTSServiceOpenAI.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = TTSServiceOpenAI.swift; sourceTree = "<group>"; };
		A10022 /* ConfigServiceImpl.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = ConfigServiceImpl.swift; sourceTree = "<group>"; };
		A10024 /* PlecoLinkServiceImpl.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = PlecoLinkServiceImpl.swift; sourceTree = "<group>"; };
		A10026 /* HomeView.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = HomeView.swift; sourceTree = "<group>"; };
		A10028 /* DocumentView.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = DocumentView.swift; sourceTree = "<group>"; };
		A10030 /* SentenceRowView.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = SentenceRowView.swift; sourceTree = "<group>"; };
		A10032 /* SettingsView.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = SettingsView.swift; sourceTree = "<group>"; };
		A10034 /* HomeViewModel.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = HomeViewModel.swift; sourceTree = "<group>"; };
		A10036 /* DocumentViewModel.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = DocumentViewModel.swift; sourceTree = "<group>"; };
		A10038 /* SentenceViewModel.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = SentenceViewModel.swift; sourceTree = "<group>"; };
		A10040 /* SettingsViewModel.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = SettingsViewModel.swift; sourceTree = "<group>"; };
		A10042 /* SnapzifyConfig.json */ = {isa = PBXFileReference; lastKnownFileType = text.json; path = SnapzifyConfig.json; sourceTree = "<group>"; };
		A10044 /* ShareViewController.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = ShareViewController.swift; sourceTree = "<group>"; };
		A10045 /* ShareExtension.appex */ = {isa = PBXFileReference; explicitFileType = "wrapper.app-extension"; includeInIndex = 0; path = ShareExtension.appex; sourceTree = BUILT_PRODUCTS_DIR; };
		A10046 /* Info.plist */ = {isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = "<group>"; };
		A10047 /* Snapzify.entitlements */ = {isa = PBXFileReference; lastKnownFileType = text.plist.entitlements; path = Snapzify.entitlements; sourceTree = "<group>"; };
		A10048 /* ShareExtension-Info.plist */ = {isa = PBXFileReference; lastKnownFileType = text.plist.xml; name = "Info.plist"; path = "ShareExtension/Info.plist"; sourceTree = SOURCE_ROOT; };
		A10049 /* ShareExtension.entitlements */ = {isa = PBXFileReference; lastKnownFileType = text.plist.entitlements; path = ShareExtension.entitlements; sourceTree = "<group>"; };
/* End PBXFileReference section */

/* Begin PBXFrameworksBuildPhase section */
		A10050 /* Frameworks */ = {
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
		A10051 /* Frameworks */ = {
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
		A10052 = {
			isa = PBXGroup;
			children = (
				A10053 /* Snapzify */,
				A10054 /* Products */,
			);
			sourceTree = "<group>";
		};
		A10053 /* Snapzify */ = {
			isa = PBXGroup;
			children = (
				A10055 /* Snapzify */,
				A10056 /* ShareExtension */,
			);
			path = Snapzify;
			sourceTree = "<group>";
		};
		A10054 /* Products */ = {
			isa = PBXGroup;
			children = (
				A10001 /* Snapzify.app */,
				A10045 /* ShareExtension.appex */,
			);
			name = Products;
			sourceTree = "<group>";
		};
		A10055 /* Snapzify */ = {
			isa = PBXGroup;
			children = (
				A10002 /* SnapzifyApp.swift */,
				A10057 /* Views */,
				A10058 /* ViewModels */,
				A10059 /* Models */,
				A10060 /* Services */,
				A10061 /* Utils */,
				A10062 /* Resources */,
				A10046 /* Info.plist */,
				A10047 /* Snapzify.entitlements */,
			);
			path = Snapzify;
			sourceTree = "<group>";
		};
		A10056 /* ShareExtension */ = {
			isa = PBXGroup;
			children = (
				A10044 /* ShareViewController.swift */,
				A10048 /* Info.plist */,
				A10049 /* ShareExtension.entitlements */,
			);
			path = ShareExtension;
			sourceTree = "<group>";
		};
		A10057 /* Views */ = {
			isa = PBXGroup;
			children = (
				A10026 /* HomeView.swift */,
				A10028 /* DocumentView.swift */,
				A10030 /* SentenceRowView.swift */,
				A10032 /* SettingsView.swift */,
			);
			path = Views;
			sourceTree = "<group>";
		};
		A10058 /* ViewModels */ = {
			isa = PBXGroup;
			children = (
				A10034 /* HomeViewModel.swift */,
				A10036 /* DocumentViewModel.swift */,
				A10038 /* SentenceViewModel.swift */,
				A10040 /* SettingsViewModel.swift */,
			);
			path = ViewModels;
			sourceTree = "<group>";
		};
		A10059 /* Models */ = {
			isa = PBXGroup;
			children = (
				A10006 /* DataModels.swift */,
			);
			path = Models;
			sourceTree = "<group>";
		};
		A10060 /* Services */ = {
			isa = PBXGroup;
			children = (
				A10008 /* ServiceProtocols.swift */,
				A10010 /* OCRServiceImpl.swift */,
				A10012 /* ScriptConversionServiceImpl.swift */,
				A10014 /* SentenceSegmentationServiceImpl.swift */,
				A10016 /* PinyinServiceImpl.swift */,
				A10018 /* TranslationServiceOpenAI.swift */,
				A10020 /* TTSServiceOpenAI.swift */,
				A10022 /* ConfigServiceImpl.swift */,
				A10024 /* PlecoLinkServiceImpl.swift */,
			);
			path = Services;
			sourceTree = "<group>";
		};
		A10061 /* Utils */ = {
			isa = PBXGroup;
			children = (
				A10004 /* Theme.swift */,
			);
			path = Utils;
			sourceTree = "<group>";
		};
		A10062 /* Resources */ = {
			isa = PBXGroup;
			children = (
				A10042 /* SnapzifyConfig.json */,
			);
			path = Resources;
			sourceTree = "<group>";
		};
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
		A10063 /* Snapzify */ = {
			isa = PBXNativeTarget;
			buildConfigurationList = A10064;
			buildPhases = (
				A10065 /* Sources */,
				A10050 /* Frameworks */,
				A10066 /* Resources */,
			);
			buildRules = (
			);
			dependencies = (
			);
			name = Snapzify;
			productName = Snapzify;
			productReference = A10001;
			productType = "com.apple.product-type.application";
		};
		A10067 /* ShareExtension */ = {
			isa = PBXNativeTarget;
			buildConfigurationList = A10068;
			buildPhases = (
				A10069 /* Sources */,
				A10051 /* Frameworks */,
				A10070 /* Resources */,
			);
			buildRules = (
			);
			dependencies = (
			);
			name = ShareExtension;
			productName = ShareExtension;
			productReference = A10045;
			productType = "com.apple.product-type.app-extension";
		};
/* End PBXNativeTarget section */

/* Begin PBXProject section */
		A10071 /* Project object */ = {
			isa = PBXProject;
			attributes = {
				BuildIndependentTargetsInParallel = 1;
				LastSwiftUpdateCheck = 1500;
				LastUpgradeCheck = 1500;
			};
			buildConfigurationList = A10072;
			compatibilityVersion = "Xcode 14.0";
			developmentRegion = en;
			hasScannedForEncodings = 0;
			knownRegions = (
				en,
			);
			mainGroup = A10052;
			productRefGroup = A10054;
			projectDirPath = "";
			projectRoot = "";
			targets = (
				A10063 /* Snapzify */,
				A10067 /* ShareExtension */,
			);
		};
/* End PBXProject section */

/* Begin PBXResourcesBuildPhase section */
		A10066 /* Resources */ = {
			isa = PBXResourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
				A10041 /* SnapzifyConfig.json in Resources */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
		A10070 /* Resources */ = {
			isa = PBXResourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
/* End PBXResourcesBuildPhase section */

/* Begin PBXSourcesBuildPhase section */
		A10065 /* Sources */ = {
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
				A10001 /* SnapzifyApp.swift in Sources */,
				A10003 /* Theme.swift in Sources */,
				A10005 /* DataModels.swift in Sources */,
				A10007 /* ServiceProtocols.swift in Sources */,
				A10009 /* OCRServiceImpl.swift in Sources */,
				A10011 /* ScriptConversionServiceImpl.swift in Sources */,
				A10013 /* SentenceSegmentationServiceImpl.swift in Sources */,
				A10015 /* PinyinServiceImpl.swift in Sources */,
				A10017 /* TranslationServiceOpenAI.swift in Sources */,
				A10019 /* TTSServiceOpenAI.swift in Sources */,
				A10021 /* ConfigServiceImpl.swift in Sources */,
				A10023 /* PlecoLinkServiceImpl.swift in Sources */,
				A10025 /* HomeView.swift in Sources */,
				A10027 /* DocumentView.swift in Sources */,
				A10029 /* SentenceRowView.swift in Sources */,
				A10031 /* SettingsView.swift in Sources */,
				A10033 /* HomeViewModel.swift in Sources */,
				A10035 /* DocumentViewModel.swift in Sources */,
				A10037 /* SentenceViewModel.swift in Sources */,
				A10039 /* SettingsViewModel.swift in Sources */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
		A10069 /* Sources */ = {
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
				A10043 /* ShareViewController.swift in Sources */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
/* End PBXSourcesBuildPhase section */

/* Begin XCBuildConfiguration section */
		A10073 /* Debug */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				ALWAYS_SEARCH_USER_PATHS = NO;
				CLANG_ANALYZER_NONNULL = YES;
				CLANG_ANALYZER_NUMBER_OBJECT_CONVERSION = YES_AGGRESSIVE;
				CLANG_CXX_LANGUAGE_STANDARD = "gnu++20";
				CLANG_ENABLE_MODULES = YES;
				CLANG_ENABLE_OBJC_ARC = YES;
				CLANG_ENABLE_OBJC_WEAK = YES;
				CLANG_WARN_BLOCK_CAPTURE_AUTORELEASING = YES;
				CLANG_WARN_BOOL_CONVERSION = YES;
				CLANG_WARN_COMMA = YES;
				CLANG_WARN_CONSTANT_CONVERSION = YES;
				CLANG_WARN_DEPRECATED_OBJC_IMPLEMENTATIONS = YES;
				CLANG_WARN_DIRECT_OBJC_ISA_USAGE = YES_ERROR;
				CLANG_WARN_DOCUMENTATION_COMMENTS = YES;
				CLANG_WARN_EMPTY_BODY = YES;
				CLANG_WARN_ENUM_CONVERSION = YES;
				CLANG_WARN_INFINITE_RECURSION = YES;
				CLANG_WARN_INT_CONVERSION = YES;
				CLANG_WARN_NON_LITERAL_NULL_CONVERSION = YES;
				CLANG_WARN_OBJC_IMPLICIT_RETAIN_SELF = YES;
				CLANG_WARN_OBJC_LITERAL_CONVERSION = YES;
				CLANG_WARN_OBJC_ROOT_CLASS = YES_ERROR;
				CLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER = YES;
				CLANG_WARN_RANGE_LOOP_ANALYSIS = YES;
				CLANG_WARN_STRICT_PROTOTYPES = YES;
				CLANG_WARN_SUSPICIOUS_MOVE = YES;
				CLANG_WARN_UNGUARDED_AVAILABILITY = YES_AGGRESSIVE;
				CLANG_WARN_UNREACHABLE_CODE = YES;
				CLANG_WARN__DUPLICATE_METHOD_MATCH = YES;
				COPY_PHASE_STRIP = NO;
				DEBUG_INFORMATION_FORMAT = dwarf;
				ENABLE_STRICT_OBJC_MSGSEND = YES;
				ENABLE_TESTABILITY = YES;
				GCC_C_LANGUAGE_STANDARD = gnu11;
				GCC_DYNAMIC_NO_PIC = NO;
				GCC_NO_COMMON_BLOCKS = YES;
				GCC_OPTIMIZATION_LEVEL = 0;
				GCC_PREPROCESSOR_DEFINITIONS = (
					"DEBUG=1",
					"$(inherited)",
				);
				GCC_WARN_64_TO_32_BIT_CONVERSION = YES;
				GCC_WARN_ABOUT_RETURN_TYPE = YES_ERROR;
				GCC_WARN_UNDECLARED_SELECTOR = YES;
				GCC_WARN_UNINITIALIZED_AUTOS = YES_AGGRESSIVE;
				GCC_WARN_UNUSED_FUNCTION = YES;
				GCC_WARN_UNUSED_VARIABLE = YES;
				IPHONEOS_DEPLOYMENT_TARGET = 17.0;
				MTL_ENABLE_DEBUG_INFO = INCLUDE_SOURCE;
				MTL_FAST_MATH = YES;
				ONLY_ACTIVE_ARCH = YES;
				SDKROOT = iphoneos;
				SWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;
				SWIFT_OPTIMIZATION_LEVEL = "-Onone";
			};
			name = Debug;
		};
		A10074 /* Release */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				ALWAYS_SEARCH_USER_PATHS = NO;
				CLANG_ANALYZER_NONNULL = YES;
				CLANG_ANALYZER_NUMBER_OBJECT_CONVERSION = YES_AGGRESSIVE;
				CLANG_CXX_LANGUAGE_STANDARD = "gnu++20";
				CLANG_ENABLE_MODULES = YES;
				CLANG_ENABLE_OBJC_ARC = YES;
				CLANG_ENABLE_OBJC_WEAK = YES;
				CLANG_WARN_BLOCK_CAPTURE_AUTORELEASING = YES;
				CLANG_WARN_BOOL_CONVERSION = YES;
				CLANG_WARN_COMMA = YES;
				CLANG_WARN_CONSTANT_CONVERSION = YES;
				CLANG_WARN_DEPRECATED_OBJC_IMPLEMENTATIONS = YES;
				CLANG_WARN_DIRECT_OBJC_ISA_USAGE = YES_ERROR;
				CLANG_WARN_DOCUMENTATION_COMMENTS = YES;
				CLANG_WARN_EMPTY_BODY = YES;
				CLANG_WARN_ENUM_CONVERSION = YES;
				CLANG_WARN_INFINITE_RECURSION = YES;
				CLANG_WARN_INT_CONVERSION = YES;
				CLANG_WARN_NON_LITERAL_NULL_CONVERSION = YES;
				CLANG_WARN_OBJC_IMPLICIT_RETAIN_SELF = YES;
				CLANG_WARN_OBJC_LITERAL_CONVERSION = YES;
				CLANG_WARN_OBJC_ROOT_CLASS = YES_ERROR;
				CLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER = YES;
				CLANG_WARN_RANGE_LOOP_ANALYSIS = YES;
				CLANG_WARN_STRICT_PROTOTYPES = YES;
				CLANG_WARN_SUSPICIOUS_MOVE = YES;
				CLANG_WARN_UNGUARDED_AVAILABILITY = YES_AGGRESSIVE;
				CLANG_WARN_UNREACHABLE_CODE = YES;
				CLANG_WARN__DUPLICATE_METHOD_MATCH = YES;
				COPY_PHASE_STRIP = NO;
				DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";
				ENABLE_NS_ASSERTIONS = NO;
				ENABLE_STRICT_OBJC_MSGSEND = YES;
				GCC_C_LANGUAGE_STANDARD = gnu11;
				GCC_NO_COMMON_BLOCKS = YES;
				GCC_WARN_64_TO_32_BIT_CONVERSION = YES;
				GCC_WARN_ABOUT_RETURN_TYPE = YES_ERROR;
				GCC_WARN_UNDECLARED_SELECTOR = YES;
				GCC_WARN_UNINITIALIZED_AUTOS = YES_AGGRESSIVE;
				GCC_WARN_UNUSED_FUNCTION = YES;
				GCC_WARN_UNUSED_VARIABLE = YES;
				IPHONEOS_DEPLOYMENT_TARGET = 17.0;
				MTL_ENABLE_DEBUG_INFO = NO;
				MTL_FAST_MATH = YES;
				SDKROOT = iphoneos;
				SWIFT_COMPILATION_MODE = wholemodule;
				SWIFT_OPTIMIZATION_LEVEL = "-O";
				VALIDATE_PRODUCT = YES;
			};
			name = Release;
		};
		A10075 /* Debug */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
				CODE_SIGN_ENTITLEMENTS = Snapzify/Snapzify.entitlements;
				CODE_SIGN_STYLE = Automatic;
				CURRENT_PROJECT_VERSION = 1;
				DEVELOPMENT_TEAM = "";
				ENABLE_PREVIEWS = YES;
				GENERATE_INFOPLIST_FILE = NO;
				INFOPLIST_FILE = Snapzify/Info.plist;
				INFOPLIST_KEY_UIApplicationSceneManifest_Generation = YES;
				INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents = YES;
				INFOPLIST_KEY_UILaunchScreen_Generation = YES;
				INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad = "UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight";
				INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone = "UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight";
				IPHONEOS_DEPLOYMENT_TARGET = 17.0;
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/Frameworks",
				);
				MARKETING_VERSION = 1.0;
				PRODUCT_BUNDLE_IDENTIFIER = com.snapzify;
				PRODUCT_NAME = "$(TARGET_NAME)";
				SWIFT_EMIT_LOC_STRINGS = YES;
				SWIFT_VERSION = 5.0;
				TARGETED_DEVICE_FAMILY = "1,2";
			};
			name = Debug;
		};
		A10076 /* Release */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
				CODE_SIGN_ENTITLEMENTS = Snapzify/Snapzify.entitlements;
				CODE_SIGN_STYLE = Automatic;
				CURRENT_PROJECT_VERSION = 1;
				DEVELOPMENT_TEAM = "";
				ENABLE_PREVIEWS = YES;
				GENERATE_INFOPLIST_FILE = NO;
				INFOPLIST_FILE = Snapzify/Info.plist;
				INFOPLIST_KEY_UIApplicationSceneManifest_Generation = YES;
				INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents = YES;
				INFOPLIST_KEY_UILaunchScreen_Generation = YES;
				INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad = "UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight";
				INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone = "UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight";
				IPHONEOS_DEPLOYMENT_TARGET = 17.0;
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/Frameworks",
				);
				MARKETING_VERSION = 1.0;
				PRODUCT_BUNDLE_IDENTIFIER = com.snapzify;
				PRODUCT_NAME = "$(TARGET_NAME)";
				SWIFT_EMIT_LOC_STRINGS = YES;
				SWIFT_VERSION = 5.0;
				TARGETED_DEVICE_FAMILY = "1,2";
			};
			name = Release;
		};
		A10077 /* Debug */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				CODE_SIGN_ENTITLEMENTS = ShareExtension/ShareExtension.entitlements;
				CODE_SIGN_STYLE = Automatic;
				CURRENT_PROJECT_VERSION = 1;
				DEVELOPMENT_TEAM = "";
				GENERATE_INFOPLIST_FILE = NO;
				INFOPLIST_FILE = ShareExtension/Info.plist;
				INFOPLIST_KEY_CFBundleDisplayName = ShareExtension;
				INFOPLIST_KEY_NSHumanReadableCopyright = "";
				IPHONEOS_DEPLOYMENT_TARGET = 17.0;
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/Frameworks",
					"@executable_path/../../Frameworks",
				);
				MARKETING_VERSION = 1.0;
				PRODUCT_BUNDLE_IDENTIFIER = com.snapzify.ShareExtension;
				PRODUCT_NAME = "$(TARGET_NAME)";
				SKIP_INSTALL = YES;
				SWIFT_EMIT_LOC_STRINGS = YES;
				SWIFT_VERSION = 5.0;
				TARGETED_DEVICE_FAMILY = "1,2";
			};
			name = Debug;
		};
		A10078 /* Release */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				CODE_SIGN_ENTITLEMENTS = ShareExtension/ShareExtension.entitlements;
				CODE_SIGN_STYLE = Automatic;
				CURRENT_PROJECT_VERSION = 1;
				DEVELOPMENT_TEAM = "";
				GENERATE_INFOPLIST_FILE = NO;
				INFOPLIST_FILE = ShareExtension/Info.plist;
				INFOPLIST_KEY_CFBundleDisplayName = ShareExtension;
				INFOPLIST_KEY_NSHumanReadableCopyright = "";
				IPHONEOS_DEPLOYMENT_TARGET = 17.0;
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/Frameworks",
					"@executable_path/../../Frameworks",
				);
				MARKETING_VERSION = 1.0;
				PRODUCT_BUNDLE_IDENTIFIER = com.snapzify.ShareExtension;
				PRODUCT_NAME = "$(TARGET_NAME)";
				SKIP_INSTALL = YES;
				SWIFT_EMIT_LOC_STRINGS = YES;
				SWIFT_VERSION = 5.0;
				TARGETED_DEVICE_FAMILY = "1,2";
			};
			name = Release;
		};
/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
		A10064 /* Build configuration list for PBXNativeTarget "Snapzify" */ = {
			isa = XCConfigurationList;
			buildConfigurations = (
				A10075 /* Debug */,
				A10076 /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		};
		A10068 /* Build configuration list for PBXNativeTarget "ShareExtension" */ = {
			isa = XCConfigurationList;
			buildConfigurations = (
				A10077 /* Debug */,
				A10078 /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		};
		A10072 /* Build configuration list for PBXProject "Snapzify" */ = {
			isa = XCConfigurationList;
			buildConfigurations = (
				A10073 /* Debug */,
				A10074 /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		};
/* End XCConfigurationList section */
	};
	rootObject = A10071 /* Project object */;
}
PBXEOF

echo "✅ Fixed project.pbxproj with proper build phases"
echo "✅ Now try opening the project again in Xcode"