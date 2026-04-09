//
//  ChatView.swift
//  Agent Island
//
//  Redesigned chat interface with clean visual hierarchy
//

import Combine
import SwiftUI

struct ChatView: View {
    let sessionId: String
    let initialSession: SessionState
    let sessionMonitor: AgentSessionMonitor
    @ObservedObject var viewModel: NotchViewModel
    private let chatFacade: AgentChatFacade

    @State private var inputText: String = ""
    @State private var history: [ChatHistoryItem] = []
    @State private var session: SessionState
    @State private var isLoading: Bool = true
    @State private var hasLoadedOnce: Bool = false
    @State private var shouldScrollToBottom: Bool = false
    @State private var isAutoscrollPaused: Bool = false
    @State private var newMessageCount: Int = 0
    @State private var previousHistoryCount: Int = 0
    @State private var isBottomVisible: Bool = true
    @State private var isInterruptingTurn: Bool = false
    @State private var isTerminatingSession: Bool = false
    @FocusState private var isInputFocused: Bool

    init(
        sessionId: String,
        initialSession: SessionState,
        sessionMonitor: AgentSessionMonitor,
        viewModel: NotchViewModel,
        chatFacade: AgentChatFacade? = nil
    ) {
        self.sessionId = sessionId
        self.initialSession = initialSession
        self.sessionMonitor = sessionMonitor
        self._viewModel = ObservedObject(wrappedValue: viewModel)
        self.chatFacade = chatFacade ?? .shared
        self._session = State(initialValue: initialSession)
        let initialHistory = ChatView.filteredHistoryItems(from: initialSession)
        let alreadyLoaded = !initialHistory.isEmpty
        self._history = State(initialValue: initialHistory)
        self._isLoading = State(initialValue: !alreadyLoaded)
        self._hasLoadedOnce = State(initialValue: alreadyLoaded)
    }

    /// Whether we're waiting for approval
    private var isWaitingForApproval: Bool {
        session.unifiedViewKind == .permissionRequested
    }

    /// Extract the tool name if waiting for approval
    private var approvalTool: String? {
        session.unifiedPendingApprovalEvent?.payload.tool?.toolName ?? session.phase.approvalToolName
    }

    private var usesTerminalApprovalUI: Bool {
        isWaitingForApproval && session.approvalCapability.kind == .terminalOnly
    }

    private var canInterruptTurn: Bool {
        chatFacade.canInterruptTurn(for: session)
            && (session.phase.isActive || session.phase.isWaitingForApproval)
    }

    private var canTerminateSession: Bool {
        chatFacade.canTerminateSession(for: session)
    }

    private var showsCodexTerminalHint: Bool {
        session.agentType.supportsPostTurnFollowUpInIsland
            && approvalTool == nil
            && session.phase == .waitingForInput
            && canSendMessages
    }

    
    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // Header
                chatHeader

                // Messages
                if isLoading {
                    loadingState
                } else if history.isEmpty {
                    emptyState
                } else {
                    messageList
                }

