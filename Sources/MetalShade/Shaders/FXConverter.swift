import Foundation

/// Converts ReShade .fx (HLSL) pixel shaders to Metal Shading Language compute kernels.
/// Parses ReShade annotations: ui_label, ui_type, ui_min, ui_max, ui_default.
enum FXConverter {

    struct ParsedUniform {
        let hlslType:     String          // float, float2, float3, float4, int, bool
        let name:         String          // HLSL variable name
        let label:        String          // ui_label or falls back to name
        let min:          Float
        let max:          Float
        let defaultValue: Float
    }

    struct Result {
        let mslSource:    String
        let functionName: String          // e.g. "fx_CoolShader"
        let displayName:  String
        let uniforms:     [ParsedUniform] // for building ShaderParam list
    }

    // MARK: - Public

    static func convert(source: String, fileName: String) -> (result: Result?, error: String?) {
        let stripped = stripComments(source)

        guard let (_, psBody) = extractPixelShader(from: stripped) else {
            return (nil,
                    "Не найден пиксельный шейдер (функция с : SV_Target).\n" +
                    "Убедись, что .fx файл содержит пиксельный шейдер.")
        }

        let uniforms = extractUniforms(from: stripped)
        let mslBody  = convertHLSLBody(psBody)

        let safeName    = sanitize(fileName)
        let fnName      = "fx_\(safeName)"
        let displayName = fileName
            .replacingOccurrences(of: ".fx",    with: "")
            .replacingOccurrences(of: ".metal", with: "")

        let msl = buildKernel(functionName: fnName, psBody: mslBody, uniforms: uniforms)

        let result = Result(
            mslSource:    msl,
            functionName: fnName,
            displayName:  displayName,
            uniforms:     uniforms
        )
        return (result, nil)
    }

    // MARK: - Comment stripping

    private static func stripComments(_ src: String) -> String {
        // Line comments
        var s = src.components(separatedBy: "\n").map { line -> String in
            if let r = line.range(of: "//") { return String(line[..<r.lowerBound]) }
            return line
        }.joined(separator: "\n")

        // Block comments /* */
        while let open = s.range(of: "/*"), let close = s.range(of: "*/"),
              open.lowerBound < close.lowerBound {
            s.removeSubrange(open.lowerBound...close.upperBound)
        }
        return s
    }

    // MARK: - Uniform extraction with ReShade annotations

    /// Parses `uniform float Name < ui_label="..."; ui_min=0; ui_max=1; ui_default=0.5; > = 0.5;`
    private static func extractUniforms(from src: String) -> [ParsedUniform] {
        var results: [ParsedUniform] = []

        // Match: uniform <type> <name> [< annotations >] [= default] ;
        let pattern = #"uniform\s+(float[234]?|int[234]?|bool)\s+(\w+)\s*(?:<([^>]*)>)?\s*(?:=\s*([\d.eE+\-]+))?;"#
        guard let regex = try? NSRegularExpression(pattern: pattern,
                                                    options: .dotMatchesLineSeparators) else { return results }

        let nsStr   = src as NSString
        let matches = regex.matches(in: src, range: NSRange(src.startIndex..., in: src))

        for m in matches {
            let hlslType     = nsStr.substring(with: m.range(at: 1))
            let name         = nsStr.substring(with: m.range(at: 2))
            let annotations  = m.range(at: 3).location != NSNotFound
                                 ? nsStr.substring(with: m.range(at: 3)) : ""
            let defaultRaw   = m.range(at: 4).location != NSNotFound
                                 ? nsStr.substring(with: m.range(at: 4)) : nil

            let label        = annotation(key: "ui_label",   in: annotations) ?? name
            let minVal       = Float(annotation(key: "ui_min",     in: annotations) ?? "0")  ?? 0
            let maxVal       = Float(annotation(key: "ui_max",     in: annotations) ?? "1")  ?? 1
            let defAnnot     = annotation(key: "ui_default", in: annotations)
            let defVal       = Float(defAnnot ?? defaultRaw ?? "0.5") ?? 0.5

            results.append(ParsedUniform(
                hlslType:     hlslType,
                name:         name,
                label:        label,
                min:          minVal,
                max:          maxVal,
                defaultValue: defVal
            ))
        }
        return results
    }

    /// Extract a value from annotation block: `key = "value"` or `key = value`
    private static func annotation(key: String, in block: String) -> String? {
        let pattern = key + #"\s*=\s*"?([^";,\s]+)"?"#
        guard let regex  = try? NSRegularExpression(pattern: pattern),
              let match  = regex.firstMatch(in: block, range: NSRange(block.startIndex..., in: block)),
              let range  = Range(match.range(at: 1), in: block) else { return nil }
        return String(block[range])
    }

