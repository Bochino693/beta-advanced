param(
    # 1 = topo do jogo na esquerda do HDMI, -1 = na direita, 0 = sem giro
    [ValidateSet(1, -1, 0)][int]$Giro = 1,
    # Instala na TV Box pelo adb depois de gerar (TV Box ligada no adb)
    [switch]$Instalar,
    # (antigo: nao precisa mais - o Arduino vai sempre no APK)
    [switch]$ComLeds,
    # Gera o APK sem a camera (o Arduino continua)
    [switch]$SemCamera,
    # Caminho do Godot 4.6.1 (opcional: se nao achar, o script baixa)
    [string]$CaminhoGodot = "",
    # Pasta de trabalho (opcional: o padrao e C:\StrikeKidsBuild)
    [string]$PastaTrabalho = ""
)
# STRIKE KIDS - GERAR APK (TV BOX ANDROID). Rode pelo GERAR_APK.bat.
#
# Faz tudo sozinho e mostra cada passo na tela:
#  - trabalha numa COPIA do projeto numa pasta curta e sem acentos
#    (C:\StrikeKidsBuild): o projeto original nao e alterado;
#  - acha ou BAIXA o que faltar: Godot 4.6.1, Java (JDK 17), Android SDK
#    (licencas, platform-tools, build-tools 35.0.1, plataforma 35, NDK) e os
#    templates Android do Godot (so a parte Android, ~300 MB, nao o pacote
#    inteiro de 1,2 GB);
#  - gera o APK pelo Gradle COM o Arduino (plugin StrikeSerial: os 5
#    sensores, a porta das bolas e o botao de configuracao) e a camera USB
#    (plugin StrikeCamera); se a camera atrapalhar, tenta sem ela. So se o
#    Gradle nao funcionar de jeito nenhum sai um APK sem os dois (e avisa);
#  - nenhum passo fica parado para sempre: cada programa tem tempo-limite.
# 1a vez: de 15 a 40 min (downloads). Depois: 2 a 5 min.
# Historico completo: build\android\GERACAO-COMPLETA.log (envie se falhar).

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
} catch { }
try { Add-Type -AssemblyName System.IO.Compression } catch { }
try { Add-Type -AssemblyName System.IO.Compression.FileSystem } catch { }

