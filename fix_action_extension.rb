#!/usr/bin/env ruby

require 'xcodeproj'

# Open the project
project_path = 'Snapzify.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# Find the ActionExtension target
extension_target = project.targets.find { |t| t.name == 'ActionExtension' }

if extension_target
  # Fix the product name and bundle identifier
  extension_target.build_configurations.each do |config|
    config.build_settings['PRODUCT_NAME'] = 'ActionExtension'
    config.build_settings['PRODUCT_MODULE_NAME'] = 'ActionExtension'
    config.build_settings['INFOPLIST_FILE'] = 'ActionExtension/Info.plist'
    config.build_settings['CODE_SIGN_ENTITLEMENTS'] = 'ActionExtension/ActionExtension.entitlements'
    config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.snapzify.app.ActionExtension'
    config.build_settings['SWIFT_VERSION'] = '5.0'
    config.build_settings['TARGETED_DEVICE_FAMILY'] = '1,2'
    config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '15.0'
    config.build_settings['DEVELOPMENT_TEAM'] = '$(inherited)'
    config.build_settings['CODE_SIGN_STYLE'] = 'Automatic'
    config.build_settings['SKIP_INSTALL'] = 'YES'
    config.build_settings['LD_RUNPATH_SEARCH_PATHS'] = [
      '$(inherited)',
      '@executable_path/Frameworks',
      '@executable_path/../../Frameworks'
    ]
  end
  
  # Update the product reference name
  if extension_target.product_reference
    extension_target.product_reference.path = 'ActionExtension.appex'
    extension_target.product_reference.name = 'ActionExtension.appex'
  end
  
  # Save the project
  project.save
  
  puts "✅ Fixed ActionExtension target configuration!"
  puts "📦 Product name set to: ActionExtension"
  puts "🔧 Build settings updated"
else
  puts "❌ ActionExtension target not found!"
end