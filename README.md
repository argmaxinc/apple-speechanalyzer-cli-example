# `apple-speechanalyzer-cli`

🗣️ A macOS CLI tool for transcribing audio files using the new Apple Speech framework (macOS 26.0+).

## Features

- Offline or live-mode transcription using Apple’s latest SpeechTranscriber APIs
- Automatic language model download for the specified locale
- CLI output to a plain `.txt` file
- Fully async Swift implementation

## Requirements

- macOS 26.0+
- Xcode 16 beta with macOS 26 SDK and command-line tools

## Installation

```bash
swift build -c release
```

## Usage

```bash
.build/release/apple-speechanalyzer-cli \
    --input-audio-path <path-to-audio> \
    --output-txt-path <path-to-output> \
    [--locale <locale-id>] \
    [--live]
```

### Arguments

| Flag | Required | Type | Description |
|------|----------|------|-------------|
| `--input-audio-path` | ✅ | `String` | Path to input audio file (e.g., `.flac`, `.wav`) |
| `--output-txt-path`  | ✅ | `String` | Path to write output `.txt` transcription |
| `--locale`           | ❌ | `String` | Locale for transcription (default: system locale) |
| `--live`             | ❌ | `Flag`   | Enable progressive live transcription (default: offline) |

### Example

```bash
.build/release/apple-speechanalyzer-cli \
    --input-audio-path demo.flac \
    --output-txt-path demo.txt \
    --locale en-US
```

## How It Works

1. **Argument parsing:** CLI args are parsed to configure audio input/output paths, locale, and mode.
2. **API check:** Ensures your system is running macOS 26.0 or later.
3. **Speech model installation:** Downloads locale-specific model if not already installed.
4. **Transcription:**
   - Runs `SpeechTranscriber` via `SpeechAnalyzer`
   - In `--live` mode, uses `.progressiveLiveTranscription` for real-time feedback
   - Otherwise, defaults to `.offlineTranscription`
5. **Result saving:** Aggregates transcribed `AttributedString` to plain text and writes to file.

## Output

✅ On success: transcript is saved to the specified output path.

❌ On error: descriptive messages printed to `stderr`.

## License

apple-speechanalyzer-cli is released under the MIT License. See [LICENSE](./LICENSE) for more details.