                // Approval bar, interactive prompt, or Input bar
                if let tool = approvalTool {
                    if tool == "AskUserQuestion" {
                        // Interactive tools - show prompt to answer in terminal
                        interactivePromptBar
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .move(edge: .bottom)),
                                removal: .opacity
                            ))
                    } else if usesTerminalApprovalUI {
                        terminalApprovalBar(tool: tool)
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .move(edge: .bottom)),
                                removal: .opacity
                            ))
                    } else {
                        approvalBar(tool: tool)
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .move(edge: .bottom)),
                                removal: .opacity
                            ))
                    }
                } else {
                    VStack(spacing: 0) {
                        if showsCodexTerminalHint {
                            codexTerminalHint
                                .transition(.opacity.combined(with: .move(edge: .bottom)))
                        }

                        inputBar
                            .transition(.opacity)
                    }
                }
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: isWaitingForApproval)
        .animation(nil, value: viewModel.status)
        .task {
            // Skip if already loaded (prevents redundant work on view recreation)
            guard !hasLoadedOnce else { return }
            hasLoadedOnce = true

            // Load in background, show loading state
            sessionMonitor.loadHistory(sessionId: sessionId, cwd: session.cwd)

            withAnimation(.easeOut(duration: 0.2)) {
                isLoading = false
            }
        }
        .onReceive(chatFacade.sessionsPublisher.receive(on: DispatchQueue.main)) { sessions in
            if let updated = sessions.first(where: { $0.sessionId == sessionId }) {
                let newHistory = Self.filteredHistoryItems(from: updated)
                let countChanged = newHistory.count != history.count
                let lastItemChanged = newHistory.last?.id != history.last?.id

                if countChanged || lastItemChanged || newHistory != history {
                    if isAutoscrollPaused && newHistory.count > previousHistoryCount {
                        let addedCount = newHistory.count - previousHistoryCount
                        newMessageCount += addedCount
                        previousHistoryCount = newHistory.count
                    }

                    history = newHistory

                    if !isAutoscrollPaused && countChanged {
                        shouldScrollToBottom = true
                    }

                    // If we have data, skip loading state (handles view recreation)
                    if isLoading && !newHistory.isEmpty {
                        isLoading = false
                    }
                }
                session = updated

                let wasWaiting = isWaitingForApproval
                let isNowProcessing = updated.phase == .processing

                if wasWaiting && isNowProcessing {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        shouldScrollToBottom = true
                    }
                }
            } else if hasLoadedOnce {
                viewModel.exitChat()
            }
        }
        .onChange(of: canSendMessages) { _, canSend in
            // Auto-focus input when tmux messaging becomes available
            if canSend && !isInputFocused {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isInputFocused = true
                }
            }
        }
        .onAppear {
            // Auto-focus input when chat opens and tmux messaging is available
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                if canSendMessages {
                    isInputFocused = true
                }
            }
        }
    }

    // MARK: - Header

    @State private var isHeaderHovered = false

    private var chatHeader: some View {
        Button {
            viewModel.exitChat()
        } label: {
            HStack(spacing: 8) {
                Image(agentIcon: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white.opacity(isHeaderHovered ? 1.0 : 0.6))
                    .frame(width: 24, height: 24)

                Text(session.displayTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white.opacity(isHeaderHovered ? 1.0 : 0.85))
                    .lineLimit(1)

                Spacer()

                if canInterruptTurn {
                    headerControlButton(
                        title: "Esc",
                        isBusy: isInterruptingTurn,
                        action: interruptTurn
                    )
                }

                if canTerminateSession,
                   let exitLabel = session.agentType.terminalControlProfile.exitCommand?.buttonLabel {
                    headerControlButton(
                        title: exitLabel,
                        isBusy: isTerminatingSession,
                        action: terminateSession
                    )
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isHeaderHovered ? Color.white.opacity(0.08) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHeaderHovered = $0 }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.black.opacity(0.2))
        .overlay(alignment: .bottom) {
            LinearGradient(
                colors: [fadeColor.opacity(0.7), fadeColor.opacity(0)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 24)
            .offset(y: 24) // Push below header
            .allowsHitTesting(false)
        }
        .zIndex(1) // Render above message list
    }

    private func headerControlButton(title: String, isBusy: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(isBusy ? "..." : title)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(.white.opacity(0.85))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(Color.white.opacity(0.08))
                        .overlay(
                            Capsule()
                                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                        )
                )
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
    }

    /// Whether the session is currently processing
    private var isProcessing: Bool {
        session.phase == .processing || session.phase == .compacting
    }

    private var showsTerminalApprovalIndicator: Bool {
        usesTerminalApprovalUI
    }

    /// Get the last user message ID for stable text selection per turn
    private var lastUserMessageId: String {
        for item in history.reversed() {
            if case .user = item.type {
                return item.id
            }
        }
        return ""
    }

    // MARK: - Loading State

    private var loadingState: some View {
        VStack(spacing: 8) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .white.opacity(0.4)))
                .scaleEffect(0.8)
            Text(L10n.text(.chatLoadingMessages))
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.4))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(agentIcon: "bubble.left.and.bubble.right")
                .font(.system(size: 24))
                .foregroundColor(.white.opacity(0.2))
            Text(L10n.text(.chatNoMessagesYet))
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.4))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Message List

    /// Background color for fade gradients
    private let fadeColor = Color(red: 0.00, green: 0.00, blue: 0.00)

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 16) {
                    // Invisible anchor at bottom (first due to flip)
                    Color.clear
                        .frame(height: 1)
                        .id("bottom")

                    // Status indicator at bottom (first due to flip)
                    if showsTerminalApprovalIndicator {
                        TerminalApprovalIndicatorView(turnId: lastUserMessageId)
                            .padding(.horizontal, 16)
                            .scaleEffect(x: 1, y: -1)
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .scale(scale: 0.95)).combined(with: .offset(y: -4)),
                                removal: .opacity
                            ))
                    } else if isProcessing {
                        ProcessingIndicatorView(
                            turnId: lastUserMessageId,
                            color: session.agentType.accentColor
                        )
                            .padding(.horizontal, 16)
                            .scaleEffect(x: 1, y: -1)
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .scale(scale: 0.95)).combined(with: .offset(y: -4)),
                                removal: .opacity
                            ))
                    }

                    ForEach(history.reversed()) { item in
                        MessageItemView(item: item, agentDescriptions: session.subagentState.agentDescriptions)
                            .padding(.horizontal, 16)
                            .scaleEffect(x: 1, y: -1)
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .scale(scale: 0.98)),
                                removal: .opacity
                            ))
                    }
                }
                .padding(.top, 20)
                .padding(.bottom, 20)
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isProcessing)
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: showsTerminalApprovalIndicator)
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: history.count)
            }
            .scaleEffect(x: 1, y: -1)
            .onScrollGeometryChange(for: Bool.self) { geometry in
                // Check if we're near the top of the content (which is bottom in inverted view)
                // contentOffset.y near 0 means at bottom, larger means scrolled up
                geometry.contentOffset.y < 50
            } action: { wasAtBottom, isNowAtBottom in
                if wasAtBottom && !isNowAtBottom {
                    // User scrolled away from bottom
                    pauseAutoscroll()
                } else if !wasAtBottom && isNowAtBottom && isAutoscrollPaused {
                    // User scrolled back to bottom
                    resumeAutoscroll()
                }
            }
            .onChange(of: shouldScrollToBottom) { _, shouldScroll in
                if shouldScroll {
                    withAnimation(.easeOut(duration: 0.3)) {
                        // In inverted scroll, use .bottom anchor to scroll to the visual bottom
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                    shouldScrollToBottom = false
                    resumeAutoscroll()
                }
            }
            // New messages indicator overlay
            .overlay(alignment: .bottom) {
                if isAutoscrollPaused && newMessageCount > 0 {
                    NewMessagesIndicator(count: newMessageCount) {
                        withAnimation(.easeOut(duration: 0.3)) {
                            // In inverted scroll, use .bottom anchor to scroll to the visual bottom
                            proxy.scrollTo("bottom", anchor: .bottom)
                        }
                        resumeAutoscroll()
                    }
                    .padding(.bottom, 16)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .bottom)),
                        removal: .opacity
                    ))
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: isAutoscrollPaused && newMessageCount > 0)
        }
    }

    // MARK: - Input Bar

    private var canSendMessages: Bool {
        chatFacade.canSendMessages(for: session)
    }

    private var messagePlaceholder: String {
        if session.agentType.supportsPostTurnFollowUpInIsland && canSendMessages {
            return L10n.text(.chatContinueInTerminal)
        }
        if canSendMessages {
            return L10n.text(.chatMessagePlaceholder, session.agentType.displayName)
        }
        return L10n.text(.chatEnableMessagingPlaceholder, session.agentType.displayName)
    }

    private var codexTerminalHint: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(TerminalColors.amber)
                .frame(width: 7, height: 7)

            Text(L10n.text(.chatContinueInTerminal))
                .font(.footnote.weight(.medium))
                .foregroundColor(.white.opacity(0.72))

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.04))
    }

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField(messagePlaceholder, text: $inputText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundColor(canSendMessages ? .white : .white.opacity(0.4))
                .focused($isInputFocused)
                .disabled(!canSendMessages)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color.white.opacity(canSendMessages ? 0.08 : 0.04))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                        )
                )
                .onSubmit {
                    sendMessage()
                }

            Button {
                sendMessage()
            } label: {
                Image(agentIcon: "arrow.up.circle.fill")
                    .font(.system(size: 28))
                    .foregroundColor(!canSendMessages || inputText.isEmpty ? .white.opacity(0.2) : .white.opacity(0.9))
            }
            .buttonStyle(.plain)
            .disabled(!canSendMessages || inputText.isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.black.opacity(0.2))
        .overlay(alignment: .top) {
            LinearGradient(
                colors: [fadeColor.opacity(0), fadeColor.opacity(0.7)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 24)
            .offset(y: -24) // Push above input bar
            .allowsHitTesting(false)
        }
        .zIndex(1) // Render above message list
    }

    // MARK: - Approval Bar

    private func approvalBar(tool: String) -> some View {
        ChatApprovalBar(
            tool: tool,
            toolInput: session.pendingToolInput,
            agentType: session.agentType,
            supportedActions: session.approvalCapability.supportedActions,
            isInTerminalMultiplexer: session.isInTerminalMultiplexer,
            permissionSourceDescription: session.permissionSourceDescription,
            onAction: { action in handleApprovalAction(action) }
        )
    }

    private func terminalApprovalBar(tool: String) -> some View {
        ChatTerminalApprovalBar(
            tool: tool,
            toolInput: session.pendingToolInput,
            agentName: session.agentType.displayName,
            isInTerminalMultiplexer: session.isInTerminalMultiplexer
        )
    }

    // MARK: - Interactive Prompt Bar

    /// Bar for interactive tools like AskUserQuestion that need terminal input
    private var interactivePromptBar: some View {
        ChatInteractivePromptBar(
            agentName: session.agentType.displayName,
            isInTerminalMultiplexer: session.isInTerminalMultiplexer
        )
    }

    // MARK: - Autoscroll Management

    /// Pause autoscroll (user scrolled away from bottom)
    private func pauseAutoscroll() {
        isAutoscrollPaused = true
        previousHistoryCount = history.count
    }

    /// Resume autoscroll and reset new message count
    private func resumeAutoscroll() {
        isAutoscrollPaused = false
        newMessageCount = 0
        previousHistoryCount = history.count
    }

    // MARK: - Actions

    private func executeApprovalPolicy(_ policy: ApprovalPolicy) {
        sessionMonitor.executeApprovalPolicy(sessionId: sessionId, policy: policy)
        viewModel.notchClose()
    }

    private func handleApprovalAction(_ action: ApprovalAction) {
        switch action {
        case .deny:
            executeApprovalPolicy(.deny)
        case .allowOnce:
            executeApprovalPolicy(.allowOnce)
        case .allowAlways:
            executeApprovalPolicy(.allowAlways)
        case .autoExecute:
            executeApprovalPolicy(.autoExecute)
        }
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        inputText = ""

        // Resume autoscroll when user sends a message
        resumeAutoscroll()
        shouldScrollToBottom = true

        // Don't add to history here - it will be synced from JSONL when UserPromptSubmit event fires
        Task {
            await sendToSession(text)
        }
    }

    private func sendToSession(_ text: String) async {
        let sent = await chatFacade.sendMessage(text, for: session)
        if !sent {
            await MainActor.run {
                inputText = text
            }
        }
    }

    private func interruptTurn() {
        guard !isInterruptingTurn else { return }

        isInterruptingTurn = true
        Task {
            _ = await chatFacade.interruptTurn(for: session)
            await MainActor.run {
                isInterruptingTurn = false
            }
        }
    }

    private func terminateSession() {
        guard !isTerminatingSession else { return }

        isTerminatingSession = true
        Task {
            _ = await chatFacade.terminateSession(for: session)
            await MainActor.run {
                isTerminatingSession = false
            }
        }
    }

    private static func filteredHistoryItems(from session: SessionState) -> [ChatHistoryItem] {
        var subagentToolIds = Set<String>()
        for item in session.chatItems {
            if case .toolCall(let tool) = item.type, tool.name == "Task" {
                for subagentTool in tool.subagentTools {
                    subagentToolIds.insert(subagentTool.id)
                }
            }
        }

        let filteredItems = session.chatItems.filter { !subagentToolIds.contains($0.id) }
        let retainedCount = AppSettings.chatHistoryRetentionLimit
        if filteredItems.count <= retainedCount {
            return filteredItems
        }
        return Array(filteredItems.suffix(retainedCount))
    }
}

