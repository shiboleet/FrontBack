[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$scriptDirectory = $PSScriptRoot

function Write-Status([string]$Message, [string]$Kind = "Info") {
    $color = switch ($Kind) {
        "Ok" { "Green" }
        "Warn" { "Yellow" }
        "Error" { "Red" }
        default { "Cyan" }
    }
    Write-Host ("[{0}] {1}" -f $Kind.ToUpperInvariant(), $Message) -ForegroundColor $color
}

function Resolve-GameRoot {
    $detected = [IO.Path]::GetFullPath((Join-Path $scriptDirectory "..\..\.."))
    if (Test-Path -LiteralPath (Join-Path $detected "WoW.exe") -PathType Leaf) {
        Write-Status "Detected WoW root: $detected" "Ok"
        return $detected
    }

    Write-Status "Expected WoW.exe at '$detected'. FrontBack may have been moved." "Warn"
    while ($true) {
        $entered = Read-Host "Enter the full folder path containing WoW.exe (or leave blank to cancel)"
        if ([string]::IsNullOrWhiteSpace($entered)) {
            throw "Installation cancelled because no WoW folder was supplied."
        }
        try {
            $candidate = (Resolve-Path -LiteralPath $entered.Trim()).Path
        } catch {
            Write-Status "That folder does not exist: $entered" "Error"
            continue
        }
        if (Test-Path -LiteralPath (Join-Path $candidate "WoW.exe") -PathType Leaf) {
            Write-Status "Using WoW root: $candidate" "Ok"
            return $candidate
        }
        Write-Status "WoW.exe was not found in '$candidate'." "Error"
    }
}

function Find-BundledDll([string]$FileName) {
    $candidates = @(
        (Join-Path $scriptDirectory $FileName),
        (Join-Path (Join-Path $scriptDirectory "dependencies") $FileName)
    )
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return $candidate
        }
    }
    return $null
}

function Test-WindowsDll([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $false
    }
    $length = (Get-Item -LiteralPath $Path).Length
    if ($length -lt 1024) {
        return $false
    }
    $stream = [IO.File]::OpenRead($Path)
    try {
        $first = $stream.ReadByte()
        $second = $stream.ReadByte()
        return ($first -eq 0x4D -and $second -eq 0x5A)
    } finally {
        $stream.Dispose()
    }
}

function Download-LatestReleaseFile([string]$Repository, [string]$AssetName, [string]$Destination) {
    Write-Status "Checking the latest $AssetName release from GitHub..."
    $headers = @{ "User-Agent" = "FrontBack dependency installer" }
    $release = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repository/releases/latest" -Headers $headers -TimeoutSec 30
    $asset = $release.assets | Where-Object { $_.name -ieq $AssetName } | Select-Object -First 1
    if (-not $asset) {
        throw "The latest $Repository release does not contain $AssetName."
    }
    Write-Status "Downloading $AssetName from $($release.tag_name)..."
    Invoke-WebRequest -Uri $asset.browser_download_url -Headers $headers -OutFile $Destination -UseBasicParsing -TimeoutSec 120
}

function Download-SuperWoW([string]$Destination, [string]$TempRoot) {
    $headers = @{ "User-Agent" = "FrontBack dependency installer" }
    Write-Status "Checking the latest SuperWoW release from GitHub..."
    $release = Invoke-RestMethod -Uri "https://api.github.com/repos/balakethelock/SuperWoW/releases/latest" -Headers $headers -TimeoutSec 30
    $asset = $release.assets |
        Where-Object { $_.name -match "(?i)\.zip$" } |
        Select-Object -First 1
    if (-not $asset) {
        throw "The latest SuperWoW release does not contain a ZIP archive."
    }
    $zipPath = Join-Path $TempRoot "SuperWoW.zip"
    $extractPath = Join-Path $TempRoot "SuperWoW"
    Write-Status "Downloading SuperWoW $($release.tag_name)..."
    Invoke-WebRequest -Uri $asset.browser_download_url -Headers $headers -OutFile $zipPath -UseBasicParsing -TimeoutSec 120
    Expand-Archive -LiteralPath $zipPath -DestinationPath $extractPath -Force
    $dll = Get-ChildItem -LiteralPath $extractPath -Recurse -Filter "SuperWoWhook.dll" -File |
        Select-Object -First 1
    if (-not $dll) {
        throw "The SuperWoW archive did not contain SuperWoWhook.dll."
    }
    Copy-Item -LiteralPath $dll.FullName -Destination $Destination -Force
}

