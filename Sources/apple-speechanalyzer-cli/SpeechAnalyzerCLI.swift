
// Apple Speech Analyzer CLI (macOS 26.0+)
// Build with: swift build -c release
// Usage:
//   .build/release/apple-speechanalyzer-cli \
//       --input-audio-path <path-to-audio> \
//       --output-text-path <path-to-output> \
//       [--locale en-US] \
//       [--custom-phrases "word1,word2,phrase one"]
//
// Requires: Xcode 26 and macOS 26.0 runtime.
// Reference: https://developer.apple.com/documentation/speech/analysiscontext

import Foundation
import AVFAudio
import Speech
import Darwin

@main
struct SpeechAnalyzerCLI {
    static func main() async throws {
        var inputPath: String?
        var outputPath: String?
        var localeIdentifier = Locale.current.identifier
        var customPhrasesString: String?

        var it = CommandLine.arguments.dropFirst().makeIterator()
        while let arg = it.next() {
            switch arg {
            case "--input-audio-path": inputPath  = it.next()
            case "--output-text-path": outputPath = it.next()
            case "--locale":           localeIdentifier = it.next() ?? localeIdentifier
            case "--custom-phrases":   customPhrasesString = it.next()
            default:                   CLIUsage.exit()
            }
        }

        guard let inPath = inputPath, let outPath = outputPath else {
            CLIUsage.exit()
        }

        guard #available(macOS 26.0, *) else {
            fputs("Error: SpeechAnalyzer requires macOS 26.0 or newer.\n", stderr)
            Darwin.exit(EXIT_FAILURE)
        }

        // Parse custom phrases from comma-separated string
        let customPhrases: [String]? = customPhrasesString?.split(separator: ",").map {
            String($0).trimmingCharacters(in: .whitespaces)
        }

        let locale = Locale(identifier: localeIdentifier)
        
        // Use the correct SpeechTranscriber initializer for macOS 26
        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: [.audioTimeRange]
        )

        // Check if locale is installed, download if needed
        let installedLocales = await SpeechTranscriber.installedLocales
        if !installedLocales.contains(where: { $0.identifier == locale.identifier }) {
            FileHandle.standardError.write(Data("Downloading speech model for \(localeIdentifier)…\n".utf8))
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                try await request.downloadAndInstall()
            }
        }

        let inputURL  = URL(fileURLWithPath: inPath)
        let audioFile = try AVAudioFile(forReading: inputURL)
        let outputURL = URL(fileURLWithPath: outPath)

        // Create AnalysisContext with custom phrases if provided
        // Reference: https://developer.apple.com/documentation/speech/analysiscontext
        let context: AnalysisContext = {
            var ctx = AnalysisContext()
            if let phrases = customPhrases, !phrases.isEmpty {
                // Use the vocabulary tag for custom phrases
                let vocabTag = AnalysisContext.ContextualStringsTag(rawValue: "vocabulary")
                ctx.contextualStrings = [vocabTag: phrases]
                FileHandle.standardError.write(Data("Using custom phrases: \(phrases)\n".utf8))
            }
            return ctx
        }()

        // Use the file-based SpeechAnalyzer initializer
        // The analyzer processes the audio file and feeds results to transcriber.results
        _ = try await SpeechAnalyzer(
            inputAudioFile: audioFile,
            modules: [transcriber],
            analysisContext: context,
            finishAfterFile: true
        )

        // Collect transcription results
        var transcript = AttributedString("")
        for try await result in transcriber.results {
            transcript.append(result.text)
            transcript.append(AttributedString(" "))
        }

        let plainText = String(transcript.characters)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        try plainText.write(to: outputURL, atomically: true, encoding: .utf8)
        print("✅ Saved transcript to \(outputURL.path)")
    }
}

enum CLIUsage {
    static func exit() -> Never {
        let prog = (CommandLine.arguments.first as NSString?)?.lastPathComponent ?? "apple-speechanalyzer-cli"
        fputs("""
Usage: \(prog) --input-audio-path <file> --output-text-path <file> [--locale <id>] [--custom-phrases <phrases>]

Options:
  --input-audio-path  Path to input audio file (required)
  --output-text-path  Path to output transcript file (required)
  --locale            Locale identifier for transcription (default: system locale)
  --custom-phrases    Comma-separated list of custom vocabulary phrases to boost

Example:
  .build/release/\(prog) --input-audio-path demo.flac \\
                         --output-text-path demo.txt \\
                         --locale en-US \\
                         --custom-phrases "Argmax,WhisperKit,SpeakerKit"

Custom phrases improve recognition accuracy for domain-specific terms.
Reference: https://developer.apple.com/documentation/speech/analysiscontext

""", stderr)
        Darwin.exit(EXIT_FAILURE)
    }
}
