#!/usr/bin/env pwsh

$ModuleRoot = "$(
  if (([System.Environment]::OSVersion.Platform -eq "Win32NT") `
        -or ($PSVersionTable.Platform -eq "Windows")) {
    "$([Environment]::GetFolderPath("MyDocuments"))/WindowsPowerShell"
  }
  elseif ($env:XDG_DATA_HOME) {
    "$env:XDG_DATA_HOME/powershell"
  }
  else {
    "$([Environment]::GetFolderPath('LocalApplicationData'))/powershell"
  }
)/Modules"

New-Item -Type Directory -Force "$ModuleRoot/Workspace" 1>$null
Copy-Item Workspace.psm1 "$ModuleRoot/Workspace/Workspace.psm1"
