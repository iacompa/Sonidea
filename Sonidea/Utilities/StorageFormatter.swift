//
//  StorageFormatter.swift
//  Sonidea
//
//  Human-readable file size formatter and storage utilities.
//

import Foundation

// MARK: - Storage Formatter

enum StorageFormatter {

    /// Format bytes to human-readable string (e.g., "12.4 KB", "9.8 MB")
    /// Uses binary units (1024 base)
    static func format(_ bytes: Int64) -> String {
        guard bytes > 0 else { return "0 B" }

        let units = ["B", "KB", "MB", "GB", "TB"]
        let base: Double = 1024

        // Find the appropriate unit
        let exponent = min(Int(log(Double(bytes)) / log(base)), units.count - 1)
        let unit = units[exponent]

        if exponent == 0 {
            // Bytes - no decimal
            return "\(bytes) B"
        }

        let value = Double(bytes) / pow(base, Double(exponent))

        // Use 1-2 decimal places depending on value
        if value >= 100 {
            return String(format: "%.0f %@", value, unit)
        } else if value >= 10 {
            return String(format: "%.1f %@", value, unit)
        } else {
            return String(format: "%.2f %@", value, unit)
        }
    }

    /// Get file size in bytes for a given URL
    /// Returns nil if file doesn't exist or can't be read
    static func fileSize(at url: URL) -> Int64? {
        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
            if let size = attrs[.size] as? Int64 {
                return size
            }
            if let size = attrs[.size] as? NSNumber {
                return size.int64Value
            }
            return nil
        } catch {
            return nil
        }
    }

    /// Get formatted file size for a given URL
    /// Returns "—" if file doesn't exist
    static func formattedFileSize(at url: URL) -> String {
        guard let size = fileSize(at: url) else {
            return "—"
        }
        return format(size)
    }
}
