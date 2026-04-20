import Foundation
import UIKit

private func WFHelperLog(_ format: String, _ args: CVarArg..., sourceFile: String = #fileID) {
    let message = args.isEmpty ? format : String(format: format, arguments: args)
    WFLogSwift(sourceFile, "[WatchImageHelper] \(message)")
}

struct WatchImageHelper {
    struct ProductVersion {
        let family: String
        let major: Int
        let minor: Int
    }

    enum PreviewStatus: Equatable {
        case emptyInput
        case invalidProductType
        case unmappedProductType
        case mappedProductType
    }

    struct Preview {
        let productType: String
        let status: PreviewStatus
        let version: ProductVersion?
        let nanoRegistrySize: Int?
        let bridgeSize: Int?
        let sizeAlias: String?
        let fallbackMaterial: Int?
        let bridgeAssetName: String?
        let loadedAssetName: String?
        let bridgeImage: UIImage?
        let symbolName: String
    }

    private static let bridgeBundlePath = "/System/Library/PrivateFrameworks/BridgePreferences.framework"
    private static let productTypePattern = #"^([A-Za-z]+)(\d+),(\d+)$"#

    static func preview(for productType: String?) -> Preview {
        let normalized = (productType ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            return Preview(
                productType: "",
                status: .emptyInput,
                version: nil,
                nanoRegistrySize: nil,
                bridgeSize: nil,
                sizeAlias: nil,
                fallbackMaterial: nil,
                bridgeAssetName: nil,
                loadedAssetName: nil,
                bridgeImage: nil,
                symbolName: "applewatch"
            )
        }

        guard let version = parseProductType(normalized) else {
            return Preview(
                productType: normalized,
                status: .invalidProductType,
                version: nil,
                nanoRegistrySize: nil,
                bridgeSize: nil,
                sizeAlias: nil,
                fallbackMaterial: nil,
                bridgeAssetName: nil,
                loadedAssetName: nil,
                bridgeImage: nil,
                symbolName: "applewatch"
            )
        }

        let nanoRegistrySize = nanoRegistrySize(for: version)
        WFHelperLog("productType=%@ family=%@ major=%d minor=%d => nanoRegistrySize=%@",
              normalized, version.family, version.major, version.minor,
              nanoRegistrySize.map(String.init) ?? "nil")

        let bridgeSize: Int? = nanoRegistrySize.flatMap { nrSize in
            let bs = WatchDeviceBridgeSizeForNRSize(nrSize)
            return bs > 0 ? bs : nil
        }
        WFHelperLog("nanoRegistrySize=%@ => bridgeSize=%@",
              nanoRegistrySize.map(String.init) ?? "nil",
              bridgeSize.map(String.init) ?? "nil")

        let sizeAlias = bridgeSize.map { WatchDeviceDisplayNameForBridgeSize($0) as String }
        WFHelperLog("bridgeSize=%@ => sizeAlias=%@",
              bridgeSize.map(String.init) ?? "nil",
              sizeAlias ?? "nil")

        let bridgeAssetName: String? = bridgeSize.flatMap { size in
            WatchDeviceAssetNameForBridgeSize(size, "WatchPairingRestore")
        }
        WFHelperLog("bridgeAssetName=%@", bridgeAssetName ?? "nil")
        let (bridgeImage, loadedAssetName) = loadBridgeImage(named: bridgeAssetName)

        return Preview(
            productType: normalized,
            status: bridgeSize == nil ? .unmappedProductType : .mappedProductType,
            version: version,
            nanoRegistrySize: nanoRegistrySize,
            bridgeSize: bridgeSize,
            sizeAlias: sizeAlias,
            fallbackMaterial: bridgeSize.flatMap { bs in
                let m = WatchDeviceFallbackMaterialForBridgeSize(bs)
                return m > 0 ? m : nil
            },
            bridgeAssetName: bridgeAssetName,
            loadedAssetName: loadedAssetName,
            bridgeImage: bridgeImage,
            symbolName: symbolName(for: bridgeSize)
        )
    }

    private static func parseProductType(_ productType: String) -> ProductVersion? {
        guard let expression = try? NSRegularExpression(pattern: productTypePattern),
              let match = expression.firstMatch(in: productType, range: NSRange(productType.startIndex..., in: productType)),
              let familyRange = Range(match.range(at: 1), in: productType),
              let majorRange = Range(match.range(at: 2), in: productType),
              let minorRange = Range(match.range(at: 3), in: productType),
              let major = Int(String(productType[majorRange])),
              let minor = Int(String(productType[minorRange])) else {
            return nil
        }

        return ProductVersion(
            family: String(productType[familyRange]),
            major: major,
            minor: minor
        )
    }

    private static func nanoRegistrySize(for version: ProductVersion) -> Int? {
        guard version.family == "Watch" else {
            return nil
        }
        let size = WatchDeviceNRSizeForWatchMajorMinor(version.major, version.minor)
        return size > 0 ? size : nil
    }

    private static func symbolName(for bridgeSize: Int?) -> String {
        switch bridgeSize {
        case 19, 20, 21:
            return "applewatch.side.right"
        default:
            return "applewatch"
        }
    }

    private static func loadBridgeImage(named assetName: String?) -> (UIImage?, String?) {
        guard let assetName else {
            NSLog("[WatchImageHelper] loadBridgeImage: assetName is nil, skip")
            return (nil, nil)
        }
        guard let bridgeBundle = Bundle(path: bridgeBundlePath) else {
            NSLog("[WatchImageHelper] loadBridgeImage: failed to load Bundle at path=%@", bridgeBundlePath)
            return (nil, nil)
        }
        NSLog("[WatchImageHelper] loadBridgeImage: bundle loaded, bundlePath=%@", bridgeBundle.bundlePath)

        let candidates = bridgeAssetCandidates(for: assetName)
        NSLog("[WatchImageHelper] loadBridgeImage: trying candidates=%@", candidates.joined(separator: ", "))
        for candidate in candidates {
            let image = UIImage(named: candidate, in: bridgeBundle, compatibleWith: nil)
            NSLog("[WatchImageHelper] UIImage(named:%@) => %@", candidate, image == nil ? "nil" : "loaded")
            if let image {
                return (image, candidate)
            }
        }

        // Asset Catalog 查找全部失败，尝试直接按文件路径加载
        let resourcePath = bridgeBundle.resourcePath ?? bridgeBundle.bundlePath
        for suffix in ["", "@3x", "@2x"] {
            let filePath = (resourcePath as NSString).appendingPathComponent("\(assetName)\(suffix).png")
            NSLog("[WatchImageHelper] fallback file load: %@", filePath)
            if let image = UIImage(contentsOfFile: filePath) {
                NSLog("[WatchImageHelper] fallback success: %@", filePath)
                return (image, "\(assetName)\(suffix).png")
            }
        }

        NSLog("[WatchImageHelper] loadBridgeImage: all candidates failed for assetName=%@", assetName)
        return (nil, nil)
    }

    private static func bridgeAssetCandidates(for assetName: String) -> [String] {
        let roundedScale = max(2, min(3, Int(UIScreen.main.scale.rounded())))
        var candidates = [assetName, "\(assetName)@\(roundedScale)x", "\(assetName)@3x", "\(assetName)@2x"]
        var seen = Set<String>()
        candidates.removeAll { !seen.insert($0).inserted }
        return candidates
    }
}
