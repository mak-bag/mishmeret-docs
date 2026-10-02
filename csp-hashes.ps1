<#
  csp-hashes.ps1 — טביעות האצבע של ה-<script> הפנימיים, בשביל ה-CSP ב-_headers.

  למה PowerShell: אין python על המכונה (SEC-REVIEW, הנדאוף ל-DevOps).
  הקובץ מחליף את scripts/csp-hashes.py שמוזכר ב-_headers ומעולם לא נכתב.

  מה הוא עושה:
    1. מוצא כל <script> בלי src   (רק אלה נכנסים ל-CSP כ-hash)
    2. מנרמל CRLF -> LF           (הדפדפן מחשב על מה שהוא קיבל, וה-zip נבנה ב-Windows)
    3. SHA-256 -> base64 -> 'sha256-...'
    4. משווה לארבעת ה-hashes שב-_headers ואומר מה חסר ומה מיותר

  שימוש:
    .\scripts\csp-hashes.ps1
    .\scripts\csp-hashes.ps1 -Html .\app.html -Headers .\_headers
    .\scripts\csp-hashes.ps1 -Update     # מדפיס שורת script-src מוכנה להדבקה

  יוצא עם 1 כשיש אי-התאמה, כדי שאפשר יהיה לתלות בו בדיקה.
#>
[CmdletBinding()]
param(
  [string]$Html    = "app.html",
  [string]$Headers = "_headers",
  [switch]$Update,
  [switch]$Apply
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path $Html))    { Write-Error "not found: $Html" }
if (-not (Test-Path $Headers)) { Write-Error "not found: $Headers" }

# --- 1+2. קריאה ונרמול שורות -------------------------------------------------
# ReadAllText מזהה UTF-8 לבד. הנרמול חייב לקרות לפני ה-hash: קובץ שנערך
# ב-Windows יישמר עם CRLF, והדפדפן יראה את מה שהשרת שלח. אם ה-zip נבנה
# כמו שהוא, הערכים כאן חייבים להתאים לבייטים שיוצאים בפועל.
$raw = [System.IO.File]::ReadAllText((Resolve-Path $Html).Path)
$raw = $raw -replace "`r`n", "`n"

# --- 3. חילוץ וחישוב ---------------------------------------------------------
$rx  = [regex]'(?s)<script\b([^>]*)>(.*?)</script\s*>'
$sha = [System.Security.Cryptography.SHA256]::Create()

$found = @()
foreach ($m in $rx.Matches($raw)) {
  $attrs = $m.Groups[1].Value
  # <script src=...> נטען מבחוץ ונשלט ב-CSP דרך המקור, לא דרך hash.
  if ($attrs -match '\bsrc\s*=') { continue }

  $body  = $m.Groups[2].Value
  $bytes = [System.Text.Encoding]::UTF8.GetBytes($body)
  $b64   = [Convert]::ToBase64String($sha.ComputeHash($bytes))

  # מספר השורה שבה נפתח התג, כדי שאפשר יהיה למצוא אותו בקובץ
  $line  = ($raw.Substring(0, $m.Index) -split "`n").Count

  $found += [pscustomobject]@{
    Line  = $line
    Attrs = $attrs.Trim()
    Bytes = $bytes.Length
    Hash  = "sha256-$b64"
  }
}

Write-Host "`n$($found.Count) inline <script> blocks in $Html`n" -ForegroundColor Cyan
$found | Format-Table Line, Bytes, Attrs, Hash -AutoSize

