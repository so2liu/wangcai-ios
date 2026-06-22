import Foundation

/// 数据结构版本。每次对持久化结构做**不兼容**修改时把 current +1，
/// 并在 `WorthSnapStore.migrateStep` 里补一条 from→from+1 的升级路径。
public enum WorthSnapSchema {
    public static let current = 2
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
            // 史前文件：没有信封、没有版本号，顶层即 WorthSnapData（结构等同 v1 的 data 负载）。
            // 包成 v1 信封后并入统一迁移路径，复用 v1→v2 转换，避免重复逻辑。
            guard let object = try? JSONSerialization.jsonObject(with: raw),
                  let wrapped = try? JSONSerialization.data(withJSONObject: ["schemaVersion": 1, "data": object]) else {
                throw WorthSnapStoreError.corrupted(reason: "legacy file is not valid JSON object")
            }
            let migrated = try migrate(wrapped, from: 1)
            do {
                return try decoder.decode(Envelope.self, from: migrated).data
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
        case 1:
            return try v1ToV2(raw)
        default:
            return raw
        }
    }

    /// v1 → v2：引入「成员」。v1 的 Account 用 `ownership` 枚举（me/partner/shared）表达归属，
    /// v2 改为 `ownerMemberId`（指向成员，nil=共同）+ `responsibleMemberId`，并在顶层加 `members` / `currentMemberId`。
    ///
    /// 迁移规则（人走数据留、不丢不重标）：
    /// - 新建本机成员「我」，`currentMemberId` 指向它；ownership=me 的账户归到「我」。
    /// - 仅当存在 ownership=partner 的账户时，才新建「伴侣」成员并归过去。
    /// - ownership=shared → ownerMemberId 置空（共同财产）。
    /// - responsibleMemberId 默认等于 ownerMemberId。
    private static func v1ToV2(_ raw: Data) throws -> Data {
        guard var envelope = (try? JSONSerialization.jsonObject(with: raw)) as? [String: Any],
              var data = envelope["data"] as? [String: Any] else {
            throw WorthSnapStoreError.corrupted(reason: "v1 envelope missing data object")
        }

        // 时间戳沿用账本创建时间，缺失则用当前时间，保证迁移可重放、不依赖随机。
        let now = ISO8601DateFormatter().string(from: Date())
        let ledgerCreatedAt = (data["ledger"] as? [String: Any])?["createdAt"] as? String ?? now

        func makeMember(name: String, color: String) -> [String: Any] {
            ["id": UUID().uuidString, "name": name, "colorHex": color,
             "archived": false, "createdAt": ledgerCreatedAt, "updatedAt": ledgerCreatedAt]
        }

        let me = makeMember(name: "我", color: "C8A24B")
        let meId = me["id"] as! String
        var partner: [String: Any]?

        var accounts = data["accounts"] as? [[String: Any]] ?? []
        for index in accounts.indices {
            let ownership = accounts[index]["ownership"] as? String ?? "me"
            accounts[index].removeValue(forKey: "ownership")
            switch ownership {
            case "partner":
                if partner == nil { partner = makeMember(name: "伴侣", color: "E08F6B") }
                let pid = partner!["id"] as! String
                accounts[index]["ownerMemberId"] = pid
                accounts[index]["responsibleMemberId"] = pid
            case "shared":
                break // ownerMemberId 缺省 = nil（共同）
            default: // me
                accounts[index]["ownerMemberId"] = meId
                accounts[index]["responsibleMemberId"] = meId
            }
        }
        data["accounts"] = accounts

        var members = [me]
        if let partner { members.append(partner) }
        data["members"] = members
        data["currentMemberId"] = meId

        envelope["data"] = data
        envelope["schemaVersion"] = 2
        return try JSONSerialization.data(withJSONObject: envelope)
    }
}
