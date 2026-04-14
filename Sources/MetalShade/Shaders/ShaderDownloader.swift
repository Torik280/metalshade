import Foundation

/// Downloads ReShade .fx / .metal shaders from known public GitHub repositories.
/// Successful downloads are cached in ~/Library/Application Support/MetalShade/Shaders/
enum ShaderDownloader {

    // MARK: - Known repos (raw content, no trailing slash)
    // Tried in order — first 200 response with non-HTML content wins.

    private static let repos: [String] = [
        // Official ReShade shader pack
        "https://raw.githubusercontent.com/crosire/reshade-shaders/slim/Shaders",
        // prod80 color-grading collection (PD80_* shaders)
        "https://raw.githubusercontent.com/prod80/prod80-ReShade-Repository/master/Shaders",
        // qUINT suite (MXAO, DOF, SSR, Bloom, …)
        "https://raw.githubusercontent.com/martymcmodding/qUINT/master/Shaders",
        // PPFX / FXShaders (SSDO, Godrays, …)
        "https://raw.githubusercontent.com/luluco250/FXShaders/master/Shaders",
        // Depth3D / BlueSkyDefender
        "https://raw.githubusercontent.com/BlueSkyDefender/Depth3D/master/Shaders",
        // Daodan reshade collection
        "https://raw.githubusercontent.com/Daodan317081/reshade-shaders/master/Shaders",
        // Fubax shaders
        "https://raw.githubusercontent.com/Fubaxiusz/fubax-shaders/master/Shaders",
        // CeeJay / SweetFX
        "https://raw.githubusercontent.com/CeeJayDK/SweetFX/master/Shaders",
        // haasn legacy collection
        "https://raw.githubusercontent.com/haasn/reshade-shaders/master/Shaders",
        // Some repos put shaders in root, not /Shaders/
        "https://raw.githubusercontent.com/crosire/reshade-shaders/slim",
        "https://raw.githubusercontent.com/martymcmodding/qUINT/master",
        "https://raw.githubusercontent.com/luluco250/FXShaders/master",
    ]

    // MARK: - Cache

    /// ~/Library/Application Support/MetalShade/Shaders/
    static let cacheDir: URL = {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("MetalShade/Shaders", isDirectory: true)
    }()

    /// Returns cached URL if the file was downloaded before.
    static func cached(_ fileName: String) -> URL? {
        let url = cacheDir.appendingPathComponent(fileName)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    // MARK: - Download

    /// Try every known repo until one returns a valid shader source.
    /// On success the file is written to `cacheDir` and its URL is returned.
    /// Returns nil if every repo returns 404 / error.
    static func download(_ fileName: String) async -> URL? {
        // Return cached version immediately
        if let hit = cached(fileName) { return hit }

        try? FileManager.default.createDirectory(
            at: cacheDir, withIntermediateDirectories: true, attributes: nil
        )

        let encoded = fileName.addingPercentEncoding(
            withAllowedCharacters: .urlPathAllowed
        ) ?? fileName

        for base in repos {
            guard let url = URL(string: "\(base)/\(encoded)") else { continue }
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                guard
                    let http = response as? HTTPURLResponse,
                    http.statusCode == 200,
                    let text = String(data: data, encoding: .utf8),
                    !text.isEmpty,
                    !text.hasPrefix("<!") // skip HTML error pages
                else { continue }

                let dest = cacheDir.appendingPathComponent(fileName)
                try data.write(to: dest, options: .atomic)
                return dest
            } catch { continue }
        }
        return nil
    }
}
