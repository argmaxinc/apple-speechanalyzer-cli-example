
// Apple Speech Analyzer CLI (macOS 26.0+)
// Build with: swift build -c release
// Usage:
//   .build/release/apple-speechanalyzer-cli \
//       --input-audio-path <path-to-audio> \
//       --output-text-path <path-to-output> [--locale en-US]
//
// Requires: Xcode 26 beta command-line tools and macOS 26.0 runtime.

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
        var useSFSpeech = false // Use SFSpeechRecognizer instead of SpeechTranscriber

        var it = CommandLine.arguments.dropFirst().makeIterator()
        while let arg = it.next() {
            switch arg {
            case "--input-audio-path": inputPath  = it.next()
            case "--output-text-path": outputPath = it.next()
            case "--locale":           localeIdentifier = it.next() ?? localeIdentifier
            case "--custom-phrases":   customPhrasesString = it.next()
            case "--sfspeech":         useSFSpeech = true
            default:                   CLIUsage.exit()
            }
        }

        guard let inPath = inputPath, let outPath = outputPath else {
            CLIUsage.exit()
        }

        // Parse phrases
        let customPhrases: [String]? = customPhrasesString?.split(separator: ",").map {
            String($0).trimmingCharacters(in: .whitespaces)
        }

        let locale = Locale(identifier: localeIdentifier)
        let inputURL  = URL(fileURLWithPath: inPath)
        let outputURL = URL(fileURLWithPath: outPath)

        // If we have custom phrases and want them to work, use SFSpeechRecognizer
        // contextualStrings only works with SFSpeechRecognizer (not SpeechTranscriber)
        let hasCustomPhrases = customPhrases?.isEmpty == false
        let shouldUseSFSpeech = useSFSpeech || hasCustomPhrases

        var plainText = ""

        if shouldUseSFSpeech {
            // Use SFSpeechRecognizer
            // This is the only way contextualStrings actually works
            guard let recognizer = SFSpeechRecognizer(locale: locale) else {
                fputs("Error: Could not create SFSpeechRecognizer for locale \(localeIdentifier)\n", stderr)
                Darwin.exit(EXIT_FAILURE)
            }

            if !recognizer.isAvailable {
                fputs("Error: Speech recognizer not available\n", stderr)
                Darwin.exit(EXIT_FAILURE)
            }

            let request = SFSpeechURLRecognitionRequest(url: inputURL)
            request.requiresOnDeviceRecognition = false
            request.addsPunctuation = true

            if let phrases = customPhrases, !phrases.isEmpty {
                request.contextualStrings = phrases
            }

            // Perform recognition using continuation for async/await compatibility
            do {
                plainText = try await withCheckedThrowingContinuation { continuation in
                    recognizer.recognitionTask(with: request) { result, error in
                        if let error = error {
                            continuation.resume(throwing: error)
                            return
                        }
                        if let result = result, result.isFinal {
                            continuation.resume(returning: result.bestTranscription.formattedString)
                        }
                    }
                }
            } catch {
                fputs("Error: \(error)\n", stderr)
                Darwin.exit(EXIT_FAILURE)
            }

        } else {
            // Use new SpeechTranscriber (on-device, faster)
            guard #available(macOS 26.0, *) else {
                fputs("Error: SpeechTranscriber requires macOS 26.0 or newer.\n", stderr)
                Darwin.exit(EXIT_FAILURE)
            }

            let transcriber = SpeechTranscriber(
                locale: locale,
                transcriptionOptions: [],
                reportingOptions: [],
                attributeOptions: []
            )

            if !(await SpeechTranscriber.installedLocales).contains(locale) {
                FileHandle.standardError.write(Data("Downloading speech model for \(localeIdentifier)…\n".utf8))
                if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                    try await request.downloadAndInstall()
                }
            }

            let analyzer    = SpeechAnalyzer(modules: [transcriber])
            let audioFile   = try AVAudioFile(forReading: inputURL)

            async let attrTranscript: AttributedString = transcriber.results.reduce(into: AttributedString("")) { partial, result in
                partial.append(result.text)
                partial.append(AttributedString(" "))
            }

            if let last = try await analyzer.analyzeSequence(from: audioFile) {
                try await analyzer.finalizeAndFinish(through: last)
            } else {
                await analyzer.cancelAndFinishNow()
            }

            plainText = String((try await attrTranscript).characters)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        try plainText.write(to: outputURL, atomically: true, encoding: .utf8)
        print("✅ Saved transcript to \(outputURL.path)")
    }
}

enum CLIUsage {
    static func exit() -> Never {
        let prog = (CommandLine.arguments.first as NSString?)?.lastPathComponent ?? "apple-speechanalyzer-cli"
        fputs("""
Usage: \(prog) --input-audio-path <file> --output-text-path <file> [--locale <id>] [--sfspeech] [--custom-phrases <phrases>]

Example:
  .build/release/\(prog) --input-audio-path demo.flac \\
                         --output-txt-path demo.txt \\
                         --locale en-US

""", stderr)
        Darwin.exit(EXIT_FAILURE)
    }
}
