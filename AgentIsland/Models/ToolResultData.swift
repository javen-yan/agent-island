//
//  ToolResultData.swift
//  Agent Island
//
//  Structured models for all Claude Code tool results
//

import Foundation

// MARK: - Tool Result Wrapper

/// Structured tool result data - parsed from JSONL tool_result blocks
enum ToolResultData: Equatable, Sendable {
    case read(ReadResult)
    case edit(EditResult)
    case write(WriteResult)
    case bash(BashResult)
    case grep(GrepResult)
    case glob(GlobResult)
    case todoWrite(TodoWriteResult)
    case task(TaskResult)
    case webFetch(WebFetchResult)
    case webSearch(WebSearchResult)
    case askUserQuestion(AskUserQuestionResult)
    case bashOutput(BashOutputResult)
    case killShell(KillShellResult)
    case exitPlanMode(ExitPlanModeResult)
    case mcp(MCPResult)
    case generic(GenericResult)
}

enum ToolResultPreview {
    static let maxTextCharacters = 1200
    static let maxCodeCharacters = 2400
    static let maxPatchLines = 10

    static func truncate(_ text: String, limit: Int) -> String {
        guard text.count > limit else { return text }
        let endIndex = text.index(text.startIndex, offsetBy: limit)
        let remaining = text.distance(from: endIndex, to: text.endIndex)
        return String(text[..<endIndex]) + "\n... (\(remaining) more characters)"
    }

    static func truncatePatchLines(_ patches: [PatchHunk]?) -> [PatchHunk]? {
        guard let patches else { return nil }
        return patches.map { patch in
            PatchHunk(
                oldStart: patch.oldStart,
                oldLines: patch.oldLines,
                newStart: patch.newStart,
                newLines: patch.newLines,
                lines: Array(patch.lines.prefix(maxPatchLines))
            )
        }
    }
}

// MARK: - Read Tool Result

struct ReadResult: Equatable, Sendable {
    let filePath: String
    let content: String
    let numLines: Int
    let startLine: Int
    let totalLines: Int

    var filename: String {
        URL(fileURLWithPath: filePath).lastPathComponent
    }
}

// MARK: - Edit Tool Result

struct EditResult: Equatable, Sendable {
    let filePath: String
    let oldString: String
    let newString: String
    let replaceAll: Bool
    let userModified: Bool
    let structuredPatch: [PatchHunk]?

    var filename: String {
        URL(fileURLWithPath: filePath).lastPathComponent
    }
}

struct PatchHunk: Equatable, Sendable {
    let oldStart: Int
    let oldLines: Int
    let newStart: Int
    let newLines: Int
    let lines: [String]
}

// MARK: - Write Tool Result

struct WriteResult: Equatable, Sendable {
    enum WriteType: String, Equatable, Sendable {
        case create
        case overwrite
    }

    let type: WriteType
    let filePath: String
    let content: String
    let structuredPatch: [PatchHunk]?

    var filename: String {
        URL(fileURLWithPath: filePath).lastPathComponent
    }
}

// MARK: - Bash Tool Result

struct BashResult: Equatable, Sendable {
    let stdout: String
    let stderr: String
    let interrupted: Bool
    let isImage: Bool
    let returnCodeInterpretation: String?
    let backgroundTaskId: String?

    var hasOutput: Bool {
        !stdout.isEmpty || !stderr.isEmpty
    }

    var displayOutput: String {
        if !stdout.isEmpty {
            return stdout
        }
        if !stderr.isEmpty {
            return stderr
        }
        return "(No content)"
    }
}

// MARK: - Grep Tool Result

struct GrepResult: Equatable, Sendable {
    enum Mode: String, Equatable, Sendable {
        case filesWithMatches = "files_with_matches"
        case content
        case count
    }

    let mode: Mode
    let filenames: [String]
    let numFiles: Int
    let content: String?
    let numLines: Int?
    let appliedLimit: Int?
}

// MARK: - Glob Tool Result

struct GlobResult: Equatable, Sendable {
    let filenames: [String]
    let durationMs: Int
    let numFiles: Int
    let truncated: Bool
}

// MARK: - TodoWrite Tool Result

