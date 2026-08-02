$root = $PSScriptRoot
$port = 8888
$ip = "0.0.0.0"

# Simple TCP-based HTTP server - no admin rights needed
$listener = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Any, $port)
$listener.Start()

$localIP = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -like '192.168.*' -or $_.IPAddress -like '10.*' } | Select-Object -First 1).IPAddress
Write-Host "========================================" -ForegroundColor Green
Write-Host "  Grit Server" -ForegroundColor Green
Write-Host "  Phone:  http://${localIP}:${port}/" -ForegroundColor Cyan
Write-Host "  PC:     http://localhost:${port}/" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Green
Write-Host "  Press Ctrl+C to stop" -ForegroundColor Yellow

$mimeTypes = @{
    ".html" = "text/html; charset=utf-8"
    ".js" = "application/javascript"
    ".ttf" = "font/ttf"
    ".svg" = "image/svg+xml"
}

while ($true) {
    $client = $listener.AcceptTcpClient()
    $stream = $client.GetStream()
    $reader = New-Object System.IO.StreamReader($stream)
    $writer = New-Object System.IO.StreamWriter($stream)
    $writer.AutoFlush = $false
    
    $request = $reader.ReadLine()
    if (-not $request) { $client.Close(); continue }
    
    $parts = $request -split ' '
    $path = $parts[1].TrimStart('/')
    if ($path -eq "" -or $path -eq "grit.html") { $path = "index.html" }
    $path = $path -replace '\?.*$', ''
    
    $fp = Join-Path $root $path
    if (Test-Path $fp) {
        $ext = [System.IO.Path]::GetExtension($path)
        $mime = $mimeTypes[$ext]
        if (-not $mime) { $mime = "application/octet-stream" }
        $bytes = [System.IO.File]::ReadAllBytes($fp)
        $header = "HTTP/1.1 200 OK`r`nContent-Type: $mime`r`nContent-Length: $($bytes.Length)`r`nConnection: close`r`n`r`n"
        $writer.Write($header)
        $writer.Flush()
        $stream.Write($bytes, 0, $bytes.Length)
    } else {
        $msg = "404 Not Found"
        $header = "HTTP/1.1 404 Not Found`r`nContent-Type: text/plain`r`nContent-Length: $($msg.Length)`r`nConnection: close`r`n`r`n"
        $writer.Write($header + $msg)
        $writer.Flush()
    }
    $client.Close()
}