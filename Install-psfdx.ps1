$modulespath = ($env:psmodulepath -split ";")[0]
$pssfdxpath = "$modulespath\psfdx"

Write-Host "Creating module directory"
New-Item -Type Container -Force -path $pswatchpath | out-null

Write-Host "Downloading and installing"
(new-object net.webclient).DownloadString("https://github.com/ZenInternet/psfdx/blob/master/psfdx.psm1") | Out-File "$pssfdxpath\psfdx.psm1" 

Write-Host "Installed!"
Write-Host 'Use "Import-Module psfdx" and then "Get-Command -Module psfdx"'