// MARK: - Message Item View

struct MessageItemView: View {
    let item: ChatHistoryItem
    let agentDescriptions: [String: String]

    var body: some View {
        switch item.type {
        case .user(let text):
            UserMessageView(text: text)
        case .assistant(let text):
            AssistantMessageView(text: text)
        case .toolCall(let tool):
            ToolCallView(tool: tool, agentDescriptions: agentDescriptions)
        case .thinking(let text):
            ThinkingView(text: text)
        case .interrupted:
            InterruptedMessageView()
        }
    }
}

// MARK: - User Message

struct UserMessageView: View {
    let text: String

    var body: some View {
        HStack {
            Spacer(minLength: 60)

            MarkdownText(text, color: .white, fontSize: 13)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 18)
                        .fill(Color.white.opacity(0.15))
                )
        }
    }
}

// MARK: - Assistant Message

struct AssistantMessageView: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            // White dot indicator
            Circle()
                .fill(Color.white.opacity(0.6))
                .frame(width: 6, height: 6)
                .padding(.top, 5)

            MarkdownText(text, color: .white.opacity(0.9), fontSize: 13)

            Spacer(minLength: 60)
        }
    }
}

// MARK: - Processing Indicator

struct ProcessingIndicatorView: View {
    private let baseTexts = [
        L10n.text(.chatProcessing),
        L10n.text(.chatWorking)
    ]
    private let color: Color
    private let baseText: String

