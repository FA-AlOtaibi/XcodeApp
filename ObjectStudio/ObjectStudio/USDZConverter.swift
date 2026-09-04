import Foundation
import ModelIO

struct USDZConverter {
    enum ConversionError: LocalizedError {
        case unsupportedInput(String)
        case unsupportedOutput

        var errorDescription: String? {
            switch self {
            case .unsupportedInput(let ext): return "صيغة \(ext.uppercased()) لا يمكن تحويلها محليًا إلى USDZ على هذا الجهاز."
            case .unsupportedOutput: return "هذا إصدار iOS لا يدعم تصدير USDZ عبر Model I/O."
            }
        }
    }

    static func convertToUSDZ(_ sourceURL: URL) throws -> URL {
        let ext = sourceURL.pathExtension.lowercased()
        if ext == "usdz" { return sourceURL }
        guard MDLAsset.canImportFileExtension(ext) else {
            throw ConversionError.unsupportedInput(ext)
        }
        guard MDLAsset.canExportFileExtension("usdz") else {
            throw ConversionError.unsupportedOutput
        }

        let asset = MDLAsset(url: sourceURL)
        asset.loadTextures()
        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent("ObjectStudio-\(UUID().uuidString)")
            .appendingPathExtension("usdz")
        try? FileManager.default.removeItem(at: out)
        try asset.export(to: out)
        return out
    }
}
