#!/usr/bin/env python3
import re

file_path = "/Users/melvinlu/snapzify/Snapzify/SnapzifyApp.swift"

with open(file_path, 'r') as f:
    content = f.read()

# Fix the malformed logger calls
content = re.sub(r'logger\."([^"]+)"\)', r'logger.debug("\1")', content)
content = re.sub(r'logger\.debug\("([^"]*Error[^"]*)"\)', r'logger.error("\1")', content, flags=re.IGNORECASE)
content = re.sub(r'logger\.debug\("([^"]*Failed[^"]*)"\)', r'logger.error("\1")', content, flags=re.IGNORECASE)
content = re.sub(r'logger\.debug\("([^"]*No [^"]* found[^"]*)"\)', r'logger.info("\1")', content, flags=re.IGNORECASE)
content = re.sub(r'logger\.debug\("([^"]*Processing[^"]*)"\)', r'logger.info("\1")', content)
content = re.sub(r'logger\.debug\("([^"]*Looking for[^"]*)"\)', r'logger.debug("\1")', content)
content = re.sub(r'logger\.debug\("([^"]*Found[^"]*)"\)', r'logger.info("\1")', content)
content = re.sub(r'logger\.debug\("([^"]*Successfully[^"]*)"\)', r'logger.info("\1")', content)
content = re.sub(r'logger\.debug\("([^"]*loaded[^"]*)"\)', r'logger.info("\1")', content)
content = re.sub(r'logger\.debug\("([^"]*exists[^"]*)"\)', r'logger.debug("\1")', content)
content = re.sub(r'logger\.debug\("([^"]*Cleaned up[^"]*)"\)', r'logger.info("\1")', content)

# Clean up the "AppState: " prefix
content = re.sub(r'(logger\.\w+\()"AppState: ', r'\1"', content)

with open(file_path, 'w') as f:
    f.write(content)

print("Fixed logging in SnapzifyApp.swift")