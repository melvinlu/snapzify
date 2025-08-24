#!/usr/bin/env python3
import re
import sys

project_file = "Snapzify.xcodeproj/project.pbxproj"

# Read the project file
with open(project_file, 'r') as f:
    content = f.read()

# Check if PinyinServiceOpenAI already exists
if "PinyinServiceOpenAI.swift" in content:
    print("PinyinServiceOpenAI.swift already in project")
    sys.exit(0)

# Generate new UUIDs (simplified - in real scenario should be unique)
file_ref_id = "3D9B1A201234567890123457"
build_file_id = "3D9B1A211234567890123458"
build_file_id2 = "3D9B1A221234567890123459"

# Find PinyinServiceImpl references and add PinyinServiceOpenAI after them

# Add to PBXBuildFile section
build_file_pattern = r'(3D9B1A0E1234567890123456 /\* PinyinServiceImpl\.swift in Sources \*/ = {[^}]+};\n)'
build_file_addition = f'\t\t{build_file_id} /* PinyinServiceOpenAI.swift in Sources */ = {{isa = PBXBuildFile; fileRef = {file_ref_id} /* PinyinServiceOpenAI.swift */; }};\n'
content = re.sub(build_file_pattern, r'\1' + build_file_addition, content)

# Also add for ShareExtension
share_ext_pattern = r'(3D4F30C32C6FC87E002CC01C /\* PinyinServiceImpl\.swift in Sources \*/[^}]+};\n)'
share_ext_addition = f'\t\t{build_file_id2} /* PinyinServiceOpenAI.swift in Sources */ = {{isa = PBXBuildFile; fileRef = {file_ref_id} /* PinyinServiceOpenAI.swift */; }};\n'
content = re.sub(share_ext_pattern, r'\1' + share_ext_addition, content)

# Add to PBXFileReference section
file_ref_pattern = r'(3D9B1A0F1234567890123456 /\* PinyinServiceImpl\.swift \*/ = {[^}]+};\n)'
file_ref_addition = f'\t\t{file_ref_id} /* PinyinServiceOpenAI.swift */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = PinyinServiceOpenAI.swift; sourceTree = "<group>"; }};\n'
content = re.sub(file_ref_pattern, r'\1' + file_ref_addition, content)

# Add to Services group
services_pattern = r'(3D9B1A0F1234567890123456 /\* PinyinServiceImpl\.swift \*/,\n)'
services_addition = f'\t\t\t\t{file_ref_id} /* PinyinServiceOpenAI.swift */,\n'
content = re.sub(services_pattern, r'\1' + services_addition, content)

# Add to build phases
build_phase_pattern = r'(3D9B1A0E1234567890123456 /\* PinyinServiceImpl\.swift in Sources \*/,\n)'
build_phase_addition = f'\t\t\t\t{build_file_id} /* PinyinServiceOpenAI.swift in Sources */,\n'
content = re.sub(build_phase_pattern, r'\1' + build_phase_addition, content)

# Add to ShareExtension build phases
share_build_pattern = r'(3D4F30C32C6FC87E002CC01C /\* PinyinServiceImpl\.swift in Sources \*/,\n)'
share_build_addition = f'\t\t\t\t{build_file_id2} /* PinyinServiceOpenAI.swift in Sources */,\n'
content = re.sub(share_build_pattern, r'\1' + share_build_addition, content)

# Write back
with open(project_file, 'w') as f:
    f.write(content)

print("Added PinyinServiceOpenAI.swift to project")