# Local Chat for LM Studio. PowerShell 5.1/7, nessuna dipendenza aggiuntiva.
# Interfaccia HTTP solo per rete locale fidata, senza autenticazione.
$ErrorActionPreference = 'Stop'
$Port = 3000
$LMBase = 'http://127.0.0.1:1234'
$MaxPostBytes = 512KB
$HtmlPath = Join-Path $PSScriptRoot 'chat.html'
$Host.UI.RawUI.WindowTitle = 'Local Chat for LM Studio'

function Write-Line([string]$Text, [string]$Color = 'Cyan') { Write-Host $Text -ForegroundColor $Color }
function Get-LanIP {
    try {
        $configs = Get-NetIPConfiguration -ErrorAction Stop | Where-Object { $_.IPv4Address -and $_.IPv4DefaultGateway }
        foreach ($cfg in $configs) {
            foreach ($addr in $cfg.IPv4Address) {
                $ip = [string]$addr.IPAddress
                if ($ip -match '^(192\.168\.|10\.|172\.(1[6-9]|2\d|3[01])\.)') { return $ip }
            }
        }
    } catch {}
    return $null
}
function Write-HttpResponse($Stream, [int]$Status, [string]$ContentType, [byte[]]$Body) {
    $reason = switch ($Status) { 200 {'OK'} 204 {'No Content'} 400 {'Bad Request'} 404 {'Not Found'} 405 {'Method Not Allowed'} 411 {'Length Required'} 413 {'Payload Too Large'} 502 {'Bad Gateway'} default {'Internal Server Error'} }
    $header = "HTTP/1.1 $Status $reason`r`nContent-Type: $ContentType`r`nContent-Length: $($Body.Length)`r`nConnection: close`r`nCache-Control: no-store`r`nX-Content-Type-Options: nosniff`r`nReferrer-Policy: no-referrer`r`n`r`n"
    $headerBytes = [System.Text.Encoding]::ASCII.GetBytes($header)
    $Stream.Write($headerBytes, 0, $headerBytes.Length)
    if ($Body.Length -gt 0) { $Stream.Write($Body, 0, $Body.Length) }
    $Stream.Flush()
}
function Respond($Stream, [int]$Status, [string]$Text, [string]$Type = 'application/json; charset=utf-8') {
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
    Write-HttpResponse $Stream $Status $Type $bytes
}
function Read-Request($Stream) {
    # Legge le intestazioni come bytes, senza rischiare di consumare parte del body.
    $head = New-Object System.IO.MemoryStream
    $one = [byte[]]::new(1)
    $last4 = @(0,0,0,0)
    while ($head.Length -lt 16384) {
        if ($Stream.Read($one,0,1) -eq 0) { throw 'Connessione interrotta.' }
        $b = [int]$one[0]
        $head.WriteByte($one[0])
        $last4[0] = $last4[1]; $last4[1] = $last4[2]; $last4[2] = $last4[3]; $last4[3] = $b
        if ($last4[0] -eq 13 -and $last4[1] -eq 10 -and $last4[2] -eq 13 -and $last4[3] -eq 10) { break }
    }
    if (-not ($last4[0] -eq 13 -and $last4[1] -eq 10 -and $last4[2] -eq 13 -and $last4[3] -eq 10)) { throw 'Intestazioni HTTP troppo lunghe o incomplete.' }
    $headerText = [System.Text.Encoding]::ASCII.GetString($head.ToArray())
    $firstLine = ($headerText -split "`r`n", 2)[0]
    if ($firstLine -match '^(GET|POST)\s+(/\S*)\s+HTTP/1\.[01]$') { $method = $Matches[1]; $path = $Matches[2] }
    else { throw 'Richiesta HTTP non valida.' }
    $len = 0
    if ($method -eq 'POST') {
        $match = [regex]::Match($headerText, '(?im)^Content-Length:\s*(\d+)\s*$')
        if (-not $match.Success) { throw 'Content-Length mancante.' }
        $len = [int]$match.Groups[1].Value
        if ($len -gt $MaxPostBytes) { throw 'Messaggio troppo grande.' }
    }
    $body = [byte[]]::new($len)
    $offset = 0
    while ($offset -lt $len) {
        $read = $Stream.Read($body, $offset, $len - $offset)
        if ($read -le 0) { throw 'Corpo HTTP incompleto.' }
        $offset += $read
    }
    return @{ Method = $method; Path = $path; Body = $body }
}
function Request-LM([string]$Method, [string]$Path, [byte[]]$Body) {
    $uri = "$LMBase$Path"
    $req = [System.Net.WebRequest]::Create($uri)
    $req.Method = $Method
    $req.Timeout = 240000
    $req.ReadWriteTimeout = 240000
    $req.KeepAlive = $false
    if ($Method -eq 'POST') {
        $req.ContentType = 'application/json; charset=utf-8'
        $req.ContentLength = $Body.Length
        $out = $req.GetRequestStream()
        try { $out.Write($Body, 0, $Body.Length) } finally { $out.Dispose() }
    }
    try {
        $response = $req.GetResponse()
        $status = [int]$response.StatusCode
    } catch [System.Net.WebException] {
        if ($_.Exception.Response -eq $null) { throw }
        $response = $_.Exception.Response
        $status = [int]$response.StatusCode
    }
    try {
        $rs = $response.GetResponseStream()
        $reader = [System.IO.StreamReader]::new($rs, [System.Text.Encoding]::UTF8)
        try { $content = $reader.ReadToEnd() } finally { $reader.Dispose() }
    } finally { $response.Dispose() }
    return @{ Status = $status; Content = $content }
}

