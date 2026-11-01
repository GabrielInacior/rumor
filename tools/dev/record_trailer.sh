#!/bin/bash
# Grava as cenas do trailer (mudo). Uso: bash tools/dev/record_trailer.sh nome:CLIP:LARGxALT[:ENV=v,...] ...
# A janela sem borda pode passar do tamanho do monitor (vídeo vertical 1080x1920 nítido).
G="/c/Users/gabri/AppData/Local/Microsoft/WinGet/Packages/GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe/Godot_v4.7.1-stable_win64_console.exe"
OUT="${TR_OUT:-C:/Users/gabri/AppData/Local/Temp/tr/clips}"
mkdir -p "$OUT"
cd "$(dirname "$0")/../../game"
for spec in "$@"; do
  IFS=':' read -r name clip res extra <<< "$spec"
  log="$OUT/$name.log"
  echo "== $name ($clip $res) $(date +%T)"
  W="${res%x*}"; H="${res#*x}"
  {
    echo "[display]"
    echo ""
    echo "window/size/window_width_override=$W"
    echo "window/size/window_height_override=$H"
    echo "window/size/borderless=true"
    echo "window/size/initial_position_type=0"
    echo "window/size/initial_position=Vector2i(0, 0)"
  } > override.cfg
  env RUMOR_URL=ws://127.0.0.1:9 TRAILER_CLIP="$clip" $(echo "$extra" | tr ',' ' ') timeout 900 "$G" --audio-driver Dummy --path . \
    --write-movie "$OUT/$name.avi" --fixed-fps 30 --quit-after 3600 res://tools_dev/trailer.tscn > "$log" 2>&1
  grep -E "SCRIPT ERROR|TRAILER_(ABORT|DONE)|Parse Error" "$log" | head -5
  t0=$(grep -m1 "TRAILER_T0" "$log" | awk '{print $2}')
  echo "${t0:-0}" > "$OUT/$name.t0"
done
rm -f override.cfg
echo ALL_DONE
