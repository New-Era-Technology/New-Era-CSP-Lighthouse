<#
Execute:

.\Deploy-Lighthouse-Bulk.ps1 `
   -ContinueOnError

.\Deploy-Lighthouse-Bulk.ps1 `
  -WhatIf
  
#>

<#
.SYNOPSIS
  Bulk-deploys an Azure Lighthouse subscription-scope ARM template to many subscriptions.

.DESCRIPTION
  For each subscription ID selected from user selectable popup:
    - Selects the subscription (in the specified customer tenant)
    - Ensures Microsoft.ManagedServices provider is registered
    - Runs New-AzSubscriptionDeployment with the given template
    - Logs outcome to a CSV summary

.PARAMETER Location
  Any Azure region; required for subscription-scope deployments (default: eastus)

.PARAMETER OutputCsv
  Optional: path for results CSV; default auto-generates with timestamp

.PARAMETER ContinueOnError
  Continue processing remaining subscriptions after an error

.EXAMPLE
  .\Deploy-Lighthouse-Bulk.ps1

.EXAMPLE
  .\Deploy-Lighthouse-Bulk.ps1 `
    -ContinueOnError

.EXAMPLE
  .\Deploy-Lighthouse-Bulk.ps1 `
    -WhatIf
#>

#Requires -Version 7.1

[CmdletBinding(SupportsShouldProcess = $true, PositionalBinding = $false)]
param(
  [Parameter()][string]$Location = "eastus",
  [Parameter()][string]$OutputCsv,
  [switch]$ContinueOnError
)

# setup session for required modules
	# Check if Az module is installed
	Write-Host "Checking for required Azure modules.  Installing if needed."
	if (-not (Get-InstalledModule -Name Az -ErrorAction SilentlyContinue)) {
		Write-Host "Az module not found. Installing Az module..."
		Install-Module -Name Az -Repository PSGallery -Force
	} else {
		Write-Host "Az module is already installed."
	}

	# Check if Az.Accounts module is installed
	if (-not (Get-InstalledModule -Name Az.Accounts -ErrorAction SilentlyContinue)) {
		Write-Host "Az.Accounts module not found. Installing Az.Accounts..."
		Install-Module -Name Az.Accounts -Repository PSGallery -Force
	} else {
		Write-Host "Az.Accounts module is already installed."
	}

	# Check if Az.Resources module is installed
	if (-not (Get-InstalledModule -Name Az.Resources -ErrorAction SilentlyContinue)) {
		Write-Host "Az.Resources module not found. Installing Az.Resources..."
		Install-Module -Name Az.Resources -Repository PSGallery -Force
	} else {
		Write-Host "Az.Resources module is already installed."
	}

	# Check if Az.Accounts module is loaded
	if (-not (Get-Module -Name Az.Accounts)) {
		Write-Host "Importing Az.Accounts module..."
		Import-Module Az.Accounts
	} else {
		Write-Host "Az.Accounts module is already loaded."
	}

	# Check if Az.Resources module is loaded
	if (-not (Get-Module -Name Az.Resources)) {
		Write-Host "Importing Az.Resources module..."
		Import-Module Az.Resources
	} else {
		Write-Host "Az.Resources module is already loaded."
	}


# ---- Helper: Ensure provider registration in the current subscription ----
function Ensure-ManagedServicesProvider {
  param([switch]$Simulate)
  $rp = Get-AzResourceProvider -ProviderNamespace Microsoft.ManagedServices -ErrorAction Stop
  if ($rp.RegistrationState -eq "Registered") {
    return $true
  }

  if ($Simulate) {
    Write-Host "     [WhatIf] Would register provider: Microsoft.ManagedServices" -ForegroundColor DarkYellow
    return $true
  }

  Write-Host "     Registering provider: Microsoft.ManagedServices ..." -ForegroundColor Yellow
  Register-AzResourceProvider -ProviderNamespace Microsoft.ManagedServices -ErrorAction Stop | Out-Null

  # Wait until registration shows as Registered (up to ~2 minutes)
  $deadline = (Get-Date).AddMinutes(2)
  do {
    Start-Sleep -Seconds 5
    $rp = Get-AzResourceProvider -ProviderNamespace Microsoft.ManagedServices -ErrorAction Stop
    Write-Host "       Status: $($rp.RegistrationState)"
  } while ($rp.RegistrationState -ne "Registered" -and (Get-Date) -lt $deadline)

  return ($rp.RegistrationState -eq "Registered")
}

# ---- MAIN ----

# Set the Output CSV file name to default or input paramater
if (-not $OutputCsv) {
  $stamp = Get-Date -Format "yyyyMMddHHmmss"
  $OutputCsv = Join-Path -Path (Get-Location) -ChildPath "Lighthouse_Deployment_Results_$stamp.csv"
}


