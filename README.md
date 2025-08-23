# Snapzify

Turn screenshots into readable, tappable Chinese sentences with pinyin, English translation, and audio.

## Features

- **On-device OCR**: Process Chinese screenshots using Apple Vision framework
- **Simplified/Traditional Toggle**: Switch between character sets with OpenCC
- **Smart Segmentation**: Automatically split text into sentences and tokens
- **Pinyin Generation**: On-device pinyin with polyphone handling
- **Translation**: OpenAI-powered English translation (optional)
- **Text-to-Speech**: Generate audio with OpenAI TTS (optional)
- **Pleco Integration**: Deep link sentences to Pleco dictionary
- **Share Extension**: Process screenshots directly from iOS share sheet
- **Privacy-focused**: OCR, segmentation, and pinyin stay on device

## Architecture

### MVVM + Protocol-Oriented Design
- **Services**: Protocol-based with dependency injection
- **ViewModels**: Handle business logic and state management
- **Views**: SwiftUI with modern dark gradient theme
- **Store**: Document persistence via App Group

### Key Services
- `OCRService`: Vision framework text recognition
- `ScriptConversionService`: OpenCC-based S↔T conversion
- `SentenceSegmentationService`: Chinese punctuation-aware splitting
- `PinyinService`: Character-to-pinyin mapping with caching
- `TranslationService`: OpenAI API batch translation
- `TTSService`: OpenAI TTS with local caching
- `ConfigService`: Keychain-backed API key management

## Setup

### 1. Configure Xcode Project

1. Open `Snapzify.xcodeproj` in Xcode
2. Select the main app target
3. Go to Signing & Capabilities
4. Add "App Groups" capability
5. Create group: `group.com.snapzify`
6. Repeat for ShareExtension target

### 2. Add OpenCC Assets

Download OpenCC conversion dictionaries and add to bundle:
- `s2t.json` (Simplified to Traditional)
- `t2s.json` (Traditional to Simplified)

Place in `Snapzify/Resources/OpenCC/`

### 3. Configure OpenAI API Key

#### Option A: Edit Config File
Edit `Snapzify/Resources/SnapzifyConfig.json`:
```json
{
  "openai": {
    "apiKey": "sk-your-actual-api-key-here",
    ...
  }
}
```

#### Option B: In-App Settings
1. Launch app
2. Tap gear icon → Settings
3. Enter API key in secure field
4. Tap "Save Key"

The key is stored securely in iOS Keychain.

### 4. Build and Run

1. Select target device/simulator (iOS 17+)
2. Build and run (⌘R)
3. Allow photo library access when prompted

## Usage

### Processing Screenshots

#### Via Share Extension
1. Take a screenshot
2. Open Photos app
3. Select screenshot → Share
4. Choose "Snapzify" from share sheet
5. Tap "Open in Snapzify"

#### Via Main App
1. Launch Snapzify
2. Tap "Import Screenshot" or "Paste Image"
3. Select from photo library

### Viewing Results

- **Tap sentence**: Expand to show pinyin and translation
- **Show Original**: Toggle image overlay
- **Translate**: Generate English translation
- **Open in Pleco**: Look up in dictionary
- **Play**: Listen to TTS audio

### Settings

- **Script**: Toggle Simplified/Traditional
- **Auto-translate**: Process on import
- **Auto-audio**: Generate on expand
- **Voice**: Select TTS voice per script
- **Speed**: Adjust playback rate

## Testing

Run tests with:
```bash
xcodebuild test -scheme Snapzify -destination 'platform=iOS Simulator,name=iPhone 15'
```

Key test areas:
- Sentence segmentation edge cases
- Script conversion accuracy
- Polyphone handling
- Translation batch ordering
- Cache key generation
- Config precedence

## Privacy

- **On-device**: OCR, segmentation, pinyin, OpenCC
- **Cloud (text only)**: Translation, TTS
- **Never uploaded**: Images, personal data
- **Secure storage**: API keys in Keychain

## Dependencies

- iOS 17.0+
- Xcode 15.0+
- Swift 5.9+
- No external packages (all native/embedded)

## Performance

- Concurrent pinyin generation via TaskGroup
- Batched translation (12 sentences/request)
- LRU caching for conversions
- Audio file caching in App Group
- Throttled API requests

## Troubleshooting

### Share Extension Not Appearing
1. Check App Group configuration matches
2. Verify both targets have same group ID
3. Clean build folder (⇧⌘K) and rebuild

### Translation/Audio Not Working
1. Verify API key is valid
2. Check Settings → Translation status
3. Ensure network connectivity
4. Look for rate limit errors in console

### OCR Quality Issues
1. Ensure screenshot has clear text
2. Check image isn't blurry/rotated
3. Try both Simplified and Traditional modes

## License

Proprietary - All rights reserved