    @State private var dotCount: Int = 1
    private let timer = Timer.publish(every: 0.4, on: .main, in: .common).autoconnect()

    /// Use a turnId to select text consistently per user turn
    init(turnId: String = "", color: Color = TerminalColors.claude) {
        // Use hash of turnId to pick base text consistently for this turn
        let index = abs(turnId.hashValue) % baseTexts.count
        baseText = baseTexts[index]
        self.color = color
    }

    private var dots: String {
        String(repeating: ".", count: dotCount)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            ProcessingSpinner(color: color)
                .frame(width: 6)

            Text(baseText + dots)
                .font(.system(size: 13))
                .foregroundColor(color)

            Spacer()
        }
        .onReceive(timer) { _ in
            dotCount = (dotCount % 3) + 1
        }
    }
}

struct TerminalApprovalIndicatorView: View {
    private let color = TerminalColors.amber
    private let baseText = L10n.text(.chatWaitingForConfirmationInTerminal)

    @State private var dotCount: Int = 1
    private let timer = Timer.publish(every: 0.4, on: .main, in: .common).autoconnect()

    init(turnId: String = "") {
        _ = turnId
    }

    private var dots: String {
        String(repeating: ".", count: dotCount)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            ProcessingSpinner(color: TerminalColors.amber)
                .frame(width: 6)

            Text(baseText + dots)
                .font(.system(size: 13))
                .foregroundColor(color)

            Spacer()
        }
        .onReceive(timer) { _ in
            dotCount = (dotCount % 3) + 1
        }
    }
}

