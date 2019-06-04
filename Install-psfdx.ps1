$modulespath = ($env:psmodulepath -split ";")[0]
$pssfdxpath = "$modulespath\psfdx"

Write-Host "Creating module directory"
New-Item -Type Container -Force -path $pssfdxpath | out-null

Write-Host "Downloading and installing"
(new-object net.webclient).DownloadString("https://raw.githubusercontent.com/ZenInternet/psfdx/master/psfdx.psm1") | Out-File "$pssfdxpath\psfdx.psm1" 

Write-Host "Installed!"
Write-Host 'Use "Import-Module psfdx" and then "Get-Command -Module psfdx"'