#!/usr/bin/env ruby

require 'xcodeproj'

# Open the project
project_path = 'Snapzify.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# Check if ActionExtension target already exists
existing_target = project.targets.find { |t| t.name == 'ActionExtension' }
if existing_target
  puts "ActionExtension target already exists. Removing it first..."
  project.targets.delete(existing_target)
end

# Create the ActionExtension target
extension_target = project.new_target(:app_extension, 'ActionExtension', :ios, '15.0')
extension_target.build_configurations.each do |config|
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

# Create ActionExtension group
action_extension_group = project.main_group.find_subpath('ActionExtension', true)
action_extension_group.clear

# Add files to the group and target
files_to_add = [
  'ActionExtension/ActionViewController.swift',
  'ActionExtension/MainInterface.storyboard',
  'ActionExtension/Info.plist',
  'ActionExtension/ActionExtension.entitlements'
]

files_to_add.each do |file_path|
  file_ref = action_extension_group.new_reference(file_path)
  
  # Add to target's build phases (except Info.plist and entitlements)
  unless file_path.include?('Info.plist') || file_path.include?('.entitlements')
    if file_path.include?('.swift')
      extension_target.source_build_phase.add_file_reference(file_ref)
    elsif file_path.include?('.storyboard')
      extension_target.resources_build_phase.add_file_reference(file_ref)
    end
  end
end

# Find the main app target
main_target = project.targets.find { |t| t.name == 'Snapzify' }
if main_target
  # Add ActionExtension as a dependency
  main_target.add_dependency(extension_target)
  
  # Add to Embed App Extensions build phase
  embed_phase = main_target.build_phases.find { |p| p.is_a?(Xcodeproj::Project::Object::PBXCopyFilesBuildPhase) && p.name == 'Embed App Extensions' }
  
  if embed_phase.nil?
    embed_phase = main_target.new_copy_files_build_phase('Embed App Extensions')
    embed_phase.dst_subfolder_spec = '13'  # .plugins
    embed_phase.dst_path = ''
  end
  
  # Add the extension product to the embed phase
  build_file = embed_phase.add_file_reference(extension_target.product_reference)
  build_file.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }
end

# Save the project
project.save

puts "✅ ActionExtension successfully added to Xcode project!"
puts "📦 Target created: ActionExtension"
puts "📁 Files added:"
files_to_add.each { |f| puts "   - #{f}" }
puts "🔗 Dependency added to main app target"
puts "📱 Extension will be embedded in main app"