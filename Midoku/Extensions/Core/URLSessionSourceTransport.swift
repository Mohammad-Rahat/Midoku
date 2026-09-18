import Foundation

/// Receives bounded chunks on URLSession's delegate queue, never one actor hop per byte.
nonisolated final class URLSessionSourceTransport: SourceHTTPTransport, Sendable {
    private let session: URLSession

    init(protocolClasses: [AnyClass]? = nil) {
        let configuration = URLSessionConfiguration.ephemeral
        if let protocolClasses { configuration.protocolClasses = protocolClasses }
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
        session = URLSession(configuration: configuration)
    }

    func send(_ request: URLRequest, maximumBytes: Int) async throws -> SourceHTTPResponse {
        let transfer = BoundedTransfer(maximumBytes: maximumBytes)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let task = session.dataTask(with: request)
                task.delegate = transfer
                transfer.start(task: task, continuation: continuation)
            }
        } onCancel: {
            transfer.cancel()
        }
    }
}

/// The lock protects delegate callbacks racing cancellation and task creation.
nonisolated private final class BoundedTransfer: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private let maximumBytes: Int
    private var task: URLSessionDataTask?
    private var continuation: CheckedContinuation<SourceHTTPResponse, any Error>?
    private var response: HTTPURLResponse?
    private var body = Data()
    private var finished = false

    init(maximumBytes: Int) { self.maximumBytes = maximumBytes }

    func start(task: URLSessionDataTask, continuation: CheckedContinuation<SourceHTTPResponse, any Error>) {
        let cancelled = lock.withLock {
            if finished { return true }
            self.task = task
            self.continuation = continuation
            return false
        }
        if cancelled {
            task.cancel()
            continuation.resume(throwing: CancellationError())
        } else {
            task.resume()
        }
    }

    func cancel() { finish(.failure(CancellationError())) }

    private func finish(_ result: Result<SourceHTTPResponse, any Error>) {
        let pending = lock.withLock {
            guard !finished else { return (nil as CheckedContinuation<SourceHTTPResponse, any Error>?, nil as URLSessionDataTask?) }
            finished = true
            let pending = (continuation, task)
            continuation = nil
            task = nil
            body = Data()
            return pending
        }
        pending.1?.cancel()
        pending.0?.resume(with: result)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask,
                    didReceive response: URLResponse,
                    completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void) {
        guard let http = response as? HTTPURLResponse, http.url != nil else {
            completionHandler(.cancel)
            finish(.failure(ExtensionFailure.invalidResponse("Non-HTTP response.")))
            return
        }
        guard response.expectedContentLength <= Int64(maximumBytes) else {
            completionHandler(.cancel)
            finish(.failure(ExtensionFailure.responseTooLarge))
            return
        }
        let allowed = lock.withLock {
            guard !finished else { return false }
            self.response = http
            return true
        }
        completionHandler(allowed ? .allow : .cancel)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        let oversized = lock.withLock {
            guard !finished else { return false }
            guard data.count <= maximumBytes - body.count else { return true }
            body.append(data)
            return false
        }
        if oversized { finish(.failure(ExtensionFailure.responseTooLarge)) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        if let error {
            finish(.failure(error))
            return
        }
        let result: SourceHTTPResponse? = lock.withLock {
            guard !finished, let response, let url = response.url else { return nil }
            var headers: [String: String] = [:]
            for (key, value) in response.allHeaderFields {
                headers[String(describing: key).lowercased()] = String(describing: value)
            }
            return SourceHTTPResponse(url: url, status: response.statusCode, headers: headers, body: body)
        }
        if let result { finish(.success(result)) }
        else { finish(.failure(ExtensionFailure.invalidResponse("Missing HTTP response."))) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        // Permission, cookie, and redirect limits remain owned by the coordinator.
        completionHandler(nil)
    }
}