$Projeto = $PSScriptRoot.TrimEnd('\')
$IdGodot = "4.6.1.stable"
$ExeGodot = "Godot_v4.6.1-stable_win64.exe"
$UrlBase = "https://github.com/godotengine/godot-builds/releases/download/4.6.1-stable"
$UrlGodot = "$UrlBase/Godot_v4.6.1-stable_win64.exe.zip"
$UrlTemplates = "$UrlBase/Godot_v4.6.1-stable_export_templates.tpz"
$NomeTpz = "Godot_v4.6.1-stable_export_templates.tpz"
# versoes que o build Gradle do Godot 4.6.1 usa (android_source.zip: config.gradle)
$BuildTools = "35.0.1"
$PlataformaSdk = "android-35"
$VersaoNdk = "28.1.13356709"
$NomePreset = "Android TV Box"
$Pacote = "com.lazersport.strikekids"

$PastaLogs = Join-Path $Projeto "build\android"
$LogGeral = Join-Path $PastaLogs "GERACAO-COMPLETA.log"
$script:Etapa = 0
$script:TotalEtapas = 8
$script:Inicio = Get-Date

# ------------------------------------------------------------------ tela

function Titulo([string]$Texto) {
    $script:Etapa++
    Write-Host ""
    Write-Host ("[{0}/{1}] {2}" -f $script:Etapa, $script:TotalEtapas, $Texto) -ForegroundColor Cyan
}
function Info([string]$Texto) { Write-Host "    $Texto" }
function Ok([string]$Texto) { Write-Host "    OK: $Texto" -ForegroundColor Green }
function Aviso([string]$Texto) { Write-Host "    AVISO: $Texto" -ForegroundColor Yellow }

function Pasta([string]$Caminho) {
    [void][IO.Directory]::CreateDirectory($Caminho)
    return $Caminho
}

function Apagar([string]$Caminho) {
    if ($Caminho -and (Test-Path -LiteralPath $Caminho)) {
        Remove-Item -LiteralPath $Caminho -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# ------------------------------------------------------- rodar programas

# Junta argumentos como o Windows espera (aspas so onde precisa).
function Juntar-Argumentos([string[]]$Lista) {
    $partes = foreach ($a in $Lista) {
        if ($a -eq '') { '""' }
        elseif ($a -match '[\s";=,&()^|<>]') { '"' + (($a -replace '(\\*)"', '$1$1\"') -replace '(\\+)$', '$1$1') + '"' }
        else { $a }
    }
    return ($partes -join ' ')
}

# Mostra na tela o que o programa escreveu no log desde a ultima leitura.
function Mostrar-Novo([string]$Arquivo, [long]$Posicao, [bool]$Tudo) {
    if (-not (Test-Path -LiteralPath $Arquivo)) { return $Posicao }
    try {
        $fs = New-Object IO.FileStream($Arquivo, [IO.FileMode]::Open, [IO.FileAccess]::Read, ([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
    } catch { return $Posicao }
    try {
        if ($fs.Length -le $Posicao) { return $Posicao }
        [void]$fs.Seek($Posicao, [IO.SeekOrigin]::Begin)
        $n = [int][Math]::Min([long]4MB, [long]($fs.Length - $Posicao))
        $buf = New-Object byte[] $n
        $lidos = $fs.Read($buf, 0, $n)
        if ($lidos -le 0) { return $Posicao }
        # so ate o ultimo fim de linha; o resto fica para a proxima leitura
        $fim = $lidos - 1
        if (-not $Tudo) {
            while ($fim -ge 0 -and $buf[$fim] -ne 10 -and $buf[$fim] -ne 13) { $fim-- }
            if ($fim -lt 0) {
                if ($lidos -lt 4MB) { return $Posicao }
                $fim = $lidos - 1
            }
        }
        $texto = [Text.Encoding]::UTF8.GetString($buf, 0, $fim + 1)
        foreach ($linha in ($texto -split "`r`n|`n|`r")) {
            $l = $linha.TrimEnd()
            if (-not $l) { continue }
            # barras de progresso (sdkmanager): no maximo uma a cada 3 s
            if ($l -match '^\s*\[[=> ]*\]\s*\d+%' -or $l -match '^\s*\d+%') {
                if (((Get-Date) - $script:UltimoProgresso).TotalSeconds -lt 3) { continue }
                $script:UltimoProgresso = Get-Date
            }
            if ($l.Length -gt 300) { $l = $l.Substring(0, 300) + " ..." }
            Write-Host "      $l" -ForegroundColor Gray
            $script:UltimaSaida = Get-Date
        }
        return $Posicao + $fim + 1
    } finally { $fs.Dispose() }
}

# Roda um programa mostrando a saida ao vivo, com tempo-limite (nunca trava
# para sempre). Devolve o codigo de saida (-999 = estourou o tempo).
function Executar {
    param(
        [string]$Programa,
        [string[]]$Argumentos = @(),
        [string]$Log,
        [int]$LimiteMin = 30,
        [string]$Rotulo = "",
        [string]$Entrada = "",
        [string]$Diretorio = "",
        [switch]$Quieto
    )
    $exe = $Programa
    $linha = Juntar-Argumentos $Argumentos
    if ($Programa -match '\.(bat|cmd)$') {
        # .bat roda pelo cmd: /s /c "<linha inteira entre aspas>"
        $exe = $env:ComSpec
        $linha = '/d /s /c "' + (Juntar-Argumentos (@($Programa) + $Argumentos)) + '"'
    }
    $logErros = "$Log.erros"
    Apagar $Log
    Apagar $logErros
    $opcoes = @{
        FilePath = $exe
        NoNewWindow = $true
        PassThru = $true
        RedirectStandardOutput = $Log
        RedirectStandardError = $logErros
    }
    if ($linha) { $opcoes.ArgumentList = $linha }
    if ($Entrada) { $opcoes.RedirectStandardInput = $Entrada }
    if ($Diretorio) { $opcoes.WorkingDirectory = $Diretorio }
    $p = Start-Process @opcoes
    try { $null = $p.Handle } catch { }   # guarda o handle: sem isso o ExitCode pode vir vazio
    $pos = @{ $Log = 0L; $logErros = 0L }
    $comeco = Get-Date
    $script:UltimaSaida = $comeco
    $script:UltimoProgresso = $comeco.AddSeconds(-10)
    $estourou = $false
    while (-not $p.HasExited) {
        Start-Sleep -Milliseconds 700
        if (-not $Quieto) {
            foreach ($f in @($Log, $logErros)) { $pos[$f] = Mostrar-Novo $f $pos[$f] $false }
        }
        $agora = Get-Date
        $min = ($agora - $comeco).TotalMinutes
        if (($agora - $script:UltimaSaida).TotalSeconds -ge 60) {
            Write-Host ("      ... {0} trabalhando ha {1} min (normal, nao feche a janela)" -f $Rotulo, [int][Math]::Floor($min)) -ForegroundColor DarkGray
            $script:UltimaSaida = $agora
        }
        if ($min -ge $LimiteMin) {
            $estourou = $true
            Aviso "$Rotulo passou de $LimiteMin min: interrompido."
            try {
                Start-Process -FilePath "taskkill.exe" -ArgumentList "/PID $($p.Id) /T /F" -NoNewWindow -Wait -RedirectStandardOutput (Join-Path $script:Logs "taskkill.txt") -RedirectStandardError (Join-Path $script:Logs "taskkill-erros.txt")
            } catch { try { $p.Kill() } catch { } }
            break
        }
    }
    try { $p.WaitForExit(60000) | Out-Null } catch { }
    if (-not $Quieto) {
        foreach ($f in @($Log, $logErros)) { $pos[$f] = Mostrar-Novo $f $pos[$f] $true }
    }
    if ($estourou) { return -999 }
    return [int]$p.ExitCode
}

# Saida curta de um programa (ex.: "java -version"), com tempo-limite.
function Saida-De([string]$Programa, [string[]]$Argumentos, [int]$Segundos = 60) {
    try {
        $psi = New-Object Diagnostics.ProcessStartInfo
        $psi.FileName = $Programa
        $psi.Arguments = Juntar-Argumentos $Argumentos
        $psi.UseShellExecute = $false
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.CreateNoWindow = $true
        $p = [Diagnostics.Process]::Start($psi)
        $o = $p.StandardOutput.ReadToEndAsync()
        $e = $p.StandardError.ReadToEndAsync()
        if (-not $p.WaitForExit($Segundos * 1000)) {
            try { $p.Kill() } catch { }
            return ""
        }
        return ($o.Result + "`n" + $e.Result)
    } catch { return "" }
}

function Ler-Log([string]$Log) {
    $t = ""
    foreach ($f in @($Log, "$Log.erros")) {
        if (Test-Path -LiteralPath $f) {
            try { $t += [IO.File]::ReadAllText($f) + "`n" } catch { }
        }
    }
    return $t
}

# --------------------------------------------------------------- downloads

function Nova-Requisicao([string]$Url) {
    $r = [Net.HttpWebRequest]::Create($Url)
    $r.UserAgent = "StrikeKids-GerarApk"
    $r.Timeout = 60000
    $r.ReadWriteTimeout = 300000
    $r.AllowAutoRedirect = $true
    return $r
}

function Ler-Texto-Url([string]$Url) {
    $resp = (Nova-Requisicao $Url).GetResponse()
    try {
        $sr = New-Object IO.StreamReader($resp.GetResponseStream())
        return $sr.ReadToEnd()
    } finally { $resp.Close() }
}

function Copiar-Com-Progresso($Entrada, $Saida, [long]$Total) {
    $buf = New-Object byte[] 1048576
    $feito = 0L
    $proximo = 10
    $n = $Entrada.Read($buf, 0, $buf.Length)
    while ($n -gt 0) {
        $Saida.Write($buf, 0, $n)
        $feito += $n
        if ($Total -gt 0) {
            $pct = [int][Math]::Floor(100.0 * $feito / $Total)
            if ($pct -ge $proximo) {
                Write-Host ("      {0,3}%  ({1:N0} de {2:N0} MB)" -f $pct, ($feito / 1MB), ($Total / 1MB))
                $proximo = $pct + 10
            }
        }
        $n = $Entrada.Read($buf, 0, $buf.Length)
    }
    return $feito
}

function Baixar-Net([string]$Url, [string]$Arquivo) {
    $resp = (Nova-Requisicao $Url).GetResponse()
    try {
        $entrada = $resp.GetResponseStream()
        $saida = [IO.File]::Create($Arquivo)
        try { [void](Copiar-Com-Progresso $entrada $saida $resp.ContentLength) }
        finally { $saida.Dispose(); $entrada.Dispose() }
    } finally { $resp.Close() }
}

# Baixa um arquivo (curl.exe do Windows, que continua de onde parou;
# se nao der, pelo .NET). Devolve $true se o arquivo ficou pronto.
function Baixar([string]$Url, [string]$Destino, [string]$Nome) {
    if (Test-Path -LiteralPath $Destino) { return $true }
    [void](Pasta (Split-Path $Destino -Parent))
    $parte = "$Destino.parte"
    Info "Baixando $Nome ..."
    Info "  $Url"
    $curl = $null
    if ($env:SystemRoot) { $curl = Join-Path $env:SystemRoot "System32\curl.exe" }
    if ($curl -and (Test-Path -LiteralPath $curl)) {
        for ($i = 1; $i -le 3; $i++) {
            if ($i -eq 3) { Apagar $parte }
            & $curl -L --fail --retry 3 --retry-delay 5 --connect-timeout 30 -C - -o $parte $Url
            $cod = $LASTEXITCODE
            if ($cod -eq 0 -and (Test-Path -LiteralPath $parte)) {
                Move-Item -LiteralPath $parte -Destination $Destino -Force
                return $true
            }
            if ($cod -eq 22) { break }   # 404 etc.: tentar de novo nao adianta
            Aviso "download interrompido (curl $cod); tentando de novo ($i/3)..."
            Start-Sleep -Seconds 3
        }
    }
    try {
        Apagar $parte
        Baixar-Net $Url $parte
        Move-Item -LiteralPath $parte -Destination $Destino -Force
        return $true
    } catch {
        Apagar $parte
        Aviso "nao consegui baixar $Nome ($($_.Exception.Message))"
        return $false
    }
}

# ------------------------------------------------------------------- zips

function Zip-Valido([string]$Arquivo, [long]$Minimo = 1MB) {
    if (-not (Test-Path -LiteralPath $Arquivo)) { return $false }
    if ((Get-Item -LiteralPath $Arquivo).Length -lt $Minimo) { return $false }
    try {
        $z = [IO.Compression.ZipFile]::OpenRead($Arquivo)
        $n = $z.Entries.Count
        $z.Dispose()
        return ($n -gt 0)
    } catch { return $false }
}

function Extrair-Zip([string]$Zip, [string]$Destino) {
    [void](Pasta $Destino)
    $z = [IO.Compression.ZipFile]::OpenRead($Zip)
    try {
        foreach ($e in $z.Entries) {
            $alvo = [IO.Path]::Combine($Destino, $e.FullName)
            if ($e.FullName.EndsWith('/') -or $e.FullName.EndsWith('\')) {
                [void][IO.Directory]::CreateDirectory($alvo)
                continue
            }
            [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($alvo))
            [IO.Compression.ZipFileExtensions]::ExtractToFile($e, $alvo, $true)
        }
    } finally { $z.Dispose() }
}

# Tira do zip so os arquivos pedidos: @{ "pasta/arquivo" = "destino" }
function Extrair-DoZip([string]$Zip, [hashtable]$Quero) {
    $z = [IO.Compression.ZipFile]::OpenRead($Zip)
    try {
        foreach ($nome in @($Quero.Keys)) {
            $e = $z.GetEntry($nome)
            if (-not $e) { throw "$nome nao esta em $Zip" }
            [void](Pasta (Split-Path $Quero[$nome] -Parent))
            [IO.Compression.ZipFileExtensions]::ExtractToFile($e, $Quero[$nome], $true)
        }
    } finally { $z.Dispose() }
}

# --------------------------------------- zip remoto (so a parte Android)

function Ler-Faixa([string]$Url, [long]$Inicio, [long]$Fim) {
    $req = Nova-Requisicao $Url
    $req.AddRange($Inicio, $Fim)
    $resp = $req.GetResponse()
    try {
        if ([int]$resp.StatusCode -ne 206) { throw "o servidor nao aceitou download parcial (HTTP $([int]$resp.StatusCode))" }
        $entrada = $resp.GetResponseStream()
        try {
            $ms = New-Object IO.MemoryStream
            $entrada.CopyTo($ms)
            return , $ms.ToArray()
        } finally { $entrada.Dispose() }
    } finally { $resp.Close() }
}

function Tamanho-Remoto([string]$Url) {
    $req = Nova-Requisicao $Url
    $req.AddRange(0L, 0L)
    $resp = $req.GetResponse()
    try {
        $faixa = $resp.Headers["Content-Range"]
        if ([int]$resp.StatusCode -ne 206 -or -not $faixa) { throw "o servidor nao aceitou download parcial" }
        return [long]($faixa.Split('/')[1])
    } finally { $resp.Close() }
}

function Baixar-Faixa([string]$Url, [long]$Inicio, [long]$Tamanho, $Saida) {
    $feito = 0L
    $proximo = 10
    while ($feito -lt $Tamanho) {
        $n = [long][Math]::Min([long]16MB, [long]($Tamanho - $feito))
        $bytes = $null
        for ($t = 1; $t -le 5; $t++) {
            try {
                $bytes = Ler-Faixa $Url ($Inicio + $feito) ($Inicio + $feito + $n - 1)
                if ($bytes.Length -ne $n) { throw "parte incompleta" }
                break
            } catch {
                if ($t -eq 5) { throw }
                Start-Sleep -Seconds (3 * $t)
            }
        }
        $Saida.Write($bytes, 0, $bytes.Length)
        $feito += $n
        $pct = [int][Math]::Floor(100.0 * $feito / $Tamanho)
        if ($Tamanho -ge 4MB -and $pct -ge $proximo) {
            Write-Host ("      {0,3}%  ({1:N0} de {2:N0} MB)" -f $pct, ($feito / 1MB), ($Tamanho / 1MB))
            $proximo = $pct + 10
        }
    }
}

# Le o indice (fim) do zip remoto e baixa so os arquivos pedidos,
# em partes de 16 MB (cada parte com novas tentativas).
function Extrair-Remoto([string]$Url, [hashtable]$Quero) {
    $total = Tamanho-Remoto $Url
    $tamCauda = [long][Math]::Min([long]65557, $total)
    $cauda = Ler-Faixa $Url ($total - $tamCauda) ($total - 1)
    $i = -1
    for ($k = $cauda.Length - 22; $k -ge 0; $k--) {
        if ($cauda[$k] -eq 0x50 -and $cauda[$k + 1] -eq 0x4B -and $cauda[$k + 2] -eq 5 -and $cauda[$k + 3] -eq 6) { $i = $k; break }
    }
    if ($i -lt 0) { throw "indice do zip nao encontrado" }
    $tamIndice = [long][BitConverter]::ToUInt32($cauda, $i + 12)
    $posIndice = [long][BitConverter]::ToUInt32($cauda, $i + 16)
    if ($posIndice -eq 4294967295 -or $tamIndice -eq 4294967295) { throw "zip64 nao suportado" }
    $indice = Ler-Faixa $Url $posIndice ($posIndice + $tamIndice - 1)
    $achados = @{}
    $p = 0
    while ($p + 46 -le $indice.Length -and [BitConverter]::ToUInt32($indice, $p) -eq 0x02014B50) {
        $nNome = [BitConverter]::ToUInt16($indice, $p + 28)
        $nExtra = [BitConverter]::ToUInt16($indice, $p + 30)
        $nComent = [BitConverter]::ToUInt16($indice, $p + 32)
        $nome = [Text.Encoding]::UTF8.GetString($indice, $p + 46, $nNome)
        if ($Quero.ContainsKey($nome)) {
            $achados[$nome] = @{
                Metodo = [int][BitConverter]::ToUInt16($indice, $p + 10)
                Comprimido = [long][BitConverter]::ToUInt32($indice, $p + 20)
                Real = [long][BitConverter]::ToUInt32($indice, $p + 24)
                Local = [long][BitConverter]::ToUInt32($indice, $p + 42)
            }
        }
        $p += 46 + $nNome + $nExtra + $nComent
    }
    foreach ($nome in @($Quero.Keys)) {
        if (-not $achados.ContainsKey($nome)) { throw "$nome nao esta no pacote" }
    }
    foreach ($nome in @($Quero.Keys)) {
        $a = $achados[$nome]
        $cab = Ler-Faixa $Url $a.Local ($a.Local + 29)
        if ([BitConverter]::ToUInt32($cab, 0) -ne 0x04034B50) { throw "cabecalho invalido em $nome" }
        $dados = $a.Local + 30 + [BitConverter]::ToUInt16($cab, 26) + [BitConverter]::ToUInt16($cab, 28)
        $destino = $Quero[$nome]
        [void](Pasta (Split-Path $destino -Parent))
        $temp = "$destino.baixando"
        Info ("{0} ({1:N0} MB)" -f (Split-Path $nome -Leaf), ($a.Comprimido / 1MB))
        $fs = [IO.File]::Create($temp)
        try { if ($a.Comprimido -gt 0) { Baixar-Faixa $Url $dados $a.Comprimido $fs } }
        finally { $fs.Dispose() }
        if ($a.Metodo -eq 0) {
            Move-Item -LiteralPath $temp -Destination $destino -Force
        } elseif ($a.Metodo -eq 8) {
            $ent = [IO.File]::OpenRead($temp)
            try {
                $ds = New-Object IO.Compression.DeflateStream($ent, [IO.Compression.CompressionMode]::Decompress)
                $sai = [IO.File]::Create($destino)
                try { $ds.CopyTo($sai, 1048576) } finally { $sai.Dispose(); $ds.Dispose() }
            } finally { $ent.Dispose() }
            Apagar $temp
        } else { throw "compressao $($a.Metodo) nao suportada em $nome" }
        if ((Get-Item -LiteralPath $destino).Length -ne $a.Real) {
            Apagar $destino
            throw "$nome veio com tamanho errado"
        }
    }
}

# ------------------------------------------------------- pasta de trabalho

function Gravavel([string]$Caminho) {
    try {
        [void][IO.Directory]::CreateDirectory($Caminho)
        $t = Join-Path $Caminho ".teste-escrita"
        [IO.File]::WriteAllText($t, "ok")
        Remove-Item -LiteralPath $t -Force
        return $true
    } catch { return $false }
}

function Escolher-Trabalho {
    $opcoes = @()
    if ($PastaTrabalho) { $opcoes += $PastaTrabalho }
    $opcoes += (Join-Path $env:SystemDrive "StrikeKidsBuild")
    if ($env:PUBLIC) { $opcoes += (Join-Path $env:PUBLIC "StrikeKidsBuild") }
    if ($env:LOCALAPPDATA) { $opcoes += (Join-Path $env:LOCALAPPDATA "StrikeKidsBuild") }
    # de preferencia sem espacos nem acentos (o Gradle e o Android gostam)
    foreach ($c in $opcoes) {
        if ($c -match '^[A-Za-z0-9:\\/._-]+$' -and (Gravavel $c)) { return $c.TrimEnd('\') }
    }
    foreach ($c in $opcoes) {
        if ($c -and (Gravavel $c)) { return $c.TrimEnd('\') }
    }
    throw "nao consegui criar a pasta de trabalho (tente -PastaTrabalho D:\SKB)."
}

# ------------------------------------------------------------------ Godot

function Versao-Godot([string]$Exe) {
    $s = (Saida-De $Exe @("--version") 90).Trim()
    if ($s -match '(\d+\.\d+(?:\.\d+)?\.[a-z0-9]+)') { return $Matches[1] }
    return ""
}

function Achar-Godot {
    $lista = New-Object Collections.Generic.List[string]
    foreach ($c in @($CaminhoGodot, $env:GODOT, $env:GODOT_BIN)) {
        if ($c -and (Test-Path -LiteralPath $c -PathType Leaf)) {
            $lista.Add(($c -replace '_console\.exe$', '.exe'))
        }
    }
    $pastas = @($Projeto, (Split-Path $Projeto -Parent))
    if ($env:USERPROFILE) {
        $pastas += @((Join-Path $env:USERPROFILE "Downloads"), (Join-Path $env:USERPROFILE "Desktop"),
            (Join-Path $env:USERPROFILE "OneDrive\Desktop"), (Join-Path $env:USERPROFILE "Documents"))
    }
    try { $pastas += [Environment]::GetFolderPath("Desktop") } catch { }
    try { $pastas += [Environment]::GetFolderPath("MyDocuments") } catch { }
    $pastas += @("C:\Godot", "D:\Godot")
    if ($env:ProgramFiles) { $pastas += (Join-Path $env:ProgramFiles "Godot") }
    if ($env:LOCALAPPDATA) { $pastas += (Join-Path $env:LOCALAPPDATA "Programs") }
    foreach ($d in ($pastas | Where-Object { $_ } | Select-Object -Unique)) {
        if (-not (Test-Path -LiteralPath $d)) { continue }
        $achado = Get-ChildItem -LiteralPath $d -Recurse -Depth 3 -File -Filter $ExeGodot -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($achado) { $lista.Add($achado.FullName) }
    }
    foreach ($c in $lista) {
        if (Test-Path -LiteralPath $c) { return $c }
    }
    return $null
}

function Garantir-Godot {
    $pasta = Pasta (Join-Path $script:Trabalho "godot")
    $destino = Join-Path $pasta $ExeGodot
    if (-not (Test-Path -LiteralPath $destino)) {
        $achado = Achar-Godot
        if ($achado) {
            Info "Godot encontrado: $achado"
            Copy-Item -LiteralPath $achado -Destination $destino -Force
            $console = $achado -replace '\.exe$', '_console.exe'
            if (Test-Path -LiteralPath $console) { Copy-Item -LiteralPath $console -Destination ($destino -replace '\.exe$', '_console.exe') -Force }
        } else {
            Info "Godot 4.6.1 nao encontrado no PC: baixando (80 MB)."
            $zip = Join-Path $script:Downloads "Godot_v4.6.1-stable_win64.exe.zip"
            if (-not (Baixar $UrlGodot $zip "Godot 4.6.1")) { throw "nao consegui baixar o Godot 4.6.1. Baixe em godotengine.org e rode de novo." }
            if (-not (Zip-Valido $zip 10MB)) { Apagar $zip; throw "o download do Godot veio corrompido; rode de novo." }
            Extrair-Zip $zip $pasta
            if (-not (Test-Path -LiteralPath $destino)) {
                $x = Get-ChildItem -LiteralPath $pasta -Recurse -File -Filter $ExeGodot | Select-Object -First 1
                if ($x) { Move-Item -LiteralPath $x.FullName -Destination $destino -Force }
            }
        }
    }
    if (-not (Test-Path -LiteralPath $destino)) { throw "Godot 4.6.1 indisponivel." }
    Get-ChildItem -LiteralPath $pasta -File -Filter "*.exe" | ForEach-Object { try { Unblock-File -LiteralPath $_.FullName } catch { } }
    # modo "autocontido": configuracoes e templates deste Godot ficam nesta
    # pasta (nao mexe na configuracao do Godot que voce usa no dia a dia)
    [IO.File]::WriteAllText((Join-Path $pasta "_sc_"), "")
    $script:Godot = $destino
    $script:DadosGodot = Pasta (Join-Path $pasta "editor_data")
    $v = Versao-Godot $destino
    if ($v -and -not $v.StartsWith("4.6.1.")) {
        Apagar $destino
        throw "o Godot encontrado e a versao $v; o projeto precisa do 4.6.1 (rode de novo: o script baixa o certo)."
    }
    Ok "Godot $(if ($v) { $v } else { '4.6.1' }) em $pasta"
}

# ------------------------------------------------------------------- Java

function Versao-Java([string]$Pasta) {
    if (-not $Pasta) { return 0 }
    foreach ($f in @("java.exe", "javac.exe", "keytool.exe")) {
        if (-not (Test-Path -LiteralPath (Join-Path $Pasta "bin\$f"))) { return 0 }
    }
    $s = Saida-De (Join-Path $Pasta "bin\java.exe") @("-version") 60
    if ($s -match 'version "(\d+)(?:\.(\d+))?') {
        $maior = [int]$Matches[1]
        if ($maior -eq 1 -and $Matches[2]) { $maior = [int]$Matches[2] }
        return $maior
    }
    return 0
}

function Garantir-Java {
    $candidatos = New-Object Collections.Generic.List[string]
    foreach ($c in @($env:JAVA_HOME, $env:JDK_HOME)) { if ($c) { $candidatos.Add($c.TrimEnd('\')) } }
    foreach ($cmd in @(Get-Command javac.exe -All -ErrorAction SilentlyContinue)) {
        $candidatos.Add((Split-Path (Split-Path $cmd.Path -Parent) -Parent))
    }
    $bases = @((Join-Path $script:Trabalho "jdk"))
    foreach ($pf in @($env:ProgramFiles, ${env:ProgramW6432})) {
        if (-not $pf) { continue }
        foreach ($n in @("Eclipse Adoptium", "Java", "Microsoft", "Zulu", "Amazon Corretto", "BellSoft", "OpenJDK", "Semeru", "RedHat", "Android\Android Studio")) {
            $bases += (Join-Path $pf $n)
        }
    }
    foreach ($b in $bases) {
        if (-not (Test-Path -LiteralPath $b)) { continue }
        $candidatos.Add($b)
        Get-ChildItem -LiteralPath $b -Directory -ErrorAction SilentlyContinue | ForEach-Object { $candidatos.Add($_.FullName) }
    }
    $escolhido = $null
    $versao = 0
    foreach ($c in ($candidatos | Select-Object -Unique)) {
        $v = Versao-Java $c
        # o Gradle 8.11 do Godot roda com Java 17 a 23 (17 e o recomendado)
        if ($v -ge 17 -and $v -le 23) {
            if ($v -eq 17) { $escolhido = $c; $versao = 17; break }
            if (-not $escolhido) { $escolhido = $c; $versao = $v }
        }
    }
    if (-not $escolhido) {
        Info "Java (JDK 17) nao encontrado: baixando (~190 MB)."
        $zip = Join-Path $script:Downloads "jdk17-windows-x64.zip"
        $urls = @(
            "https://api.adoptium.net/v3/binary/latest/17/ga/windows/x64/jdk/hotspot/normal/eclipse?project=jdk",
            "https://aka.ms/download-jdk/microsoft-jdk-17-windows-x64.zip"
        )
        foreach ($u in $urls) {
            if ((Baixar $u $zip "Java JDK 17") -and (Zip-Valido $zip 50MB)) { break }
            Apagar $zip
        }
        if (-not (Test-Path -LiteralPath $zip)) { throw "nao consegui baixar o Java JDK 17. Instale o 'Temurin 17 JDK' (adoptium.net) e rode de novo." }
        $destJdk = Join-Path $script:Trabalho "jdk"
        Apagar $destJdk
        Info "Extraindo o Java..."
        Extrair-Zip $zip $destJdk
        foreach ($d in (Get-ChildItem -LiteralPath $destJdk -Directory)) {
            $v = Versao-Java $d.FullName
            if ($v -ge 17) { $escolhido = $d.FullName; $versao = $v; break }
        }
        if (-not $escolhido) { throw "o Java baixado nao funcionou." }
    }
    $script:JavaHome = (Resolve-Path -LiteralPath $escolhido).Path.TrimEnd('\')
    $env:JAVA_HOME = $script:JavaHome
    $env:PATH = (Join-Path $script:JavaHome "bin") + ";" + $env:PATH
    Ok "Java $versao em $($script:JavaHome)"
}

# ------------------------------------------------------------ Android SDK

function Achar-Sdkmanager([string]$Sdk) {
    $lista = @()
    $raiz = Join-Path $Sdk "cmdline-tools"
    if (Test-Path -LiteralPath (Join-Path $raiz "latest\bin\sdkmanager.bat")) { $lista += (Join-Path $raiz "latest\bin\sdkmanager.bat") }
    if (Test-Path -LiteralPath $raiz) {
        Get-ChildItem -LiteralPath $raiz -Directory | Sort-Object Name -Descending | ForEach-Object {
            $b = Join-Path $_.FullName "bin\sdkmanager.bat"
            if (Test-Path -LiteralPath $b) { $lista += $b }
        }
    }
    foreach ($b in $lista) {
        $props = Join-Path (Split-Path (Split-Path $b -Parent) -Parent) "source.properties"
        $rev = 0
        if (Test-Path -LiteralPath $props) {
            $m = [regex]::Match([IO.File]::ReadAllText($props), 'Pkg\.Revision=(\d+)')
            if ($m.Success) { $rev = [int]$m.Groups[1].Value }
        }
        # versoes antigas nao rodam com o Java 17
        if ($rev -ge 8) { return $b }
    }
    return $null
}

function Garantir-Sdkmanager([string]$Sdk) {
    $b = Achar-Sdkmanager $Sdk
    if ($b) { return $b }
    Info "Instalando as ferramentas do Android SDK (cmdline-tools)..."
    $numeros = @()
    try {
        $xml = Ler-Texto-Url "https://dl.google.com/android/repository/repository2-3.xml"
        $numeros += @([regex]::Matches($xml, 'commandlinetools-win-(\d+)_latest\.zip') | ForEach-Object { [long]$_.Groups[1].Value } | Sort-Object -Descending)
    } catch { }
    $numeros += @(13114758, 12266719, 11479570, 11076708)
    foreach ($n in ($numeros | Select-Object -Unique)) {
        $zip = Join-Path $script:Downloads "commandlinetools-win-$n.zip"
        if (-not (Baixar "https://dl.google.com/android/repository/commandlinetools-win-${n}_latest.zip" $zip "Android cmdline-tools")) { continue }
        if (-not (Zip-Valido $zip 10MB)) { Apagar $zip; continue }
        $tmp = Join-Path $Sdk "cmdline-tools\_novo"
        Apagar $tmp
        Extrair-Zip $zip $tmp
        $latest = Join-Path $Sdk "cmdline-tools\latest"
        Apagar $latest
        Move-Item -LiteralPath (Join-Path $tmp "cmdline-tools") -Destination $latest -Force
        Apagar $tmp
        break
    }
    return (Achar-Sdkmanager $Sdk)
}

# As mesmas licencas que o "sdkmanager --licenses" grava ao aceitar.
function Gravar-Licencas([string]$Sdk) {
    $pasta = Pasta (Join-Path $Sdk "licenses")
    $licencas = @{
        "android-sdk-license" = @("8933bad161af4178b1185d1a37fbf41ea5269c55", "d56f5187479451eabf01fb78af6dfcb131a6481e", "24333f8a63b6825ea9c5514f83c2829b004d1fee")
        "android-sdk-preview-license" = @("84831b9409646a918e30573bab4c9c91346d8abd")
        "android-sdk-arm-dbt-license" = @("859f317696f67ef3d7f30a50a5560e7834b43903")
    }
    foreach ($nome in @($licencas.Keys)) {
        $arq = Join-Path $pasta $nome
        $atual = ""
        if (Test-Path -LiteralPath $arq) { $atual = [IO.File]::ReadAllText($arq) }
        $novo = $atual
        foreach ($h in $licencas[$nome]) { if (-not $novo.Contains($h)) { $novo = $novo.TrimEnd() + "`n" + $h } }
        if ($novo -ne $atual) { [IO.File]::WriteAllText($arq, $novo) }
    }
}

function Tem-Apksigner([string]$Sdk) {
    $bt = Join-Path $Sdk "build-tools"
    if (-not (Test-Path -LiteralPath $bt)) { return $false }
    foreach ($d in (Get-ChildItem -LiteralPath $bt -Directory -ErrorAction SilentlyContinue)) {
        if (Test-Path -LiteralPath (Join-Path $d.FullName "apksigner.bat")) { return $true }
    }
    return $false
}

function Faltando-Sdk([string]$Sdk, [bool]$Gradle) {
    $p = @()
    if (-not (Test-Path -LiteralPath (Join-Path $Sdk "platform-tools\adb.exe"))) { $p += "platform-tools" }
    if (-not (Test-Path -LiteralPath (Join-Path $Sdk "build-tools\$BuildTools\apksigner.bat"))) { $p += "build-tools;$BuildTools" }
    if ($Gradle) {
        if (-not (Test-Path -LiteralPath (Join-Path $Sdk "platforms\$PlataformaSdk\android.jar"))) { $p += "platforms;$PlataformaSdk" }
        if (-not (Test-Path -LiteralPath (Join-Path $Sdk "ndk\$VersaoNdk\source.properties"))) { $p += "ndk;$VersaoNdk" }
    }
    return , $p
}

function Garantir-Sdk {
    $candidatos = @($env:ANDROID_HOME, $env:ANDROID_SDK_ROOT, "C:\AndroidSdk", "C:\Android\Sdk", "C:\Android\android-sdk")
    if ($env:LOCALAPPDATA) { $candidatos += (Join-Path $env:LOCALAPPDATA "Android\Sdk") }
    if (${env:ProgramFiles(x86)}) { $candidatos += (Join-Path ${env:ProgramFiles(x86)} "Android\android-sdk") }
    $candidatos += (Join-Path $script:Trabalho "android-sdk")
    $candidatos = @($candidatos | Where-Object { $_ } | ForEach-Object { $_.TrimEnd('\') } | Select-Object -Unique)
    $sdk = $null
    foreach ($c in $candidatos) {
        if ((Test-Path -LiteralPath (Join-Path $c "platform-tools\adb.exe")) -and (Tem-Apksigner $c)) { $sdk = $c; break }
    }
    if (-not $sdk) {
        foreach ($c in $candidatos) {
            if ((Test-Path -LiteralPath (Join-Path $c "platform-tools")) -or (Test-Path -LiteralPath (Join-Path $c "build-tools")) -or (Test-Path -LiteralPath (Join-Path $c "cmdline-tools"))) { $sdk = $c; break }
        }
    }
    if (-not $sdk) {
        $sdk = Join-Path $env:SystemDrive "AndroidSdk"
        if (-not (Gravavel $sdk)) { $sdk = Join-Path $script:Trabalho "android-sdk" }
        Info "Android SDK nao encontrado: instalando em $sdk"
    } else {
        Info "Android SDK: $sdk"
    }
    [void](Pasta $sdk)
    $script:Sdk = $sdk
    $env:ANDROID_HOME = $sdk
    $env:ANDROID_SDK_ROOT = $sdk
    Gravar-Licencas $sdk
    $faltam = Faltando-Sdk $sdk $script:QuerGradle
    if ($faltam.Count -gt 0) {
        Info ("Faltando no SDK: " + ($faltam -join ", "))
        $sdkmanager = Garantir-Sdkmanager $sdk
        if (-not $sdkmanager) {
            Aviso "nao consegui instalar o sdkmanager (sem acesso ao dl.google.com?)."
        } else {
            $sim = Join-Path $script:Trabalho "sim.txt"
            [IO.File]::WriteAllText($sim, ("y`r`n" * 60))
            Info "Aceitando as licencas do Android SDK..."
            [void](Executar $sdkmanager @("--sdk_root=$sdk", "--licenses") -Log (Join-Path $script:Logs "sdk-licencas.log") -LimiteMin 10 -Rotulo "sdkmanager" -Entrada $sim -Quieto)
            Info "Instalando: $($faltam -join ', ') (o NDK e grande: pode demorar)"
            $cod = Executar $sdkmanager (@("--sdk_root=$sdk", "--install") + $faltam) -Log (Join-Path $script:Logs "sdk-instalar.log") -LimiteMin 90 -Rotulo "sdkmanager" -Entrada $sim
            if ($cod -ne 0) { Aviso "o sdkmanager terminou com o codigo $cod (veja sdk-instalar.log)." }
        }
    }
    if (-not (Test-Path -LiteralPath (Join-Path $sdk "platform-tools\adb.exe")) -or -not (Tem-Apksigner $sdk)) {
        throw "o Android SDK em $sdk ficou incompleto (falta platform-tools ou build-tools). Confira a internet e rode de novo."
    }
    $resto = Faltando-Sdk $sdk $script:QuerGradle
    if ($resto.Count -gt 0) {
        Aviso ("ainda falta no SDK: " + ($resto -join ", ") + " (o Gradle tenta baixar sozinho).")
    } else {
        Ok "Android SDK completo"
    }
}

# -------------------------------------------------------------- templates

function Garantir-Templates {
    $pasta = Pasta (Join-Path $script:DadosGodot "export_templates\$IdGodot")
    $script:PastaTemplates = $pasta
    [IO.File]::WriteAllText((Join-Path $pasta "version.txt"), "$IdGodot`n")
    $precisa = @("android_release.apk")
    if ($script:QuerGradle) { $precisa += "android_source.zip" }
    $faltam = { @($precisa | Where-Object { -not (Zip-Valido (Join-Path $pasta $_) 10MB) }) }
    if ((& $faltam).Count -eq 0) { Ok "templates Android $IdGodot prontos"; return }
    # 1) ja instalados pelo Godot deste PC
    $origens = @()
    if ($env:APPDATA) { $origens += (Join-Path $env:APPDATA "Godot\export_templates\$IdGodot") }
    foreach ($o in $origens) {
        foreach ($f in (& $faltam)) {
            $src = Join-Path $o $f
            if (Zip-Valido $src 10MB) {
                Info "copiando $f de $o"
                Copy-Item -LiteralPath $src -Destination (Join-Path $pasta $f) -Force
            }
        }
    }
    if ((& $faltam).Count -eq 0) { Ok "templates Android copiados do Godot deste PC"; return }
    # 2) o pacote .tpz ja baixado (Downloads, Desktop, pasta do projeto)
    $locais = @((Join-Path $script:Downloads $NomeTpz), (Join-Path $Projeto $NomeTpz), (Join-Path (Split-Path $Projeto -Parent) $NomeTpz))
    if ($env:USERPROFILE) { $locais += @((Join-Path $env:USERPROFILE "Downloads\$NomeTpz"), (Join-Path $env:USERPROFILE "Desktop\$NomeTpz")) }
    foreach ($tpz in $locais) {
        if ((& $faltam).Count -eq 0) { break }
        if (-not (Zip-Valido $tpz 100MB)) { continue }
        Info "extraindo do pacote $tpz"
        $mapa = @{}
        foreach ($f in (& $faltam)) { $mapa["templates/$f"] = Join-Path $pasta $f }
        try { Extrair-DoZip $tpz $mapa } catch { Aviso $_.Exception.Message }
    }
    if ((& $faltam).Count -eq 0) { Ok "templates Android extraidos"; return }
    # 3) baixa so a parte Android do pacote oficial (~300 MB em vez de 1,2 GB)
    Info "Baixando so a parte Android dos templates oficiais do Godot 4.6.1..."
    $mapa = @{}
    foreach ($f in (& $faltam)) { $mapa["templates/$f"] = Join-Path $pasta $f }
    try { Extrair-Remoto $UrlTemplates $mapa } catch { Aviso "download parcial falhou ($($_.Exception.Message)); baixando o pacote inteiro." }
    if ((& $faltam).Count -eq 0) { Ok "templates Android baixados"; return }
    # 4) o pacote inteiro (1,2 GB), com retomada
    $tpz = Join-Path $script:Downloads $NomeTpz
    if (-not (Baixar $UrlTemplates $tpz "templates do Godot 4.6.1 (1,2 GB)")) { throw "nao consegui baixar os templates do Godot." }
    $mapa = @{}
    foreach ($f in (& $faltam)) { $mapa["templates/$f"] = Join-Path $pasta $f }
    Extrair-DoZip $tpz $mapa
    if ((& $faltam).Count -gt 0) { throw "templates Android incompletos." }
    Ok "templates Android prontos"
}

# --------------------------------------------------- copia do projeto

function Copiar-Projeto {
    $script:Copia = Pasta (Join-Path $script:Trabalho "projeto")
    # limpa a copia anterior, menos o cache de importacao (.godot) e o
    # modelo Gradle (android): assim a 2a vez e bem mais rapida
    Get-ChildItem -LiteralPath $script:Copia -Force | Where-Object { @('.godot', 'android') -notcontains $_.Name } | Remove-Item -Recurse -Force
    $fora = @('.godot', 'android', 'build', 'APK-Pronto', '.git') | ForEach-Object { Join-Path $Projeto $_ }
    $argumentos = @($Projeto, $script:Copia, '/E', '/R:2', '/W:1', '/NFL', '/NDL', '/NJH', '/NJS', '/NP', '/XD') + $fora
    & robocopy.exe @argumentos | Out-Null
    if ($LASTEXITCODE -ge 8) { throw "falha ao copiar o projeto para $($script:Copia) (robocopy $LASTEXITCODE)." }
    if (-not (Test-Path -LiteralPath (Join-Path $script:Copia "project.godot"))) { throw "a copia do projeto ficou incompleta." }
    Ok "projeto copiado para $($script:Copia)"
}

# Liga/desliga o Gradle, os plugins (Arduino e camera) e o giro NA COPIA
# do projeto.
function Preparar-Projeto([bool]$Gradle, [bool]$Camera) {
    $gradle = $Gradle
    $utf8 = New-Object Text.UTF8Encoding($false)
    $presets = Join-Path $script:Copia "export_presets.cfg"
    $t = [IO.File]::ReadAllText($presets)
    $t = [Regex]::Replace($t, '(?m)^gradle_build/use_gradle_build=[^\r\n]*', "gradle_build/use_gradle_build=$($gradle.ToString().ToLower())")
    $t = [Regex]::Replace($t, '(?m)^gradle_build/min_sdk=[^\r\n]*', 'gradle_build/min_sdk=""')
    $t = [Regex]::Replace($t, '(?m)^gradle_build/target_sdk=[^\r\n]*', 'gradle_build/target_sdk=""')
    $t = [Regex]::Replace($t, '(?m)^package/show_in_android_tv=[^\r\n]*', 'package/show_in_android_tv=false')
    [IO.File]::WriteAllText($presets, $t, $utf8)
    $proj = Join-Path $script:Copia "project.godot"
    $c = [IO.File]::ReadAllText($proj)
    $c = [Regex]::Replace($c, '(?m)^tela/giro=[^\r\n]*', "tela/giro=$Giro")
    # imagem de abertura (logo Lazer & Sport) ja girada como a tela do jogo
    if ($Giro -eq 1) { $s = "1" } elseif ($Giro -eq -1) { $s = "m1" } else { $s = "0" }
    $c = [Regex]::Replace($c, '(?m)^boot_splash/image\.android=[^\r\n]*', "boot_splash/image.android=""res://ui/splash_giro_$s.png""")
    # plugins Android: so entram no APK pelo Gradle. O do Arduino vai
    # sempre (sem ele a maquina nao le os sensores); o da camera, se pedido.
    $plugins = @()
    $ignCamera = Join-Path $script:Copia "addons\StrikeCamera\.gdignore"
    $ignSerial = Join-Path $script:Copia "addons\StrikeSerial\.gdignore"
    Apagar (Join-Path $script:Copia "addons\.gdignore")
    if ($Gradle -and $Camera) { $plugins += '"res://addons/StrikeCamera/plugin.cfg"'; Apagar $ignCamera }
    else { [IO.File]::WriteAllText($ignCamera, "") }
    if ($Gradle) { $plugins += '"res://addons/StrikeSerial/plugin.cfg"'; Apagar $ignSerial }
    else { [IO.File]::WriteAllText($ignSerial, "") }
    $c = [Regex]::Replace($c, '(?ms)^\[editor_plugins\]\s*enabled=PackedStringArray\([^)]*\)\s*', '')
    if ($plugins.Count -gt 0) {
        $c = $c.TrimEnd() + "`n`n[editor_plugins]`n`nenabled=PackedStringArray(" + ($plugins -join ", ") + ")`n"
    }
    [IO.File]::WriteAllText($proj, $c, $utf8)
}

# Instala o modelo Gradle (o que o menu Projeto > Instalar Modelo de
# Build Android faz): android/build + android/.build_version.
function Instalar-ModeloGradle {
    $android = Pasta (Join-Path $script:Copia "android")
    $build = Join-Path $android "build"
    $versao = Join-Path $android ".build_version"
    $instalado = (Test-Path -LiteralPath (Join-Path $build "build.gradle")) -and (Test-Path -LiteralPath $versao)
    if ($instalado -and ([IO.File]::ReadAllText($versao).Trim() -eq $IdGodot)) { Ok "modelo Gradle ja instalado"; return }
    Info "Instalando o modelo Gradle do Godot $IdGodot na copia do projeto..."
    Apagar $build
    [void](Pasta $build)
    [IO.File]::WriteAllText($versao, "$IdGodot`n")
    [IO.File]::WriteAllText((Join-Path $build ".gdignore"), "`n")
    Extrair-Zip (Join-Path $script:PastaTemplates "android_source.zip") $build
    if (-not (Test-Path -LiteralPath (Join-Path $build "build.gradle"))) { throw "o modelo Gradle nao foi instalado." }
    Ok "modelo Gradle instalado"
}

# O Godot (autocontido) le o Java e o Android SDK daqui.
function Escrever-ConfigEditor {
    $arq = Join-Path $script:DadosGodot "editor_settings-4.6.tres"
    $j = $script:JavaHome.Replace('\', '/')
    $s = $script:Sdk.Replace('\', '/')
    $texto = "[gd_resource type=""EditorSettings"" format=3]`n`n[resource]`nexport/android/java_sdk_path = ""$j""`nexport/android/android_sdk_path = ""$s""`n"
    [IO.File]::WriteAllText($arq, $texto, (New-Object Text.UTF8Encoding($false)))
}

# Chave de assinatura do Strike Kids: vai JUNTO do projeto
# (tools\android\strikekids.keystore), entao o APK gerado em qualquer PC
# (e o APK pronto que veio no pacote) instala POR CIMA do anterior na TV
# Box, sem perder os recordes. Se ela faltar, usa a chave debug do Godot.
function Garantir-Chave {
    $keytool = Join-Path $script:JavaHome "bin\keytool.exe"
    $local = Join-Path (Pasta (Join-Path $script:Trabalho "chave")) "strikekids.keystore"
    $teste = { param($k, $alias, $senha) (Saida-De $keytool @("-list", "-keystore", $k, "-storepass", $senha, "-alias", $alias) 60) -match 'PrivateKeyEntry' }
    $opcoes = @(@{ Arquivo = (Join-Path $Projeto "tools\android\strikekids.keystore"); Alias = "strikekids"; Senha = "strikekids" })
    if ($env:APPDATA) { $opcoes += @{ Arquivo = (Join-Path $env:APPDATA "Godot\keystores\debug.keystore"); Alias = "androiddebugkey"; Senha = "android" } }
    $opcoes += @{ Arquivo = (Join-Path $script:Trabalho "chave\nova.keystore"); Alias = "strikekids"; Senha = "strikekids" }
    $escolhida = $null
    foreach ($o in $opcoes) {
        if ((Test-Path -LiteralPath $o.Arquivo) -and (& $teste $o.Arquivo $o.Alias $o.Senha)) { $escolhida = $o; break }
    }
    if (-not $escolhida) {
        Info "Criando uma chave de assinatura para o APK..."
        $escolhida = @{ Arquivo = (Join-Path $script:Trabalho "chave\nova.keystore"); Alias = "strikekids"; Senha = "strikekids" }
        Apagar $escolhida.Arquivo
        [void](Executar $keytool @("-genkeypair", "-keystore", $escolhida.Arquivo, "-storetype", "PKCS12", "-storepass", "strikekids", "-keypass", "strikekids", "-alias", "strikekids", "-dname", "CN=Strike Kids,O=Lazer e Sport,C=BR", "-keyalg", "RSA", "-keysize", "2048", "-validity", "10000") -Log (Join-Path $script:Logs "keytool.log") -LimiteMin 5 -Rotulo "keytool" -Quieto)
        if (-not (Test-Path -LiteralPath $escolhida.Arquivo)) { throw "nao consegui criar a chave de assinatura (veja keytool.log)." }
        Aviso "chave NOVA: se a TV Box ja tiver um Strike Kids com outra chave, desinstale-o antes de instalar este APK."
    }
    Copy-Item -LiteralPath $escolhida.Arquivo -Destination $local -Force
    $env:GODOT_ANDROID_KEYSTORE_RELEASE_PATH = $local
    $env:GODOT_ANDROID_KEYSTORE_RELEASE_USER = $escolhida.Alias
    $env:GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD = $escolhida.Senha
    Ok "chave de assinatura: $($escolhida.Arquivo)"
}

# ----------------------------------------------------------------- Gradle

function Gradlew { return (Join-Path $script:Copia "android\build\gradlew.bat") }

# Baixa o Gradle e o plugin Android ANTES da exportacao, mostrando o
# progresso (dentro do Godot o Gradle trabalha calado). Devolve "" se ok.
function Preparar-Gradle {
    $g = Gradlew
    $dir = Split-Path $g -Parent
    Info "Gradle 8.11.1 (1a vez baixa ~150 MB)..."
    $cod = Executar $g @("--version") -Log (Join-Path $script:Logs "gradle-versao.log") -LimiteMin 30 -Rotulo "Gradle" -Diretorio $dir
    if ($cod -ne 0) { return "o Gradle nao foi baixado (internet?) - veja gradle-versao.log" }
    $marca = Join-Path $env:GRADLE_USER_HOME "strikekids-ok.txt"
    if (-not (Test-Path -LiteralPath $marca)) {
        Info "Gradle: baixando o plugin Android (1a vez; alguns minutos)..."
        $cod = Executar $g @("help", "--console=plain") -Log (Join-Path $script:Logs "gradle-plugin.log") -LimiteMin 45 -Rotulo "Gradle" -Diretorio $dir
        if ($cod -ne 0) { return "o Gradle nao conseguiu preparar o build Android - veja gradle-plugin.log" }
    }
    return ""
}

function Parar-Gradle {
    $g = Gradlew
    if (Test-Path -LiteralPath $g) {
        try { [void](Executar $g @("--stop") -Log (Join-Path $script:Logs "gradle-parar.log") -LimiteMin 3 -Rotulo "Gradle" -Diretorio (Split-Path $g -Parent) -Quieto) } catch { }
    }
}

# ---------------------------------------------------------------- exportar

function Exportar([bool]$Gradle, [bool]$Camera) {
    Preparar-Projeto $Gradle $Camera
    $gradle = $Gradle
    $saida = Pasta (Join-Path $script:Trabalho "saida")
    Get-ChildItem -LiteralPath $saida -Force | Remove-Item -Recurse -Force
    $apk = Join-Path $saida "StrikeKids.apk"
    $nome = "exportar-sem-gradle.log"
    if ($gradle -and $Camera) { $nome = "exportar-gradle-com-camera.log" }
    elseif ($gradle) { $nome = "exportar-gradle-sem-camera.log" }
    $log = Join-Path $script:Logs $nome
    $limite = 40
    if ($gradle) { $limite = 90 }
    $script:UltimoLogExportacao = $log
    for ($tentativa = 1; $tentativa -le 2; $tentativa++) {
        $cod = Executar $script:Godot @("--headless", "--path", $script:Copia, "--export-release", $NomePreset, $apk) -Log $log -LimiteMin $limite -Rotulo "Godot" -Diretorio $script:Copia
        $texto = Ler-Log $log
        if ($cod -eq 0 -and (Zip-Valido $apk 5MB)) { return $apk }
        if ($cod -eq -999 -and (Zip-Valido $apk 5MB) -and $texto -match 'DONE \] export') { return $apk }
        if ($texto -match 'SCRIPT ERROR: Parse Error|Failed to load script|Failed to create an autoload') {
            throw "erro de script no projeto Godot (veja $log)."
        }
        # 0, 1 = o Godot terminou normalmente (deu erro de exportacao);
        # outro codigo = fechou no meio (ex.: importacao) -> tenta de novo
        if ($cod -eq 0 -or $cod -eq 1 -or $cod -eq -999) { break }
        Aviso "o Godot fechou no meio (codigo $cod); tentando de novo..."
    }
    return $null
}

function Mostrar-Motivo([string]$Log) {
    $linhas = @((Ler-Log $Log) -split "`r`n|`n")
    $i = -1
    for ($k = 0; $k -lt $linhas.Count; $k++) { if ($linhas[$k] -match 'What went wrong') { $i = $k; break } }
    $trecho = @()
    if ($i -ge 0) { $trecho = $linhas[$i..([Math]::Min($i + 14, $linhas.Count - 1))] }
    else { $trecho = @($linhas | Where-Object { $_ -match 'ERROR|error:|FAILURE|Could not|failed' } | Select-Object -Last 15) }
    foreach ($l in $trecho) { if ($l.Trim()) { Write-Host "      $l" -ForegroundColor Yellow } }
}

# --------------------------------------------------------------- principal

function Principal {
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host " STRIKE KIDS - GERAR APK PARA A TV BOX (Godot 4.6.1)" -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host " A 1a vez baixa o que faltar e pode levar de 15 a 40 min."
    Write-Host " Nao feche a janela. Se clicar dentro dela e o texto parar,"
    Write-Host " aperte ESC (o Windows pausa a janela quando se seleciona texto)."
    Write-Host " Projeto: $Projeto"
    if (-not (Test-Path -LiteralPath (Join-Path $Projeto "project.godot"))) {
        throw "project.godot nao encontrado. Extraia o ZIP inteiro e rode o GERAR_APK.bat de dentro da pasta strike-kids."
    }
    if (-not [Environment]::Is64BitOperatingSystem) { throw "este gerador precisa do Windows 64 bits." }
    # o Gradle e sempre preciso: o plugin do Arduino (sensores, porta e
    # botao de configuracao) so entra no APK por ele
    $script:QuerGradle = $true
    if ($Instalar) { $script:TotalEtapas = 9 }

    Titulo "Pasta de trabalho"
    $script:Trabalho = Escolher-Trabalho
    $script:Downloads = Pasta (Join-Path $script:Trabalho "downloads")
    $script:Logs = Pasta (Join-Path $script:Trabalho "logs")
    $env:TEMP = Pasta (Join-Path $script:Trabalho "tmp")
    $env:TMP = $env:TEMP
    $env:GRADLE_USER_HOME = Pasta (Join-Path $script:Trabalho "gradle")
    $env:ANDROID_USER_HOME = Pasta (Join-Path $script:Trabalho "android-user")
    Ok $script:Trabalho
    try {
        $drive = Split-Path $script:Trabalho -Qualifier
        $livre = (Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$drive'").FreeSpace
        Info ("Espaco livre em {0} {1:N1} GB" -f $drive, ($livre / 1GB))
        if ($livre -lt 8GB) { Aviso "pouco espaco: a 1a geracao com camera precisa de uns 8 GB (SDK, NDK, Gradle)." }
    } catch { }

    Titulo "Godot 4.6.1"
    Garantir-Godot

    Titulo "Java (JDK 17)"
    Garantir-Java

    Titulo "Android SDK"
    Garantir-Sdk

    Titulo "Templates Android do Godot"
    Garantir-Templates

    Titulo "Copia do projeto"
    Copiar-Projeto
    Escrever-ConfigEditor
    Garantir-Chave

    Titulo "Exportando o APK"
    $apk = $null
    $comCamera = $false
    $comArduino = $false
    $motivo = ""
    if ($script:QuerGradle) {
        Instalar-ModeloGradle
        $motivo = Preparar-Gradle
        if (-not $motivo) {
            Info "Exportando COM o Arduino e a camera (Godot + Gradle). Na 1a vez o Gradle"
            Info "ainda baixa bibliotecas e trabalha uns minutos sem escrever nada: e normal."
            $querCamera = -not $SemCamera
            $apk = Exportar $true $querCamera
            if (-not $apk -and $querCamera) {
                # a libuvc (webcam direto pelo USB) vem do JitPack: se ele
                # falhar, a camera continua pela camera do sistema e Camera2
                Mostrar-Motivo $script:UltimoLogExportacao
                Aviso "o build com a UVC direta falhou; tentando a camera sem ela..."
                $env:STRIKE_SEM_UVC = "1"
                $apk = Exportar $true $true
                if ($apk) { $script:SemUvc = $true }
            }
            if (-not $apk -and $querCamera) {
                Mostrar-Motivo $script:UltimoLogExportacao
                Aviso "o build com a camera falhou; tentando so com o Arduino..."
                $querCamera = $false
                $apk = Exportar $true $false
            }
            if ($apk) {
                $comArduino = $true
                $comCamera = $querCamera
                [IO.File]::WriteAllText((Join-Path $env:GRADLE_USER_HOME "strikekids-ok.txt"), (Get-Date).ToString("s"))
            } else {
                $motivo = "o build Gradle falhou"
                Mostrar-Motivo $script:UltimoLogExportacao
            }
        }
        Parar-Gradle
        if (-not $apk) {
            Aviso "$motivo. Gerando um APK SEM o Arduino e SEM a camera: os sensores, a porta e o botao de configuracao NAO funcionam nele (so a Zero Delay). Para a maquina, use o APK pronto que veio no pacote."
        }
    }
    if (-not $apk) {
        $apk = Exportar $false $false
        if (-not $apk) {
            Mostrar-Motivo $script:UltimoLogExportacao
            throw "o Godot nao gerou o APK (veja $($script:UltimoLogExportacao))."
        }
    }

    Titulo "Entregando o APK"
    $pastaApk = Pasta (Join-Path $Projeto "APK-Pronto")
    Get-ChildItem -LiteralPath $pastaApk -Force | Remove-Item -Recurse -Force
    $final = Join-Path $pastaApk "StrikeKids.apk"
    Copy-Item -LiteralPath $apk -Destination $final -Force
    $tamanho = (Get-Item -LiteralPath $final).Length
    $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $final).Hash
    $minutos = [int][Math]::Ceiling(((Get-Date) - $script:Inicio).TotalMinutes)
    Write-Host ""
    Write-Host "APK GERADO COM SUCESSO" -ForegroundColor Green
    Write-Host "  Arquivo: $final"
    Write-Host ("  Tamanho: {0:N1} MB   (levou {1} min)" -f ($tamanho / 1MB), $minutos)
    Write-Host "  SHA256:  $hash"
    if ($comArduino) {
        Write-Host "  Arduino (5 sensores, porta das bolas, botao de configuracao, LEDs): INCLUIDO." -ForegroundColor Green
        Write-Host "  Na 1a vez a TV Box pergunta sobre o Arduino no USB: marque 'Usar por padrao' e OK."
    } else {
        Write-Host "  Arduino: NAO incluido (sem o Gradle). Os sensores so funcionam pela Zero Delay." -ForegroundColor Red
        Write-Host "  Para a maquina com o Arduino, use o APK pronto do pacote (StrikeKids_v5.0_TVBox.apk)." -ForegroundColor Red
    }
    if ($comCamera) {
        Write-Host "  Camera USB: INCLUIDA (ligue a webcam na TV Box; teste no menu do operador > TESTE DA CAMERA)." -ForegroundColor Green
        if ($script:SemUvc) { Write-Host "  (sem a UVC direta: a webcam abre pela camera do sistema/Camera2)" -ForegroundColor Yellow }
        else { Write-Host "  Caminhos da camera: sistema, Camera2 e UVC direta pelo USB (igual ao jogo de soco)." -ForegroundColor Green }
        Write-Host "  Na 1a vez a TV Box pergunta: permita a CAMERA e, se aparecer, a webcam USB (marque 'Usar por padrao')."
    } else {
        Write-Host "  Camera USB: NAO incluida neste APK (o jogo usa os mascotes no lugar das fotos)." -ForegroundColor Yellow
        if ($motivo) { Write-Host "  Motivo: $motivo" -ForegroundColor Yellow }
    }
    Write-Host "  Instale este APK na TV Box (pendrive + gerenciador de arquivos, ou adb)."
    Write-Host "  O jogo gira a imagem sozinho: deixe o HDMI da TV Box em paisagem (deitado)."

    if ($Instalar) {
        Titulo "Instalando na TV Box (adb)"
        $adb = Join-Path $script:Sdk "platform-tools\adb.exe"
        $cod = Executar $adb @("install", "-r", $final) -Log (Join-Path $script:Logs "adb-instalar.log") -LimiteMin 10 -Rotulo "adb"
        if ($cod -eq 0) {
            [void](Executar $adb @("shell", "monkey", "-p", $Pacote, "-c", "android.intent.category.LAUNCHER", "1") -Log (Join-Path $script:Logs "adb-abrir.log") -LimiteMin 2 -Rotulo "adb" -Quieto)
            Ok "instalado e aberto na TV Box"
        } else {
            Aviso "o adb nao instalou (TV Box conectada? depuracao ligada?). Se aparecer INSTALL_FAILED_UPDATE_INCOMPATIBLE, desinstale o Strike Kids da TV Box e rode de novo."
        }
    }
}

# ------------------------------------------------------------------ inicio

$CodigoSaida = 1
try { [void][IO.Directory]::CreateDirectory($PastaLogs) } catch { }
$transcrevendo = $false
try { Start-Transcript -LiteralPath $LogGeral -Force | Out-Null; $transcrevendo = $true } catch {
    try { Start-Transcript -Path $LogGeral -Force | Out-Null; $transcrevendo = $true } catch { }
}
try {
    Principal
    $CodigoSaida = 0
} catch {
    Write-Host ""
    Write-Host "FALHA: $($_.Exception.Message)" -ForegroundColor Red
    if ($_.InvocationInfo) { Write-Host ("  (linha {0} do GERAR_APK.ps1)" -f $_.InvocationInfo.ScriptLineNumber) -ForegroundColor DarkGray }
    Write-Host "Envie o arquivo: $LogGeral" -ForegroundColor Red
    if ($script:Logs) { Write-Host "(e, se puder, a pasta $($script:Logs))" -ForegroundColor Red }
} finally {
    # os logs de cada programa tambem vao para build\android do projeto
    try {
        if ($script:Logs -and (Test-Path -LiteralPath $script:Logs)) {
            Get-ChildItem -LiteralPath $script:Logs -File | ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $PastaLogs -Force -ErrorAction SilentlyContinue }
        }
    } catch { }
    if ($transcrevendo) { try { Stop-Transcript | Out-Null } catch { } }
}
exit $CodigoSaida
