import Foundation

// MARK: - 設定・状態の読み書き（~/.config/opencode-go-meter/）
// ファイルが無い・壊れている場合も既定値で動作する。

enum StateStore {

    /// 設定ディレクトリ。テスト用に環境変数で上書きできる。
    static var configDirectory: URL {
        if let override = ProcessInfo.processInfo.environment["OPENCODE_GO_METER_CONFIG_DIR"],
           !override.isEmpty {
            return URL(fileURLWithPath: (override as NSString).expandingTildeInPath, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config", isDirectory: true)
            .appendingPathComponent("opencode-go-meter", isDirectory: true)
    }

    static var configURL: URL {
        configDirectory.appendingPathComponent("config.json")
    }

    static var stateURL: URL {
        configDirectory.appendingPathComponent("state.json")
    }

    /// config.json を読む。無ければ既定値を生成して保存する。壊れていても既定値で動く。
    static func loadConfig() -> Config {
        ensureDirectory()
        guard let data = try? Data(contentsOf: configURL) else {
            let defaults = Config.defaults
            saveConfig(defaults)
            return defaults
        }
        // 未知キーは Codable が自動で無視する
        if let config = try? JSONDecoder().decode(Config.self, from: data) {
            return config
        }
        return Config.defaults
    }

    static func saveConfig(_ config: Config) {
        ensureDirectory()
        guard let data = try? JSONEncoder().encode(config) else { return }
        try? data.write(to: configURL, options: .atomic)
    }

    /// state.json を読む。無ければ空状態、壊れていても空状態で動く。
    static func loadState() -> PersistedState {
        ensureDirectory()
        guard let data = try? Data(contentsOf: stateURL) else {
            return PersistedState.empty
        }
        if let state = try? JSONDecoder().decode(PersistedState.self, from: data) {
            return state
        }
        return PersistedState.empty
    }

    static func saveState(_ state: PersistedState) {
        ensureDirectory()
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: stateURL, options: .atomic)
    }

    private static func ensureDirectory() {
        try? FileManager.default.createDirectory(at: configDirectory,
                                                 withIntermediateDirectories: true)
    }
}
