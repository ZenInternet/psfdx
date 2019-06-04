# psfdx
PowerShell module that wraps Salesforce SFDX command line interface
# Installation
```
git clone https://github.com/ZenInternet/psfdx
cd psfdx
.\Install-psfdx.ps1
```
# Examples
1. Connect to a Salesforce Sandbox Org
```
Import-Module psfdx
Connect-Salesforce -IsSandbox
```
A web browser will appear, login to Salesforce as you would normally.
This uses Salesforce's standard authentication which encrypts and stores the credentials locally.
Other psfdx commands require a username - typically email address or alias - to use the local encrypted authentication details

2. Retrieve first 10 Salesforce Accounts
```
Import-Module psfdx
Select-SalesforceObjects -Query "SELECT Id,Name FROM Account LIMIT 10" -Username my@email.com
```
NB you only need to Import-Module psfdx once per PowerShell session

3. Create and use a Salesforce Alias
```
Add-SalesforceAlias -Username my@email.com -Alias myalias
```

4. Retrieve every psfdx cmdlet
```
Get-Command -Module psfdx
```