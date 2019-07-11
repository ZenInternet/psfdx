$toolingApiObjects = @("SandboxInfo", "ProfileLayout")

function Get-SalesforceDateTime {
    [CmdletBinding()]
    Param([Parameter(Mandatory = $false)][datetime] $Datetime) 

    if ($null -eq $Datetime) { $Datetime = Get-Date}
    return $Datetime.ToString('s') + 'Z'
}

function Connect-Salesforce {
    [CmdletBinding()]
    Param([Parameter(Mandatory = $false)][switch] $IsSandbox)     
    if ($IsSandbox -eq $true) {
        sfdx force:auth:web:login -r "https://test.salesforce.com"
    }
    else {
        sfdx force:auth:web:login
    }
}

function Disconnect-Salesforce {
    [CmdletBinding()]
    Param([Parameter(Mandatory = $true)][string] $Username)     
    sfdx force:auth:logout -u $Username -p
}

function Grant-SalesforceJWT {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $ConsumerKey,
        [Parameter(Mandatory = $true)][string] $Username,
        [Parameter(Mandatory = $true)][string] $JwtKeyfile,
        [Parameter(Mandatory = $false)][switch] $IsSandbox
    )
    if (-not(Test-Path $JwtKeyfile)) { throw "File does not exist: $JwtKeyfile"}
    $url = "https://login.salesforce.com/"
    if ($IsSandbox) { $url = "https://test.salesforce.com" }
    
    $result = sfdx force:auth:jwt:grant --clientid $ConsumerKey --username $Username --jwtkeyfile $JwtKeyfile --instanceurl $url --json
    return ($result | ConvertFrom-Json).result
}

function Open-Salesforce {
    [CmdletBinding()]
    Param([Parameter(Mandatory = $true)][string] $Username )     
    sfdx force:org:open -u $Username
}

function Get-Salesforce {    
    [CmdletBinding()]
    $values = sfdx force:org:list --json | ConvertFrom-Json
    return $values.result.nonScratchOrgs  | Select-Object orgId, instanceUrl, username, connectedStatus, isDevHub, lastUsed, alias
}

function Get-SalesforceScratchOrgs {
    [CmdletBinding()]
    $values = sfdx force:org:list --all --json | ConvertFrom-Json    
    return $values.result.scratchOrgs | Select-Object orgId, instanceUrl, username, connectedStatus, isDevHub, lastUsed, alias
}

function New-SalesforceScratchOrg {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][string] $DefinitionFile = 'config/project-scratch-def.json',
        [Parameter(Mandatory = $true)][string] $Username
    )       
    return (sfdx force:org:create -f $DefinitionFile -v $Username --json | ConvertFrom-Json).result
}

function Select-SalesforceObjects {    
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $Query,    
        [Parameter(Mandatory = $true)][string] $Username,
        [Parameter(Mandatory = $false)][switch] $UseToolingApi
    )            
    Write-Verbose $Query
    if ($UseToolingApi) {
        $json = (sfdx force:data:soql:query -q $Query -u $Username -t --json -r json)
    } else {
        $json = (sfdx force:data:soql:query -q $Query -u $Username --json -r json)
    }  
    $values = $json | ConvertFrom-Json     
    # TODO: Check Status    
    return $values.result.records
}

function Get-SalesforceLimits {
    [CmdletBinding()]
    Param([Parameter(Mandatory = $true)][string] $Username)  
    return ((sfdx force:limits:api:display -u $Username --json) | ConvertFrom-Json).result
}

function Get-SalesforceDataStorage {
    [CmdletBinding()]
    Param([Parameter(Mandatory = $true)][string] $Username)       
    $values = Get-SalesforceLimits -Username $Username | Where-Object Name -eq "DataStorageMB"        
    $values | Add-Member -NotePropertyName InUse -NotePropertyValue ($values.max + ($values.remaining * -1))
    $values | Add-Member -NotePropertyName Usage -NotePropertyValue (($values.max + ($values.remaining * -1)) / $values.max).ToString('P')
    return $values 
}

function Get-SalesforceApiUsage {
    [CmdletBinding()]
    Param([Parameter(Mandatory = $true)][string] $Username)       
    $values = Get-SalesforceLimits -Username $Username | Where-Object Name -eq "DailyApiRequests"        
    $values | Add-Member -NotePropertyName Usage -NotePropertyValue (($values.max + ($values.remaining * -1)) / $values.max).ToString('P')
    return $values
}

function Describe-SalesforceObjects {
    [CmdletBinding()]
    Param([Parameter(Mandatory = $true)][string] $Username) 
    return ((sfdx force:schema:sobject:list -c all -u $Username --json) | ConvertFrom-Json).result
}

