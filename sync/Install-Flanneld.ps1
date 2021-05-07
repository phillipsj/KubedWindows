Param(
    [parameter(HelpMessage = "Flanneld version to use")]
    [string] $ContainerDVersion = "1.4.4"
)

$ErrorActionPreference = 'Stop'

function DownloadFile($destination, $source) {
    Write-Host("Downloading $source to $destination")
    curl.exe --silent --fail -Lo $destination $source

    if (!$?) {
        Write-Error "Download $source failed"
        exit 1
    }
}

$global:KubernetesPath = "$env:SystemDrive\k"
$global:NssmInstallDirectory = "$env:ProgramFiles\nssm"

Copy-Item -Path C:\sync\kubeadmconfig -Destination C:\k\config
mkdir -force C:\k\flannel
mkdir -force C:\k\flannel\var\run\secrets\kubernetes.io\serviceaccount

Write-Output "Getting Flanneld binaries"
$global:FlannelDPath = "$global:KubernetesPath\flannel"
mkdir -Force $global:FlannelDPath | Out-Null
DownloadFile "$global:FlannelDPath\flanneld.exe" https://github.com/coreos/flannel/releases/download/v${flannelVersion}/flanneld.exe

Add-MpPreference -ExclusionProcess "$global:FlannelDPath\flanneld.exe"


Write-Host "Registering flanneld service"
nssm install flanneld $global:Powershell $global:PowershellArgs $global:StartFlannelScript

# Need to understand config
$containerRuntime = "docker"
if (Test-Path /host/etc/cni/net.d/0-containerd-nat.json) {
  $containerRuntime = "containerd"
}

Write-Host "Configuring CNI for $containerRuntime"

    $serviceSubnet = yq r /etc/kubeadm-config/ClusterConfiguration networking.serviceSubnet
    $podSubnet = yq r /etc/kubeadm-config/ClusterConfiguration networking.podSubnet
    $networkJson = wins cli net get | convertfrom-json
    if ($containerRuntime -eq "docker") {
      $cniJson = get-content /etc/kube-flannel-windows/cni-conf.json | ConvertFrom-Json
      $cniJson.delegate.policies[0].Value.ExceptionList = $serviceSubnet, $podSubnet
      $cniJson.delegate.policies[1].Value.DestinationPrefix = $serviceSubnet
      Set-Content -Path /host/etc/cni/net.d/10-flannel.conf ($cniJson | ConvertTo-Json -depth 100)
    } elseif ($containerRuntime -eq "containerd") {
      $cniJson = get-content /etc/kube-flannel-windows/cni-conf-containerd.json | ConvertFrom-Json
      $cniJson.delegate.AdditionalArgs[0].Value.Settings.Exceptions = $serviceSubnet, $podSubnet
      $cniJson.delegate.AdditionalArgs[1].Value.Settings.DestinationPrefix = $serviceSubnet
      $cniJson.delegate.AdditionalArgs[2].Value.Settings.ProviderAddress = $networkJson.AddressCIDR.Split('/')[0]
      Set-Content -Path /host/etc/cni/net.d/10-flannel.conf ($cniJson | ConvertTo-Json -depth 100)
    }


