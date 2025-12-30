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
        var debug = false
        var useServerRecognition = false // Default to on-device with SpeechTranscriber

        var it = CommandLine.arguments.dropFirst().makeIterator()
        while let arg = it.next() {
            switch arg {
            case "--input-audio-path": inputPath  = it.next()
            case "--output-text-path": outputPath = it.next()
            case "--locale":           localeIdentifier = it.next() ?? localeIdentifier
            case "--custom-phrases":   customPhrasesString = it.next()
            case "--debug":            debug = true
            case "--server":           useServerRecognition = true // Use SFSpeechRecognizer with server
            default:                   break
            }
        }

        guard let inPath = inputPath, let outPath = outputPath else {
            fputs("Usage: cli --input-audio-path <file> --output-text-path <file> [--custom-phrases <p>] [--server] [--debug]\n", stderr)
            Darwin.exit(1)
        }

        // Parse phrases
        let customPhrases: [String]? = customPhrasesString?.split(separator: ",").map {
            String($0).trimmingCharacters(in: .whitespaces)
        }

        if debug {
            fputs("=== DEBUG: Input Parameters ===\n", stderr)
            fputs("  Input: \(inPath)\n", stderr)
            fputs("  Output: \(outPath)\n", stderr)
            fputs("  Locale: \(localeIdentifier)\n", stderr)
            fputs("  Custom phrases: \(customPhrases ?? [])\n", stderr)
            fputs("  Use server: \(useServerRecognition)\n", stderr)
        }

        let locale = Locale(identifier: localeIdentifier)
        let inputURL  = URL(fileURLWithPath: inPath)
        let outputURL = URL(fileURLWithPath: outPath)

        // If we have custom phrases and want them to work, use server-based recognition
        // contextualStrings only works with SFSpeechRecognizer + server (not on-device)
        let hasCustomPhrases = customPhrases?.isEmpty == false
        let shouldUseServer = useServerRecognition || hasCustomPhrases

        var plainText = ""

        if shouldUseServer {
            // Use SFSpeechRecognizer with server-based recognition
            // This is the only way contextualStrings actually works
            if debug {
                fputs("\n=== Using SFSpeechRecognizer (server-based) for contextualStrings support ===\n", stderr)
            }

            guard let recognizer = SFSpeechRecognizer(locale: locale) else {
                fputs("Error: Could not create SFSpeechRecognizer for locale \(localeIdentifier)\n", stderr)
                Darwin.exit(1)
            }

            if !recognizer.isAvailable {
                fputs("Error: Speech recognizer not available\n", stderr)
                Darwin.exit(1)
            }

            let request = SFSpeechURLRecognitionRequest(url: inputURL)
            request.requiresOnDeviceRecognition = false // CRITICAL: Use server for contextualStrings
            request.addsPunctuation = true

            if let phrases = customPhrases, !phrases.isEmpty {
                request.contextualStrings = phrases
                if debug {
                    fputs("  Set contextualStrings: \(phrases)\n", stderr)
                }
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
                Darwin.exit(1)
            }

        } else {
            // Use new SpeechTranscriber (on-device, faster, but contextualStrings don't work)
            guard #available(macOS 26.0, *) else {
                fputs("Error: SpeechTranscriber requires macOS 26.0+\n", stderr)
                Darwin.exit(1)
            }

            if debug {
                fputs("\n=== Using SpeechTranscriber (on-device) ===\n", stderr)
            }

            let transcriber = SpeechTranscriber(
                locale: locale,
                transcriptionOptions: [],
                reportingOptions: [],
                attributeOptions: []
            )

            let installedLocales = await SpeechTranscriber.installedLocales
            if !installedLocales.contains(where: { $0.identifier == locale.identifier }) {
                if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                    try await request.downloadAndInstall()
                }
            }

            let audioFile = try AVAudioFile(forReading: inputURL)

            // Note: context is NOT used here because it doesn't work with SpeechTranscriber
            let _ = try await SpeechAnalyzer(
                inputAudioFile: audioFile,
                modules: [transcriber],
                finishAfterFile: true
            )

            // Collect results
            var transcript = AttributedString("")
            for try await result in transcriber.results {
                transcript.append(result.text)
                transcript.append(AttributedString(" "))
            }

            plainText = String(transcript.characters).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if debug {
            fputs("\n=== DEBUG: Final Transcript ===\n", stderr)
            fputs("  \(plainText)\n", stderr)
        }

        try plainText.write(to: outputURL, atomically: true, encoding: .utf8)
        print("OK")
    }
}
