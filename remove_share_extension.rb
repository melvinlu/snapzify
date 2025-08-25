#!/usr/bin/env ruby

require 'xcodeproj'

# Open the project
project_path = 'Snapzify.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# Find and remove ShareExtension target
share_target = project.targets.find { |t| t.name == 'ShareExtension' }
if share_target
  puts "Found ShareExtension target, removing..."
  
  # Remove from main app's dependencies
  main_target = project.targets.find { |t| t.name == 'Snapzify' }
  if main_target
    dependency = main_target.dependencies.find { |d| d.target == share_target }
    main_target.dependencies.delete(dependency) if dependency
    
    # Remove from Embed App Extensions phase
    main_target.build_phases.each do |phase|
      if phase.is_a?(Xcodeproj::Project::Object::PBXCopyFilesBuildPhase)
        phase.files.each do |file|
          if file.file_ref && file.file_ref.path && file.file_ref.path.include?('ShareExtension')
            phase.files.delete(file)
            puts "Removed ShareExtension from embed phase"
          end
        end
      end
    end
  end
  
  # Remove the target
  project.targets.delete(share_target)
  puts "✅ ShareExtension target removed"
else
  puts "ShareExtension target not found (already removed)"
end

# Remove ShareExtension group if it exists
share_group = project.main_group.find_subpath('ShareExtension', false)
if share_group
  share_group.remove_from_project
  puts "✅ ShareExtension group removed"
end

# Save the project
project.save

puts "✅ ShareExtension completely removed from Xcode project!"