# --- 4. השוואה ל-_headers ----------------------------------------------------
# BOM ב-_headers: עורכים ב-Windows מוסיפים אותו בשקט, והוא יושב לפני השורה
# הראשונה. Cloudflare קורא את הקובץ כטקסט, והתו הבלתי-נראה הזה הופך את
# שורת ההערה הראשונה לשורה שאינה הערה. קרה ב-02/10. נבדק כאן כדי שלא
# יחזור בשקט. (DevOps — המחזיק של _headers)
$hdrPath  = (Resolve-Path $Headers).Path
$firstTwo = [byte[]](Get-Content -LiteralPath $hdrPath -Encoding Byte -TotalCount 3)
if ($firstTwo.Length -ge 3 -and $firstTwo[0] -eq 0xEF -and $firstTwo[1] -eq 0xBB -and $firstTwo[2] -eq 0xBF) {
  Write-Host "BOM in $Headers - remove it before shipping the zip." -ForegroundColor Red
  Write-Host "  PowerShell: [IO.File]::WriteAllText('$hdrPath', [IO.File]::ReadAllText('$hdrPath'), (New-Object Text.UTF8Encoding `$false))" -ForegroundColor Gray
  $bom = $true
} else {
  $bom = $false
}

$hdr      = [System.IO.File]::ReadAllText($hdrPath)
$inHdr    = [regex]::Matches($hdr, "'(sha256-[A-Za-z0-9+/=]+)'") |
              ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique
$computed = $found.Hash | Select-Object -Unique

$missing = @($computed | Where-Object { $inHdr -notcontains $_ })
$stale   = @($inHdr    | Where-Object { $computed -notcontains $_ })

Write-Host "_headers holds $($inHdr.Count) hash(es); the file produces $($computed.Count)." -ForegroundColor Cyan

if ($missing.Count -eq 0 -and $stale.Count -eq 0 -and -not $bom) {
  Write-Host "MATCH - every inline script is covered, nothing stale, no BOM.`n" -ForegroundColor Green
  $exit = 0
} elseif ($missing.Count -eq 0 -and $stale.Count -eq 0) {
  Write-Host "hashes match, but the BOM above must go.`n" -ForegroundColor Yellow
  $exit = 1
} else {
  foreach ($h in $missing) { Write-Host "MISSING from _headers : $h" -ForegroundColor Red }
  foreach ($h in $stale)   { Write-Host "STALE in _headers     : $h" -ForegroundColor Yellow }
  Write-Host ""
  $exit = 1
}

if ($Update) {
  $joined = ($computed | ForEach-Object { "'$_'" }) -join ' '
  Write-Host "script-src 'self' https://cdn.jsdelivr.net 'wasm-unsafe-eval' $joined" -ForegroundColor Gray
  Write-Host ""
}

# --- 5. -Apply: כותב את ה-hashes לתוך _headers -------------------------------
# זה הנתיב היחיד שבו _headers אמור להשתנות. עריכה ידנית היא מה שהכניסה
# BOM ב-02/10 ומה שהשאיר hash של גרסת ביניים. הכתיבה כאן היא UTF-8 בלי
# BOM, ושאר הקובץ אינו נגוע — מוחלף רק רצף ה-'sha256-...'.
#
# מריצים אותו על הקובץ שבתוך ה-zip, לא על עץ העבודה:
#   .\scripts\csp-hashes.ps1 -Html <zip>\index.html -Headers <zip>\_headers -Apply
if ($Apply) {
  if ($missing.Count -eq 0 -and $stale.Count -eq 0 -and -not $bom) {
    Write-Host "nothing to apply - already correct.`n" -ForegroundColor Green
  } else {
    $joined  = ($computed | ForEach-Object { "'$_'" }) -join ' '
    $updated = $hdr -replace "(?:'sha256-[A-Za-z0-9+/=]+'\s*)+", "$joined "
    if ($updated -eq $hdr) {
      Write-Host "could not find a hash list in $Headers - not written." -ForegroundColor Red
      exit 1
    }
    [System.IO.File]::WriteAllText($hdrPath, $updated, (New-Object System.Text.UTF8Encoding $false))
    Write-Host "written: $($computed.Count) hash(es) into $Headers (UTF-8, no BOM).`n" -ForegroundColor Green
    $exit = 0
  }
}

exit $exit
