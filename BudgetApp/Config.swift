import Foundation

enum AppConfig {
    static var baseURL: URL {
        guard let urlString = Bundle.main.infoDictionary?["BACKEND_BASE_URL"] as? String,
              let url = URL(string: urlString) else {
            // Fallback to a default URL if not found in Info.plist
            // This should ideally not be reached if xcconfig is set up correctly
            return URL(string: "https://budget-app-project-benj.onrender.com/api")!
        }
        return url
    }
}