// MARK: - Tool Call View

struct ToolCallView: View {
    let tool: ToolCallItem
    let agentDescriptions: [String: String]

    @State private var pulseOpacity: Double = 0.6
    @State private var isExpanded: Bool = false
    @State private var isHovering: Bool = false

    private var statusColor: Color {
        switch tool.unifiedKind {
        case .toolStarted:
            return Color.white
        case .permissionRequested:
            return Color.orange
        case .toolCompleted:
            return Color.green
        case .toolFailed:
            return Color.red
        default:
            return Color.white.opacity(0.6)
        }
    }

    private var textColor: Color {
        switch tool.unifiedKind {
        case .toolStarted:
            return .white.opacity(0.6)
        case .permissionRequested:
            return Color.orange.opacity(0.9)
        case .toolCompleted:
            return .white.opacity(0.7)
        case .toolFailed:
            return Color.red.opacity(0.8)
        default:
            return .white.opacity(0.6)
        }
    }

    private var hasResult: Bool {
        tool.result != nil || tool.structuredResult != nil
    }

    /// Whether the tool can be expanded (has result, NOT Task tools, NOT Edit tools)
    private var canExpand: Bool {
        tool.name != "Task" && tool.name != "Edit" && hasResult
    }

    private var showContent: Bool {
        tool.name == "Edit" || isExpanded
    }