$listener = $null
try {
    Write-Line '================================================='
    Write-Line '   LOCAL CHAT FOR LM STUDIO'
    Write-Line '================================================='
    if (-not (Test-Path -LiteralPath $HtmlPath)) { throw 'Manca chat.html nella cartella del programma.' }
    Write-Line 'Controllo modello e API su localhost:1234 ...'
    $check = Request-LM 'GET' '/v1/models' ([byte[]]::new(0))
    if ($check.Status -eq 401 -or $check.Status -eq 403) { throw 'LM Studio richiede un token. Disattiva Require Authentication in Server Settings.' }
    if ($check.Status -ne 200) { throw "LM Studio ha risposto con HTTP $($check.Status)." }
    $models = $check.Content | ConvertFrom-Json
    if (-not $models.data -or @($models.data).Count -eq 0) { throw 'Nessun modello API disponibile. Carica un modello in LM Studio.' }
    Write-Line "[OK] LM Studio attivo. Modelli disponibili: $(@($models.data).Count)" 'Green'

    $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Any, $Port)
    $listener.Start(25)
    $localURL = "http://localhost:$Port"
    $lanIP = Get-LanIP
    Write-Line "[OK] Chat sul PC: $localURL" 'Green'
    if ($lanIP) { Write-Line "[OK] Chat in rete: http://$($lanIP):$Port" 'Green' }
    else { Write-Line '[INFO] Usa http://IP_DEL_PC:3000 da un dispositivo della LAN.' 'Yellow' }
    Write-Line 'Chiudi questa finestra o premi Ctrl+C per arrestare la chat.' 'Yellow'
    Write-Line 'ATTENZIONE: nessun login. Usa soltanto una LAN privata fidata.' 'Yellow'
    try { Start-Process $localURL } catch {}
    while ($true) {
        $client = $listener.AcceptTcpClient()
        $client.NoDelay = $true
        $client.ReceiveTimeout = 240000
        $client.SendTimeout = 240000
        try {
            $stream = $client.GetStream()
            try {
                $request = Read-Request $stream
                $method = $request.Method
                $path = ($request.Path -split '\?', 2)[0]
                switch ("$method $path") {
                    'GET /' {
                        $content = [System.IO.File]::ReadAllText($HtmlPath, [System.Text.Encoding]::UTF8)
                        Respond $stream 200 $content 'text/html; charset=utf-8'
                    }
                    'GET /api/models' {
                        $response = Request-LM 'GET' '/v1/models' ([byte[]]::new(0))
                        Respond $stream $response.Status $response.Content
                    }
                    'POST /api/chat' {
                        $response = Request-LM 'POST' '/v1/chat/completions' $request.Body
                        Respond $stream $response.Status $response.Content
                    }
                    'GET /favicon.ico' { Respond $stream 204 '' 'text/plain' }
                    default { Respond $stream 404 '{"error":"Percorso inesistente"}' }
                }
            } catch {
                Write-Line "[ATTENZIONE] Richiesta fallita: $($_.Exception.Message)" 'Yellow'
                try {
                    $errMsg = [string]$_.Exception.Message
                    $errJson = @{ error = $errMsg } | ConvertTo-Json -Compress
                    Respond $stream 502 $errJson
                } catch {}
            } finally { $stream.Dispose() }
        } finally { $client.Close() }
    }
} catch {
    Write-Line "[ERRORE] $($_.Exception.Message)" 'Red'
    Write-Line 'Controlla che LM Studio sia avviato, che il modello sia caricato e che la porta 3000 sia libera.' 'Yellow'
    Write-Line 'Per l accesso da telefono potrebbe essere necessaria una regola firewall TCP 3000.' 'Yellow'
    Read-Host 'Premi INVIO per chiudere' | Out-Null
    exit 1
} finally {
    if ($listener -ne $null) { $listener.Stop() }
}
