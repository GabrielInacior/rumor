# Ferramenta de pos-processamento das camadas do fundo do menu.
# Uso:
#   .\imgtool.ps1 -Op <op> -In <png> -Out <png> [args...]
# Ops: crop, key, fill, grade, regrid, stats, pipeline

param(
  [string]$Op = "stats",
  [string]$In = "",
  [string]$Out = "",
  [int]$CropY = 80,
  [int]$CropH = 864,
  [int]$DstY = 0,
  [int]$ShiftX = 0,
  [double]$SatMul = 1.0,
  [double]$SatCap = 1.0,
  [double]$Gamma = 1.0,
  [double]$Bright = 1.0,
  [int]$Grid = 2,
  [int]$Levels = 0,
  [int]$FadeTop = 0,
  [int]$KeyTol = 90,
  [switch]$Fill,
  [switch]$Key,
  [switch]$NoCrop
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing

$cs = @'
using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;

public static class ImgTool {

  public static byte[] Load(string path, out int w, out int h) {
    using (Bitmap src = new Bitmap(path)) {
      w = src.Width; h = src.Height;
      Bitmap bmp = new Bitmap(w, h, PixelFormat.Format32bppArgb);
      using (Graphics g = Graphics.FromImage(bmp)) {
        g.CompositingMode = System.Drawing.Drawing2D.CompositingMode.SourceCopy;
        g.DrawImage(src, 0, 0, w, h);
      }
      byte[] buf = new byte[w * h * 4];
      BitmapData bd = bmp.LockBits(new Rectangle(0,0,w,h), ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
      Marshal.Copy(bd.Scan0, buf, 0, buf.Length);
      bmp.UnlockBits(bd);
      bmp.Dispose();
      return buf; // BGRA
    }
  }

  public static void Save(byte[] buf, int w, int h, string path) {
    Bitmap bmp = new Bitmap(w, h, PixelFormat.Format32bppArgb);
    BitmapData bd = bmp.LockBits(new Rectangle(0,0,w,h), ImageLockMode.WriteOnly, PixelFormat.Format32bppArgb);
    Marshal.Copy(buf, 0, bd.Scan0, buf.Length);
    bmp.UnlockBits(bd);
    bmp.Save(path, ImageFormat.Png);
    bmp.Dispose();
  }

  // Reenquadramento: leva a imagem 1536x1024 da API pro quadro 1536x864 (16:9)
  // da camada, SEM reescalar — reescalar mudaria a densidade de pixel e e
  // justamente ela que precisa ser igual em todas as camadas. A linha de
  // origem (`srcY`) escolhe QUE faixa entra; a de destino (`dstY`) escolhe ONDE
  // ela pousa no quadro (o que sobra acima fica transparente, e e assim que a
  // borda distante do enxame desce pro lugar certo da composicao); `shiftX`
  // desloca lateralmente, pra tirar a fortaleza de cima da coluna de botoes.
  public static byte[] Place(byte[] src, int w, int h, int srcY, int dstY, int shiftX, int outH) {
    byte[] dst = new byte[w * outH * 4];
    for (int y = dstY; y < outH; y++) {
      int sy = srcY + (y - dstY);
      if (sy < 0 || sy >= h) continue;
      for (int x = 0; x < w; x++) {
        int sx = x - shiftX;
        if (sx < 0 || sx >= w) continue;
        Array.Copy(src, (sy*w+sx)*4, dst, (y*w+x)*4, 4);
      }
    }
    return dst;
  }

  // Chroma key de magenta puro. Distancia em BGR ao magenta de referencia.
  // Tolerancia generosa: o pos-regrid amostra PONTO, entao franja parcial que
  // sobrar vira pixel duro em vez de halo -- melhor cortar de mais.
  public static void Key(byte[] b, int w, int h, int tol) {
    // A cor de fundo e AMOSTRADA do canto superior direito, nao fixada em
    // #FF00FF: a API nunca devolve o magenta exato pedido (numa rodada veio
    // #B70BA6), e chavear contra a constante deixava o fundo inteiro opaco.
    long sb=0, sg=0, sr=0; int n=0;
    for (int y = 4; y < 64; y++) {
      for (int x = w-64; x < w-4; x++) {
        int i = (y*w+x)*4;
        sb += b[i]; sg += b[i+1]; sr += b[i+2]; n++;
      }
    }
    int kb = (int)(sb/n), kg = (int)(sg/n), kr = (int)(sr/n);
    // Se o canto nao for magenta, a camada nao tem fundo pra chavear —
    // melhor nao fazer nada que abrir um buraco no meio da arte.
    if (!(kr > 100 && kb > 100 && kg < 90)) return;

    int t2 = tol * tol;
    for (int i = 0; i < w * h * 4; i += 4) {
      int bl = b[i], gr = b[i+1], re = b[i+2];
      // Criterio 1: DOMINANCIA DE MAGENTA (vermelho E azul acima do verde).
      // E ele que aguenta o halo rosa degrade que a API costuma pintar em
      // volta da silhueta: a distancia ate a cor de fundo cresce ao longo do
      // halo e um chave por distancia deixaria uma franja larga, mas a
      // dominancia de magenta continua valendo do fundo chapado ate a borda.
      // Pedra cinza-azulada (R~G), brasa laranja (R>G>B) e arco ciano (G,B>R)
      // nao disparam esse teste.
      if (Math.Min(re, bl) - gr > 22) { b[i]=0; b[i+1]=0; b[i+2]=0; b[i+3]=0; continue; }
      int db = bl - kb, dg = gr - kg, dr = re - kr;
      int d2 = db*db + dg*dg + dr*dr;
      if (d2 < t2) { b[i]=0; b[i+1]=0; b[i+2]=0; b[i+3]=0; continue; }
      // Despill: magenta que sobrou na borda tem azul+vermelho muito acima do
      // verde. Puxa os dois pro nivel do verde na proporcao do excesso.
      if (re > gr + 40 && bl > gr + 40) {
        int lim = gr + 40;
        b[i+2] = (byte)Math.Min(re, lim + (re - lim) / 3);
        b[i]   = (byte)Math.Min(bl, lim + (bl - lim) / 3);
      }
    }
  }

  // Preenchimento solido abaixo da silhueta, por COLUNA.
  // Evita que a camada de tras vaze por baixo da da frente. O contorno usado e
  // SUAVIZADO (media movel do y do primeiro pixel opaco) porque replicar o
  // ultimo pixel opaco literal de cada coluna cria listra vertical de "cerca".
  public static void FillBelow(byte[] b, int w, int h) {
    int[] firstOpaque = new int[w];
    for (int x = 0; x < w; x++) {
      firstOpaque[x] = -1;
      for (int y = 0; y < h; y++) {
        if (b[(y*w+x)*4+3] > 128) { firstOpaque[x] = y; break; }
      }
    }
    for (int x = 0; x < w; x++) {
      if (firstOpaque[x] < 0) continue;
      // Cor de preenchimento: media das 6 linhas logo abaixo do contorno,
      // pra herdar o tom local da encosta em vez de um cinza global.
      long sb=0, sg=0, sr=0; int n=0;
      for (int k = 0; k < 6; k++) {
        int y = firstOpaque[x] + k;
        if (y >= h) break;
        int i = (y*w+x)*4;
        if (b[i+3] < 128) continue;
        sb += b[i]; sg += b[i+1]; sr += b[i+2]; n++;
      }
      if (n == 0) continue;
      byte fb = (byte)(sb/n), fg = (byte)(sg/n), fr = (byte)(sr/n);
      for (int y = firstOpaque[x]; y < h; y++) {
        int i = (y*w+x)*4;
        if (b[i+3] > 128) continue;
        b[i]=fb; b[i+1]=fg; b[i+2]=fr; b[i+3]=255;
      }
    }
  }

  // Dissolve DITHERIZADO no topo da camada.
  // A borda distante do enxame sai da API como uma reta perfeita de ponta a
  // ponta — lida como um corte, nao como distancia. Um degrade de alfa comum
  // resolveria, mas alfa parcial em arte pixel vira franja meio-transparente
  // na ampliacao; aqui o alfa continua BINARIO e quem cria a transicao e a
  // probabilidade por pixel, sorteada pela matriz de Bayer. E o mesmo
  // vocabulario de xadrez do resto da imagem.
  public static void FadeTop(byte[] b, int w, int h, int rows) {
    for (int x = 0; x < w; x++) {
      int first = -1;
      for (int y = 0; y < h; y++) {
        if (b[(y*w+x)*4+3] > 128) { first = y; break; }
      }
      if (first < 0) continue;
      for (int k = 0; k < rows; k++) {
        int y = first + k;
        if (y >= h) break;
        double keep = (double)k / rows;
        double thr = (BAYER8[y & 7, x & 7] + 0.5) / 64.0;
        if (keep < thr) b[(y*w+x)*4+3] = 0;
      }
    }
  }

  static void RgbToHsv(double r, double g, double bl, out double hh, out double ss, out double vv) {
    double mx = Math.Max(r, Math.Max(g, bl));
    double mn = Math.Min(r, Math.Min(g, bl));
    double d = mx - mn;
    vv = mx;
    ss = (mx <= 0.0) ? 0.0 : d / mx;
    if (d <= 0.0) { hh = 0.0; return; }
    if (mx == r) hh = ((g - bl) / d) % 6.0;
    else if (mx == g) hh = (bl - r) / d + 2.0;
    else hh = (r - g) / d + 4.0;
    hh *= 60.0;
    if (hh < 0) hh += 360.0;
  }

  static void HsvToRgb(double hh, double ss, double vv, out double r, out double g, out double bl) {
    double c = vv * ss;
    double x = c * (1.0 - Math.Abs(((hh / 60.0) % 2.0) - 1.0));
    double m = vv - c;
    double r1, g1, b1;
    if (hh < 60)      { r1=c; g1=x; b1=0; }
    else if (hh<120)  { r1=x; g1=c; b1=0; }
    else if (hh<180)  { r1=0; g1=c; b1=x; }
    else if (hh<240)  { r1=0; g1=x; b1=c; }
    else if (hh<300)  { r1=x; g1=0; b1=c; }
    else              { r1=c; g1=0; b1=x; }
    r = r1+m; g = g1+m; bl = b1+m;
  }

  // Grade de saturacao/valor. `satCap` e um TETO duro: e ele que garante que
  // nenhuma massa da imagem passe de um limite, mesmo que a geracao venha
  // gritando -- a excecao sao os pixels muito claros (brasa, arco eletrico),
  // preservados porque e justamente o contraste deles com a massa contida que
  // faz o destaque funcionar.
  public static void Grade(byte[] b, int w, int h, double satMul, double satCap, double gamma, double bright) {
    for (int i = 0; i < w*h*4; i += 4) {
      if (b[i+3] == 0) continue;
      double bl = b[i]/255.0, g = b[i+1]/255.0, r = b[i+2]/255.0;
      double hh, ss, vv;
      RgbToHsv(r, g, bl, out hh, out ss, out vv);
      // Pixel muito claro = fonte de luz. Fica de fora do teto.
      double protect = (vv > 0.80) ? (vv - 0.80) / 0.20 : 0.0;
      if (protect > 1.0) protect = 1.0;
      double target = ss * satMul;
      if (target > satCap) target = satCap;
      ss = target * (1.0 - protect) + ss * protect;
      vv = Math.Pow(vv, gamma) * bright;
      if (vv > 1.0) vv = 1.0;
      double nr, ng, nb;
      HsvToRgb(hh, ss, vv, out nr, out ng, out nb);
      b[i]   = (byte)Math.Max(0, Math.Min(255, (int)Math.Round(nb*255)));
      b[i+1] = (byte)Math.Max(0, Math.Min(255, (int)Math.Round(ng*255)));
      b[i+2] = (byte)Math.Max(0, Math.Min(255, (int)Math.Round(nr*255)));
    }
  }

  // Re-grid: reduz por AMOSTRAGEM DE PONTO (nunca media -- media borra o
  // dithering em xadrez que da o efeito de muitos degraus de sombra) e amplia
  // de volta com vizinho-mais-proximo. E isto, nao o prompt, que garante a
  // MESMA densidade de pixel em todas as camadas.
  static readonly int[,] BAYER8 = {
    { 0,32, 8,40, 2,34,10,42},{48,16,56,24,50,18,58,26},
    {12,44, 4,36,14,46, 6,38},{60,28,52,20,62,30,54,22},
    { 3,35,11,43, 1,33, 9,41},{51,19,59,27,49,17,57,25},
    {15,47, 7,39,13,45, 5,37},{63,31,55,23,61,29,53,21}
  };

  public static byte[] Regrid(byte[] src, int w, int h, int grid, int levels) {
    int lw = w / grid, lh = h / grid;
    byte[] small = new byte[lw*lh*4];
    for (int y = 0; y < lh; y++) {
      int sy = y*grid + grid/2;
      if (sy >= h) sy = h-1;
      for (int x = 0; x < lw; x++) {
        int sx = x*grid + grid/2;
        if (sx >= w) sx = w-1;
        Array.Copy(src, (sy*w+sx)*4, small, (y*lw+x)*4, 4);
      }
    }
    // Posterizacao com dithering ORDENADO (Bayer 8x8), na resolucao LOGICA.
    // E este passo, nao o prompt, que garante o vocabulario de "muitos degraus
    // de sombra em xadrez" mesmo quando a geracao volta como pintura lisa
    // (acontece em boa parte das rodadas). Feito ANTES da ampliacao pra o
    // padrao de xadrez cair exatamente na grade de pixel logica.
    if (levels > 1) {
      double step = 255.0 / (levels - 1);
      for (int y = 0; y < lh; y++) {
        for (int x = 0; x < lw; x++) {
          int i = (y*lw+x)*4;
          if (small[i+3] < 128) continue;
          double t = (BAYER8[y & 7, x & 7] + 0.5) / 64.0 - 0.5;
          for (int c = 0; c < 3; c++) {
            double v = small[i+c] + t * step;
            int q = (int)Math.Round(v / step);
            if (q < 0) q = 0; if (q > levels-1) q = levels-1;
            small[i+c] = (byte)Math.Round(q * step);
          }
        }
      }
    }
    byte[] dst = new byte[w*h*4];
    for (int y = 0; y < h; y++) {
      int ly = y/grid; if (ly >= lh) ly = lh-1;
      for (int x = 0; x < w; x++) {
        int lx = x/grid; if (lx >= lw) lx = lw-1;
        Array.Copy(small, (ly*lw+lx)*4, dst, (y*w+x)*4, 4);
      }
    }
    return dst;
  }

  // Medida objetiva do eixo que o usuario reclamou. Devolve
  // "satMedia satP90 fracaoAcima06 valorMedio opacos".
  public static string Stats(byte[] b, int w, int h) {
    int n = 0; double sum = 0; int hi = 0; double vsum = 0; double csum = 0; int chi = 0;
    int[] hist = new int[101];
    for (int i = 0; i < w*h*4; i += 4) {
      if (b[i+3] < 128) continue;
      double bl = b[i]/255.0, g = b[i+1]/255.0, r = b[i+2]/255.0;
      double hh, ss, vv;
      RgbToHsv(r, g, bl, out hh, out ss, out vv);
      // CROMA (max-min) e a medida honesta pra comparar duas artes de brilho
      // diferente: a saturacao HSV de um azul-marinho escuro e altissima, mas
      // o olho le a cor como cinza. E a croma que diz se a tela "grita".
      double chroma = Math.Max(r, Math.Max(g, bl)) - Math.Min(r, Math.Min(g, bl));
      n++; sum += ss; vsum += vv; csum += chroma;
      if (ss > 0.6) hi++;
      if (chroma > 0.25) chi++;
      int k = (int)(ss*100); if (k>100) k=100; if (k<0) k=0;
      hist[k]++;
    }
    if (n == 0) return "vazio";
    int acc = 0, p90 = 0;
    for (int k = 0; k <= 100; k++) { acc += hist[k]; if (acc >= n*0.90) { p90 = k; break; } }
    return string.Format("croma_media={0:F3} frac_croma>0.25={1:F3} | sat_hsv={2:F3} sat_p90={3:F2} val={4:F3} opacos={5}",
      csum/n, (double)chi/n, sum/n, p90/100.0, vsum/n, n);
  }
}
'@

Add-Type -TypeDefinition $cs -ReferencedAssemblies System.Drawing

$w = 0; $h = 0
$buf = [ImgTool]::Load($In, [ref]$w, [ref]$h)

switch ($Op) {
  "stats" {
    Write-Output ("{0}  {1}x{2}  {3}" -f (Split-Path $In -Leaf), $w, $h, [ImgTool]::Stats($buf, $w, $h))
  }
  "pipeline" {
    # Chaveia ANTES de reenquadrar: a amostra da cor de fundo vem do canto
    # superior direito da imagem ORIGINAL, que e onde o magenta chapado esta
    # garantido — depois do reenquadramento aquele canto pode ja ser arte.
    if ($Key) { [ImgTool]::Key($buf, $w, $h, $KeyTol) }
    if (-not $NoCrop) {
      $buf = [ImgTool]::Place($buf, $w, $h, $CropY, $DstY, $ShiftX, $CropH)
      $h = $CropH
    }
    if ($Fill) { [ImgTool]::FillBelow($buf, $w, $h) }
    if ($FadeTop -gt 0) { [ImgTool]::FadeTop($buf, $w, $h, $FadeTop) }
    [ImgTool]::Grade($buf, $w, $h, $SatMul, $SatCap, $Gamma, $Bright)
    $buf = [ImgTool]::Regrid($buf, $w, $h, $Grid, $Levels)
    [ImgTool]::Save($buf, $w, $h, $Out)
    Write-Output ("OK {0} {1}x{2}  {3}" -f (Split-Path $Out -Leaf), $w, $h, [ImgTool]::Stats($buf, $w, $h))
  }
  default { throw "op desconhecida: $Op" }
}
