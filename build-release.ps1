<#
  build-release.ps1 — בונה חבילת שחרור אחת, ושולח את אותו קובץ לשני המקומות.

  **העיקרון: zip אחד.** staging ופרודקשן מקבלים בייט-לבייט את אותה חבילה.
  בנייה נפרדת לכל סביבה פירושה ש-"נבדק ב-staging" לא אומר דבר על מה שעלה
  לפרודקשן — וזו כל הסיבה ש-staging קיים.

  **סדר הפעולות, והוא שונה ממה שנכתב בבריף בכוונה:**
      העמדה → csp-hashes -Apply → zip → md5 → builds/<md5>.zip
  הבריף כתב "zip → md5 → -Apply על ה-zip". זה לא יכול לעבוד: כל שינוי
  אחרי חישוב ה-md5 משנה את הקובץ, וה-md5 בשם כבר לא מתאר את התוכן.
  ה-hash חייב להיכנס *לפני* האריזה, ועל עותקי ההעמדה — שהם קפואים,
  בניגוד לעץ העבודה. (הקריאה הקרועה שנמדדה ב-03/10.)

  שימוש:
    .\scripts\build-release.ps1 -Label beta-6
    .\scripts\build-release.ps1 -Label beta-6 -SourceDir . -OutDir builds
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][string]$Label,
  [string]$SourceDir = ".",
  [string]$OutDir    = "builds",
  [string]$AppHtml   = "app.html",
  [switch]$KeepStage
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$src = (Resolve-Path $SourceDir).Path
function P([string]$rel) { Join-Path $src $rel }

# --- 1. מה נכנס לחבילה. רשימה סגורה, לא "מה שיש בתיקייה" ----------------
# תיקייה שלמה הייתה גוררת פנימה מוקאפים, רתמות וקבצי עבודה. הרשימה
# הזו היא גם ההגדרה של מה האתר הוא.
$required = @{
  'index.html' = P $AppHtml      # app.html מוגש כ-index.html בשורש
  'legal.html' = P 'legal.html'
  '_headers'   = P '_headers'
}
$requiredDirs = @{ 'assets' = P 'assets' }

foreach ($k in $required.Keys) {
  if (-not (Test-Path $required[$k])) { throw "missing: $($required[$k]) (needed as $k)" }
}
foreach ($k in $requiredDirs.Keys) {
  if (-not (Test-Path $requiredDirs[$k])) { throw "missing directory: $($requiredDirs[$k])" }
}

# --- 2. העמדה: עותק קפוא, שעליו נחתום -----------------------------------
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$stage = Join-Path ([IO.Path]::GetTempPath()) "mishmeret-release-$stamp"
if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
New-Item -ItemType Directory -Path $stage | Out-Null

foreach ($k in $required.Keys)     { Copy-Item $required[$k]     (Join-Path $stage $k) -Force }
foreach ($k in $requiredDirs.Keys) { Copy-Item $requiredDirs[$k] (Join-Path $stage $k) -Recurse -Force }

Write-Host "`nstaged in $stage" -ForegroundColor Cyan

# --- 3. CSP: חותמים על עותקי ההעמדה, לא על עץ העבודה ---------------------
$csp = Join-Path $PSScriptRoot 'csp-hashes.ps1'
if (-not (Test-Path $csp)) { throw "missing: $csp" }

& $csp -Html (Join-Path $stage 'index.html') -Headers (Join-Path $stage '_headers') -Apply
if ($LASTEXITCODE -ne 0) { throw "csp-hashes -Apply failed; nothing was packaged." }

# אימות אחרי הכתיבה: חייב MATCH ובלי BOM, אחרת לא אורזים.
& $csp -Html (Join-Path $stage 'index.html') -Headers (Join-Path $stage '_headers')
if ($LASTEXITCODE -ne 0) { throw "CSP does not match the staged files; nothing was packaged." }

# --- 4. אריזה. שמות כניסה עם '/' במפורש ----------------------------------
# ZipFile::CreateFromDirectory ב-.NET Framework כותב '\' בשמות הכניסות,
# ו-Cloudflare לא מוצא את הקבצים. לכן בונים ידנית.
if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Path $OutDir | Out-Null }
$tmpZip = Join-Path ([IO.Path]::GetTempPath()) "mishmeret-$stamp.zip"
if (Test-Path $tmpZip) { Remove-Item $tmpZip -Force }

