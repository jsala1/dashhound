// Range un clip écrit : copie dans Documents/Clips, ajout dans Photos (autorisation « ajout seul »),
// miniature pour l'écran. Cf. CLAUDE.md.
import AVFoundation
import Photos
import UIKit
import os

struct SavedClip: Identifiable {
  let id = UUID()
  let fileURL: URL
  let duration: TimeInterval
  let date: Date
  let thumbnail: UIImage?
  let savedToPhotos: Bool
  let photosError: String?
  let audioMutedForCall: Bool
}

enum ClipStore {
  private static let log = Logger(subsystem: "com.julian.glassesdashcam", category: "ClipStore")

  static var clipsDirectory: URL {
    let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    let dir = docs.appendingPathComponent("Clips", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
  }

  static func newClipURL(date: Date = Date()) -> URL {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyyMMdd-HHmmss"
    return clipsDirectory.appendingPathComponent("dashhound-\(formatter.string(from: date)).mov")
  }

  /// Ajoute le fichier (déjà dans Documents/Clips) à Photos et prépare la miniature.
  static func publish(_ url: URL, duration: TimeInterval, date: Date, audioMutedForCall: Bool) async -> SavedClip {
    var photosError: String?
    let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
    if status == .authorized || status == .limited {
      do {
        try await PHPhotoLibrary.shared().performChanges {
          PHAssetCreationRequest.forAsset().addResource(with: .video, fileURL: url, options: nil)
        }
      } catch {
        photosError = error.localizedDescription
      }
    } else {
      photosError = String(localized: "Accès à Photos refusé")
    }
    if let photosError { log.error("Photos : \(photosError, privacy: .public)") }

    let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
    generator.appliesPreferredTrackTransform = true
    generator.maximumSize = CGSize(width: 240, height: 240)
    let thumbnail = try? await generator.image(at: CMTime(seconds: min(1, duration), preferredTimescale: 600)).image

    return SavedClip(
      fileURL: url, duration: duration, date: date, thumbnail: thumbnail.map { UIImage(cgImage: $0) },
      savedToPhotos: photosError == nil, photosError: photosError, audioMutedForCall: audioMutedForCall)
  }
}
