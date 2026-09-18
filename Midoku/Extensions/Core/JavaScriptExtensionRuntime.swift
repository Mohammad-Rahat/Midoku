import Foundation
import JavaScriptCore

protocol ExtensionRuntime: Sendable {
    func validate(bundle: String, manifest: ExtensionManifest) async throws
    func invoke(bundle: String, method: String, input: Data, host: any ExtensionHost) async throws -> Data
}

/// Each call gets a fresh VM, confined to this actor. Adapters must be stateless.
/// A public JavaScriptCore API cannot forcibly stop arbitrary synchronous JS.
/// Only reviewed, app-bundled code is accepted by the registry at this stage.
actor JavaScriptExtensionRuntime: ExtensionRuntime {
    private let maximumJSONBytes = 4 * 1024 * 1024


    func validate(bundle: String, manifest: ExtensionManifest) throws {
        try manifest.validate()
        let context = try makeContext(bundle: bundle)
        let methods = manifest.capabilities.flatMap(\.methods)
        let encoded = try JSONEncoder().encode(methods)
        let json = String(decoding: encoded, as: UTF8.self)
        let valid = context.evaluateScript("""
            \(json).every(name => typeof MidokuExtension.default[name] === "function")
            """)?.toBool() == true
        guard context.exception == nil, valid else {
            throw ExtensionFailure.invalidManifest("A declared capability is missing its implementation.")
        }
    }

    func invoke(bundle: String, method: String, input: Data, host: any ExtensionHost) async throws -> Data {
        guard input.count <= 65_536 else { throw ExtensionFailure.responseTooLarge }
        try Task.checkCancellation()
        let context = try makeContext(bundle: bundle)
        guard let bridge = context.objectForKeyedSubscript("__midoku") else {
            throw ExtensionFailure.runtimeFailure
        }
        bridge.invokeMethod("begin", withArguments: [method, String(decoding: input, as: UTF8.self)])
        var hostRequestCount = 0
        var idleDeadline = ContinuousClock.now.advanced(by: .seconds(5))

        while true {
            try Task.checkCancellation()
            guard context.exception == nil else { throw ExtensionFailure.runtimeFailure }
            if let value = bridge.invokeMethod("result", withArguments: []), !value.isNull, !value.isUndefined {
                guard let string = value.toString(), string.utf8.count <= maximumJSONBytes else {
                    throw ExtensionFailure.responseTooLarge
                }
                let data = Data(string.utf8)
                let envelope = try JSONDecoder().decode(RuntimeResult.self, from: data)
                guard envelope.ok, let payload = envelope.json else { throw ExtensionFailure.runtimeFailure }
                let output = Data(payload.utf8)
                try validateJSON(output)
                return output
            }

            guard let requests = bridge.invokeMethod("drain", withArguments: [])?.toString(),
                  requests.utf8.count <= 65_536 else { throw ExtensionFailure.responseTooLarge }
            let jobs = try JSONDecoder().decode([HostJob].self, from: Data(requests.utf8))
            for job in jobs {
                hostRequestCount += 1
                guard hostRequestCount <= 32 else { throw ExtensionFailure.responseTooLarge }
                // Native verification errors propagate directly, never as adapter parser errors.
                let response = try await host.request(job.request)
                try Task.checkCancellation()
                let visibleHeaders = response.headers.filter {
                    !["set-cookie", "set-cookie2", "authorization", "proxy-authorization"].contains($0.key.lowercased())
                }
                let result = HostResponse(
                    url: response.url, status: response.status, headers: visibleHeaders,
                    body: String(decoding: response.body, as: UTF8.self)
                )
                let json = try JSONEncoder().encode(result)
                guard json.count <= 12 * 1024 * 1024 else { throw ExtensionFailure.responseTooLarge }
                bridge.invokeMethod("deliver", withArguments: [job.id, String(decoding: json, as: UTF8.self)])
                // Interactive verification time is not counted as an idle-JS timeout.
                idleDeadline = .now.advanced(by: .seconds(5))
            }
            guard .now < idleDeadline else { throw ExtensionFailure.timedOut }
            if jobs.isEmpty {
                try await Task.sleep(for: .milliseconds(10))
            }
        }
    }

    private func makeContext(bundle: String) throws -> JSContext {
        guard bundle.utf8.count <= 2 * 1024 * 1024,
              let context = JSContext(virtualMachine: JSVirtualMachine()) else {
            throw ExtensionFailure.runtimeFailure
        }
        context.evaluateScript(Self.bootstrap)
        context.evaluateScript(bundle)
        guard context.exception == nil,
              context.evaluateScript("typeof MidokuExtension.default === 'object'")?.toBool() == true else {
            throw ExtensionFailure.runtimeFailure
        }
        return context
    }

    private func validateJSON(_ data: Data) throws {
        guard data.count <= maximumJSONBytes else { throw ExtensionFailure.responseTooLarge }
        let value = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        var remaining = 50_000
        func visit(_ value: Any, depth: Int) throws {
            remaining -= 1
            guard remaining >= 0, depth <= 24 else { throw ExtensionFailure.responseTooLarge }
            if let text = value as? String, text.utf8.count > 262_144 {
                throw ExtensionFailure.responseTooLarge
            }
            if let values = value as? [Any] {
                guard values.count <= 2_000 else { throw ExtensionFailure.responseTooLarge }
                for child in values { try visit(child, depth: depth + 1) }
            } else if let values = value as? [String: Any] {
                guard values.count <= 100 else { throw ExtensionFailure.responseTooLarge }
                for child in values.values { try visit(child, depth: depth + 1) }
            }
        }
        try visit(value, depth: 0)
    }

    private struct HostJob: Decodable {
        let id: Int
        let request: SourceHTTPRequest
    }

    private struct HostResponse: Encodable {
        let url: URL
        let status: Int
        let headers: [String: String]
        let body: String
    }

    private struct RuntimeResult: Decodable {
        let ok: Bool
        let json: String?
    }

    nonisolated private static let bootstrap = """
        globalThis.__midoku = (() => {
            let sequence = 0, result = null;
            const jobs = [], pending = new Map();
            const host = Object.freeze({
                request(request) {
                    return new Promise((resolve) => {
                        const id = ++sequence;
                        pending.set(id, resolve);
                        jobs.push({id, request: {url: request.url, headers: request.headers || {}}});
                    });
                }
            });
            return {
                begin(method, input) {
                    Promise.resolve()
                        .then(() => MidokuExtension.default[method](JSON.parse(input), host))
                        .then(value => {
                            const json = JSON.stringify(value);
                            if (json === undefined) throw new Error("Missing result");
                            result = JSON.stringify({ok: true, json});
                        })
                        .catch(() => { result = JSON.stringify({ok: false}); });
                },
                drain() { return JSON.stringify(jobs.splice(0)); },
                deliver(id, json) {
                    const resolve = pending.get(id);
                    if (!resolve) return;
                    pending.delete(id);
                    resolve(JSON.parse(json));
                },
                result() { return result; }
            };
        })();
        """
}
