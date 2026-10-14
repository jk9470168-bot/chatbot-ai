param(
    [string]$HostAddress = "127.0.0.1",
    [int]$Port = 8000,
    [string]$Model = $(if ($env:OLLAMA_MODEL) { $env:OLLAMA_MODEL } else { "qwen3:4b" }),
    [string]$OllamaUrl = $(if ($env:OLLAMA_URL) { $env:OLLAMA_URL.TrimEnd("/") } else { "http://127.0.0.1:11434" })
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$SystemPrompt = @"
You are an intelligent, friendly, and professional AI chatbot powered by the locally installed Ollama model qwen3:4b.

Your objective is to provide accurate, helpful, and easy-to-understand answers about programming, education, technology, general knowledge, and problem-solving. Understand the request before answering. Be direct and relevant, explain complex topics simply, and keep answers concise unless detail is requested. For programming questions, provide correct code and explanations, with sample output when useful. Help debug errors by explaining the cause and offering a corrected solution. For educational questions, use definitions, descriptions, algorithms, examples, and results when appropriate. Ask clarifying questions when essential information is missing. Use numbered steps and bullet points when they improve readability. Do not invent facts or claim capabilities you do not have. Maintain a respectful, professional, and supportive tone.

Use your available model knowledge and information supplied by the user. Do not claim internet access unless an internet-search tool is connected and available. Do not claim access to local files or applications without the required tools or permissions. Do not disclose private information. Clearly acknowledge uncertainty when an answer cannot be verified.

When appropriate, structure answers as a direct answer, explanation, example or code, expected output, and conclusion.
"@
$StaticFiles = @{
    "/" = @{ File = "index.html"; Type = "text/html; charset=utf-8" }
    "/index.html" = @{ File = "index.html"; Type = "text/html; charset=utf-8" }
    "/styles.css" = @{ File = "styles.css"; Type = "text/css; charset=utf-8" }
    "/app.js" = @{ File = "app.js"; Type = "text/javascript; charset=utf-8" }
}

function Send-JsonResponse($Response, [int]$Status, $Payload) {
    $bytes = [System.Text.Encoding]::UTF8.GetBytes(($Payload | ConvertTo-Json -Compress -Depth 8))
    $Response.StatusCode = $Status
    $Response.ContentType = "application/json; charset=utf-8"
    $Response.Headers["Cache-Control"] = "no-store"
    $Response.ContentLength64 = $bytes.Length
    $Response.OutputStream.Write($bytes, 0, $bytes.Length)
    $Response.Close()
}

$Listener = New-Object System.Net.HttpListener
$Listener.Prefixes.Add("http://${HostAddress}:${Port}/")
$Listener.Start()
Write-Host "Cedar & Signal is running at http://localhost:$Port (model: $Model)"

try {
    while ($Listener.IsListening) {
        $Context = $Listener.GetContext()
        $Request = $Context.Request
        $Response = $Context.Response

        if ($Request.HttpMethod -eq "GET" -and $StaticFiles.ContainsKey($Request.Url.AbsolutePath)) {
            $FileInfo = $StaticFiles[$Request.Url.AbsolutePath]
            $Bytes = [System.IO.File]::ReadAllBytes((Join-Path $Root $FileInfo.File))
            $Response.StatusCode = 200
            $Response.ContentType = $FileInfo.Type
            $Response.Headers["X-Content-Type-Options"] = "nosniff"
            $Response.Headers["Cache-Control"] = "no-store"
            $Response.ContentLength64 = $Bytes.Length
            $Response.OutputStream.Write($Bytes, 0, $Bytes.Length)
            $Response.Close()
            continue
        }

        if ($Request.HttpMethod -ne "POST" -or $Request.Url.AbsolutePath -ne "/api/chat") {
            Send-JsonResponse $Response 404 @{ error = "Not found." }
            continue
        }

        if ($Request.ContentLength64 -lt 1 -or $Request.ContentLength64 -gt 16384) {
            Send-JsonResponse $Response 400 @{ error = "Message is empty or too large." }
            continue
        }

        try {
            $Reader = New-Object System.IO.StreamReader($Request.InputStream, $Request.ContentEncoding)
            $Payload = $Reader.ReadToEnd() | ConvertFrom-Json
            $Reader.Dispose()
            $Messages = @($Payload.messages)
            if ($Messages.Count -lt 1 -or $Messages.Count -gt 12) {
                Send-JsonResponse $Response 400 @{ error = "Please send a message to get started." }
                continue
            }

            $SafeMessages = @()
            $InvalidMessage = $false
            foreach ($Message in $Messages) {
                if ($Message.role -notin @("user", "assistant") -or $Message.content -isnot [string]) {
                    $InvalidMessage = $true
                    break
                }
                if ($Message.role -eq "user" -and $Message.content.Length -gt 2000) {
                    Send-JsonResponse $Response 400 @{ error = "Your question is too long. Please keep it under 2,000 characters." }
                    $InvalidMessage = $true
                    break
                }
                $Content = $Message.content
                if ($Message.role -eq "assistant" -and $Content.Length -gt 2000) {
                    $Content = $Content.Substring(0, 1988) + " [truncated]"
                }
                $SafeMessages += @{ role = $Message.role; content = $Content }
            }
            if ($InvalidMessage) {
                continue
            }

            $OllamaMessages = @(@{ role = "system"; content = $SystemPrompt }) + $SafeMessages
            $OllamaBody = @{
                model = $Model
                stream = $false
                messages = $OllamaMessages
                options = @{ temperature = 0.6 }
            } | ConvertTo-Json -Depth 10 -Compress
            for ($Attempt = 1; $Attempt -le 2; $Attempt++) {
                try {
                    $Result = Invoke-RestMethod -Uri "$OllamaUrl/api/chat" -Method Post -ContentType "application/json" -Body $OllamaBody -TimeoutSec 300
                    break
                }
                catch {
                    $TransientConnectionError = $_.Exception.Message -match "Unable to connect|actively refused|connection.*(closed|reset|aborted)"
                    if (-not $TransientConnectionError -or $Attempt -eq 2) {
                        throw
                    }
                    Start-Sleep -Seconds 1
                }
            }
            $Reply = [string]$Result.message.content
            if ([string]::IsNullOrWhiteSpace($Reply)) {
                Send-JsonResponse $Response 502 @{ error = "The assistant returned an empty response. Please try again." }
                continue
            }
            Send-JsonResponse $Response 200 @{ reply = $Reply.Trim() }
        }
        catch {
            $Message = $_.Exception.Message
            $Status = 500
            Write-Warning "Chat request failed: $Message"
            if ($_.Exception -is [System.ArgumentException] -or $_.Exception -is [System.Management.Automation.ParameterBindingException]) {
                $Status = 400
            }
            elseif ($Message -match "timed out|timeout") {
                $Status = 504
                $Message = "Ollama did not respond within 300 seconds. Check whether the model is still loading or busy."
            }
            elseif ($Message -match "Unable to connect|actively refused|connection") {
                $Status = 502
                $Message = "Cannot connect to Ollama at $OllamaUrl. Start Ollama and verify its local API is available."
            }
            Send-JsonResponse $Response $Status @{ error = $Message }
        }
    }
}
finally {
    $Listener.Stop()
    $Listener.Close()
}