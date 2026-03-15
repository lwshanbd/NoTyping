import Foundation

enum RealtimeReconnectPlanner {
    static let maxAttempts = 3

    static func delayMilliseconds(forAttempt attempt: Int) -> Int {
        switch attempt {
        case ...1:
            return 250
        case 2:
            return 750
        default:
            return 2_000
        }
    }

    static func delay(forAttempt attempt: Int) -> Duration {
        .milliseconds(delayMilliseconds(forAttempt: attempt))
    }
}

@MainActor
protocol RealtimeTranscriptionServiceDelegate: AnyObject {
    func transcriptionService(_ service: RealtimeTranscriptionServiceProtocol, didReceive event: TranscriptionEvent)
}

@MainActor
protocol RealtimeTranscriptionServiceProtocol: AnyObject {
    var delegate: RealtimeTranscriptionServiceDelegate? { get set }
    func start(configuration: RealtimeTranscriptionConfiguration) async throws
    func appendAudio(_ data: Data) async throws
    func commitCurrentBuffer() async throws
    func stop() async
}

struct RealtimeTranscriptionServiceFactory {
    private let keychainStore: KeychainStore
    private let diagnosticStore: DiagnosticStore

    init(keychainStore: KeychainStore, diagnosticStore: DiagnosticStore) {
        self.keychainStore = keychainStore
        self.diagnosticStore = diagnosticStore
    }

    @MainActor
    func make(for provider: ProviderSettings) -> RealtimeTranscriptionServiceProtocol {
        switch provider.profile {
        case .mock:
            MockRealtimeTranscriptionService()
        case .openAI, .customCompatible:
            OpenAIRealtimeTranscriptionService(keychainStore: keychainStore, diagnosticStore: diagnosticStore)
        }
    }
}

@MainActor
final class OpenAIRealtimeTranscriptionService: NSObject, RealtimeTranscriptionServiceProtocol {
    weak var delegate: RealtimeTranscriptionServiceDelegate?

    private let keychainStore: KeychainStore
    private let diagnosticStore: DiagnosticStore
    private let session: URLSession
    private var task: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var provider: ProviderSettings?
    private var configuration: RealtimeTranscriptionConfiguration?
    private var bufferedUncommittedAudio: [Data] = []
    private var commitRequestedForCurrentBuffer = false
    private var reconnectAttempts = 0
    private var isStopping = false

    init(keychainStore: KeychainStore, diagnosticStore: DiagnosticStore) {
        self.keychainStore = keychainStore
        self.diagnosticStore = diagnosticStore
        self.session = URLSession(configuration: .default)
        super.init()
    }

    func start(configuration: RealtimeTranscriptionConfiguration) async throws {
        isStopping = false
        reconnectAttempts = 0
        bufferedUncommittedAudio.removeAll()
        commitRequestedForCurrentBuffer = false
        reconnectTask?.cancel()
        reconnectTask = nil
        self.configuration = configuration
        provider = configuration.provider
        notifyConnectionStatus(.connecting)
        try await connect(using: configuration)
    }

    func appendAudio(_ data: Data) async throws {
        bufferedUncommittedAudio.append(data)
        if let task {
            do {
                try await sendAudioAppend(data, over: task)
            } catch {
                await handleSocketFailure(error, from: task)
            }
        } else {
            diagnosticStore.record(subsystem: "realtime", message: "Queued audio chunk while realtime socket reconnects")
        }
    }

    func commitCurrentBuffer() async throws {
        commitRequestedForCurrentBuffer = true
        if let task {
            do {
                try await send(json: ["type": "input_audio_buffer.commit"], over: task)
            } catch {
                await handleSocketFailure(error, from: task)
            }
        } else {
            diagnosticStore.record(subsystem: "realtime", message: "Queued commit request while realtime socket reconnects")
        }
    }

    func stop() async {
        isStopping = true
        configuration = nil
        reconnectTask?.cancel()
        reconnectTask = nil
        receiveTask?.cancel()
        receiveTask = nil
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        bufferedUncommittedAudio.removeAll()
        commitRequestedForCurrentBuffer = false
        reconnectAttempts = 0
        notifyConnectionStatus(.stopped)
    }

