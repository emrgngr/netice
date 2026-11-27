#!/usr/bin/env bash
# Örnek belgelerden (flutter test tool/ornek_raporlar_test.dart) site dosyaları üretir.
#   tool/site/ornek_raporlar.sh site <site kökü>   <kök>/img/raporlar/<dil>/<ad>.jpg (ilk sayfa, 100 dpi)
#                                                  ve <kök>/belgeler/<dil>/ (PDF, Word, Excel indirmeleri)
#   tool/site/ornek_raporlar.sh kucuk              uygulama önizleme testi için küçük PNG'ler
set -euo pipefail
kaynak=build/ornek-raporlar
mod=${1:-site}
for d in "$kaynak"/*/; do
  dil=$(basename "$d")
  [ -n "$(ls "$d"*.pdf 2>/dev/null)" ] || continue
  if [ "$mod" = kucuk ]; then
    hedef=$kaynak/kucuk/$dil
    mkdir -p "$hedef"
    for f in "$d"*.pdf; do
      pdftoppm -f 1 -l 1 -r 48 -png -singlefile "$f" "$hedef/$(basename "$f" .pdf)"
    done
  else
    kok=${2:?site kökü}
    hedef=$kok/img/raporlar/$dil
    mkdir -p "$hedef" "$kok/belgeler/$dil"
    for f in "$d"*.pdf; do
      pdftoppm -f 1 -l 1 -r 100 -jpeg -jpegopt quality=80,optimize=y -singlefile "$f" "$hedef/$(basename "$f" .pdf)"
    done
    cp "$d"*.pdf "$d"*.docx "$d"*.csv "$kok/belgeler/$dil/" 2>/dev/null || true
  fi
  echo "$dil: hazır"
done
