import Commandant
import Dispatch
import Foundation
import SwiftLintFramework

enum LintOrAnalyzeMode {
    case lint, analyze

    var verb: String {
        switch self {
        case .lint:
            return "linting"
        case .analyze:
            return "analyzing"
        }
    }
}

struct LintOrAnalyzeCommand {
    // swiftlint:disable:next function_body_length
    static func run(_ options: LintOrAnalyzeOptions) -> Result<(), CommandantError<()>> {
        var fileBenchmark = Benchmark(name: "files")
        var ruleBenchmark = Benchmark(name: "rules")
        var violations = [StyleViolation]()
        let storage = RuleStorage()
        let configuration = Configuration(options: options)
        let reporter = reporterFrom(optionsReporter: options.reporter, configuration: configuration)
        let cache = options.ignoreCache ? nil : LinterCache(configuration: configuration)
        let visitorMutationQueue = DispatchQueue(label: "io.realm.swiftlint.lintVisitorMutation")
        let rootPath = options.paths.first?.absolutePathStandardized() ?? ""
        let baseline = Baseline(baselinePath: rootPath)
        if options.useBaseline {
            baseline.readBaseline()
        }
        return configuration.visitLintableFiles(options: options, cache: cache, storage: storage) { linter in
            var currentViolations: [StyleViolation]
            if options.benchmark {
                let start = Date()
                let (violationsBeforeLeniency, currentRuleTimes) = linter.styleViolationsAndRuleTimes(using: storage)
                currentViolations = applyLeniency(options: options, violations: violationsBeforeLeniency)
                if options.useBaseline {
                    currentViolations = filteredViolations(baseline: baseline, currentViolations: currentViolations)
                }
                visitorMutationQueue.sync {
                    fileBenchmark.record(file: linter.file, from: start)
                    currentRuleTimes.forEach { ruleBenchmark.record(id: $0, time: $1) }
                    violations += currentViolations
                }
            } else {
                currentViolations = applyLeniency(options: options, violations: linter.styleViolations(using: storage))
                if options.useBaseline {
                    currentViolations = filteredViolations(baseline: baseline, currentViolations: currentViolations)
                }
                visitorMutationQueue.sync {
                    violations += currentViolations
                }
            }
            linter.file.invalidateCache()
            reporter.report(violations: currentViolations, realtimeCondition: true)
        }.flatMap { files in
            if options.useBaseline {
                baseline.saveBaseline(violations: violations)
            }
            if isWarningThresholdBroken(configuration: configuration, violations: violations)
                && !options.lenient {
                violations.append(createThresholdViolation(threshold: configuration.warningThreshold!))
                reporter.report(violations: [violations.last!], realtimeCondition: true)
            }
            reporter.report(violations: violations, realtimeCondition: false)
            let numberOfSeriousViolations = violations.filter({ $0.severity == .error }).count
            if !options.quiet {
                printStatus(violations: violations, files: files, serious: numberOfSeriousViolations,
                            verb: options.verb)
            }
            if options.benchmark {
                fileBenchmark.save()
                ruleBenchmark.save()
            }
            try? cache?.save()
            guard numberOfSeriousViolations == 0 else { exit(2) }
            return .success(())
        }
    }

    private static func filteredViolations(baseline: Baseline,
                                           currentViolations: [StyleViolation]) -> [StyleViolation] {
        var filteredViolations = [StyleViolation]()
        for violation in currentViolations {
            if !baseline.isInBaseline(violation: violation) {
                filteredViolations.append(violation)
            }
        }
        return filteredViolations
    }

    private static func printStatus(violations: [StyleViolation], files: [SwiftLintFile], serious: Int, verb: String) {
        let pluralSuffix = { (collection: [Any]) -> String in
            return collection.count != 1 ? "s" : ""
        }
        queuedPrintError(
            "Done \(verb)! Found \(violations.count) violation\(pluralSuffix(violations)), " +
            "\(serious) serious in \(files.count) file\(pluralSuffix(files))."
        )
    }

    private static func isWarningThresholdBroken(configuration: Configuration,
                                                 violations: [StyleViolation]) -> Bool {
        guard let warningThreshold = configuration.warningThreshold else { return false }
        let numberOfWarningViolations = violations.filter({ $0.severity == .warning }).count
        return numberOfWarningViolations >= warningThreshold
    }

    private static func createThresholdViolation(threshold: Int) -> StyleViolation {
        let description = RuleDescription(
            identifier: "warning_threshold",
            name: "Warning Threshold",
            description: "Number of warnings thrown is above the threshold.",
            kind: .lint
        )
        return StyleViolation(
            ruleDescription: description,
            severity: .error,
            location: Location(file: "", line: 0, character: 0),
            reason: "Number of warnings exceeded threshold of \(threshold).")
    }

    private static func applyLeniency(options: LintOrAnalyzeOptions, violations: [StyleViolation]) -> [StyleViolation] {
        switch (options.lenient, options.strict) {
        case (false, false):
            return violations

        case (true, false):
            return violations.map {
                if $0.severity == .error {
                    return $0.with(severity: .warning)
                } else {
                    return $0
                }
            }

        case (false, true):
            return violations.map {
                if $0.severity == .warning {
                    return $0.with(severity: .error)
                } else {
                    return $0
                }
            }

        case (true, true):
            queuedFatalError("Invalid command line options: 'lenient' and 'strict' are mutually exclusive.")
        }
    }
}

struct LintOrAnalyzeOptions {
    let mode: LintOrAnalyzeMode
    let paths: [String]
    let useSTDIN: Bool
    let configurationFile: String
    let strict: Bool
    let lenient: Bool
    let forceExclude: Bool
    let useExcludingByPrefix: Bool
    let useScriptInputFiles: Bool
    let benchmark: Bool
    let reporter: String
    let quiet: Bool
    let cachePath: String
    let ignoreCache: Bool
    let enableAllRules: Bool
    let useBaseline: Bool
    let autocorrect: Bool
    let compilerLogPath: String
    let compileCommands: String

    init(_ options: LintOptions) {
        mode = .lint
        paths = options.paths
        useSTDIN = options.useSTDIN
        configurationFile = options.configurationFile
        strict = options.strict
        lenient = options.lenient
        forceExclude = options.forceExclude
        useExcludingByPrefix = options.excludeByPrefix
        useScriptInputFiles = options.useScriptInputFiles
        benchmark = options.benchmark
        reporter = options.reporter
        quiet = options.quiet
        cachePath = options.cachePath
        ignoreCache = options.ignoreCache
        enableAllRules = options.enableAllRules
        useBaseline = options.useBaseline
        autocorrect = false
        compilerLogPath = ""
        compileCommands = ""
    }

    init(_ options: AnalyzeOptions) {
        mode = .analyze
        paths = options.paths
        useSTDIN = false
        configurationFile = options.configurationFile
        strict = options.strict
        lenient = options.lenient
        forceExclude = options.forceExclude
        useExcludingByPrefix = options.excludeByPrefix
        useScriptInputFiles = options.useScriptInputFiles
        benchmark = options.benchmark
        reporter = options.reporter
        quiet = options.quiet
        cachePath = ""
        ignoreCache = true
        enableAllRules = options.enableAllRules
        useBaseline = false
        autocorrect = options.autocorrect
        compilerLogPath = options.compilerLogPath
        compileCommands = options.compileCommands
    }

    var verb: String {
        if autocorrect {
            return "correcting"
        } else {
            return mode.verb
        }
    }
}