struct TodoWriteResult: Equatable, Sendable {
    let oldTodos: [TodoItem]
    let newTodos: [TodoItem]
}

struct TodoItem: Equatable, Sendable {
    let content: String
    let status: String // "pending", "in_progress", "completed"
    let activeForm: String?
}

// MARK: - Task (Agent) Tool Result

struct TaskResult: Equatable, Sendable {
    let agentId: String
    let status: String
    let content: String
    let prompt: String?
    let totalDurationMs: Int?
    let totalTokens: Int?
    let totalToolUseCount: Int?
}

// MARK: - WebFetch Tool Result

struct WebFetchResult: Equatable, Sendable {
    let url: String
    let code: Int
    let codeText: String
    let bytes: Int
    let durationMs: Int
    let result: String
}

// MARK: - WebSearch Tool Result

struct WebSearchResult: Equatable, Sendable {
    let query: String
    let durationSeconds: Double
    let results: [SearchResultItem]
}

struct SearchResultItem: Equatable, Sendable {
    let title: String
    let url: String
    let snippet: String
}

// MARK: - AskUserQuestion Tool Result

struct AskUserQuestionResult: Equatable, Sendable {
    let questions: [QuestionItem]
    let answers: [String: String]
}

struct QuestionItem: Equatable, Sendable {
    let question: String
    let header: String?
    let options: [QuestionOption]
}

struct QuestionOption: Equatable, Sendable {
    let label: String
    let description: String?
}

// MARK: - BashOutput Tool Result

struct BashOutputResult: Equatable, Sendable {
    let shellId: String
    let status: String
    let stdout: String
    let stderr: String
    let stdoutLines: Int
    let stderrLines: Int
    let exitCode: Int?
    let command: String?
    let timestamp: String?
}

// MARK: - KillShell Tool Result

struct KillShellResult: Equatable, Sendable {
    let shellId: String
    let message: String
}

// MARK: - ExitPlanMode Tool Result

struct ExitPlanModeResult: Equatable, Sendable {
    let filePath: String?
    let plan: String?
    let isAgent: Bool
}

// MARK: - MCP Tool Result (Generic)

struct MCPResult: Equatable, @unchecked Sendable {
    let serverName: String
    let toolName: String
    let rawResult: [String: Any]

    static func == (lhs: MCPResult, rhs: MCPResult) -> Bool {
        lhs.serverName == rhs.serverName &&
        lhs.toolName == rhs.toolName &&
        NSDictionary(dictionary: lhs.rawResult).isEqual(to: rhs.rawResult)
    }
}

// MARK: - Generic Tool Result (Fallback)

struct GenericResult: Equatable, @unchecked Sendable {
    let rawContent: String?
    let rawData: [String: Any]?

    static func == (lhs: GenericResult, rhs: GenericResult) -> Bool {
        lhs.rawContent == rhs.rawContent
    }
}

