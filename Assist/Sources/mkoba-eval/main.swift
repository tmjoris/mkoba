import AnyLanguageModel
import Foundation
import MkobaAssist
import MkobaCore

// mkoba-eval run --reader regex|ollama [--model qwen2.5:3b] [--cases Evals/messages.jsonl]
//                [--out results.jsonl] [--shard 1/4]
// mkoba-eval summarize [--cases Evals/messages.jsonl] results/*.jsonl

func option(_ name: String, in args: [String]) -> String? {
    guard let index = args.firstIndex(of: "--\(name)"), index + 1 < args.count else { return nil }
    return args[index + 1]
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(2)
}

let args = Array(CommandLine.arguments.dropFirst())
switch args.first {
case "run":
    let cases = try EvalCase.load(URL(fileURLWithPath: option("cases", in: args) ?? "Evals/messages.jsonl"))
    var selected = cases
    if let shard = option("shard", in: args) {
        let parts = shard.split(separator: "/").compactMap { Int($0) }
        guard parts.count == 2, parts[0] >= 1, parts[0] <= parts[1] else { fail("--shard k/n") }
        selected = cases.enumerated().filter { $0.offset % parts[1] == parts[0] - 1 }.map(\.element)
    }
    let state = EvalChama.state()
    let readerName = option("reader", in: args) ?? "regex"
    var read: (String) async throws -> MessageReading
    switch readerName {
    case "regex":
        read = { MpesaSMSReader.read($0) }
    case "ollama":
        guard let name = option("model", in: args) else { fail("--model is required for ollama") }
        let base = URL(string: option("ollama-url", in: args) ?? "http://localhost:11434")!
        let reader = ModelReader(model: OllamaLanguageModel(baseURL: base, model: name,
                                                            responseStartTimeout: .seconds(600)))
        read = { try await reader.read($0) }
    default:
        fail("unknown reader \(readerName)")
    }

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    var lines: [String] = []
    for (number, c) in selected.enumerated() {
        let started = Date()
        var reading: MessageReading?
        var error: String?
        for attempt in 1...2 where reading == nil {
            do {
                reading = try await read(c.text)
                error = nil
            } catch let caught {
                error = "attempt \(attempt): \(caught)"
            }
        }
        let result = EvalResult.evaluate(c, reading: reading, error: error,
                                         seconds: Date().timeIntervalSince(started), state: state)
        lines.append(String(decoding: try encoder.encode(result), as: UTF8.self))
        print("[\(number + 1)/\(selected.count)] \(c.id) expect=\(c.expect.rawValue) "
            + "checks=\(result.withChecks.rawValue) trusted=\(result.withoutChecks.rawValue) "
            + String(format: "%.1fs", result.seconds) + (error.map { " error=\($0.prefix(200))" } ?? ""))
    }
    let out = option("out", in: args) ?? "results.jsonl"
    try (lines.joined(separator: "\n") + "\n").write(toFile: out, atomically: true, encoding: .utf8)

case "summarize":
    let decoder = JSONDecoder()
    let casesPath = option("cases", in: args) ?? "Evals/messages.jsonl"
    let cases = Dictionary(uniqueKeysWithValues: try EvalCase.load(URL(fileURLWithPath: casesPath)).map { ($0.id, $0) })
    let state = EvalChama.state()
    let paths = args.dropFirst().filter { $0 != "--cases" && $0 != casesPath }
    var all: [(String, [EvalResult])] = []
    for path in paths {
        // Outcomes are re-scored from the saved readings with the current checks, so a change
        // to the checks can be measured on an earlier run without calling the models again.
        let results = try String(contentsOfFile: path, encoding: .utf8)
            .split(separator: "\n")
            .map { try decoder.decode(EvalResult.self, from: Data($0.utf8)) }
            .map { saved -> EvalResult in
                guard let c = cases[saved.id] else { return saved }
                return EvalResult.evaluate(c, reading: saved.reading, error: saved.error, seconds: saved.seconds,
                                           state: state)
            }
        let name = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        all.append((name, results))
        guard name != "regex" else { continue }
        // Rules first: the regex reads the standard SMS exactly and for free, and the model
        // only sees what the regex calls "not a payment". Computed from the saved readings.
        let hybrid = results.compactMap { result -> EvalResult? in
            guard let c = cases[result.id] else { return nil }
            let rules = MpesaSMSReader.read(c.text)
            return rules.isIncomingPayment
                ? EvalResult.evaluate(c, reading: rules, error: nil, seconds: 0, state: state)
                : EvalResult.evaluate(c, reading: result.reading, error: result.error, seconds: result.seconds,
                                      state: state)
        }
        all.append(("rules + \(name)", hybrid))
    }
    print(EvalSummary.header)
    for (name, results) in all {
        print(EvalSummary(name: name, results: results).rows())
    }
    print("\nWrong or missed with checks on:\n")
    for (name, results) in all {
        let bad = results.filter { $0.withChecks == .wrong || $0.withChecks == .missed }
        let text = bad.isEmpty ? "none" : bad.map { "\($0.id) (\($0.withChecks.rawValue))" }.joined(separator: ", ")
        print("- \(name): \(text)")
    }

default:
    fail("usage: mkoba-eval run --reader regex|ollama [--model NAME] [--shard k/n] [--out FILE] | summarize FILES")
}
