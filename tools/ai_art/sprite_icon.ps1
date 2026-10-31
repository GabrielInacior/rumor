# Pos-processamento de SPRITE PEQUENO gerado pela API (icone de HUD, cursor).
#
# Tecnica de "peca pequena" da skill fortaleza-context 3.4: o prompt pede o
# desenho JA na resolucao logica final sobre magenta chapado; este script impoe
# o que o prompt nao garante:
#   1. chave do magenta (cor amostrada dos 4 cantos + dominancia de magenta, o
#      mesmo criterio do `imgtool.ps1` — a API nunca devolve #FF00FF exato);
#   2. caixa justa do que sobrou (linhas/colunas com menos de `MinRun` pixels
#      opacos sao ruido de halo e nao contam);
#   3. re-grid: a caixa e dividida em celulas e cada celula vira UM pixel pela
#      cor MAIS FREQUENTE da regiao central dela (moda, nunca media — media
#      inventaria a cor de meio-tom que a borda dura do pixel art nao tem);
#   4. alfa binario, sprite encaixado em `Size`x`Size` (centrado, ou colado no
#      canto superior esquerdo com `-AnchorTopLeft`, que e o que um cursor quer:
#      a ponta da seta no hotspot perto de 0,0).
# Imprime o primeiro pixel opaco na diagonal (menor x+y) — o candidato a hotspot.
param(
  [Parameter(Mandatory=$true)][string]$In,
  [Parameter(Mandatory=$true)][string]$Out,
  [int]$Size = 32,
  [int]$Pad = 1,
  [int]$MinRun = 6,
  [switch]$AnchorTopLeft
)
$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing
if (-not ("SpriteIcon" -as [type])) {
Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;

public static class SpriteIcon {
  public static string Run(string inPath, string outPath, int size, int pad, int minRun, bool topLeft) {
    int w, h; byte[] b;
    using (Bitmap src0 = new Bitmap(inPath)) {
      w = src0.Width; h = src0.Height;
      using (Bitmap src = new Bitmap(w, h, PixelFormat.Format32bppArgb)) {
        using (Graphics g = Graphics.FromImage(src)) g.DrawImage(src0, 0, 0, w, h);
        b = new byte[w * h * 4];
        BitmapData bd = src.LockBits(new Rectangle(0, 0, w, h), ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
        Marshal.Copy(bd.Scan0, b, 0, b.Length);
        src.UnlockBits(bd);
      }
    }
    // 1. Chave. Fundo amostrado nos quatro cantos.
    long sb = 0, sg = 0, sr = 0; int n = 0;
    int[,] corners = { {0,0}, {w-24,0}, {0,h-24}, {w-24,h-24} };
    for (int c = 0; c < 4; c++)
      for (int y = corners[c,1]; y < corners[c,1] + 24; y++)
        for (int x = corners[c,0]; x < corners[c,0] + 24; x++) {
          int i = (y * w + x) * 4; sb += b[i]; sg += b[i+1]; sr += b[i+2]; n++;
        }
    int kb = (int)(sb / n), kg = (int)(sg / n), kr = (int)(sr / n);
    bool[] opaque = new bool[w * h];
    for (int p = 0; p < w * h; p++) {
      int i = p * 4; int bl = b[i], gr = b[i+1], re = b[i+2];
      bool mag = Math.Min(re, bl) - gr > 40;
      int d2 = (bl-kb)*(bl-kb) + (gr-kg)*(gr-kg) + (re-kr)*(re-kr);
      opaque[p] = !(mag || d2 < 70*70);
    }
    // 2. Caixa justa, ignorando linhas/colunas de halo.
    int x0 = w, x1 = -1, y0 = h, y1 = -1;
    for (int y = 0; y < h; y++) { int cnt = 0; for (int x = 0; x < w; x++) if (opaque[y*w+x]) cnt++; if (cnt >= minRun) { if (y < y0) y0 = y; y1 = y; } }
    for (int x = 0; x < w; x++) { int cnt = 0; for (int y = 0; y < h; y++) if (opaque[y*w+x]) cnt++; if (cnt >= minRun) { if (x < x0) x0 = x; x1 = x; } }
    if (x1 < 0) return "vazio";
    int bw = x1 - x0 + 1, bh = y1 - y0 + 1;
    int inner = size - 2 * pad;
    double cell = Math.Max(bw, bh) / (double)inner;
    int lw = Math.Max(1, (int)Math.Round(bw / cell)), lh = Math.Max(1, (int)Math.Round(bh / cell));
    lw = Math.Min(lw, inner); lh = Math.Min(lh, inner);
    byte[] o = new byte[size * size * 4];
    int ox = topLeft ? pad : pad + (inner - lw) / 2;
    int oy = topLeft ? pad : pad + (inner - lh) / 2;
    int hx = -1, hy = -1, best = int.MaxValue;
    for (int ly = 0; ly < lh; ly++) {
      for (int lx = 0; lx < lw; lx++) {
        // 3. Moda da regiao central (metade do meio) da celula.
        double cx = x0 + (lx + 0.5) * cell, cy = y0 + (ly + 0.5) * cell;
        int r = Math.Max(1, (int)(cell * 0.25));
        Dictionary<int,int> votes = new Dictionary<int,int>();
        int opq = 0, tot = 0;
        for (int yy = (int)cy - r; yy <= (int)cy + r; yy++)
          for (int xx = (int)cx - r; xx <= (int)cx + r; xx++) {
            if (xx < 0 || yy < 0 || xx >= w || yy >= h) continue;
            tot++;
            if (!opaque[yy*w+xx]) continue;
            opq++;
            int i = (yy*w+xx)*4;
            int key = (b[i] >> 3) | ((b[i+1] >> 3) << 5) | ((b[i+2] >> 3) << 10);
            int v; votes.TryGetValue(key, out v); votes[key] = v + 1;
          }
        if (tot == 0 || opq * 2 < tot) continue;
        int bestKey = 0, bestVotes = -1;
        foreach (KeyValuePair<int,int> kv in votes) if (kv.Value > bestVotes) { bestVotes = kv.Value; bestKey = kv.Key; }
        // Cor representante: primeiro pixel real daquela classe (sem media).
        int di = ((oy + ly) * size + (ox + lx)) * 4;
        bool done = false;
        for (int yy = (int)cy - r; yy <= (int)cy + r && !done; yy++)
          for (int xx = (int)cx - r; xx <= (int)cx + r && !done; xx++) {
            if (xx < 0 || yy < 0 || xx >= w || yy >= h || !opaque[yy*w+xx]) continue;
            int i = (yy*w+xx)*4;
            int key = (b[i] >> 3) | ((b[i+1] >> 3) << 5) | ((b[i+2] >> 3) << 10);
            if (key != bestKey) continue;
            o[di] = b[i]; o[di+1] = b[i+1]; o[di+2] = b[i+2]; o[di+3] = 255; done = true;
          }
        int s = (ox + lx) + (oy + ly);
        if (s < best) { best = s; hx = ox + lx; hy = oy + ly; }
      }
    }
    using (Bitmap ob = new Bitmap(size, size, PixelFormat.Format32bppArgb)) {
      BitmapData od = ob.LockBits(new Rectangle(0, 0, size, size), ImageLockMode.WriteOnly, PixelFormat.Format32bppArgb);
      Marshal.Copy(o, 0, od.Scan0, o.Length);
      ob.UnlockBits(od);
      ob.Save(outPath, ImageFormat.Png);
    }
    return string.Format("caixa={0}x{1} celula={2:F1}px logico={3}x{4} hotspot_diag=({5},{6}) fundo=({7},{8},{9})", bw, bh, cell, lw, lh, hx, hy, kr, kg, kb);
  }
}
'@
}
$r = [SpriteIcon]::Run((Resolve-Path $In).Path, [IO.Path]::GetFullPath($Out), $Size, $Pad, $MinRun, [bool]$AnchorTopLeft)
Write-Output ("OK {0} {1}x{1} {2}" -f (Split-Path $Out -Leaf), $Size, $r)