extension ToolResultData {
    nonisolated var previewVersion: ToolResultData {
        switch self {
        case .read(let result):
            return .read(ReadResult(
                filePath: result.filePath,
                content: ToolResultPreview.truncate(result.content, limit: ToolResultPreview.maxCodeCharacters),
                numLines: result.numLines,
                startLine: result.startLine,
                totalLines: result.totalLines
            ))
        case .edit(let result):
            return .edit(EditResult(
                filePath: result.filePath,
                oldString: ToolResultPreview.truncate(result.oldString, limit: ToolResultPreview.maxCodeCharacters),
                newString: ToolResultPreview.truncate(result.newString, limit: ToolResultPreview.maxCodeCharacters),
                replaceAll: result.replaceAll,
                userModified: result.userModified,
                structuredPatch: ToolResultPreview.truncatePatchLines(result.structuredPatch)
            ))
        case .write(let result):
            return .write(WriteResult(
                type: result.type,
                filePath: result.filePath,
                content: ToolResultPreview.truncate(result.content, limit: ToolResultPreview.maxCodeCharacters),
                structuredPatch: ToolResultPreview.truncatePatchLines(result.structuredPatch)
            ))
        case .bash(let result):
            return .bash(BashResult(
                stdout: ToolResultPreview.truncate(result.stdout, limit: ToolResultPreview.maxCodeCharacters),
                stderr: ToolResultPreview.truncate(result.stderr, limit: ToolResultPreview.maxTextCharacters),
                interrupted: result.interrupted,
                isImage: result.isImage,
                returnCodeInterpretation: result.returnCodeInterpretation,
                backgroundTaskId: result.backgroundTaskId
            ))
        case .grep(let result):
            return .grep(GrepResult(
                mode: result.mode,
                filenames: result.filenames,
                numFiles: result.numFiles,
                content: result.content.map { ToolResultPreview.truncate($0, limit: ToolResultPreview.maxCodeCharacters) },
                numLines: result.numLines,
                appliedLimit: result.appliedLimit
            ))
        case .glob:
            return self
        case .todoWrite:
            return self
        case .task(let result):
            return .task(TaskResult(
                agentId: result.agentId,
                status: result.status,
                content: ToolResultPreview.truncate(result.content, limit: ToolResultPreview.maxTextCharacters),
                prompt: result.prompt.map { ToolResultPreview.truncate($0, limit: ToolResultPreview.maxTextCharacters) },
                totalDurationMs: result.totalDurationMs,
                totalTokens: result.totalTokens,
                totalToolUseCount: result.totalToolUseCount
            ))
        case .webFetch(let result):
            return .webFetch(WebFetchResult(
                url: result.url,
                code: result.code,
                codeText: result.codeText,
                bytes: result.bytes,
                durationMs: result.durationMs,
                result: ToolResultPreview.truncate(result.result, limit: ToolResultPreview.maxTextCharacters)
            ))
        case .webSearch:
            return self
        case .askUserQuestion:
            return self
        case .bashOutput(let result):
            return .bashOutput(BashOutputResult(
                shellId: result.shellId,
                status: result.status,
                stdout: ToolResultPreview.truncate(result.stdout, limit: ToolResultPreview.maxCodeCharacters),
                stderr: ToolResultPreview.truncate(result.stderr, limit: ToolResultPreview.maxTextCharacters),
                stdoutLines: result.stdoutLines,
                stderrLines: result.stderrLines,
                exitCode: result.exitCode,
                command: result.command.map { ToolResultPreview.truncate($0, limit: ToolResultPreview.maxTextCharacters) },
                timestamp: result.timestamp
            ))
        case .killShell:
            return self
        case .exitPlanMode(let result):
            return .exitPlanMode(ExitPlanModeResult(
                filePath: result.filePath,
                plan: result.plan.map { ToolResultPreview.truncate($0, limit: ToolResultPreview.maxTextCharacters) },
                isAgent: result.isAgent
            ))
        case .mcp(let result):
            let previewResult = result.rawResult.mapValues { value in
                String(describing: value).count > ToolResultPreview.maxTextCharacters
                    ? ToolResultPreview.truncate(String(describing: value), limit: ToolResultPreview.maxTextCharacters)
                    : value
            }
            return .mcp(MCPResult(serverName: result.serverName, toolName: result.toolName, rawResult: previewResult))
        case .generic(let result):
            return .generic(GenericResult(
                rawContent: result.rawContent.map { ToolResultPreview.truncate($0, limit: ToolResultPreview.maxTextCharacters) },
                rawData: result.rawData
            ))
        }
    }
}

// MARK: - Tool Status Display

struct ToolStatusDisplay {
    let text: String
    let isRunning: Bool