function Prepare-Dependency([string]$FileName, [string]$Repository, [string]$TempRoot) {
    $output = Join-Path $TempRoot $FileName
    $bundled = Find-BundledDll $FileName
    if ($bundled) {
        Write-Status "Using bundled $FileName." "Ok"
        Copy-Item -LiteralPath $bundled -Destination $output -Force
    } elseif ($FileName -ieq "SuperWoWhook.dll") {
        Download-SuperWoW $output $TempRoot
    } else {
        Download-LatestReleaseFile $Repository $FileName $output
    }
    if (-not (Test-WindowsDll $output)) {
        throw "$FileName is not a valid-looking Windows DLL (missing MZ header). It was not installed."
    }
    return $output
}

function Install-Dependency([string]$Source, [string]$FileName, [string]$GameRoot) {
    $destination = Join-Path $GameRoot $FileName
    Write-Status "Installing $FileName..."
    Copy-Item -LiteralPath $Source -Destination $destination -Force
    Start-Sleep -Milliseconds 750
    if (-not (Test-WindowsDll $destination)) {
        throw "$FileName disappeared or was changed after copying. Windows Defender or another antivirus may have quarantined it. Review Protection History/Quarantine, then rerun the installer if you trust the source."
    }
    Write-Status "$FileName is present in the WoW root." "Ok"
}

function Update-DllList([string]$GameRoot, [string[]]$DllNames) {
    $listPath = Join-Path $GameRoot "dlls.txt"
    $lines = if (Test-Path -LiteralPath $listPath -PathType Leaf) {
        [IO.File]::ReadAllLines($listPath)
    } else {
        @()
    }
    $toAdd = @()
    foreach ($name in $DllNames) {
        $found = $false
        foreach ($line in $lines) {
            if ($line.Trim() -ieq $name) {
                $found = $true
                break
            }
        }
        if (-not $found -and $toAdd -notcontains $name) {
            $toAdd += $name
        }
    }
    if ($toAdd.Count -eq 0) {
        Write-Status "dlls.txt already contains both dependencies." "Ok"
        return
    }

    if (Test-Path -LiteralPath $listPath -PathType Leaf) {
        $backup = Join-Path $GameRoot ("dlls.txt.FrontBack-backup-" + (Get-Date -Format "yyyyMMdd-HHmmss"))
        Copy-Item -LiteralPath $listPath -Destination $backup -Force
        Write-Status "Backed up dlls.txt to $(Split-Path $backup -Leaf)." "Ok"
    }
    $updated = New-Object Collections.Generic.List[string]
    foreach ($line in $lines) {
        [void]$updated.Add($line)
    }
    foreach ($name in $toAdd) {
        [void]$updated.Add($name)
        Write-Status "Adding $name to dlls.txt." "Ok"
    }
    [IO.File]::WriteAllLines($listPath, [string[]]$updated)
}

try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $gameRoot = Resolve-GameRoot
    $tempRoot = Join-Path ([IO.Path]::GetTempPath()) ("FrontBack-DLL-" + [Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $tempRoot | Out-Null
    try {
        $unitXp = Prepare-Dependency "UnitXP_SP3.dll" "brues-code/UnitXP_SP3" $tempRoot
        $superWoW = Prepare-Dependency "SuperWoWhook.dll" "balakethelock/SuperWoW" $tempRoot
        Install-Dependency $unitXp "UnitXP_SP3.dll" $gameRoot
        Install-Dependency $superWoW "SuperWoWhook.dll" $gameRoot
        Update-DllList $gameRoot @("UnitXP_SP3.dll", "SuperWoWhook.dll")
    } finally {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    Write-Status "Done. Start the game through OctoLauncher with vanillaFixes enabled." "Ok"
} catch {
    Write-Status $_.Exception.Message "Error"
    Write-Status "The script did not change antivirus settings or launch the game." "Warn"
    exit 1
}
