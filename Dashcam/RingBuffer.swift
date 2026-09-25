// Rôle (P1) : deque thread-safe de `(CMSampleBuffer HEVC, isKeyframe, hostTime)`.
// Éviction au-delà de `bufferSeconds + 15` s ; `snapshot(seconds:)` renvoie les buffers depuis la
// première keyframe ≥ now − seconds (sinon 1-2 s de bouillie verte en tête de clip).
// Seul fichier couvert par des tests unitaires : keyframe, éviction, snapshot. Cf. CLAUDE.md.
