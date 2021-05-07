$requiredWindowsFeatures = @(
    "Containers",
    "Hyper-V",
    "Hyper-V-PowerShell")

function ValidateWindowsFeatures {
    $allFeaturesInstalled = $true
    foreach ($feature in $requiredWindowsFeatures) {
        $f = Get-WindowsFeature -Name $feature
        if (-not $f.Installed) {
            Write-Warning "Windows feature: '$feature' is not installed."
            $allFeaturesInstalled = $false
        }
    }
    return $allFeaturesInstalled
}

if (-not (ValidateWindowsFeatures)) {
    Write-Output "Installing required windows features..."

    foreach ($feature in $requiredWindowsFeatures) {
        Install-WindowsFeature -Name $feature
    }

    Write-Output "Please reboot and re-run this script."
    exit 0
}