// Détection des images clés HEVC dans les échantillons hvc1 du SDK.
// Les CMSampleBuffer livrés par le stream n'ont pas l'attachement `kCMSampleAttachmentKey_NotSync`
// (mesuré en P0) : on lit directement l'en-tête des unités NAL (format « longueur + données »,
// longueur sur 4 octets big-endian). Types de point d'accès aléatoire selon H.265 (ITU-T),
// table 7-1 : BLA_W_LP (16) … CRA_NUT (21) ; 22-23 sont réservés IRAP.
import CoreMedia

enum HEVCRandomAccess {
  /// Plage `nal_unit_type` des images IRAP (décodables sans image précédente).
  static let irapTypes: ClosedRange<UInt8> = 16...23

  /// `nal_unit_type` = bits 1…6 du premier octet de l'en-tête NAL.
  static func nalUnitType(headerByte: UInt8) -> UInt8 { (headerByte & 0b0111_1110) >> 1 }

  /// Parcourt des unités NAL préfixées par leur longueur (4 octets) et dit si l'une est IRAP.
  static func containsRandomAccessPoint(_ bytes: UnsafeRawBufferPointer) -> Bool {
    var cursor = 0
    while cursor + 5 <= bytes.count {
      let length =
        Int(bytes[cursor]) << 24 | Int(bytes[cursor + 1]) << 16 | Int(bytes[cursor + 2]) << 8 | Int(bytes[cursor + 3])
      let header = cursor + 4
      guard length > 0, header + length <= bytes.count else { return false }
      if irapTypes.contains(nalUnitType(headerByte: bytes[header])) { return true }
      cursor = header + length
    }
    return false
  }
}

extension CMSampleBuffer {
  /// Vrai si l'échantillon contient une image clé HEVC (point d'accès aléatoire).
  func isHEVCKeyframe() -> Bool {
    guard let block = CMSampleBufferGetDataBuffer(self) else { return false }
    let size = CMBlockBufferGetDataLength(block)
    guard size > 0 else { return false }
    // Chemin rapide : mémoire contiguë lue en place ; sinon copie.
    var pointer: UnsafeMutablePointer<CChar>?
    var contiguous = 0
    if CMBlockBufferGetDataPointer(block, atOffset: 0, lengthAtOffsetOut: &contiguous, totalLengthOut: nil, dataPointerOut: &pointer)
      == kCMBlockBufferNoErr, contiguous == size, let pointer
    {
      return HEVCRandomAccess.containsRandomAccessPoint(UnsafeRawBufferPointer(start: pointer, count: size))
    }
    var copy = [UInt8](repeating: 0, count: size)
    guard CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: size, destination: &copy) == kCMBlockBufferNoErr
    else { return false }
    return copy.withUnsafeBytes { HEVCRandomAccess.containsRandomAccessPoint($0) }
  }
}
