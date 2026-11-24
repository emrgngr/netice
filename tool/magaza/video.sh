#!/usr/bin/env bash
# Tanıtım videosu: bash tool/magaza/video.sh <kare_klasoru> <cikti.mp4> [muzik.mp3] [acilis.mp3]
# Kareler kare_00.png … kare_99.png sırasıyla, yumuşak geçişle, hafif yakınlaşmayla birleşir.
set -euo pipefail
dir=$1; out=$2; music=${3:-}; intro=${4:-}
D=3.4; X=0.6
mapfile -t frames < <(ls "$dir"/kare_*.png | sort)
n=${#frames[@]}
inputs=(); filt=""
for i in "${!frames[@]}"; do
  d=$D; [ "$i" -eq 0 ] && d=3.0; [ "$i" -eq $((n-1)) ] && d=4.0
  inputs+=(-loop 1 -t "$d" -i "${frames[$i]}")
  fr=$(python3 -c "print(int($d*30))")
  filt+="[$i:v]scale=2112:1188,zoompan=z='1+0.04*on/$fr':x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':d=1:s=1920x1080:fps=30,format=yuv420p,setsar=1[v$i];"
done
prev="v0"; off=0
for ((i=1;i<n;i++)); do
  d0=$D; [ "$((i-1))" -eq 0 ] && d0=3.0
  off=$(python3 -c "print(round($off+$d0-$X,3))")
  filt+="[$prev][v$i]xfade=transition=fade:duration=$X:offset=$off[x$i];"
  prev="x$i"
done
total=$(python3 -c "print(round($off+4.0,2))")
if [ -n "$music" ]; then
  a=$n
  if [ -n "$intro" ]; then
    inputs+=(-i "$intro" -i "$music")
    filt+="[$a:a]volume=0.9[ai];[$((a+1)):a]volume=0.55,adelay=1500|1500[am];[ai][am]amix=inputs=2:duration=longest:normalize=0,atrim=0:$total,afade=t=out:st=$(python3 -c "print($total-2)"):d=2[aout]"
  else
    inputs+=(-i "$music")
    filt+="[$a:a]volume=0.6,atrim=0:$total,afade=t=in:d=1,afade=t=out:st=$(python3 -c "print($total-2)"):d=2[aout]"
  fi
  ffmpeg -y -loglevel error "${inputs[@]}" -filter_complex "$filt" -map "[$prev]" -map "[aout]" -c:v libx264 -crf 20 -preset medium -c:a aac -b:a 192k -t "$total" -movflags +faststart "$out"
else
  ffmpeg -y -loglevel error "${inputs[@]}" -filter_complex "${filt%;}" -map "[$prev]" -c:v libx264 -crf 20 -preset medium -t "$total" -movflags +faststart "$out"
fi
echo "$out ($total sn)"
