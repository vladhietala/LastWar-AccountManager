<#
.SYNOPSIS
  Gera um .reg contendo apenas as diferenças entre duas chaves de registro.

.PARAMETER KeyPath1
  Caminho da primeira chave (ex: HKCU:\Software\FirstFun\Last War-Survival Game-Conta1)

.PARAMETER KeyPath2
  Caminho da segunda chave (ex: HKCU:\Software\FirstFun\Last War-Survival Game-Conta2)

.PARAMETER OutRegFile
  Caminho de saída do .reg de diferenças (ex: C:\Backups\LastWar-Diff.reg)
#>
param(
  [Parameter(Mandatory)][string]$KeyPath1,
  [Parameter(Mandatory)][string]$KeyPath2,
  [Parameter(Mandatory)][string]$OutRegFile
)

# 1. Carrega os objetos de cada key (ignorando propriedades internas do Provider)
$props1 = Get-ItemProperty -Path $KeyPath1 | Select-Object -ExcludeProperty PS*, *Path, *InstanceId
$props2 = Get-ItemProperty -Path $KeyPath2 | Select-Object -ExcludeProperty PS*, *Path, *InstanceId

# 2. Constrói lista de todos os nomes de valores
$allNames = ($props1.PSObject.Properties.Name + $props2.PSObject.Properties.Name) | Sort-Object -Unique

# 3. Prepara header do .reg
$header = @(
  "Windows Registry Editor Version 5.00"
  ""
  "[${KeyPath1}]"
)

# 4. Para cada valor, detecta diferença
$body = foreach($name in $allNames) {
  $has1 = $null -ne $props1.PSObject.Properties[$name]
  $has2 = $null -ne $props2.PSObject.Properties[$name]
  switch ("$has1,$has2") {
    'True,False' {
      # existe em 1, mas não em 2 → remover
      "`"$name`"=-"
    }
    'False,True' {
      # existe só na 2 → criar/atualizar
      $v = $props2.$name
      if ($v -is [int]) {   "`"$name`"=dword:$('{0:x8}' -f $v)" }
      else {                 "`"$name`"=`"" + ($v -replace '"','\"' ) + "`"" }
    }
    'True,True' {
      # existe em ambas, mas difere?
      if ($props1.$name -ne $props2.$name) {
        $v = $props2.$name
        if ($v -is [int]) { "`"$name`"=dword:$('{0:x8}' -f $v)" }
        else              { "`"$name`"=`"" + ($v -replace '"','\"' ) + "`"" }
      }
    }
  }
}

# 5. Grava o .reg
@($header + $body | Where-Object { $_ }) `
  | Out-File -FilePath $OutRegFile -Encoding Unicode

Write-Host "Arquivo de diferenças criado em: $OutRegFile"