    // MARK: - Pixel shader extraction

    private static func extractPixelShader(from src: String) -> (name: String, body: String)? {
        let pattern = #"(?:float4|float3|half4)\s+(\w+)\s*\([^)]*\)\s*:\s*SV_[Tt]arget\w*\s*\{"#
        guard let regex = try? NSRegularExpression(pattern: pattern,
                                                    options: .dotMatchesLineSeparators),
              let match = regex.firstMatch(in: src, range: NSRange(src.startIndex..., in: src)),
              let mRange = Range(match.range, in: src) else { return nil }

        let name = (src as NSString).substring(with: match.range(at: 1))

        // Walk from the opening `{` to find the matching `}`
        var depth = 1
        var idx   = mRange.upperBound
        while idx < src.endIndex && depth > 0 {
            switch src[idx] {
            case "{": depth += 1
            case "}": depth -= 1
            default:  break
            }
            if depth > 0 { idx = src.index(after: idx) }
        }
        return (name, String(src[mRange.upperBound..<idx]))
    }

    // MARK: - HLSL → MSL body conversion

    private static func convertHLSLBody(_ hlsl: String) -> String {
        var s = hlsl

        // Rename functions
        let renames: [(String, String)] = [
            ("lerp(",  "mix("),
            ("frac(",  "fract("),
            ("ddx(",   "dfdx("),
            ("ddy(",   "dfdy("),
        ]
        for (from, to) in renames { s = s.replacingOccurrences(of: from, with: to) }

        // tex2D(sampler, uv) → __tex.sample(__s, uv)
        if let re = try? NSRegularExpression(pattern: #"tex2D\s*\(\s*\w+\s*,\s*([^)]+)\)"#) {
            s = re.stringByReplacingMatches(in: s,
                                            range: NSRange(s.startIndex..., in: s),
                                            withTemplate: "__tex.sample(__s, $1)")
        }

        // return expr; → outTex.write(float4(expr),gid); return;
        if let re = try? NSRegularExpression(pattern: #"return\s+(.+?);"#,
                                              options: .dotMatchesLineSeparators) {
            s = re.stringByReplacingMatches(in: s,
                                            range: NSRange(s.startIndex..., in: s),
                                            withTemplate: "outTex.write(clamp(float4($1), 0.0, 1.0), gid); return;")
        }

        return s
    }

    // MARK: - MSL kernel generation

    private static func buildKernel(functionName: String,
                                    psBody: String,
                                    uniforms: [ParsedUniform]) -> String {
        // Buffer 0 is always a passthrough 'intensity' (unused for multi-param shaders
        // but keeps the engine interface consistent).
        // Buffers 1+ map to each uniform in order.
        let extraParams = uniforms.enumerated().map { i, u -> String in
            let metalType = hlslTypeToMSL(u.hlslType)
            return "    constant \(metalType)& \(u.name) [[buffer(\(i + 1))]]"
        }.joined(separator: ",\n")
        let extraParamStr = extraParams.isEmpty ? "" : ",\n\(extraParams)"

        return """
        #include <metal_stdlib>
        using namespace metal;

        kernel void \(functionName)(
            texture2d<float, access::read>  __rawTex  [[texture(0)]],
            texture2d<float, access::write> outTex    [[texture(1)]],
            constant float&                 intensity [[buffer(0)]]\(extraParamStr),
            uint2 gid [[thread_position_in_grid]]
        ) {
            uint W = __rawTex.get_width();
            uint H = __rawTex.get_height();
            if (gid.x >= W || gid.y >= H) return;

            constexpr sampler __s(filter::linear, address::clamp_to_edge);
            texture2d<float> __tex = __rawTex;
            float2 texcoord = float2(gid) / float2(float(W), float(H));
            (void)texcoord;

        \(psBody)
        }
        """
    }

    private static func hlslTypeToMSL(_ type: String) -> String {
        switch type {
        case "bool":   return "bool"
        case "int":    return "int"
        case "int2":   return "int2"
        case "int3":   return "int3"
        case "int4":   return "int4"
        default:       return type  // float, float2, float3, float4 are identical in MSL
        }
    }

    static func sanitizeName(_ name: String) -> String { sanitize(name) }

    private static func sanitize(_ name: String) -> String {
        name
            .replacingOccurrences(of: ".fx",    with: "")
            .replacingOccurrences(of: ".metal", with: "")
            .replacingOccurrences(of: "[^a-zA-Z0-9]", with: "_", options: .regularExpression)
    }
}
