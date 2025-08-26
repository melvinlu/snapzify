#!/usr/bin/env python3

import re
import sys
import os

# Files to add with their group names
files_to_add = [
    ('Snapzify/Services/MediaStorageService.swift', 'Services'),
    ('Snapzify/Services/VideoFrameProcessor.swift', 'Services'),
    ('Snapzify/Services/MediaProcessingService.swift', 'Services'),
    ('Snapzify/Services/PhotoLibraryService.swift', 'Services'),
    ('Snapzify/Services/KeychainService.swift', 'Services'),
    ('Snapzify/Utils/LRUCache.swift', 'Services'),
    ('Snapzify/Utils/ErrorHandling.swift', 'Services'),
    ('Snapzify/Utils/PaginatedDocumentLoader.swift', 'Services'),
    ('Snapzify/Utils/ConcurrentProcessing.swift', 'Services'),
    ('Snapzify/Constants/Constants.swift', 'Services'),
    ('Snapzify/Views/Components/SharedPopupComponents.swift', 'Views'),
    ('Snapzify/Views/Components/MediaNavigationBar.swift', 'Views'),
    ('Snapzify/Views/Components/BaseMediaDocumentView.swift', 'Views'),
    ('Snapzify/Protocols/ServiceProtocols.swift', 'Services'),
    ('Snapzify/DependencyInjection/DependencyContainer.swift', 'Services'),
]

def generate_uuid():
    """Generate a 24-character hex string for Xcode IDs"""
    import uuid
    return uuid.uuid4().hex[:24].upper()

def add_file_to_xcode_project(project_path, file_path, group_name):
    """Add a single file to the Xcode project"""
    
    with open(project_path, 'r') as f:
        content = f.read()
    
    # Extract filename
    filename = os.path.basename(file_path)
    
    # Check if file already exists in project
    if filename in content:
        print(f"✓ {filename} already in project")
        return content
    
    # Generate IDs
    file_ref_id = generate_uuid()
    build_file_id = generate_uuid()
    
    # Find the appropriate group
    group_pattern = rf'([A-F0-9]{{24}}) /\* {group_name} \*/ = \{{'
    group_match = re.search(group_pattern, content)
    
    if not group_match:
        print(f"⚠️ Could not find {group_name} group for {filename}")
        return content
    
    group_id = group_match.group(1)
    
    # Add PBXBuildFile
    build_file_entry = f"\t\t{build_file_id} /* {filename} in Sources */ = {{isa = PBXBuildFile; fileRef = {file_ref_id} /* {filename} */; }};\n"
    
    # Find the PBXBuildFile section
    build_file_section = re.search(r'/\* Begin PBXBuildFile section \*/\n(.*?)/\* End PBXBuildFile section \*/', content, re.DOTALL)
    if build_file_section:
        # Add at the end of the section
        insert_pos = build_file_section.end() - len('/* End PBXBuildFile section */')
        content = content[:insert_pos] + build_file_entry + content[insert_pos:]
    
    # Add PBXFileReference
    file_ref_entry = f"\t\t{file_ref_id} /* {filename} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {filename}; sourceTree = \"<group>\"; }};\n"
    
    # Find the PBXFileReference section
    file_ref_section = re.search(r'/\* Begin PBXFileReference section \*/\n(.*?)/\* End PBXFileReference section \*/', content, re.DOTALL)
    if file_ref_section:
        insert_pos = file_ref_section.end() - len('/* End PBXFileReference section */')
        content = content[:insert_pos] + file_ref_entry + content[insert_pos:]
    
    # Add to group's children
    group_pattern_full = rf'{group_id} /\* {group_name} \*/ = \{{[^}}]*?children = \((.*?)\);'
    group_match_full = re.search(group_pattern_full, content, re.DOTALL)
    
    if group_match_full:
        children_content = group_match_full.group(1)
        # Add the new file reference
        new_children = children_content.rstrip() + f"\n\t\t\t\t{file_ref_id} /* {filename} */,"
        content = content[:group_match_full.start(1)] + new_children + content[group_match_full.end(1):]
    
    # Add to PBXSourcesBuildPhase
    # Find the main target's source build phase
    sources_pattern = r'([A-F0-9]{24}) /\* Sources \*/ = \{[^}]*?files = \((.*?)\);'
    sources_match = re.search(sources_pattern, content, re.DOTALL)
    
    if sources_match:
        sources_id = sources_match.group(1)
        files_content = sources_match.group(2)
        # Add the build file reference
        new_files = files_content.rstrip() + f"\n\t\t\t\t{build_file_id} /* {filename} in Sources */,"
        content = content[:sources_match.start(2)] + new_files + content[sources_match.end(2):]
    
    print(f"✅ Added {filename} to project")
    return content

def main():
    project_path = 'Snapzify.xcodeproj/project.pbxproj'
    
    # Read the project file
    with open(project_path, 'r') as f:
        content = f.read()
    
    # Add each file
    for file_path, group_name in files_to_add:
        if os.path.exists(file_path):
            content = add_file_to_xcode_project(project_path, file_path, group_name)
        else:
            print(f"⚠️ File not found: {file_path}")
    
    # Write back the modified content
    with open(project_path, 'w') as f:
        f.write(content)
    
    print("\n✅ Done! All files have been processed.")
    print("Please build the project in Xcode to verify.")

if __name__ == '__main__':
    main()