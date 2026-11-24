# clean_sim.ps1
# Removes Vivado simulator output (xvlog / xelab / xsim) from the project root
# and from sim/. Only deletes generated files; never touches source files.
#
# Usage (from anywhere):
#   powershell -ExecutionPolicy Bypass -File scripts\clean_sim.ps1

$root = Split-Path -Parent $PSScriptRoot

# Folders and file patterns the Vivado simulator generates
$dirs     = @('xsim.dir', '.Xil')
$patterns = @('*.log', '*.jou', '*.pb', '*.wdb', '*.vcd', '*.str', 'webtalk*', 'hs_err_pid*')

# Clean the project root and sim/ (where the commands are usually run from)
foreach ($base in @($root, (Join-Path $root 'sim'))) {
    if (-not (Test-Path $base)) { continue }

    foreach ($d in $dirs) {
        $p = Join-Path $base $d
        if (Test-Path $p) {
            Remove-Item -Recurse -Force $p
            Write-Host "removed $p"
        }
    }

    foreach ($pat in $patterns) {
        Get-ChildItem -Path $base -Filter $pat -File -ErrorAction SilentlyContinue | ForEach-Object {
            Remove-Item -Force $_.FullName
            Write-Host "removed $($_.FullName)"
        }
    }
}

Write-Host "Simulation clean-up done."