    private var agentDescription: String? {
        guard tool.name == "AgentOutputTool",
              let agentId = tool.input["agentId"] else {
            return nil
        }
        return agentDescriptions[agentId]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle()
                    .fill(statusColor.opacity(tool.unifiedKind == .toolStarted || tool.unifiedKind == .permissionRequested ? pulseOpacity : 0.6))
                    .frame(width: 6, height: 6)
                    .id(tool.status)  // Forces view recreation, cancelling repeatForever animation
                    .onAppear {
                        if tool.unifiedKind == .toolStarted || tool.unifiedKind == .permissionRequested {
                            startPulsing()
                        }
                    }

                // Tool name (formatted for MCP tools)
                Text(MCPToolFormatter.formatToolName(tool.name))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(textColor)
                    .fixedSize()

                if tool.name == "Task" && !tool.subagentTools.isEmpty {
                    let taskDesc = tool.input["description"] ?? L10n.text(.chatRunningAgent)
                    Text(L10n.text(.chatTaskToolsSummary, taskDesc, tool.subagentTools.count))
                        .font(.system(size: 11))
                        .foregroundColor(textColor.opacity(0.7))
                        .lineLimit(1)
                        .truncationMode(.tail)
                } else if tool.name == "AgentOutputTool", let desc = agentDescription {
                    let blocking = tool.input["block"] == "true"
                    Text(blocking ? L10n.text(.chatWaitingPrefix, desc) : desc)
                        .font(.system(size: 11))
                        .foregroundColor(textColor.opacity(0.7))
                        .lineLimit(1)
                        .truncationMode(.tail)
                } else if MCPToolFormatter.isMCPTool(tool.name) && !tool.input.isEmpty {
                    Text(MCPToolFormatter.formatArgs(tool.input))
                        .font(.system(size: 11))
                        .foregroundColor(textColor.opacity(0.7))
                        .lineLimit(1)
                        .truncationMode(.tail)
                } else {
                    Text(tool.unifiedStatusText)
                        .font(.system(size: 11))
                        .foregroundColor(textColor.opacity(0.7))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Spacer()

                // Expand indicator (only for expandable tools)
                if canExpand && tool.unifiedKind != .toolStarted && tool.unifiedKind != .permissionRequested {
                    Image(agentIcon: "chevron.right")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.white.opacity(0.3))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isExpanded)
                }
            }

            // Subagent tools list (for Task tools)
            if tool.name == "Task" && !tool.subagentTools.isEmpty {
                SubagentToolsList(tools: tool.subagentTools)
                    .padding(.leading, 12)
                    .padding(.top, 2)
            }

            // Result content (Edit always shows, others when expanded)
            // Edit tools bypass hasResult check - fallback in ToolResultContent renders from input params
            if showContent && tool.unifiedKind != .toolStarted && tool.name != "Task" && (hasResult || tool.name == "Edit") {
                ToolResultContent(tool: tool)
                    .padding(.leading, 12)
                    .padding(.top, 4)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // Edit tools show diff from input even while running
            if tool.name == "Edit" && tool.status == .running {
                EditInputDiffView(input: tool.input)
                    .padding(.leading, 12)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(canExpand && isHovering ? Color.white.opacity(0.05) : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
        }
        .onTapGesture {
            if canExpand {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                    isExpanded.toggle()
                }
            }
        }
        .animation(.easeOut(duration: 0.15), value: isHovering)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isExpanded)
    }

    private func startPulsing() {
        withAnimation(
            .easeInOut(duration: 0.6)
            .repeatForever(autoreverses: true)
        ) {
            pulseOpacity = 0.15
        }
    }
}

// MARK: - Subagent Views

/// List of subagent tools (shown during Task execution)
struct SubagentToolsList: View {
    let tools: [SubagentToolCall]

    /// Number of hidden tools (all except last 2)
    private var hiddenCount: Int {
        max(0, tools.count - 2)
    }

    /// Recent tools to show (last 2, regardless of status)
    private var recentTools: [SubagentToolCall] {
        Array(tools.suffix(2))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Show count of older hidden tools at top
            if hiddenCount > 0 {
                Text(L10n.text(.chatMoreToolUses, hiddenCount))
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.4))
            }

            // Show last 2 tools (most recent activity)
            ForEach(recentTools) { tool in
                SubagentToolRow(tool: tool)
            }
        }
    }
}

/// Single subagent tool row
struct SubagentToolRow: View {
    let tool: SubagentToolCall

    @State private var dotOpacity: Double = 0.5

    private var statusColor: Color {
        tool.unifiedStatusColor
    }

