$txt = [System.IO.File]::ReadAllText("$PSScriptRoot\index.html")
$m = [regex]::Match($txt, '<script>(.*?)</script>', [System.Text.RegularExpressions.RegexOptions]::Singleline)
$js = $m.Groups[1].Value

# Strip all string literals and comments first
$cleaned = ""
$i = 0
$len = $js.Length
while ($i -lt $len) {
  $ch = $js[$i]
  $next = if ($i+1 -lt $len) { $js[$i+1] } else { '' }
  
  # Single quote string
  if ($ch -eq "'") {
    $cleaned += "'_'"
    $i++
    $esc = $false
    while ($i -lt $len) {
      if ($esc) { $esc = $false; $i++; continue }
      if ($js[$i] -eq '\') { $esc = $true; $i++; continue }
      if ($js[$i] -eq "'") { $cleaned += "'_'"; $i++; break }
      $i++
    }
    continue
  }
  # Double quote string
  if ($ch -eq '"') {
    $cleaned += '"_"'
    $i++
    $esc = $false
    while ($i -lt $len) {
      if ($esc) { $esc = $false; $i++; continue }
      if ($js[$i] -eq '\') { $esc = $true; $i++; continue }
      if ($js[$i] -eq '"') { $cleaned += '"_"'; $i++; break }
      $i++
    }
    continue
  }
  # Template literal
  if ($ch -eq '`') {
    $cleaned += '`_`'
    $i++
    $esc = $false
    while ($i -lt $len) {
      if ($esc) { $esc = $false; $i++; continue }
      if ($js[$i] -eq '\') { $esc = $true; $i++; continue }
      if ($js[$i] -eq '`') { $cleaned += '`_`'; $i++; break }
      $i++
    }
    continue
  }
  # Single line comment
  if ($ch -eq '/' -and $next -eq '/') {
    $cleaned += '//'
    $i += 2
    while ($i -lt $len -and $js[$i] -ne "`n") { $i++ }
    continue
  }
  # Multi-line comment
  if ($ch -eq '/' -and $next -eq '*') {
    $cleaned += '/*'
    $i += 2
    while ($i+1 -lt $len) {
      if ($js[$i] -eq '*' -and $js[$i+1] -eq '/') { $i += 2; $cleaned += '*/'; break }
      $i++
    }
    continue
  }
  # Regex literal (simplified: /pattern/ not preceded by operator)
  if ($ch -eq '/' -and $i -gt 0 -and $js[$i-1] -match '[=,;({\[&|!?:]') {
    $cleaned += '/_/'
    $i++
    $esc = $false
    while ($i -lt $len) {
      if ($esc) { $esc = $false; $i++; continue }
      if ($js[$i] -eq '\') { $esc = $true; $i++; continue }
      if ($js[$i] -eq '/') { $cleaned += '/_/'; $i++; break }
      $i++
    }
    continue
  }
  
  $cleaned += $ch
  $i++
}

# Now find try blocks in cleaned code
$cleanedLines = $cleaned -split "`n"
$tryStack = @()
$found = $false

for ($ln = 0; $ln -lt $cleanedLines.Count; $ln++) {
  $line = $cleanedLines[$ln]
  $chars = $line.ToCharArray()
  for ($c = 0; $c -lt $chars.Count; $c++) {
    $ch = $chars[$c]
    $n = if ($c+1 -lt $chars.Count) { $chars[$c+1] } else { '' }
    $n2 = if ($c+2 -lt $chars.Count) { $chars[$c+2] } else { '' }
    $n3 = if ($c+3 -lt $chars.Count) { $chars[$c+3] } else { '' }
    $n4 = if ($c+4 -lt $chars.Count) { $chars[$c+4] } else { '' }
    $n5 = if ($c+5 -lt $chars.Count) { $chars[$c+5] } else { '' }
    $n6 = if ($c+6 -lt $chars.Count) { $chars[$c+6] } else { '' }
    
    # Check for 'try' keyword (followed by whitespace or {)
    if ($ch -eq 't' -and $n -eq 'r' -and $n2 -eq 'y') {
      $after = if ($c+3 -lt $chars.Count) { $chars[$c+3] } else { '' }
      if ($after -match '[\s{]') {
        $tryStack += @{ line = $ln+1; col = $c+1 }
      }
    }
    
    # Check for 'catch' keyword
    if ($ch -eq 'c' -and $n -eq 'a' -and $n2 -eq 't' -and $n3 -eq 'c' -and $n4 -eq 'h') {
      $after = if ($c+5 -lt $chars.Count) { $chars[$c+5] } else { '' }
      if ($after -match '[\s({]') {
        if ($tryStack.Count -gt 0) {
          $tryStack = $tryStack[0..($tryStack.Count-2)]
        }
      }
    }
    
    # Check for 'finally' keyword
    if ($ch -eq 'f' -and $n -eq 'i' -and $n2 -eq 'n' -and $n3 -eq 'a' -and $n4 -eq 'l' -and $n5 -eq 'l' -and $n6 -eq 'y') {
      $after = if ($c+7 -lt $chars.Count) { $chars[$c+7] } else { '' }
      if ($after -match '[\s{]') {
        if ($tryStack.Count -gt 0) {
          $tryStack = $tryStack[0..($tryStack.Count-2)]
        }
      }
    }
  }
}

if ($tryStack.Count -gt 0) {
  Write-Host "UNMATCHED try blocks found:" -ForegroundColor Red
  foreach ($t in $tryStack) {
    Write-Host "  Line $($t.line), col $($t.col)" -ForegroundColor Red
    Write-Host "  Context: $($lines[$t.line-1].Trim())" -ForegroundColor Yellow
  }
} else {
  Write-Host "ALL try blocks have matching catch/finally" -ForegroundColor Green
}

# Also check for .catch() without preceding try
Write-Host ""
Write-Host "--- Manual key try blocks ---"
$matches = [regex]::Matches($js, 'try\s*\{')
Write-Host "try{ count: $($matches.Count)"
$matches = [regex]::Matches($js, 'catch\s*[\s(]')
Write-Host "catch count: $($matches.Count)"
$matches = [regex]::Matches($js, 'finally\s*\{')
Write-Host "finally{ count: $($matches.Count)"