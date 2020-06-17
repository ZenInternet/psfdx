$toolingApiObjects = @("SandboxInfo", "ProfileLayout")

function Invoke-Expression2 {
    [CmdletBinding()]
    Param([Parameter(Mandatory = $true)][string] $Command)        
    Write-Verbose $Command
    return Invoke-Expression -Command $Command
}

function Show-SalesforceJsonResult {
    [CmdletBinding()]
    Param([Parameter(Mandatory = $true)][psobject] $Result)        
    
    $result = $Result | ConvertFrom-Json
    if ($result.status -ne 0) {
        throw ($result.message)
    }
    return $result.result
}

function Get-SalesforceDateTime {
    [CmdletBinding()]
    Param([Parameter(Mandatory = $false)][datetime] $Datetime) 

    if ($null -eq $Datetime) { $Datetime = Get-Date}
    return $Datetime.ToString('s') + 'Z'
}

function Connect-Salesforce {
    [CmdletBinding()]
    Param([Parameter(Mandatory = $false)][switch] $IsSandbox)  
    
    $command = "sfdx force:auth:web:login"    
    if ($IsSandbox -eq $true) { 
        $command += " -r https://test.salesforce.com" 
    }
    Invoke-Expression2 -Command $command
}

function Disconnect-Salesforce {
    [CmdletBinding()]
    Param([Parameter(Mandatory = $true)][string] $Username)         
    Invoke-Expression2 -Command "sfdx force:auth:logout -u $Username -p"
}

function Grant-SalesforceJWT {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $ConsumerKey,
        [Parameter(Mandatory = $true)][string] $Username,
        [Parameter(Mandatory = $true)][string] $JwtKeyfile,
        [Parameter(Mandatory = $false)][switch] $IsSandbox,
        [Parameter(Mandatory = $false)][switch] $SetDefaultUsername
    )
    if (-not(Test-Path $JwtKeyfile)) { 
        throw "File does not exist: $JwtKeyfile"
    }

    $url = "https://login.salesforce.com/"
    if ($IsSandbox) { $url = "https://test.salesforce.com" }
    
    $command = "sfdx force:auth:jwt:grant --clientid $ConsumerKey --username $Username --jwtkeyfile $JwtKeyfile --instanceurl $url "
    if ($SetDefaultUsername) {
        $command += "--setdefaultusername "
    }
    $command += "--json"

    $result = Invoke-Expression2 -Command $command  
    return Show-SalesforceJsonResult -Result $result
}

function Open-Salesforce {
    [CmdletBinding()]
    Param([Parameter(Mandatory = $true)][string] $Username)     
    Invoke-Expression2 -Command "sfdx force:org:open -u $Username"    
}

function Get-Salesforce {    
    [CmdletBinding()]
    Param()    
    $result = Invoke-Expression2 -Command "sfdx force:org:list --json"
    $result = $result | ConvertFrom-Json
    $result = $result.result.nonScratchOrgs # Exclude Scratch Orgs
    $result = $result | Select-Object orgId, instanceUrl, username, connectedStatus, isDevHub, lastUsed, alias
    return $result
}

function Get-SalesforceScratchOrgs {
    [CmdletBinding()]
    Param([Parameter(Mandatory = $false)][switch] $Last)
    $result = Invoke-Expression2 -Command "sfdx force:org:list --all --json"
    $result = $result | ConvertFrom-Json   
    $result = $result.result.scratchOrgs
    $result = $result | Select-Object orgId, instanceUrl, username, connectedStatus, isDevHub, lastUsed, alias
    if ($Last) {
        $result = $result | Sort-Object lastUsed -Descending | Select-Object -First 1
    }
    return $result
}

function New-SalesforceScratchOrg {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][string] $DefinitionFile = 'config/project-scratch-def.json',
        [Parameter(Mandatory = $true)][string] $Username
    )     
    $result = Invoke-Expression2 -Command "sfdx force:org:create -f $DefinitionFile -v $Username --json"   
    $result = $result | ConvertFrom-Json
    return Show-SalesforceJsonResult -Result $result
}