    private func connect(using configuration: RealtimeTranscriptionConfiguration) async throws {
        let token = try await authorizationToken(for: configuration.provider)
        guard let url = webSocketURL(from: configuration.provider.baseURL) else {
            throw DictationError.providerConfiguration("Invalid realtime URL.")
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("realtime=v1", forHTTPHeaderField: "OpenAI-Beta")

        let socketTask = session.webSocketTask(with: request)
        task = socketTask
        socketTask.resume()
        diagnosticStore.record(subsystem: "realtime", message: reconnectAttempts == 0 ? "Realtime socket connected" : "Realtime socket reconnected on attempt \(reconnectAttempts)")
        notifyConnectionStatus(.connected(resumedAfterReconnect: reconnectAttempts > 0))

        receiveTask?.cancel()
        receiveTask = Task { [weak self] in
            await self?.receiveLoop(for: socketTask)
        }

        try await send(json: sessionPayload(for: configuration), over: socketTask)

        for chunk in bufferedUncommittedAudio {
            try await sendAudioAppend(chunk, over: socketTask)
        }

        if commitRequestedForCurrentBuffer {
            try await send(json: ["type": "input_audio_buffer.commit"], over: socketTask)
        }
    }

    private func sessionPayload(for configuration: RealtimeTranscriptionConfiguration) -> [String: Any] {
        [
            "type": "transcription_session.update",
            "session": [
                "input_audio_format": "pcm16",
                "input_audio_transcription": [
                    "model": configuration.provider.transcriptionModel,
                    "prompt": configuration.prompt,
                    "language": configuration.languageMode.transcriptionLanguageHint as Any
                ].compactMapValues { $0 },
                "turn_detection": configuration.useServerVAD ? ["type": "server_vad"] : NSNull(),
                "include": ["item.input_audio_transcription.logprobs"]
            ].compactMapValues { $0 is NSNull ? nil : $0 }
        ]
    }

    private func send(json: [String: Any], over task: URLSessionWebSocketTask? = nil) async throws {
        guard let task = task ?? self.task else { throw DictationError.network("The realtime socket is not connected.") }
        let data = try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
        guard let string = String(data: data, encoding: .utf8) else {
            throw DictationError.network("Unable to encode realtime message.")
        }
        try await task.send(.string(string))
    }

    private func sendAudioAppend(_ data: Data, over task: URLSessionWebSocketTask) async throws {
        try await send(json: [
            "type": "input_audio_buffer.append",
            "audio": data.base64EncodedString()
        ], over: task)
    }

    private func receiveLoop(for socketTask: URLSessionWebSocketTask) async {
        do {
            while !Task.isCancelled {
                let message = try await socketTask.receive()
                let text: String
                switch message {
                case let .string(string):
                    text = string
                case let .data(data):
                    text = String(decoding: data, as: UTF8.self)
                @unknown default:
                    continue
                }
                handleMessage(text)
            }
        } catch {
            await handleSocketFailure(error, from: socketTask)
        }
    }

    private func handleMessage(_ string: String) {
        guard let data = string.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String
        else {
            return
        }

        switch type {
        case "transcription_session.created", "transcription_session.updated":
            reconnectAttempts = 0
            delegate?.transcriptionService(self, didReceive: .sessionCreated)
        case "input_audio_buffer.committed":
            bufferedUncommittedAudio.removeAll()
            commitRequestedForCurrentBuffer = false
            delegate?.transcriptionService(self, didReceive: .bufferCommitted(itemID: json["item_id"] as? String))
        case "conversation.item.input_audio_transcription.delta":
            delegate?.transcriptionService(self, didReceive: .partial(
                itemID: json["item_id"] as? String ?? UUID().uuidString,
                previousItemID: json["previous_item_id"] as? String,
                text: json["delta"] as? String ?? ""
            ))
        case "conversation.item.input_audio_transcription.completed":
            let averageLogProbability = (json["logprobs"] as? [[String: Any]])?.compactMap { $0["logprob"] as? Double }.average
            delegate?.transcriptionService(self, didReceive: .completed(
                itemID: json["item_id"] as? String ?? UUID().uuidString,
                previousItemID: json["previous_item_id"] as? String,
                text: json["transcript"] as? String ?? json["text"] as? String ?? "",
                averageLogProbability: averageLogProbability
            ))
        case "conversation.item.input_audio_transcription.failed":
            delegate?.transcriptionService(self, didReceive: .failed(
                itemID: json["item_id"] as? String,
                message: (json["error"] as? [String: Any])?["message"] as? String ?? "Unknown realtime transcription error."
            ))
        default:
            diagnosticStore.record(subsystem: "realtime", message: "Unhandled event: \(type)")
        }
    }

    private func handleSocketFailure(_ error: Error, from socketTask: URLSessionWebSocketTask) async {
        guard task === socketTask else { return }
        guard !isStopping, !Task.isCancelled else { return }

        diagnosticStore.record(subsystem: "realtime", message: "Realtime socket error: \(error.localizedDescription)")
        task = nil
        receiveTask = nil

        guard reconnectAttempts < RealtimeReconnectPlanner.maxAttempts else {
            delegate?.transcriptionService(self, didReceive: .failed(itemID: nil, message: error.localizedDescription))
            return
        }

        reconnectAttempts += 1
        let retryDelayMilliseconds = RealtimeReconnectPlanner.delayMilliseconds(forAttempt: reconnectAttempts)
        let delay = RealtimeReconnectPlanner.delay(forAttempt: reconnectAttempts)
        diagnosticStore.record(subsystem: "realtime", message: "Scheduling reconnect attempt \(reconnectAttempts) after transient socket failure")
        notifyConnectionStatus(.reconnecting(
            attempt: reconnectAttempts,
            maximumAttempts: RealtimeReconnectPlanner.maxAttempts,
            retryDelayMilliseconds: retryDelayMilliseconds
        ))
        reconnectTask?.cancel()
        reconnectTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: delay)
            await self.performReconnect()
        }
    }

    private func performReconnect() async {
        guard !isStopping, let configuration else { return }
        do {
            try await connect(using: configuration)
        } catch {
            diagnosticStore.record(subsystem: "realtime", message: "Realtime reconnect failed: \(error.localizedDescription)")
            if reconnectAttempts >= RealtimeReconnectPlanner.maxAttempts {
                notifyConnectionStatus(.stopped)
                delegate?.transcriptionService(self, didReceive: .failed(itemID: nil, message: error.localizedDescription))
                return
            }

            reconnectAttempts += 1
            let retryDelayMilliseconds = RealtimeReconnectPlanner.delayMilliseconds(forAttempt: reconnectAttempts)
            let delay = RealtimeReconnectPlanner.delay(forAttempt: reconnectAttempts)
            notifyConnectionStatus(.reconnecting(
                attempt: reconnectAttempts,
                maximumAttempts: RealtimeReconnectPlanner.maxAttempts,
                retryDelayMilliseconds: retryDelayMilliseconds
            ))
            reconnectTask?.cancel()
            reconnectTask = Task { @MainActor [weak self] in
                guard let self else { return }
                try? await Task.sleep(for: delay)
                await self.performReconnect()
            }
        }
    }

    private func notifyConnectionStatus(_ status: RealtimeConnectionStatus) {
        delegate?.transcriptionService(self, didReceive: .connectionStatus(status))
    }

    private func webSocketURL(from baseURL: String) -> URL? {
        guard var components = URLComponents(string: baseURL) else { return nil }
        switch components.scheme?.lowercased() {
        case "https":
            components.scheme = "wss"
        case "http":
            components.scheme = "ws"
        case "wss", "ws":
            break
        default:
            return nil
        }
        let trimmedPath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = trimmedPath.isEmpty ? "/v1/realtime" : "/\(trimmedPath)/v1/realtime"
        components.queryItems = [URLQueryItem(name: "intent", value: "transcription")]
        return components.url
    }

    private func authorizationToken(for provider: ProviderSettings) async throws -> String {
        if provider.capabilities.supportsTranscriptionClientSecrets,
           !provider.sessionTokenEndpoint.trimmed.isEmpty,
           let token = try await fetchClientSecret(from: provider.sessionTokenEndpoint, provider: provider) {
            return token
        }

        guard let apiKey = keychainStore.load(account: provider.apiKeyAccount), !apiKey.isEmpty else {
            throw DictationError.providerConfiguration("No API key is stored for the selected provider.")
        }
        return apiKey
    }

    private func fetchClientSecret(from endpoint: String, provider: ProviderSettings) async throws -> String? {
        guard let url = URL(string: endpoint),
              let apiKey = keychainStore.load(account: provider.apiKeyAccount),
              !apiKey.isEmpty
        else {
            return nil
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["provider": provider.profile.rawValue])
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            return nil
        }
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        if let direct = json?["client_secret"] as? String {
            return direct
        }
        if let nested = (json?["client_secret"] as? [String: Any])?["value"] as? String {
            return nested
        }
        return nil
    }
}

