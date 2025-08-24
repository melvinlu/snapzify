#!/usr/bin/env python3
import re

project_file = "Snapzify.xcodeproj/project.pbxproj"

# Read the project file
with open(project_file, 'r') as f:
    content = f.read()

# Check if ChineseProcessingService already exists
if "ChineseProcessingService.swift" in content:
    print("ChineseProcessingService.swift already in project")
    exit(0)

# Generate new UUIDs
file_ref_id = "3D9B1A301234567890123460"
build_file_id = "3D9B1A311234567890123461"

# Add to PBXBuildFile section - find PinyinServiceOpenAI and add after it
build_file_pattern = r'(3D9B1A211234567890123458 /\* PinyinServiceOpenAI\.swift in Sources \*/ = {[^}]+};\n)'
build_file_addition = f'\t\t{build_file_id} /* ChineseProcessingService.swift in Sources */ = {{isa = PBXBuildFile; fileRef = {file_ref_id} /* ChineseProcessingService.swift */; }};\n'
content = re.sub(build_file_pattern, r'\1' + build_file_addition, content)

# Add to PBXFileReference section
file_ref_pattern = r'(3D9B1A201234567890123457 /\* PinyinServiceOpenAI\.swift \*/ = {[^}]+};\n)'
file_ref_addition = f'\t\t{file_ref_id} /* ChineseProcessingService.swift */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = ChineseProcessingService.swift; sourceTree = "<group>"; }};\n'
content = re.sub(file_ref_pattern, r'\1' + file_ref_addition, content)

# Add to Services group
services_pattern = r'(3D9B1A201234567890123457 /\* PinyinServiceOpenAI\.swift \*/,\n)'
services_addition = f'\t\t\t\t{file_ref_id} /* ChineseProcessingService.swift */,\n'
content = re.sub(services_pattern, r'\1' + services_addition, content)

# Add to build phases
build_phase_pattern = r'(3D9B1A211234567890123458 /\* PinyinServiceOpenAI\.swift in Sources \*/,\n)'
build_phase_addition = f'\t\t\t\t{build_file_id} /* ChineseProcessingService.swift in Sources */,\n'
content = re.sub(build_phase_pattern, r'\1' + build_phase_addition, content)

# Write back
with open(project_file, 'w') as f:
    f.write(content)

print("Added ChineseProcessingService.swift to project")