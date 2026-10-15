# Daily push: copies not-yet-pushed HTML / CSS / Bootstrap pages into WebDevelopmentPractice, one commit each.
# Run by the Windows scheduled task "WebDevelopmentPractice daily push". -Count sets how many files (default 4),
# -DryRun shows the picks without writing anything, -Force pushes again on a day that already has a push.
# JavaScript goes to JavaScriptPractice, not here; Bootstrap's own library files are never copied.
param([int]$Count = 4, [switch]$DryRun, [switch]$Force)

$ErrorActionPreference = 'Stop'
$Repo    = 'D:\WebDevelopmentPractice'
$Log     = Join-Path $Repo 'tools\daily-push.log'
$Pushed  = Join-Path $Repo 'daily\pushed.txt'
$Desk    = 'C:\Users\Vineet\OneDrive\Desktop'
$Sources = @('ONLY ASSIGNMENTS', 'chapter 2', 'WD FINAL PRO', 'PAW', 'css-practice') | ForEach-Object { Join-Path $Desk $_ }
$SkipRe  = '\\(node_modules|dist|vendor)\\|\.min\.css$|\\bootstrap(\.grid|\.reboot|\.utilities)?(\.rtl)?\.css$'
$BS      = [string][char]92

# Folder (anywhere in the path) -> topic it teaches; first match wins.
$Topics = [ordered]@{
    'bootstrap-demo'   = 'Bootstrap'
    'css.all'          = 'CSS'
    'css-practice'     = 'CSS'
    'ASSIGNMENTS'      = 'web design assignments'
    'ONLY ASSIGNMENTS' = 'web design assignments'
    'WD FINAL PRO'     = 'my final web design project'
    'PAW'              = 'a pet adoption website'
}

# A file is pushed only if it has real content: at least 100 characters once comments and spaces are
# removed, and for a page, something inside <body> (an HTML skeleton alone is not pushed).
function Has-Code($path) {
    $t = Get-Content $path -Raw -ErrorAction SilentlyContinue
    if (-not $t) { return $false }
    $t = [regex]::Replace($t, '(?s)<!--.*?-->|/\*.*?\*/', '')
    if (($t -replace '\s', '').Length -lt 100) { return $false }
    if ($path -match '\.html?$' -and $t -match '(?is)<body[^>]*>(.*)</body>') { return [bool](($Matches[1] -replace '\s', '').Length) }
    return $true
}

function Log($msg) {
    $line = "{0:yyyy-MM-dd HH:mm:ss}  {1}" -f (Get-Date), $msg
    Add-Content -Path $Log -Value $line -Encoding utf8
    Write-Host $line
}

function Get-Topic($rel, $name) {
    $parts = $rel.Split($BS)
    $topic = $null
    foreach ($k in $Topics.Keys) { if ($parts -contains $k) { $topic = $Topics[$k]; break } }
    if (-not $topic) { $topic = 'HTML and CSS' }
    if ($name -match 'bootstrap|bootsrap') { $topic = 'Bootstrap' }
    $page = [IO.Path]::GetFileNameWithoutExtension($name).ToLower()
    if ($page -match 'grid') { return "$topic (grid layout)" }
    if ($page -match 'pseudo') { return "$topic (pseudo-classes)" }
    if ($page -match 'breakpoint') { return "$topic (responsive breakpoints)" }
    if ($page -match 'login|register|contact|form') { return "$topic (forms)" }
    if ($page -match 'shadow|box') { return "$topic (box model and shadows)" }
    if ($page -match 'font|text') { return "$topic (fonts and text)" }
    if ($name -match '\.css$') { return "$topic (stylesheet)" }
    return $topic
}

try {
    Set-Location $Repo
    if (-not $DryRun -and (git ls-remote --heads origin main)) { git pull --rebase --quiet origin main }
    $today = Get-Date -Format 'yyyy-MM-dd'
    if (-not (Test-Path $Pushed)) { New-Item -ItemType File -Path $Pushed -Force | Out-Null }
    $done = @(Get-Content $Pushed -ErrorAction SilentlyContinue)

    if (($done | Where-Object { $_ -like "$today|*" }) -and -not $DryRun -and -not $Force) {
        Log "Already pushed today; nothing to do."
        exit 0
    }

    $candidates = @(foreach ($s in $Sources) {
        if (-not (Test-Path $s)) { continue }
        Get-ChildItem -Path $s -Recurse -File | Where-Object {
            $_.Extension -match '^\.(html|htm|css)$' -and $_.FullName -notmatch $SkipRe -and (Has-Code $_.FullName)
        }
    })
    $candidates = @($candidates | Where-Object { $f = $_.FullName; -not ($done | Where-Object { $_.Split('|')[1] -eq $f }) })
    if (-not $candidates) { Log "No unpushed web pages left."; exit 0 }

    foreach ($pick in ($candidates | Get-Random -Count ([Math]::Min($Count, $candidates.Count)))) {
        $rel   = $pick.FullName.Substring($Desk.Length).TrimStart($BS)
        $topic = Get-Topic $rel $pick.Name
        $dest  = Join-Path $Repo ("daily" + $BS + $today + $BS + $rel)
        if ($DryRun) { Log "Dry run would push $($pick.FullName)  [$topic]"; continue }
        New-Item -ItemType Directory -Path (Split-Path $dest) -Force | Out-Null

        $content = Get-Content $pick.FullName -Raw
        $note    = "Learning $topic - practice file from $($rel.Split($BS)[0]), pushed $today"
        $header  = if ($pick.Extension -match 'css') { "/* $note */`r`n" } else { "<!-- $note -->`r`n" }
        Set-Content -Path $dest -Value ($header + $content) -Encoding utf8
        Log "Picked $($pick.FullName) -> $dest  [$topic]"

        $relDest = ("daily/$today/" + $rel.Replace($BS, '/')).Replace(' ', '%20')
        Add-Content -Path (Join-Path $Repo 'README.md') -Value ("| $today | [{0}]({1}) | Learning {2} |" -f $pick.Name, $relDest, $topic) -Encoding utf8
        Add-Content -Path $Pushed -Value "$today|$($pick.FullName)" -Encoding utf8

        git add -A
        git commit --quiet -m "Learning $topic`: $($pick.Name)" -m "Practice file from $rel."
        git push --quiet -u origin main
        Log "Pushed $($pick.Name)"
    }
}
catch {
    Log "FAILED: $($_.Exception.Message)"
    exit 1
}
