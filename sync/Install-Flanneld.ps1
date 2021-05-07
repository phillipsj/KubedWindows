Param(
    [parameter(HelpMessage = "Flanneld version to use")]
    [string] $flannelDVersion = "0.13.0",
    [parameter(HelpMessage = "ContainerD version to use")]
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

mkdir -Force $global:KubernetesPath | Out-Null
Copy-Item -Path C:\sync\config -Destination C:\k\config

# install containerd
Write-Output "Getting ContainerD binaries"
$global:ConainterDPath = "$env:ProgramFiles\containerd"
mkdir -Force $global:ConainterDPath | Out-Null
DownloadFile "$global:ConainterDPath\containerd.tar.gz" https://github.com/containerd/containerd/releases/download/v${ContainerDVersion}/containerd-${ContainerDVersion}-windows-amd64.tar.gz
tar.exe -xvf "$global:ConainterDPath\containerd.tar.gz" --strip=1 -C $global:ConainterDPath
$env:Path += ";$global:ConainterDPath"
[Environment]::SetEnvironmentVariable("Path", $env:Path, [System.EnvironmentVariableTarget]::Machine)

Add-MpPreference -ExclusionProcess "$Env:ProgramFiles\containerd\containerd.exe"

& $global:ConainterDPath\containerd.exe config default | Out-File $Env:ProgramFiles\containerd\config.toml -Encoding ascii

Write-Output "Registering ContainerD as a service"
& $global:ConainterDPath\containerd.exe --register-service

containerd.exe config default | Out-File "$global:ConainterDPath\config.toml" -Encoding ascii
$config = Get-Content "$global:ConainterDPath\config.toml"
$config = $config -replace "bin_dir = (.)*$", "bin_dir = `"c:/opt/cni/bin`""
$config = $config -replace "conf_dir = (.)*$", "conf_dir = `"c:/etc/cni/net.d`""
$config | Set-Content "$global:ConainterDPath\config.toml" -Force 

# install CNI
mkdir -Force c:\opt\cni\bin | Out-Null
mkdir -Force c:\etc\cni\net.d | Out-Null

Write-Output "Getting SDN CNI binaries"
DownloadFile "c:\opt\cni\cni-plugins.tgz" https://github.com/containernetworking/plugins/releases/download/v0.9.1/cni-plugins-windows-amd64-v0.9.1.tgz
tar.exe -xvf "c:\opt\cni\cni-plugins.tgz" --strip=1 -C "c:\opt\cni\bin"


# setup cni config
@"
{
    "name": "flannel.4096",
    "cniVersion": "0.3.0",
    "type": "flannel",
    "capabilities": {
        "dns": true
    },
    "delegate": {
        "type": "win-overlay",
        "policies": [
            {
                "Name": "EndpointPolicy",
                "Value": {
                    "Type": "OutBoundNAT",
                    "ExceptionList": [
                        "10.96.0.0/12",
                        "10.244.0.0/16"
                    ]
                }
            },
            {
                "Name": "EndpointPolicy",
                "Value": {
                    "Type": "ROUTE",
                    "DestinationPrefix": "10.96.0.0/12",
                    "NeedEncap": true
                }
            }
        ]
    }
}
"@ | Set-Content c:\etc\cni\net.d\net.json -Force

# setup a single network so that flannel doesn't fail when connection is lost
DownloadFile "c:\k\hns.psm1" https://github.com/Microsoft/SDN/raw/master/Kubernetes/windows/hns.psm1
Import-Module "c:\k\hns.psm1"
Get-HNSNetwork | Remove-HnsNetwork
New-HNSNetwork -Type Overlay -AddressPrefix "192.168.255.0/30" -Gateway "192.168.255.1" -Name "External" -AdapterName "$((Get-NetAdapter -Physical).Name)" -SubnetPolicies @(@{Type = "VSID"; VSID = 9999; })

# Install flannel
mkdir -force C:\k\flannel
mkdir -force C:\k\flannel\var\run\secrets\kubernetes.io\serviceaccount

Write-Output "Getting Flanneld binaries"
$global:FlannelDPath = "$global:KubernetesPath\flannel"
mkdir -Force $global:FlannelDPath | Out-Null
DownloadFile "$global:FlannelDPath\flanneld.exe" https://github.com/coreos/flannel/releases/download/v${flannelDVersion}/flanneld.exe

Add-MpPreference -ExclusionProcess "$global:FlannelDPath\flanneld.exe"

# setup flannel config
New-Item C:\etc\kube-flannel\ -Force -ItemType Directory | Out-Null
@"
{
  "Network": "10.244.0.0/16",
  "Backend": {
    "Type": "vxlan",
    "VNI": 4096,
    "Port": 4789
  }
}
"@ | Set-Content C:\etc\kube-flannel\net-conf.json -Force | Out-Null

New-Service -Name "flanneld" -BinaryPathName '"C:\k\flannel\flanneld.exe -kube-subnet-mgr -kubeconfig-file /k/config"' -StartupType Automatic
Start-Service flanneld
Write-Output "Waiting for FlannelD to report that it has started."
while ((Get-Service flanneld).Status -ne 'Running') { Start-Sleep -s 5 } 

# start containerd
Set-Service -Name containerd -StartupType Automatic
Start-Service containerd
Write-Output "Waiting for Containerd to report that it has started."
while ((Get-Service containerd).Status -ne 'Running') { Start-Sleep -s 5 } 