function Select-SalesforceObjects {    
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $Query,    
        [Parameter(Mandatory = $true)][string] $Username,
        [Parameter(Mandatory = $false)][switch] $UseToolingApi
    )            
    Write-Verbose $Query
    $command = "sfdx force:data:soql:query -q `"$Query`" -u $Username "
    if ($UseToolingApi) {
        $command += "-t "
    }
    $command += "--json"

    Write-Verbose $command
    $result = Invoke-Expression -Command $command

    $result = $result | ConvertFrom-Json
    if ($result.status -ne 0) {
        $result
        throw $result.message
    }
    return $result.result.records
}

function Get-SalesforceLimits {
    [CmdletBinding()]
    Param([Parameter(Mandatory = $true)][string] $Username)  
    $result = Invoke-Expression2 -Command "sfdx force:limits:api:display -u $Username --json"
    return Show-SalesforceJsonResult -Result $result    
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
    $result = Invoke-Expression2 -Command "sfdx force:schema:sobject:list -c all -u $Username --json"
    return Show-SalesforceJsonResult -Result $result    
}

function Describe-SalesforceObject {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $ObjectName,    
        [Parameter(Mandatory = $true)][string] $Username,
        [Parameter(Mandatory = $false)][switch] $UseToolingApi
    ) 
    $command = "sfdx force:schema:sobject:describe -s $ObjectName -u $Username "
    if ($UseToolingApi) {
        $command += "-t "
    }    
    $command += "--json"
    $result = Invoke-Expression2 -Command $command
    return Show-SalesforceJsonResult -Result $result
}

function Describe-SalesforceFields {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)][string] $ObjectName,    
        [Parameter(Mandatory = $true)][string] $Username,
        [Parameter(Mandatory = $false)][switch] $UseToolingApi        
    )         
    $result = Describe-SalesforceObject -ObjectName $ObjectName -Username $Username -UseToolingApi:$UseToolingApi
    $result = $result.fields
    $result = $result | Select-Object name, label, type, byteLength
    return $result
}

function Describe-SalesforceCodeTypes {
    [CmdletBinding()]
    Param([Parameter(Mandatory = $true)][string] $Username)  
    $result = Invoke-Expression2 -Command "sfdx force:mdapi:describemetadata -u $Username --json"           
    $result = $result | ConvertFrom-Json
    $result = $result.result.metadataObjects
    $result = $result | Select-Object xmlName
    return $result
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
    Write-Verbose $FieldUpdates
    $command = "sfdx force:data:record:create -s $ObjectType -v `"$FieldUpdates`" -u $Username"
    return Invoke-Expression2 -Command $command    
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
    $command = "sfdx force:data:record:update -s $ObjectType -i $Id -v `"$FieldUpdates`" -u $Username"
    return Invoke-Expression2 -Command $command        
}

function Get-SalesforceRecordType {
    [CmdletBinding()]
    Param(        
        [Parameter(Mandatory = $true)][string] $ObjectType,            
        [Parameter(Mandatory = $true)][string] $Username
    )    

    $query = "SELECT Id, SobjectType, Name, DeveloperName, IsActive, IsPersonType"
    $query += " FROM RecordType"
    if ($ObjectType) { $query += " WHERE SobjectType = '$ObjectType'" }
    return Select-SalesforceObjects -Query $query -Username $Username
}

function Pull-SalesforceCode {
    [CmdletBinding()]
    Param(        
        [Parameter(Mandatory = $true)][string] $Username,
        [Parameter(Mandatory = $false)][string][ValidateSet('ApexTrigger','ApexClass', 'LightningComponentBundle')] $CodeType
    )  

    if ($CodeType) {
        return Invoke-Expression2 -Command "sfdx force:source:retrieve -m $CodeType -u $Username"
    }
    
    $metaTypes = Get-SalesforceMetaTypes -Username $Username    
    $count = 0
    foreach ($metaType in $metaTypes) {
        Invoke-Expression2 -Command "sfdx force:source:retrieve -m $metaType -u $Username"        
        $count = $count + 1   
        Write-Progress -Activity 'Getting Salesforce MetaData' -Status $metaType -PercentComplete (($count / $metaTypes.count) * 100) 
    }
}

function Push-SalesforceCode {
    [CmdletBinding()]
    Param(        
        [Parameter(Mandatory = $false)][string][ValidateSet('ApexTrigger','ApexClass', 'LightningComponentBundle')] $CodeType = 'ApexClass',       
        [Parameter(Mandatory = $true)][string] $Name,       
        [Parameter(Mandatory = $true)][string] $Username
    )    
    $command = "sfdx force:source:deploy -m "
    if ($CodeType -eq 'ApexClass') {
        $command += "ApexClass"
    }
    elseif ($CodeType -eq 'ApexTrigger') {
        $command += "ApexTrigger"
    }
    elseif ($CodeType -eq 'LightningComponentBundle') {
        $command += "LightningComponentBundle"
    }
    else {
        throw "Unrecognised CodeType: $CodeType"    
    }
    $command += ":$Name -u $Username"
    return Invoke-Expression2 -Command $command
}

function Test-Salesforce {
    [CmdletBinding()]
    Param(        
        [Parameter(Mandatory = $false)][string] $ClassName,       
        [Parameter(Mandatory = $false)][string] $TestName, 
        [Parameter(Mandatory = $true)][string] $Username
    )   
        
    if ($ClassName -and $TestName) {        # Run specific Test in a Class
        $command = "sfdx force:apex:test:run --tests $ClassName.$TestName --synchronous -u $Username --codecoverage -r json"                        
    }     
    elseif (-not $TestName) {               # Run Test Class
        $command = "sfdx force:apex:test:run --classnames $ClassName --synchronous -u $Username --codecoverage -r json"           
    }     
    else {                                  # Run all Tests
        $command = "sfdx force:apex:test:run -l RunLocalTests -w:10 -d $PSScriptRoot -u $Username --codecoverage -r json"        
    }
    $result = Invoke-Expression2 -Command $command
    $result = $result | ConvertFrom-Json
    
    [int]$codeCoverage = ($result.result.summary.testRunCoverage -replace '%')
    if ($codeCoverage -lt 75) { 
        $result.result.coverage.coverage                
        throw 'Insufficent code coverage '
    }

    $result.result.tests
    if ($result.result.summary.outcome -ne 'Passed') { 
        throw ($result.result.summary.failing.tostring() + " Tests Failed") 
    }
}

function Invoke-SalesforceApexFile {
    [CmdletBinding()]
    Param(        
        [Parameter(Mandatory = $true)][string] $ApexFile,       
        [Parameter(Mandatory = $true)][string] $Username
    )
    $result = Invoke-Expression2 -Command "sfdx force:apex:execute -f $ApexFile -u $Username --json"
    return Show-SalesforceJsonResult -Result $result
}

function Get-SalesforceAlias {
    [CmdletBinding()]
    $result = Invoke-Expression2 -Command "sfdx force:alias:list --json"
    return Show-SalesforceJsonResult -Result $result
}

function Add-SalesforceAlias {
    [CmdletBinding()]
    Param(        
        [Parameter(Mandatory = $true)][string] $Alias,       
        [Parameter(Mandatory = $true)][string] $Username
    )    
    Invoke-Expression2 -Command "sfdx force:alias:set $Alias=$Username"    
}

function Remove-SalesforceAlias {
    [CmdletBinding()]
    Param([Parameter(Mandatory = $true)][string] $Alias)            
    Invoke-Expression2 -Command "sfdx force:alias:set $Alias="
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
    $command = "sfdx force:apex:log:tail "  
    if ($IncludeTraceFlag) {
        $command += "-s "
    }
    $command += "-c -u $Username"
    return Invoke-Expression2 -Command $command
}

function Get-SalesforceLogs {
    [CmdletBinding()]
    Param([Parameter(Mandatory = $true)][string] $Username)  
    $result = Invoke-Expression2 -Command "sfdx force:apex:log:list -u $Username --json"
    return Show-SalesforceJsonResult -Result $result
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

    $result = Invoke-Expression2 -Command "sfdx force:apex:log:get -i $LogId -u $Username --json"
    $result = $result | ConvertFrom-Json
    # TODO: Check status
    return $result.result.log
}

function Export-SalesforceLogs {
    [CmdletBinding()]
    Param(        
        [Parameter(Mandatory = $false)][int] $Limit = 50,
        [Parameter(Mandatory = $false)][string] $OutputFolder = $null,
        [Parameter(Mandatory = $true)][string] $Username
    )        
        
    if (($OutputFolder -eq $null) -or ($OutputFolder -eq "") ) {
        $currentFolder = (Get-Location).Path
        $OutputFolder = $currentFolder        
    }
    if ((Test-Path -Path $OutputFolder) -eq $false) { throw "Folder $OutputFolder does not exist" }
    Write-Verbose "Output Folder: $OutputFolder"

    $logs = Get-SalesforceLogs -Username $Username | Sort-Object -Property StartTime -Descending | Select-Object -First $Limit
    if ($null -eq $logs) {
        Write-Verbose "No Logs"
        return
    }

    $logsCount = ($logs | Measure-Object).Count + 1    
    $i = 0
    foreach ($log in $logs) {
        $fileName = $log.Id + ".log"
        $filePath = Join-Path -Path $OutputFolder -ChildPath $fileName
        Write-Verbose "Exporting file: $filePath"
        Get-SalesforceLog -LogId $log.Id -Username $Username | Out-File -FilePath $filePath   

        $percentCompleted = ($i / $logsCount) * 100
        Write-Progress -Activity "Export Salesforce Logs" -Status "Completed $fileName" -PercentComplete $percentCompleted
        $i = $i + 1
    }
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
    $result = Invoke-Expression2 -Command "sfdx force:project:create --projectname $Name --template $Template --json" 
    return Show-SalesforceJsonResult -Result $result
}

function Get-SalesforceMetaTypes {
    [CmdletBinding()]
    Param([Parameter(Mandatory = $true)][string] $Username)     

    $result = Invoke-Expression2 -Command "sfdx force:mdapi:describemetadata -u $username --json"
    $result = $result | ConvertFrom-Json
    $result = $result.result.metadataObjects    
    $result = $result.xmlName | Sort-Object
    return $result
}

function Get-SalesforceCodeCoverage {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][string] $ApexClassOrTrigger = $null,
        [Parameter(Mandatory = $true)][string] $Username
    )    
    $query = "SELECT ApexTestClass.Name, TestMethodName, ApexClassOrTrigger.Name, NumLinesUncovered, NumLinesCovered, Coverage "    
    $query += "FROM ApexCodeCoverage "
    if (($null -ne $ApexClassOrTrigger) -and ($ApexClassOrTrigger -ne '')) {
        Write-Verbose "Filtering"
        $query += "WHERE ApexTestClass.Name = '$ApexClassOrTrigger' "
    }

    $result = Invoke-Expression2 -Command "sfdx force:data:soql:query -q `"$query`" -t -u $Username --json"
    $result = $result | ConvertFrom-Json
    if ($result.status -ne 0) {
        throw ($result.message)
    }
    $result = $result.result.records   
    
    $values = @()
    foreach ($item in $result) {
        $value = New-Object -TypeName PSObject
        $value | Add-Member -MemberType NoteProperty -Name 'ApexTestClass' -Value $item.ApexTestClass.Name
        $value | Add-Member -MemberType NoteProperty -Name 'ApexClassOrTrigger' -Value $item.ApexClassOrTrigger.Name
        $value | Add-Member -MemberType NoteProperty -Name 'TestMethodName' -Value $item.TestMethodName
        $value | Add-Member -MemberType NoteProperty -Name 'NumLinesCovered' -Value $item.NumLinesCovered
        $value | Add-Member -MemberType NoteProperty -Name 'NumLinesUncovered' -Value $item.NumLinesUncovered                
        $value | Add-Member -MemberType NoteProperty -Name 'coveredLines' -Value $item.Coverage.coveredLines
        $value | Add-Member -MemberType NoteProperty -Name 'uncoveredLines' -Value $item.Coverage.uncoveredLines
        $value | Add-Member -MemberType NoteProperty -Name 'namespace' -Value $item.Coverage.namespace
        $values += $value        
    }

    return $values
}

