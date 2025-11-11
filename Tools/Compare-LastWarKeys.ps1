<#
.SYNOPSIS
  Generates a .reg file containing only the differences between two registry keys.

.PARAMETER KeyPath1
  Path to the first registry key (e.g., HKCU:\Software\FunFly\Last War-Survival Game-Account1)

.PARAMETER KeyPath2
  Path to the second registry key (e.g., HKCU:\Software\FunFly\Last War-Survival Game-Account2)

.PARAMETER OutRegFile
  Output path for the differences .reg file (e.g., C:\Backups\LastWar-Diff.reg)
#>
param(
  [Parameter(Mandatory)][string]$KeyPath1,
  [Parameter(Mandatory)][string]$KeyPath2,
  [Parameter(Mandatory)][string]$OutRegFile
)

# 1. Load the objects from each key (ignoring internal Provider properties)
$props1 = Get-ItemProperty -Path $KeyPath1 | Select-Object -ExcludeProperty PS*, *Path, *InstanceId
$props2 = Get-ItemProperty -Path $KeyPath2 | Select-Object -ExcludeProperty PS*, *Path, *InstanceId

# 2. Build list of all value names
$allNames = ($props1.PSObject.Properties.Name + $props2.PSObject.Properties.Name) | Sort-Object -Unique

# 3. Prepare .reg file header
$header = @(
  "Windows Registry Editor Version 5.00"
  ""
  "[${KeyPath1}]"
)

# 4. For each value, detect differences
$body = foreach($name in $allNames) {
  $has1 = $null -ne $props1.PSObject.Properties[$name]
  $has2 = $null -ne $props2.PSObject.Properties[$name]
  switch ("$has1,$has2") {
    'True,False' {
      # exists in 1, but not in 2 → remove
      "`"$name`"=-"
    }
    'False,True' {
      # exists only in 2 → create/update
      $v = $props2.$name
      if ($v -is [int]) {   "`"$name`"=dword:$('{0:x8}' -f $v)" }
      else {                 "`"$name`"=`"" + ($v -replace '"','\"' ) + "`"" }
    }
    'True,True' {
      # exists in both, but differs?
      if ($props1.$name -ne $props2.$name) {
        $v = $props2.$name
        if ($v -is [int]) { "`"$name`"=dword:$('{0:x8}' -f $v)" }
        else              { "`"$name`"=`"" + ($v -replace '"','\"' ) + "`"" }
      }
    }
  }
}

# 5. Write the .reg file
@($header + $body | Where-Object { $_ }) `
  | Out-File -FilePath $OutRegFile -Encoding Unicode

Write-Host "Differences file created at: $OutRegFile"
