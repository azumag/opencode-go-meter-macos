import Foundation

// MARK: - 公式 Usage API クライアント
// GET https://opencode.ai/zen/go/v1/usage
// 秘密情報（APIキー）をログや出力に含めないこと。

/// API 取得時のエラー種別。UI 表示用の日本語メッセージを持つ。
enum UsageClientError: LocalizedError {
    case missingAPIKey
    case invalidAPIKey
    case httpError(Int)
    case network(Error)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "APIキーが見つかりません"
        case .invalidAPIKey:
            return "APIキーが無効です"
        case .httpError(let code):
            return "取得に失敗しました（HTTP \(code)）"
        case .network(let error):
            return "ネットワークエラー: \(error.localizedDescription)"
        case .invalidResponse:
            return "応答の解析に失敗しました"
        }
    }
}

enum UsageClient {

    static let endpointURL = URL(string: "https://opencode.ai/zen/go/v1/usage")!

    /// APIキーの解決順（SPEC §1）:
    /// 1. 環境変数 OPENCODE_GO_API_KEY
    /// 2. config.json の apiKey
    /// 3. ~/.local/share/opencode/auth.json の ["opencode-go"]["key"]
    /// 見つからなければ nil。値自体は絶対に出力しない。
    static func resolveAPIKey(configKey: String?) -> String? {
        if let key = ProcessInfo.processInfo.environment["OPENCODE_GO_API_KEY"],
           !key.isEmpty {
            return key
        }
        if let key = configKey, !key.isEmpty {
            return key
        }
        let authURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local", isDirectory: true)
            .appendingPathComponent("share", isDirectory: true)
            .appendingPathComponent("opencode", isDirectory: true)
            .appendingPathComponent("auth.json")
        guard let data = try? Data(contentsOf: authURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let section = json["opencode-go"] as? [String: Any],
              let key = section["key"] as? String,
              !key.isEmpty else {
            return nil
        }
        return key
    }

    /// Usage API を同期的に取得する。呼び出し側はバックグラウンドスレッドで呼ぶこと。
    static func fetchUsage(apiKey: String) throws -> UsageResponse {
        var request = URLRequest(url: endpointURL, timeoutInterval: 30)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("OpenCodeGoMeter/1.0", forHTTPHeaderField: "User-Agent")

        // URLSession は非同期なのでセマフォで同期化する
        var resultData: Data?
        var resultResponse: URLResponse?
        var resultError: Error?
        let semaphore = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: request) { data, response, error in
            resultData = data
            resultResponse = response
            resultError = error
            semaphore.signal()
        }.resume()
        _ = semaphore.wait(timeout: .now() + 45)

        if let error = resultError {
            throw UsageClientError.network(error)
        }
        guard let http = resultResponse as? HTTPURLResponse,
              let data = resultData else {
            throw UsageClientError.invalidResponse
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw UsageClientError.invalidAPIKey
        }
        guard (200..<300).contains(http.statusCode) else {
            throw UsageClientError.httpError(http.statusCode)
        }
        do {
            return try JSONDecoder().decode(UsageResponse.self, from: data)
        } catch {
            throw UsageClientError.invalidResponse
        }
    }
}
