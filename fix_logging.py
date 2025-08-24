#!/usr/bin/env python3
import re

file_path = "/Users/melvinlu/snapzify/Snapzify/Services/TTSServiceOpenAI.swift"

with open(file_path, 'r') as f:
    content = f.read()

# Fix the malformed logger calls
content = re.sub(r'logger\."([^"]+)"\)', r'logger.debug("\1")', content)

# Now fix specific log levels based on content
content = re.sub(r'logger\.debug\("([^"]*error[^"]*)"\)', r'logger.error("\1")', content, flags=re.IGNORECASE)
content = re.sub(r'logger\.debug\("([^"]*failed[^"]*)"\)', r'logger.error("\1")', content, flags=re.IGNORECASE)
content = re.sub(r'logger\.debug\("([^"]*invalid[^"]*)"\)', r'logger.error("\1")', content, flags=re.IGNORECASE)
content = re.sub(r'logger\.debug\("([^"]*not configured[^"]*)"\)', r'logger.warning("\1")', content, flags=re.IGNORECASE)
content = re.sub(r'logger\.debug\("([^"]*not properly[^"]*)"\)', r'logger.warning("\1")', content, flags=re.IGNORECASE)
content = re.sub(r'logger\.debug\("(TTS[^:]*: generateAudio[^"]*)"\)', r'logger.info("\1")', content)
content = re.sub(r'logger\.debug\("(TTS[^:]*: Received[^"]*)"\)', r'logger.info("\1")', content)
content = re.sub(r'logger\.debug\("(TTS[^:]*: Audio saved[^"]*)"\)', r'logger.info("\1")', content)

# Clean up the "TTSService: " prefix
content = re.sub(r'(logger\.\w+\()"TTSService: ', r'\1"', content)

with open(file_path, 'w') as f:
    f.write(content)

print("Fixed logging in TTSServiceOpenAI.swift")