function Describe-SalesforceObject {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $ObjectName,    
        [Parameter(Mandatory = $true)][string] $Username,
        [Parameter(Mandatory = $false)][switch] $UseToolingApi
    ) 
    if ($UseToolingApi) {
        $values = sfdx force:schema:sobject:describe -s $ObjectName -u $Username -t --json
    } else {
        $values = sfdx force:schema:sobject:describe -s $ObjectName -u $Username --json
    }
    return ($values | ConvertFrom-Json).result
}

function Describe-SalesforceFields {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $ObjectName,    
        [Parameter(Mandatory = $true)][string] $Username,
        [Parameter(Mandatory = $false)][switch] $UseToolingApi        
    )         
    return (Describe-SalesforceObject -ObjectName $ObjectName -Username $Username -UseToolingApi:$UseToolingApi).fields | Select-Object name, label, type, byteLength
}

function Describe-SalesforceCodeTypes {
    [CmdletBinding()]
    Param([Parameter(Mandatory = $true)][string] $Username)             
    $values = (sfdx force:mdapi:describemetadata -u $Username --json | ConvertFrom-Json)
    return $values.result.metadataObjects | Select-Object xmlName    
}

function Build-SalesforceQuery {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $ObjectName,    
        [Parameter(Mandatory = $true)][string] $Username,
        [Parameter(Mandatory = $false)][switch] $UseToolingApi
    ) 
    $fields = Describe-SalesforceFields -ObjectName $ObjectName -Username $Username -UseToolingApi:$UseToolingApi
    if ($null -eq $fields) {
        return ""
    }

    $fieldNames = @()
    foreach ($field in $fields) { 
        $fieldNames += $field.name 
    }
    $value = "SELECT "
    foreach ($fieldName in $fieldNames) { 
        $value += $fieldName + "," 
    }
    $value = $value.TrimEnd(",")
    $value += " FROM $ObjectName"
    return $value
}

function New-SalesforceObject {
    [CmdletBinding()]
    Param(                
        [Parameter(Mandatory = $true)][string] $ObjectType,    
        [Parameter(Mandatory = $true)][string] $FieldUpdates,    
        [Parameter(Mandatory = $true)][string] $Username
    )
    return sfdx force:data:record:create -s $ObjectType -v $FieldUpdates -u $Username    
}

function Set-SalesforceObject {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $Id,    
        [Parameter(Mandatory = $true)][string] $ObjectType,    
        [Parameter(Mandatory = $true)][string] $FieldUpdates,    
        [Parameter(Mandatory = $true)][string] $Username
    )
    Write-Verbose $FieldUpdates
    return sfdx force:data:record:update -s $ObjectType -i $Id -v $FieldUpdates -u $Username
}

function Test-SalesforceClass {
    [CmdletBinding()]
    Param(        
        [Parameter(Mandatory = $true)][string] $Name,       
        [Parameter(Mandatory = $false)][string] $TestName, 
        [Parameter(Mandatory = $true)][string] $Username
    )

    if ($TestName) {
        $tests = "$Name.$TestName"
        $values = (sfdx force:apex:test:run --tests $tests --synchronous -u $Username --json | ConvertFrom-Json)
    } else {
        $values = (sfdx force:apex:test:run --classnames $Name --synchronous -u $Username --json | ConvertFrom-Json)
    }
    $values.result.tests  
    if ($values.result.summary.outcome -ne 'Passed') { 
        throw ($values.result.summary.failing.tostring() + " Tests Failed") 
    }  
}

function Pull-SalesforceCode {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string][ValidateSet('ApexTrigger','ApexClass', 'LightningComponentBundle')] $CodeType,
        [Parameter(Mandatory = $true)][string] $Username
    )  
    sfdx force:source:retrieve -m $CodeType -u $Username
}

function Push-SalesforceCode {
    [CmdletBinding()]
    Param(        
        [Parameter(Mandatory = $false)][string][ValidateSet('ApexTrigger','ApexClass', 'LightningComponentBundle')] $CodeType = 'ApexClass',       
        [Parameter(Mandatory = $true)][string] $Name,       
        [Parameter(Mandatory = $true)][string] $Username
    )    
    if ($CodeType -eq 'ApexClass') {
        sfdx force:source:deploy -m ApexClass:$Name -u $Username 
        return
    }
    if ($CodeType -eq 'ApexTrigger') {
        sfdx force:source:deploy -m ApexTrigger:$Name -u $Username 
        return        
    }
    if ($CodeType -eq 'LightningComponentBundle') {
        sfdx force:source:deploy -m LightningComponentBundle:$Name -u $Username 
        return        
    }    
    throw "Unrecognised CodeType: $CodeType"
}

