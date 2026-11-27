#!/usr/bin/env bash
# Örnek rapor PDF'lerinden (flutter test tool/ornek_raporlar_test.dart) görsel üretir.
#   tool/site/ornek_raporlar.sh site <çıktı klasörü>   web sitesi: <çıktı>/<dil>/<ad>.jpg (ilk sayfa)
#   tool/site/ornek_raporlar.sh kucuk                  uygulama önizleme testi için küçük PNG'ler
set -euo pipefail
kaynak=build/ornek-raporlar
mod=${1:-site}
for d in "$kaynak"/*/; do
  dil=$(basename "$d")
  [ -n "$(ls "$d"*.pdf 2>/dev/null)" ] || continue
  if [ "$mod" = kucuk ]; then
    hedef=$kaynak/kucuk/$dil
  else
    hedef=${2:?çıktı klasörü}/$dil
  fi
  mkdir -p "$hedef"
  for f in "$d"*.pdf; do
    ad=$(basename "$f" .pdf)
    if [ "$mod" = kucuk ]; then
      pdftoppm -f 1 -l 1 -r 48 -png -singlefile "$f" "$hedef/$ad"
    else
      # Galeride küçük, büyütünce okunaklı: 100 dpi, JPEG.
      pdftoppm -f 1 -l 1 -r 100 -jpeg -jpegopt quality=80,optimize=y -singlefile "$f" "$hedef/$ad"
    fi
  done
  echo "$dil: $(ls "$hedef" | wc -l) görsel"
done