Export-ModuleMember Get-SalesforceDateTime
Export-ModuleMember Connect-Salesforce
Export-ModuleMember Disconnect-Salesforce
Export-ModuleMember Grant-SalesforceJWT
Export-ModuleMember Open-Salesforce
Export-ModuleMember Get-Salesforce
Export-ModuleMember Get-SalesforceScratchOrgs
Export-ModuleMember New-SalesforceScratchOrg
Export-ModuleMember Select-SalesforceObjects
Export-ModuleMember Get-SalesforceLimits
Export-ModuleMember Get-SalesforceDataStorage
Export-ModuleMember Get-SalesforceApiUsage
Export-ModuleMember Describe-SalesforceObjects
Export-ModuleMember Describe-SalesforceObject
Export-ModuleMember Describe-SalesforceFields
Export-ModuleMember Describe-SalesforceCodeTypes
Export-ModuleMember Build-SalesforceQuery
Export-ModuleMember New-SalesforceObject
Export-ModuleMember Set-SalesforceObject
Export-ModuleMember Get-SalesforceRecordType
Export-ModuleMember Pull-SalesforceCode
Export-ModuleMember Push-SalesforceCode
Export-ModuleMember Test-Salesforce
Export-ModuleMember Invoke-SalesforceApexFile
Export-ModuleMember Get-SalesforceAlias
Export-ModuleMember Add-SalesforceAlias
Export-ModuleMember Remove-SalesforceAlias
Export-ModuleMember Get-SalesforcePackage
Export-ModuleMember Watch-SalesforceLogs
Export-ModuleMember Get-SalesforceLogs
Export-ModuleMember Get-SalesforceLog
Export-ModuleMember Export-SalesforceLogs
Export-ModuleMember Convert-SalesforceLog
Export-ModuleMember Out-Notepad
Export-ModuleMember New-SalesforceProject
Export-ModuleMember Get-SalesforceMetaTypes
Export-ModuleMember Get-SalesforceCodeCoverage