    /// Get status text using the same logic as regular tools
    private var statusText: String {
        if tool.status == .interrupted {
            return L10n.text(.chatInterrupted)
        } else if tool.status == .running {
            return ToolStatusDisplay.running(for: tool.name, input: tool.input).text
        } else {
            // For completed subagent tools, we don't have the result data
            // so use a simple display based on tool name and input
            return ToolStatusDisplay.running(for: tool.name, input: tool.input).text
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            // Status dot
            Circle()
                .fill(statusColor.opacity(tool.unifiedKind == .agentSubtaskStarted ? dotOpacity : 0.6))
                .frame(width: 4, height: 4)
                .id(tool.status)  // Forces view recreation, cancelling repeatForever animation
                .onAppear {
                    if tool.unifiedKind == .agentSubtaskStarted {
                        withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
                            dotOpacity = 0.2
                        }
                    }
                }

            // Tool name
            Text(tool.name)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.white.opacity(0.6))

            // Status text (same format as regular tools)
            Text(statusText)
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.5))
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

/// Summary of subagent tools (shown when Task is expanded after completion)
struct SubagentToolsSummary: View {
    let tools: [SubagentToolCall]

    private var toolCounts: [(String, Int)] {
        var counts: [String: Int] = [:]
        for tool in tools {
            counts[tool.name, default: 0] += 1
        }
        return counts.sorted { $0.value > $1.value }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n.text(.chatSubagentUsedTools, tools.count))
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.white.opacity(0.5))

            HStack(spacing: 8) {
                ForEach(toolCounts.prefix(5), id: \.0) { name, count in
                    HStack(spacing: 2) {
                        Text(name)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.white.opacity(0.4))
                        Text("×\(count)")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.white.opacity(0.3))
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.white.opacity(0.03))
        )
    }
}

// MARK: - Thinking View

struct ThinkingView: View {
    let text: String

    @State private var isExpanded = false

    private var canExpand: Bool {
        text.count > 80
    }

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Circle()
                .fill(Color.gray.opacity(0.5))
                .frame(width: 6, height: 6)
                .padding(.top, 4)

            Text(isExpanded ? text : String(text.prefix(80)) + (canExpand ? "..." : ""))
                .font(.system(size: 11))
                .foregroundColor(.gray)
                .italic()
                .lineLimit(isExpanded ? nil : 1)
                .multilineTextAlignment(.leading)

            Spacer()

            if canExpand {
                Image(agentIcon: "chevron.right")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.gray.opacity(0.5))
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .padding(.top, 3)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if canExpand {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                    isExpanded.toggle()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
    }
}

// MARK: - Interrupted Message

struct InterruptedMessageView: View {
    var body: some View {
        HStack {
            Text(L10n.text(.chatInterrupted))
                .font(.system(size: 13))
                .foregroundColor(.red)
            Spacer()
        }
    }
}

// MARK: - Chat Interactive Prompt Bar

/// Bar for interactive tools like AskUserQuestion that need terminal input
struct ChatInteractivePromptBar: View {
    let agentName: String
    let isInTerminalMultiplexer: Bool

    @State private var showContent = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(agentIcon: "bubble.left.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.cyan)
                    Text(L10n.text(.asksSuffix, agentName))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.cyan)
                }

                HStack(alignment: .top, spacing: 10) {
                    Text(MCPToolFormatter.formatToolName("AskUserQuestion"))
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundColor(TerminalColors.amber)
                        .fixedSize()
                    Text(
                        isInTerminalMultiplexer
                            ? L10n.text(.chatNeedsInputInTerminal, agentName)
                            : L10n.text(.chatTerminalUnavailable)
                    )
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.75))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .opacity(showContent ? 1 : 0)
            .offset(x: showContent ? 0 : -10)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.cyan.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.cyan.opacity(0.14), lineWidth: 1)
                )
        )
        .onAppear {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7).delay(0.05)) {
                showContent = true
            }
        }
    }
}

// MARK: - Chat Approval Bar

/// Approval bar for the chat view with animated buttons
struct ChatApprovalBar: View {
    let tool: String
    let toolInput: String?
    let agentType: AgentPlatform
    let supportedActions: [ApprovalAction]
    let isInTerminalMultiplexer: Bool
    let permissionSourceDescription: String
    let onAction: (ApprovalAction) -> Void

    @State private var showContent = false
    @State private var showButtons = false

    private var providerCapabilities: ProviderCapabilities {
        ProviderCapabilities.baseline(for: agentType)
    }

    private var approvalTitle: String {
        providerCapabilities.permissions.providerManagedPermissionsVisible
            ? L10n.text(.chatConfirmCommand)
            : L10n.text(.chatPermissionRequest)
    }