# Get and verify the JSON and Auth data 
try {
  $jsonPath = 'https://github.com/New-Era-Technology/New-Era-CSP-Lighthouse/blob/54461f6de47ed4a275b819220093b04968c537cf/NET-CSP-Lighthouse.json'
  $templateJson = (New-Object System.Net.WebClient).DownloadString($jsonPath) | ConvertFrom-Json  -AsHashtable
	
  $managedByTenantId = ""
  $managedByTenantId = (Invoke-RestMethod -UseBasicParsing -Uri "https://odc.officeapps.live.com/odc/v2.1/federationprovider?domain=newerauscsp.com" | select tenantId)

  if ($managedByTenantId.tenantId) {
	$templateJson.variables.managedByTenantId = $managedByTenantId.TenantID
	$auths = $templateJson.variables.authorizations
  } else {
	Write-Warning "Could not locate necessary parameters. Please contact New Era CSP support"
	exit
  }
  if ($auths) {
    Write-Host "==> Authorizations in template:" -ForegroundColor Yellow
    $auths | ForEach-Object {
      "    {0} -> Role {1}  (PrincipalId: {2})" -f $_.principalIdDisplayName,$_.roleDefinitionId,$_.principalId
    } | Write-Host
  }
} catch {
  Write-Warning "Could not parse template JSON for preview. Proceeding..."
}

######    Start action items   ######

# Connect to tenant with at least contributor rights 
Write-Host "==> Connecting to customer tenant ..." -ForegroundColor Cyan
Connect-AzAccount -ErrorAction Stop | Out-Null

# Get all subscriptions from the tenant
$AllSubs = Get-AzSubscription
$SelectedSubs = @()

if ($AllSubs.count -gt 0){
	$SelectedSubs = $AllSubs | Out-GridView -Title "Select Subscriptions" -PassThru
	} else {
	Write-Warning "No subscriptions found"
	exit
	}

# User to select which subscriptions to apply template to
if ($SelectedSubs.count -eq 0){
	Write-Warning "No subscriptions selected"
	exit
	}
	
$results = New-Object System.Collections.Generic.List[object]
$globalStatus = "Success"

Write-Host "`n==> Starting deployments to $($SelectedSubs.Count) subscription(s)..." -ForegroundColor Cyan

# looping through the Subscriptions 
foreach ($subId in $SelectedSubs) {
  
  Write-Host "`n--- Subscription: $subId ---" -ForegroundColor Magenta
  $row = [ordered]@{
    Timestamp          = (Get-Date).ToString("s")
    SubscriptionId     = $subId.Id
    DeploymentName     = $null
    ProvisioningState  = $null
    ManagedByTenantId  = $managedByTenantId.TenantID
    Status             = "Pending"
    Message            = $null
  }

  try {
	Select-AzSubscription -SubscriptionId $subId.Id -ErrorAction Stop | Out-Null
    $providerOk = Ensure-ManagedServicesProvider -Simulate:$WhatIf
    if (-not $providerOk) {
      throw "Provider registration failed or timed out."
    }

    $short = $subId.Id.Substring(0,8)
    $deploymentName = "lighthouse-$short-$(Get-Date -Format 'yyyyMMddHHmmss')"
    $row.DeploymentName = $deploymentName

    $deployParams = @{
      Name         = $deploymentName
      Location     = $Location
	  TemplateObject = $templateJson
      Verbose      = $true
      ErrorAction  = 'Stop'
    }
    if ($paramObject.Count -gt 0) { $deployParams.TemplateParameterObject = $paramObject }
    if ($WhatIf)                  { $deployParams.WhatIf = $true }

    Write-Host "     Deploying at subscription scope as '$deploymentName' in $Location ..." -ForegroundColor Cyan
	$result = New-AzSubscriptionDeployment @deployParams

    # When -WhatIf, $result may be $null; otherwise query status
    if ($WhatIf) {
      $row.ProvisioningState = "WhatIf"
      $row.Status = "Simulated"
      $row.Message = "No changes applied (WhatIf)."
    } else {
      $state = $result.ProvisioningState
      $row.ProvisioningState = $state
	  $row.Status = $state
      $row.Message = "Deployment completed with state: $state"
    }

    # Optional: show current registrationAssignments
    Write-Host "     Current registration assignments:" -ForegroundColor DarkCyan
    Get-AzResource -ResourceType "Microsoft.ManagedServices/registrationAssignments" -ExpandProperties -ErrorAction SilentlyContinue |
      Select-Object Name,
        @{n="Scope";e={$_.ResourceId}},
        @{n="Offer";e={$_.Properties.RegistrationDefinition.Properties.DisplayName}},
        @{n="ManagedByTenantId";e={$_.Properties.RegistrationDefinition.Properties.ManagedByTenantId}} |
      Format-Table -AutoSize

  } catch {
    $row.Status = "Failed"
    $row.Message = $_.Exception.Message
    $globalStatus = "Failed"
    Write-Error "     ERROR: $($row.Message)"

    if (-not $ContinueOnError) {
      $results.Add([pscustomobject]$row) | Out-Null
      break
    }
  }

  $results.Add([pscustomobject]$row) | Out-Null
}

# Export summary
$results | Export-Csv -LiteralPath $OutputCsv -NoTypeInformation
Write-Host "`n==> Summary written to: $OutputCsv" -ForegroundColor Green
Write-Host "==> Overall status: $globalStatus" -ForegroundColor Green