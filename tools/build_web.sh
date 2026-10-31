#!/usr/bin/env bash
# Exporta o jogo para web e pré-comprime os arquivos grandes (o Wi-Fi da escola agradece).
# Uso: bash tools/build_web.sh   (o servidor em server/ entrega server/public/)
set -e
cd "$(dirname "$0")/../game"
GODOT="${GODOT:-godot}"
rm -f ../server/public/index.*
"$GODOT" --headless --audio-driver Dummy --path . --import >/dev/null 2>&1 || true
"$GODOT" --headless --audio-driver Dummy --path . --export-release "Web" ../server/public/index.html >/dev/null 2>&1
cd ../server/public
for f in index.wasm index.pck index.js; do gzip -9 -k -f "$f"; done
rm -f index.wasm index.pck index.js   # só os .gz vão para o repositório e a hospedagem
ls -la index.*
