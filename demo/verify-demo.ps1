$ErrorActionPreference = 'Stop'
$asset = 'https://github.com/adafruit/Adafruit_nRF52_Bootloader/releases/download/0.9.2/feather_nrf52840_express_bootloader-0.9.2_s140_6.1.1.hex'
$expectedHash = '11BA9CDE8701D8F2BD5BB26EA11D1D304A0260A0E1474BD1EBEC97DD04CF4640'
$scratch = Join-Path $PSScriptRoot '_build'
New-Item -ItemType Directory -Force -Path $scratch | Out-Null
$release = Join-Path $scratch 'adafruit-release.hex'
$merged = Join-Path $scratch 'merged.hex'
Invoke-WebRequest -Uri $asset -OutFile $release -TimeoutSec 30
if ((Get-FileHash -LiteralPath $release).Hash -ne $expectedHash) { throw 'Unexpected release checksum' }
$app = Join-Path $PSScriptRoot 'application.hex'
python (Join-Path $PSScriptRoot 'prepare-images.py') $app $release $merged
if ($LASTEXITCODE) { throw 'Could not prepare the comparison images' }
Push-Location (Split-Path -Parent $PSScriptRoot)
try {
    moon run cmd/main -- $app feather-application 26000 C7000
    if ($LASTEXITCODE -ne 0) { throw 'Expected the application to pass' }
    $report = moon run cmd/main -- $merged feather-application 26000 C7000
    $code = $LASTEXITCODE
    $report
    if ($code -ne 1 -or ($report -join "`n") -notmatch '\[0xf4000, 0xfbec0\)') {
        throw 'Expected the merged image to report the bootloader address range'
    }
} finally {
    Pop-Location
}
