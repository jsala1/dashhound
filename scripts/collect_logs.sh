#!/bin/bash
# Récupère le journal de Dashhound sur l'iPhone branché et en fait un résumé de trajet.
# Usage (dans Terminal, iPhone branché) : scripts/collect_logs.sh "2026-09-28 18:55"
#   L'heure = un peu avant le départ. Demande le mot de passe Mac (sudo : exigé par macOS).
# Lecture seule : ne modifie ni l'iPhone ni le projet (écrit uniquement dans captures/, gitignoré).
set -euo pipefail
cd "$(dirname "$0")/.."

START="${1:?Donne l'heure de début, ex. : scripts/collect_logs.sh \"2026-09-28 18:55\"}"
UDID=$(xcrun devicectl list devices 2>/dev/null | awk '/available \(paired\)/ && $0 !~ /simulated/ {for (i=1;i<=NF;i++) if ($i ~ /^[0-9A-F]{8}-[0-9A-F]{16}$/) print $i}' | head -1)
[ -n "$UDID" ] || { echo "iPhone introuvable : branche-le et déverrouille-le."; exit 1; }

STAMP=$(date +%Y%m%d-%H%M)
OUT="captures/trajets/$STAMP"
mkdir -p "$OUT"
echo "== Collecte du journal depuis $START (iPhone $UDID) — mot de passe Mac demandé"
sudo /usr/bin/log collect --device-udid "$UDID" --start "$START:00" --output "$OUT/iphone.logarchive"
sudo chown -R "$(id -u):$(id -g)" "$OUT"
/usr/bin/log show --archive "$OUT/iphone.logarchive" --predicate 'subsystem == "com.julian.glassesdashcam"' --style compact > "$OUT/dashhound.log"
L="$OUT/dashhound.log"
t() { sed -E 's/^[0-9-]+ ([0-9:]{8}).*\] /\1 /'; }

echo
echo "== Sessions"
grep -E "dashcam active|dashcam arrêtée" "$L" | t | awk '!seen[$0]++' || true
echo
echo "== Clips sauvés (déclencheur, durée)"
grep -E "CLIP sauvé" "$L" | sed -E 's/^[0-9-]+ ([0-9:]{8}).*CLIP sauvé \((.*)\) durée=([0-9.]+).*/\1  \3 s  \2/' || true
echo "   total : $(grep -c 'CLIP sauvé' "$L" || true) — dont chocs : $(grep -c 'CLIP sauvé (choc' "$L" || true)"
echo
echo "== Pics d'accélération (détection de choc)"
grep -oE "\[P2\] pic [0-9.]+ g" "$L" | awk '{print $3}' | python3 -c '
import sys
v = [float(x) for x in sys.stdin]
if not v:
    print("   aucun pic ≥ 1,2 g"); sys.exit()
print(f"   {len(v)} pics ≥ 1,2 g, max {max(v):.1f} g")
print("   " + " · ".join(f"≥{t} g : {sum(x >= t for x in v)}" for t in (3, 5, 8, 10, 12, 16, 20)))'
echo
echo "== Batterie des lunettes (début → fin)"
grep -oE "^[0-9-]+ [0-9:]{8}.*batterie=[0-9]+" "$L" | sed -E 's/^[0-9-]+ ([0-9:]{8}).*batterie=([0-9]+)/\1 \2 %/' | sed -n '1p;$p' || true
echo
echo "== Écran, appels, gels, erreurs"
echo "   verrouillages écran : $(grep -c 'ÉCRAN verrouillé' "$L" || true) · suspensions iOS : $(grep -c 'SUSPENSION' "$L" || true) · appels : $(grep -c 'appel en cours' "$L" || true) · erreurs : $(grep -cE 'erreur|ERREUR' "$L" || true)"
echo
echo "Journal complet : $L — dis à Claude Code : « logs du trajet dans $OUT »"