    private var approvalFallbackText: String {
        providerCapabilities.permissions.providerManagedPermissionsVisible
            ? L10n.text(.chatReviewCommandBeforeContinuing)
            : L10n.text(.chatActionNeedsApprovalBeforeContinuing)
    }

    private var approvalFooterText: String? {
        providerCapabilities.permissions.providerManagedPermissionsVisible
            ? L10n.text(.chatProviderContinueFooter, permissionSourceDescription)
            : permissionSourceDescription
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(TerminalColors.amber)
                        .frame(width: 7, height: 7)
                    Text(approvalTitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.55))
                }

                HStack(alignment: .top, spacing: 10) {
                    Text(MCPToolFormatter.formatToolName(tool))
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundColor(TerminalColors.amber)
                        .fixedSize()

                    if let input = toolInput, !input.isEmpty {
                        Text(input)
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.78))
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text(approvalFallbackText)
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.65))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if let approvalFooterText {
                    Text(approvalFooterText)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.42))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .opacity(showContent ? 1 : 0)
            .offset(x: showContent ? 0 : -10)

            HStack(spacing: 8) {
                ForEach(supportedActions, id: \.self) { action in
                    let isEnabled = true
                    Button {
                        if isEnabled {
                            onAction(action)
                        }
                    } label: {
                        buttonLabel(for: action, isEnabled: isEnabled)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(foregroundColor(for: action, isEnabled: isEnabled))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(backgroundColor(for: action, isEnabled: isEnabled))
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(!isEnabled)
                }
            }
            .opacity(showButtons ? 1 : 0)
            .scaleEffect(showButtons ? 1 : 0.92)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                )
        )
        .onAppear {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7).delay(0.05)) {
                showContent = true
            }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7).delay(0.1)) {
                showButtons = true
            }
        }
    }

    @ViewBuilder
    private func buttonLabel(for action: ApprovalAction, isEnabled: Bool) -> some View {
        Text(action.displayLabel(provider: agentType))
    }

    private func foregroundColor(for action: ApprovalAction, isEnabled: Bool) -> Color {
        guard isEnabled else { return .white.opacity(0.35) }
        switch action {
        case .deny: return .white.opacity(0.75)
        case .allowOnce, .allowAlways, .autoExecute: return .black
        }
    }

    private func backgroundColor(for action: ApprovalAction, isEnabled: Bool) -> Color {
        guard isEnabled else { return Color.white.opacity(0.08) }
        switch action {
        case .deny:
            return Color.white.opacity(0.12)
        case .allowOnce:
            return Color.white.opacity(0.95)
        case .allowAlways:
            return Color(red: 0.95, green: 0.60, blue: 0.18)
        case .autoExecute:
            return Color(red: 0.74, green: 0.20, blue: 0.18)
        }
    }
}

struct ChatTerminalApprovalBar: View {
    let tool: String
    let toolInput: String?
    let agentName: String
    let isInTerminalMultiplexer: Bool

    @State private var showContent = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(TerminalColors.amber)
                        .frame(width: 7, height: 7)
                    Text(L10n.text(.chatConfirmInTerminal))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.55))
                }

                HStack(alignment: .top, spacing: 10) {
                    Text(MCPToolFormatter.formatToolName(tool))
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundColor(TerminalColors.amber)
                        .fixedSize()
                    Text(
                        toolInput ?? (
                            isInTerminalMultiplexer
                                ? L10n.text(.chatNeedsApprovalInTerminal, agentName)
                                : L10n.text(.chatTerminalUnavailable)
                        )
                    )
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.75))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .opacity(showContent ? 1 : 0)
            .offset(x: showContent ? 0 : -10)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                )
        )
        .onAppear {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7).delay(0.05)) {
                showContent = true
            }
        }
    }
}

// MARK: - New Messages Indicator

/// Floating indicator showing count of new messages when user has scrolled up
struct NewMessagesIndicator: View {
    let count: Int
    let onTap: () -> Void

    @State private var isHovering: Bool = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Image(agentIcon: "chevron.down")
                    .font(.system(size: 10, weight: .bold))

                Text(count == 1
                    ? L10n.text(.chatNewMessageSingular)
                    : L10n.text(.chatNewMessagePlural, count)
                )
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(Color(red: 0.85, green: 0.47, blue: 0.34)) // Claude orange
                    .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
            )
            .scaleEffect(isHovering ? 1.05 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
                isHovering = hovering
            }
        }
    }
}
