import Foundation

/// 数据结构版本。每次对持久化结构做**不兼容**修改时把 current +1，
/// 并在 `WorthSnapStore.migrateStep` 里补一条 from→from+1 的升级路径。
public enum WorthSnapSchema {
    public static let current = 1
}

public enum WorthSnapStoreError: Error, Equatable {
    /// 文件里的版本比当前 App 能识别的还新（例如新版 App 写的数据被旧版 App 打开）。
    /// 这种情况**绝不能**当成损坏去覆盖，否则会毁掉用户在新设备上的数据。
    case unsupportedFutureVersion(found: Int, supported: Int)
    /// 文件无法解析（非法 JSON、字段缺失、类型不符等）。调用方应保留原文件、进入安全模式。
    case corrupted(reason: String)
}

/// 旺财数据的编解码与版本迁移。纯函数、可命令行测试，App 层只负责文件 IO。
///
/// 磁盘格式为「信封」：`{ "schemaVersion": N, "data": { ...WorthSnapData... } }`。
/// 对早期没有信封、顶层直接是 WorthSnapData 的旧文件做了向后兼容。
public enum WorthSnapStore {
    public static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    public static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private struct Envelope: Codable {
        var schemaVersion: Int
        var data: WorthSnapData
    }

    private struct VersionProbe: Codable {
        var schemaVersion: Int?
    }

    public static func encode(_ data: WorthSnapData) throws -> Data {
        try makeEncoder().encode(Envelope(schemaVersion: WorthSnapSchema.current, data: data))
    }

    /// 解析磁盘数据。失败时抛错而**绝不**静默返回空/示例数据——
    /// 由调用方决定备份与安全模式，避免把用户真实数据覆盖掉。
    public static func decode(_ raw: Data) throws -> WorthSnapData {
        let decoder = makeDecoder()

        // 先只探版本号，不碰其余字段。
        let probe = try? decoder.decode(VersionProbe.self, from: raw)

        guard let version = probe?.schemaVersion else {
            // 旧文件：没有信封、没有版本号，顶层即 WorthSnapData。
            do {
                return try decoder.decode(WorthSnapData.self, from: raw)
            } catch {
                throw WorthSnapStoreError.corrupted(reason: String(describing: error))
            }
        }

        if version > WorthSnapSchema.current {
            throw WorthSnapStoreError.unsupportedFutureVersion(found: version, supported: WorthSnapSchema.current)
        }

        let migrated = try migrate(raw, from: version)
        do {
            return try decoder.decode(Envelope.self, from: migrated).data
        } catch {
            throw WorthSnapStoreError.corrupted(reason: String(describing: error))
        }
    }

    /// 把任意旧版本的原始 JSON 逐级升级到当前版本。
    private static func migrate(_ raw: Data, from version: Int) throws -> Data {
        var current = raw
        var v = version
        while v < WorthSnapSchema.current {
            current = try migrateStep(current, from: v)
            v += 1
        }
        return current
    }

    /// 单步迁移 from → from+1。未来新增不兼容版本时在此实现具体转换。
    private static func migrateStep(_ raw: Data, from version: Int) throws -> Data {
        switch version {
        // case 1: return try v1ToV2(raw)  // 示例：将来 current 升到 2 时实现
        default:
            return raw
        }
    }
}
