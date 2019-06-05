[CmdletBinding()]
Param([Parameter(Mandatory = $false)][switch] $LocalFile)     

# Get Module Path
$modulespath = ($env:psmodulepath -split ";")[0]
$pssfdxpath = Join-Path -Path $modulespath -ChildPath "psfdx"
Write-Verbose "Module Path: $pssfdxpath"

# Get Source Path
$filename = "psfdx.psm1"
$gitUrl = "https://raw.githubusercontent.com/ZenInternet/psfdx/master/psfdx.psm1"

# Install
Write-Host "Creating module directory"
New-Item -Type Container -Force -path $pssfdxpath | Out-Null

Write-Host "Downloading and installing"
$destination = Join-Path -Path $pssfdxpath -ChildPath $filename
if ($LocalFile) {
    $currentFile = Join-Path -Path $PSScriptRoot -ChildPath $filename        
    Write-Verbose "Source File: $currentFile"
    Copy-Item -Path $currentFile -Destination $destination -Force
} else {
    Write-Verbose "Source File: $gitUrl"
    $response = Invoke-WebRequest -Uri $gitUrl -Verbose:$false
    # TODO: Check WebRequest Status    
    $response.Content | Out-File -FilePath (Join-Path -Path $pssfdxpath -ChildPath $filename) -Force
}

Write-Host "Installed."
Write-Host 'Use "Import-Module psfdx" and then "Get-Command -Module psfdx"'