    /// Get running status text for a tool
    static func running(for toolName: String, input: [String: String]) -> ToolStatusDisplay {
        switch toolName {
        case "Read":
            return ToolStatusDisplay(text: "Reading...", isRunning: true)
        case "Edit":
            return ToolStatusDisplay(text: "Editing...", isRunning: true)
        case "Write":
            return ToolStatusDisplay(text: "Writing...", isRunning: true)
        case "Bash":
            if let desc = input["description"], !desc.isEmpty {
                return ToolStatusDisplay(text: desc, isRunning: true)
            }
            return ToolStatusDisplay(text: "Running...", isRunning: true)
        case "Grep", "Glob":
            if let pattern = input["pattern"] {
                return ToolStatusDisplay(text: "Searching: \(pattern)", isRunning: true)
            }
            return ToolStatusDisplay(text: "Searching...", isRunning: true)
        case "WebSearch":
            if let query = input["query"] {
                return ToolStatusDisplay(text: "Searching: \(query)", isRunning: true)
            }
            return ToolStatusDisplay(text: "Searching...", isRunning: true)
        case "WebFetch":
            return ToolStatusDisplay(text: "Fetching...", isRunning: true)
        case "Task":
            if let desc = input["description"], !desc.isEmpty {
                return ToolStatusDisplay(text: desc, isRunning: true)
            }
            return ToolStatusDisplay(text: "Running agent...", isRunning: true)
        case "TodoWrite":
            return ToolStatusDisplay(text: "Updating todos...", isRunning: true)
        case "EnterPlanMode":
            return ToolStatusDisplay(text: "Entering plan mode...", isRunning: true)
        case "ExitPlanMode":
            return ToolStatusDisplay(text: "Exiting plan mode...", isRunning: true)
        default:
            return ToolStatusDisplay(text: "Running...", isRunning: true)
        }
    }

    /// Get completed status text for a tool result
    static func completed(for toolName: String, result: ToolResultData?) -> ToolStatusDisplay {
        guard let result = result else {
            return ToolStatusDisplay(text: "Completed", isRunning: false)
        }

        switch result {
        case .read(let r):
            let lineText = r.totalLines > r.numLines ? "\(r.numLines)+ lines" : "\(r.numLines) lines"
            return ToolStatusDisplay(text: "Read \(r.filename) (\(lineText))", isRunning: false)

        case .edit(let r):
            return ToolStatusDisplay(text: "Edited \(r.filename)", isRunning: false)

        case .write(let r):
            let action = r.type == .create ? "Created" : "Wrote"
            return ToolStatusDisplay(text: "\(action) \(r.filename)", isRunning: false)

        case .bash(let r):
            if let bgId = r.backgroundTaskId {
                return ToolStatusDisplay(text: "Running in background (\(bgId))", isRunning: false)
            }
            if let interpretation = r.returnCodeInterpretation {
                return ToolStatusDisplay(text: interpretation, isRunning: false)
            }
            return ToolStatusDisplay(text: "Completed", isRunning: false)

        case .grep(let r):
            let fileWord = r.numFiles == 1 ? "file" : "files"
            return ToolStatusDisplay(text: "Found \(r.numFiles) \(fileWord)", isRunning: false)

        case .glob(let r):
            let fileWord = r.numFiles == 1 ? "file" : "files"
            if r.numFiles == 0 {
                return ToolStatusDisplay(text: "No files found", isRunning: false)
            }
            return ToolStatusDisplay(text: "Found \(r.numFiles) \(fileWord)", isRunning: false)

        case .todoWrite:
            return ToolStatusDisplay(text: "Updated todos", isRunning: false)

        case .task(let r):
            return ToolStatusDisplay(text: r.status.capitalized, isRunning: false)

        case .webFetch(let r):
            return ToolStatusDisplay(text: "\(r.code) \(r.codeText)", isRunning: false)

        case .webSearch(let r):
            let time = r.durationSeconds >= 1 ?
                "\(Int(r.durationSeconds))s" :
                "\(Int(r.durationSeconds * 1000))ms"
            let searchWord = r.results.count == 1 ? "search" : "searches"
            return ToolStatusDisplay(text: "Did 1 \(searchWord) in \(time)", isRunning: false)

        case .askUserQuestion:
            return ToolStatusDisplay(text: "Answered", isRunning: false)

        case .bashOutput(let r):
            return ToolStatusDisplay(text: "Status: \(r.status)", isRunning: false)

        case .killShell:
            return ToolStatusDisplay(text: "Terminated", isRunning: false)

        case .exitPlanMode:
            return ToolStatusDisplay(text: "Plan ready", isRunning: false)

        case .mcp:
            return ToolStatusDisplay(text: "Completed", isRunning: false)

        case .generic:
            return ToolStatusDisplay(text: "Completed", isRunning: false)
        }
    }
}
