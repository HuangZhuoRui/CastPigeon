import Foundation

enum DeviceRole: String, CaseIterable {
    case sender = "作为发送端"
    case receiver = "作为接收端"
}

enum WorkMode {
    case idle
    case pairing
    case working
}

struct UdpDevice: Hashable {
    let deviceName: String
    let role: String
    let hash_: String
    var ip: String? = nil
    var filePort: Int? = nil
    var deviceType: String = "Unknown"
    var prefixLength: Int? = nil
    var gateway: String? = nil
    var networkId: String? = nil
    var lanReachable: Bool = false
    var lastSeen: Int64 = 0
}

struct NotificationMessage: Codable {
    let id: String
    let appName: String
    let title: String
    let content: String
    let timestamp: Int64
    let iconBase64: String?
}
import Foundation
import SQLite3

class DatabaseManager {
    static let shared = DatabaseManager()
    
    private var db: OpaquePointer?
    
    private let dbPath: String
    private let iconsDir: String
    
    private init() {
        let fileManager = FileManager.default
        let appSupportDir = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupportDir.appendingPathComponent("CastPigeon")
        
        iconsDir = appDir.appendingPathComponent("Icons").path
        dbPath = appDir.appendingPathComponent("messages.sqlite").path
        
        // Ensure directories exist
        try? fileManager.createDirectory(atPath: appDir.path, withIntermediateDirectories: true, attributes: nil)
        try? fileManager.createDirectory(atPath: iconsDir, withIntermediateDirectories: true, attributes: nil)
        
        openDatabase()
        createTable()
    }
    
    private func openDatabase() {
        if sqlite3_open(dbPath, &db) != SQLITE_OK {
            print("Error opening database at \(dbPath)")
        }
    }
    
    private func createTable() {
        let createTableString = """
        CREATE TABLE IF NOT EXISTS messages(
            id TEXT PRIMARY KEY,
            deviceHash TEXT,
            appName TEXT,
            title TEXT,
            content TEXT,
            timestamp INTEGER
        );
        """
        
        var createTableStatement: OpaquePointer?
        if sqlite3_prepare_v2(db, createTableString, -1, &createTableStatement, nil) == SQLITE_OK {
            if sqlite3_step(createTableStatement) == SQLITE_DONE {
                print("Messages table created.")
            } else {
                print("Messages table could not be created.")
            }
        } else {
            print("CREATE TABLE statement could not be prepared.")
        }
        sqlite3_finalize(createTableStatement)
    }
    
    func insertMessage(_ msg: NotificationMessage, deviceHash: String) {
        // Handle Icon storage logic
        if let base64 = msg.iconBase64, !base64.isEmpty {
            let iconPath = (iconsDir as NSString).appendingPathComponent("\(msg.appName).png")
            if !FileManager.default.fileExists(atPath: iconPath) {
                if let data = Data(base64Encoded: base64, options: .ignoreUnknownCharacters) {
                    try? data.write(to: URL(fileURLWithPath: iconPath))
                }
            }
        }
        
        let insertStatementString = "INSERT OR IGNORE INTO messages (id, deviceHash, appName, title, content, timestamp) VALUES (?, ?, ?, ?, ?, ?);"
        var insertStatement: OpaquePointer?
        if sqlite3_prepare_v2(db, insertStatementString, -1, &insertStatement, nil) == SQLITE_OK {
            sqlite3_bind_text(insertStatement, 1, (msg.id as NSString).utf8String, -1, nil)
            sqlite3_bind_text(insertStatement, 2, (deviceHash as NSString).utf8String, -1, nil)
            sqlite3_bind_text(insertStatement, 3, (msg.appName as NSString).utf8String, -1, nil)
            sqlite3_bind_text(insertStatement, 4, (msg.title as NSString).utf8String, -1, nil)
            sqlite3_bind_text(insertStatement, 5, (msg.content as NSString).utf8String, -1, nil)
            sqlite3_bind_int64(insertStatement, 6, msg.timestamp)
            
            if sqlite3_step(insertStatement) == SQLITE_DONE {
                print("Successfully inserted row.")
            } else {
                print("Could not insert row.")
            }
        } else {
            print("INSERT statement could not be prepared.")
        }
        sqlite3_finalize(insertStatement)
    }
    
    func getMessages(for deviceHash: String? = nil) -> [NotificationMessage] {
        var queryStatementString = "SELECT id, appName, title, content, timestamp FROM messages"
        if deviceHash != nil {
            queryStatementString += " WHERE deviceHash = ?"
        }
        queryStatementString += " ORDER BY timestamp DESC"
        
        var queryStatement: OpaquePointer?
        var messages: [NotificationMessage] = []
        
        if sqlite3_prepare_v2(db, queryStatementString, -1, &queryStatement, nil) == SQLITE_OK {
            if let hash = deviceHash {
                sqlite3_bind_text(queryStatement, 1, (hash as NSString).utf8String, -1, nil)
            }
            
            while sqlite3_step(queryStatement) == SQLITE_ROW {
                let id = String(cString: sqlite3_column_text(queryStatement, 0))
                let appName = String(cString: sqlite3_column_text(queryStatement, 1))
                let title = String(cString: sqlite3_column_text(queryStatement, 2))
                let content = String(cString: sqlite3_column_text(queryStatement, 3))
                let timestamp = sqlite3_column_int64(queryStatement, 4)
                
                messages.append(NotificationMessage(
                    id: id,
                    appName: appName,
                    title: title,
                    content: content,
                    timestamp: timestamp,
                    iconBase64: nil // Icon is loaded dynamically by the UI
                ))
            }
        } else {
            print("SELECT statement could not be prepared")
        }
        sqlite3_finalize(queryStatement)
        
        return messages
    }
    
    func getIconURL(for appName: String) -> URL? {
        let iconPath = (iconsDir as NSString).appendingPathComponent("\(appName).png")
        if FileManager.default.fileExists(atPath: iconPath) {
            return URL(fileURLWithPath: iconPath)
        }
        return nil
    }
}