@MainActor
final class MockRealtimeTranscriptionService: RealtimeTranscriptionServiceProtocol {
    weak var delegate: RealtimeTranscriptionServiceDelegate?
    private var appendCount = 0
    private var languageMode: LanguageMode = .auto

    func start(configuration: RealtimeTranscriptionConfiguration) async throws {
        languageMode = configuration.languageMode
        delegate?.transcriptionService(self, didReceive: .connectionStatus(.connected(resumedAfterReconnect: false)))
        delegate?.transcriptionService(self, didReceive: .sessionCreated)
    }

    func appendAudio(_ data: Data) async throws {
        appendCount += 1
        if appendCount == 5 {
            delegate?.transcriptionService(self, didReceive: .partial(itemID: "mock-\(UUID().uuidString)", previousItemID: nil, text: languageMode == .simplifiedChinese ? "这是 模拟" : "this is mock"))
        }
    }

    func commitCurrentBuffer() async throws {
        let text: String
        switch languageMode {
        case .simplifiedChinese:
            text = "这是一个用于调试界面的模拟听写句子。"
        case .english:
            text = "This is a mock dictation sentence for end-to-end testing."
        case .auto:
            text = "This is a mock dictation sentence for end-to-end testing."
        }
        delegate?.transcriptionService(self, didReceive: .completed(itemID: "mock-final-\(UUID().uuidString)", previousItemID: nil, text: text, averageLogProbability: -0.12))
    }

    func stop() async {
        delegate?.transcriptionService(self, didReceive: .connectionStatus(.stopped))
    }
}

private extension Array where Element == Double {
    var average: Double? {
        guard !isEmpty else { return nil }
        return reduce(0, +) / Double(count)
    }
}
