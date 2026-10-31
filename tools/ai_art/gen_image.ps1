# Chamada de geracao de imagem (gpt-image-1). EXCECAO deliberada a regra de
# "nada de asset de terceiro": e o usuario quem autoriza, caso a caso, gerar
# arte 2D grande por API quando o pipeline procedural nao alcanca.
#
# A CHAVE NUNCA ENTRA NO REPOSITORIO. `-KeyFile` aponta pra um arquivo FORA da
# arvore do projeto; sem ele o script nao roda.
param(
  [Parameter(Mandatory=$true)][string]$PromptFile,
  [Parameter(Mandatory=$true)][string]$Out,
  [Parameter(Mandatory=$true)][string]$KeyFile,
  [string]$Quality = "low",
  [string]$Size = "1536x1024",
  [string]$Model = "gpt-image-1"
)
$ErrorActionPreference = "Stop"
$key = (Get-Content -Raw $KeyFile).Trim()
# `.ToString()` nao e decorativo: `Get-Content -Raw` devolve um PSObject
# embrulhando a string, e o `ConvertTo-Json` do PowerShell 5.1 serializa esse
# embrulho como OBJETO (`{"value":...,"Count":...}`) em vez de string — a API
# responde 400 "expected a string, but got an object".
$prompt = (Get-Content -Raw $PromptFile).ToString()

$body = '{"model":"' + $Model + '","prompt":' + (ConvertTo-Json -InputObject $prompt) +
        ',"size":"' + $Size + '","quality":"' + $Quality + '","n":1}'

$headers = @{ "Authorization" = "Bearer $key" }

for ($try = 1; $try -le 6; $try++) {
  try {
    $r = Invoke-RestMethod -Uri "https://api.openai.com/v1/images/generations" -Method Post `
         -Headers $headers -ContentType "application/json" `
         -Body ([Text.Encoding]::UTF8.GetBytes($body)) -TimeoutSec 600
    [IO.File]::WriteAllBytes($Out, [Convert]::FromBase64String($r.data[0].b64_json))
    Write-Output ("OK {0} [{1}] tokens_out={2}" -f (Split-Path $Out -Leaf), $Quality, $r.usage.output_tokens)
    exit 0
  } catch {
    $msg = $_.Exception.Message
    $code = 0
    if ($_.Exception.Response) { $code = [int]$_.Exception.Response.StatusCode }
    if ($code -eq 429 -or $code -ge 500) {
      $wait = 20 * $try
      Write-Output ("retry {0}/6 (HTTP {1}) aguardando {2}s" -f $try, $code, $wait)
      Start-Sleep -Seconds $wait
      continue
    }
    # Erro nao recuperavel: mostra o corpo da resposta, que e onde a API diz o
    # motivo real (prompt bloqueado, parametro invalido, etc.)
    # `ErrorDetails.Message` e onde o PS 5.1 guarda o CORPO da resposta de erro;
    # o stream em si ja foi consumido pelo Invoke-RestMethod e volta vazio.
    Write-Output ("HTTP {0}: {1}" -f $code, $_.ErrorDetails.Message)
    throw $msg
  }
}
throw "esgotou as tentativas"