function Test-Salesforce {
    [CmdletBinding()]
    Param(                
        [Parameter(Mandatory = $true)][string] $Username
    )    
    $path = $PSScriptRoot
    $values = (sfdx force:apex:test:run -l RunLocalTests -w:10 -d $PSScriptRoot -u $Username --json)
}

function Invoke-SalesforceApexFile {
    [CmdletBinding()]
    Param(        
        [Parameter(Mandatory = $true)][string] $ApexFile,       
        [Parameter(Mandatory = $true)][string] $Username
    )
    $values = (sfdx force:apex:execute -f $ApexFile -u $Username --json | ConvertFrom-Json)
    return $values.result
}

function Get-SalesforceAlias {
    [CmdletBinding()]
    $values = (sfdx force:alias:list --json | ConvertFrom-Json)
    return $values.result
}

function Add-SalesforceAlias {
    [CmdletBinding()]
    Param(        
        [Parameter(Mandatory = $true)][string] $Alias,       
        [Parameter(Mandatory = $true)][string] $Username
    )    
    sfdx force:alias:set $Alias=$Username    
}

function Get-SalesforcePackage {
    [CmdletBinding()]
    Param([Parameter(Mandatory = $true)][string] $Path)           
    if (-not (Test-Path -Path $Path)) { throw "$Path does not exist"}
    
    [xml]$package = Get-Content .\package.xml
    $results = @()    
    foreach ($t in $package.Package.types) {
        $typeName = $t.name
        foreach ($m in $t.members) {        
            $result = New-Object -TypeName psobject
            $result | Add-Member -MemberType NoteProperty -Name TypeName -Value $typeName
            $result | Add-Member -MemberType NoteProperty -Name MemberName -Value $m
            $results += $result
        } # Member
    }  # Type   
    return $results
}

function Watch-SalesforceLogs {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $Username,
        [Parameter(Mandatory = $false)][switch] $IncludeTraceFlag        
    )    
    if ($IncludeTraceFlag) {
        sfdx force:apex:log:tail -c -u $Username
    } else {
        sfdx force:apex:log:tail -s -c -u $Username
    }
}

function Get-SalesforceLogs {
    [CmdletBinding()]
    Param([Parameter(Mandatory = $true)][string] $Username)     
    $values = sfdx force:apex:log:list -u $Username --json | ConvertFrom-Json
    # TODO: Check status
    return $values.result
}

function Get-SalesforceLog {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][string] $LogId,
        [Parameter(Mandatory = $false)][switch] $Last,
        [Parameter(Mandatory = $true)][string] $Username
    )   
    
    if ((-not $LogId) -and (-not $Last)) { throw "Please provide either -LogId OR -Last"}

    if ($Last) {
        $LogId = (Get-SalesforceLogs -Username $Username | Sort-Object StartTime -Descending | Select-Object -First 1).Id
    }

    $values = sfdx force:apex:log:get -i $LogId -u $Username --json | ConvertFrom-Json
    # TODO: Check status
    return $values.result.log
}

function Convert-SalesforceLog {
    [CmdletBinding()]
    Param(
        [Parameter(ValueFromPipeline, Mandatory = $true)][string] $Log
    )      

    Write-Warning "Function still in Development"

    $results = @()
    $lines = $Log.Split([Environment]::NewLine) | Select-Object -Skip 1 # Skip Header
    $line = $lines | Select-Object -First 5
    foreach ($line in $lines) {
        $statements = $line.Split('|')
        
        $result = New-Object -TypeName PSObject
        $result | Add-Member -MemberType NoteProperty -Name 'DateTime' -Value $statements[0]
        $result | Add-Member -MemberType NoteProperty -Name 'LogType' -Value $statements[1]
        if ($null -ne $statements[2]) { $result | Add-Member -MemberType NoteProperty -Name 'SubType' -Value $statements[2] }
        if ($null -ne $statements[3]) { $result | Add-Member -MemberType NoteProperty -Name 'Detail' -Value $statements[3] }
        $results += $result
    }
    return $results
}

function Out-Notepad {
    [CmdletBinding()]
    Param([Parameter(ValueFromPipeline, Mandatory = $true)][string] $Content)     
    $filename = New-TemporaryFile
    $Content | Out-File -FilePath $filename
    notepad $filename
}

function New-SalesforceProject {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $Name,
        [Parameter(Mandatory = $false)][string][ValidateSet('standard','empty')] $Template = 'standard'
    )       
    $response = (sfdx force:project:create --projectname $Name --template $Template --json) | ConvertFrom-Json
    return $response.result
}