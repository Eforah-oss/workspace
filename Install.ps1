$ModuleRoot = "$(
  if ($PSVersionTable.Platform -eq "Windows") {
    "$([Environment]::GetFolderPath("MyDocuments"))/PowerShell"
  }
  else {
    "$([Environment]::GetFolderPath('LocalApplicationData'))/powershell"
  }
)/Modules"

if (!(Test-Path "$ModuleRoot/Workspace")) {
  New-Item -Type Directory "$ModuleRoot/Workspace" 1>$null
}
Copy-Item Workspace.psm1 "$ModuleRoot/Workspace/Workspace.psm1"
