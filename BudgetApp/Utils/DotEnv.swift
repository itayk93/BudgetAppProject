import Foundation

/// Simple .env file parser for iOS
class DotEnv {
    static let shared = DotEnv()
    
    private var env: [String: String] = [:]
    
    private init() {
        loadEnvFile()
    }
    
    private func loadEnvFile() {
        guard let path = Bundle.main.path(forResource: ".env", ofType: nil) else {
            print("⚠️ [DotEnv] .env file not found in app bundle")
            return
        }
        
        do {
            let contents = try String(contentsOfFile: path, encoding: .utf8)
            let lines = contents.components(separatedBy: .newlines)
            
            for line in lines {
                let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmedLine.isEmpty || trimmedLine.hasPrefix("#") {
                    continue
                }
                
                if let separatorIndex = trimmedLine.firstIndex(of: "=") {
                    let key = String(trimmedLine[..<separatorIndex]).trimmingCharacters(in: .whitespaces)
                    let value = String(trimmedLine[trimmedLine.index(after: separatorIndex)...]).trimmingCharacters(in: .whitespaces)
                    
                    // Remove quotes if present
                    var cleanValue = value
                    if (cleanValue.hasPrefix("\"") && cleanValue.hasSuffix("\"")) || 
                       (cleanValue.hasPrefix("'") && cleanValue.hasSuffix("'")) {
                        cleanValue = String(cleanValue.dropFirst().dropLast())
                    }
                    
                    env[key] = cleanValue
                }
            }
        } catch {
            print("⚠️ [DotEnv] Error reading .env file: \(error)")
        }
    }
    
    func get(_ key: String) -> String? {
        return env[key]
    }
}