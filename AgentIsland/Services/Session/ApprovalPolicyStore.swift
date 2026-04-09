//
//  ApprovalPolicyStore.swift
//  Agent Island
//
//  Persists exact-match approval rules for future automatic decisions.
//

import Foundation

struct ApprovalRule: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    let agentType: AgentPlatform
    let toolName: String
    let inputSignature: String
    let policy: ApprovalPolicy
    let createdAt: Date
}

actor ApprovalPolicyStore {
    static let shared = ApprovalPolicyStore()
    nonisolated static let rulesDidChangeNotification = Notification.Name("ApprovalPolicyStore.rulesDidChange")

    private let fileManager: FileManager
    private let policiesURL: URL
    private var cachedRules: [ApprovalRule]?

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.policiesURL = AppPathResolver.approvalPoliciesFileURL
        try? AppPathResolver.migrateLegacyRuntimeIfNeeded(fileManager: fileManager)
    }

    func matchingPolicy(for event: HookEvent) async -> ApprovalPolicy? {
        guard let tool = event.tool,
              let signature = Self.signature(for: event.toolInput) else {
            return nil
        }

        let rules = await loadRules()
        return rules.last(where: {
            $0.agentType == event.agentType &&
            $0.toolName == tool &&
            $0.inputSignature == signature
        })?.policy
    }

    func matchingPolicy(for event: UnifiedAgentEvent) async -> ApprovalPolicy? {
        guard event.kind == .permissionRequested,
              let tool = event.payload.tool,
              let signature = Self.signature(for: tool.arguments) else {
            return nil
        }

        let rules = await loadRules()
        return rules.last(where: {
            $0.agentType == event.provider &&
            $0.toolName == tool.toolName &&
            $0.inputSignature == signature
        })?.policy
    }

    func allRules() async -> [ApprovalRule] {
        await loadRules().sorted { lhs, rhs in
            lhs.createdAt > rhs.createdAt
        }
    }

    func removeRule(id: UUID) async {
        var rules = await loadRules()
        rules.removeAll { $0.id == id }
        await saveRules(rules)
    }

    func persistRule(for session: SessionState, permission: PermissionContext, policy: ApprovalPolicy) async {
        guard let signature = Self.signature(for: permission.toolInput) else {
            return
        }

        var rules = await loadRules()
        rules.removeAll {
            $0.agentType == session.agentType &&
            $0.toolName == permission.toolName &&
            $0.inputSignature == signature
        }
        rules.append(ApprovalRule(
            id: UUID(),
            agentType: session.agentType,
            toolName: permission.toolName,
            inputSignature: signature,
            policy: policy,
            createdAt: Date()
        ))
        await saveRules(rules)
    }

    private func loadRules() async -> [ApprovalRule] {
        if let cachedRules {
            return cachedRules
        }

        guard let data = try? Data(contentsOf: policiesURL),
              let rules = try? JSONDecoder().decode([ApprovalRule].self, from: data) else {
            cachedRules = []
            return []
        }

        cachedRules = rules
        return rules
    }

    private func saveRules(_ rules: [ApprovalRule]) async {
        cachedRules = rules

        let directory = policiesURL.deletingLastPathComponent()
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        guard let data = try? JSONEncoder().encode(rules) else {
            return
        }

        try? data.write(to: policiesURL, options: .atomic)
        await MainActor.run {
            NotificationCenter.default.post(name: Self.rulesDidChangeNotification, object: nil)
        }
        await AgentHookPluginManager.shared.refreshBridgeProfiles(using: rules)
    }

    private static func signature(for toolInput: [String: AnyCodable]?) -> String? {
        guard let toolInput, !toolInput.isEmpty else {
            return nil
        }

        let normalized = normalize(toolInput.mapValues(\.value))
        guard JSONSerialization.isValidJSONObject(normalized),
              let data = try? JSONSerialization.data(withJSONObject: normalized, options: [.sortedKeys]),
              let signature = String(data: data, encoding: .utf8),
              !signature.isEmpty else {
            return nil
        }

        return signature
    }

    private static func signature(for toolInput: [String: String]) -> String? {
        guard !toolInput.isEmpty else {
            return nil
        }

        let normalized = normalize(toolInput)
        guard JSONSerialization.isValidJSONObject(normalized),
              let data = try? JSONSerialization.data(withJSONObject: normalized, options: [.sortedKeys]),
              let signature = String(data: data, encoding: .utf8),
              !signature.isEmpty else {
            return nil
        }

        return signature
    }

    private static func normalize(_ value: Any) -> Any {
        switch value {
        case let dict as [String: Any]:
            return dict
                .keys
                .sorted()
                .reduce(into: [String: Any]()) { partialResult, key in
                    partialResult[key] = normalize(dict[key] as Any)
                }
        case let array as [Any]:
            return array.map(normalize)
        case let string as String:
            return string
        case let int as Int:
            return int
        case let double as Double:
            return double
        case let bool as Bool:
            return bool
        case is NSNull:
            return NSNull()
        default:
            return String(describing: value)
        }
    }
}