$zip = [IO.Compression.ZipFile]::Open($tmpZip, [IO.Compression.ZipArchiveMode]::Create)
try {
  # סדר קבוע + חותמת זמן קבועה = בנייה דטרמיניסטית. בלי זה zip של אותו
  # תוכן בדיוק מקבל md5 אחר בכל בנייה, כי הפורמט שומר את זמן השינוי של
  # כל קובץ — ואז ה-md5 מזהה את *הבנייה* ולא את התוכן. נמדד: שתי בניות
  # רצופות של אותם קבצים נתנו C33BAC28… ו-7A2A1FFC…
  # עם זה, "staging ופרודקשן מריצים את אותו דבר" הוא משהו שאפשר להוכיח
  # בבנייה חוזרת, ולא רק נוהל שסומכים עליו.
  $epoch = [DateTimeOffset]::new(2026,1,1,0,0,0,[TimeSpan]::Zero)
  $files = Get-ChildItem $stage -Recurse -File | Sort-Object { $_.FullName.Substring($stage.Length+1).Replace('\','/') }
  foreach ($f in $files) {
    $entry = $f.FullName.Substring($stage.Length + 1).Replace('\','/')
    # CreateEntryFromFile סוגר את הכניסה, ואז LastWriteTime כבר לא ניתן
    # לשינוי ("Cannot modify entry in Create mode after entry has been
    # opened for writing"). לכן: יוצרים, קובעים זמן, ורק אז כותבים.
    $e = $zip.CreateEntry($entry, [IO.Compression.CompressionLevel]::Optimal)
    $e.LastWriteTime = $epoch
    $out = $e.Open()
    try {
      $in = [IO.File]::OpenRead($f.FullName)
      try { $in.CopyTo($out) } finally { $in.Dispose() }
    } finally { $out.Dispose() }
    Write-Host ("  + {0,-28} {1,9:N0} bytes" -f $entry, $f.Length)
  }
} finally { $zip.Dispose() }

# אימות שאין '\' באף שם כניסה
$check = [IO.Compression.ZipFile]::OpenRead($tmpZip)
try {
  $bad = @($check.Entries | Where-Object { $_.FullName -match '\\' })
  if ($bad.Count -gt 0) { throw "zip entries contain backslashes: $($bad[0].FullName)" }
  $entryCount = $check.Entries.Count
} finally { $check.Dispose() }

# --- 5. md5 של ה-zip הסופי, ואחריו השם ----------------------------------
$md5 = (Get-FileHash $tmpZip -Algorithm MD5).Hash
$final = Join-Path $OutDir "$md5.zip"
Move-Item $tmpZip $final -Force

# md5 של index.html, כי זה המספר שלוח המצב עוקב אחריו
$idxMd5 = (Get-FileHash (Join-Path $stage 'index.html') -Algorithm MD5).Hash
$idxLen = (Get-Item (Join-Path $stage 'index.html')).Length

# --- 6. רישום. חבילה בלי רישום היא חבילה שאי אפשר לדבר עליה --------------
$manifest = Join-Path $OutDir 'releases.txt'
$line = "{0}  {1}  zip={2}  index={3} ({4:N0} bytes)  entries={5}" -f `
        (Get-Date -Format 'yyyy-MM-dd HH:mm'), $Label, $md5, $idxMd5, $idxLen, $entryCount
Add-Content -Path $manifest -Value $line -Encoding utf8

Write-Host ""
Write-Host "label      : $Label"       -ForegroundColor Green
Write-Host "zip        : $final"       -ForegroundColor Green
Write-Host "zip md5    : $md5"         -ForegroundColor Green
Write-Host "index md5  : $idxMd5  ($('{0:N0}' -f $idxLen) bytes)"
Write-Host "entries    : $entryCount"
Write-Host ""
Write-Host "THE SAME FILE goes to both: staging first, production after it passes." -ForegroundColor Yellow
Write-Host "  1. Cloudflare > Workers > <staging worker>  > upload $md5.zip"
Write-Host "  2. verify, then the identical file:"
Write-Host "  3. Cloudflare > Workers > round-field-973f   > upload $md5.zip"
Write-Host ""

if (-not $KeepStage) { Remove-Item $stage -Recurse -Force }
