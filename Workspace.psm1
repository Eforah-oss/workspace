function Get-WorkspaceConfig {
  $config = & {
    if ($env:WORKSPACE_CONFIG) {
      $env:WORKSPACE_CONFIG
    }
    else {
      "$([Environment]::GetFolderPath('ApplicationData'))/workspace/config"
    } }
  if (!(Test-Path $config)) {
    throw "No config, add a workspace first"
  }
  Get-Content $config
}

function Get-Workspaces {
  Get-WorkspaceConfig `
  | Select-String '^## ?([^#][^ ]*)' `
  | ForEach-Object { $_.Matches.Groups[1].Value }
}

function Get-WorkspacePath {
  param($Workspace)
  if ($null -eq $env:WORKSPACE_REPO_HOME) {
    $env:WORKSPACE_REPO_HOME = `
      "$([Environment]::GetFolderPath('LocalApplicationData'))/workspace"
  }
  Get-WorkspaceConfig `
  | Select-String "^## ?($Workspace)( (.*))?$" `
  | ForEach-Object { if ($_.Matches.Groups[3].Value) {
      (($_.Matches.Groups[3].Value | Select-String -AllMatches `
          "([^$]*)(\`$(\{([^}]+)\}|[A-Za-z0-9_]+))?").Matches `
      | ForEach-Object {
        if ($_.Groups[2].Value) {
          [System.Environment]::GetEnvironmentVariable((& {
                if ($_.Groups[4].Value) {
                  $_.Groups[4].Value
                }
                else {
                  $_.Groups[3].Value
                } }))
        }
        elseif ($_.Groups[1].Length -gt 0) {
          $_.Groups[1].Value
        }
      }) -join ""
    }
    else {
      $_.Matches.Groups[1].Value
    } } `
  | ForEach-Object {
    if (!(Split-Path $_ -IsAbsolute)) {
      Join-Path $env:WORKSPACE_REPO_HOME $_
    }
    else { $_ }
  }
}

function Get-WorkspaceScript {
  param($Workspace, $Action)
  $currentWorkspace = $Workspace;
  $currentAction = $Action;
  $currentShell = "powershell";
  (Get-WorkspaceConfig | ForEach-Object {
    switch -Regex ($_) {
      "^## ?([^#][^ ]*)( (.*))?$" {
        if ($Matches[1].Length -gt 0) { $currentWorkspace = $Matches.1 }
        else { $currentWorkspace = $Workspace }
        $currentAction = "clone"
        $currentShell = "powershell"
      }
      "^### ?([^#].*|)$" { $currentAction = $Matches.1 }
      "^#### ?([^#].*|)$" {
        if ($Matches[1].Length -gt 0) { $currentShell = $Matches.1 }
        else { $currentShell = "powershell" }
      }
      default {
        if ($currentWorkspace -eq $Workspace `
            -and $currentAction -eq $Action `
            -and $currentShell -eq "powershell")
        { $_ }
      }
    }
  }) -join "`n"
}

function Enter-Workspace {
  param(
    [Parameter(Position = 0)]
    [ValidateScript( { $_ -in (Get-Workspaces) })]
    [ArgumentCompleter(
      {
        param($cmd, $param, $wordToComplete)
        [array] $validValues = (Get-Workspaces)
        $validValues -like "$wordToComplete*"
      }
    )]
    $Workspace
  )
  if (!$Workspace) {
    $Workspace = (Get-Workspaces | Invoke-Fzf)
  }

  $WorkspacePath = (Get-WorkspacePath $Workspace)
  if (!$(Test-Path $WorkspacePath)) {
    New-Item -Type Directory $WorkspacePath 1>$null
    Set-Location $WorkspacePath
    Invoke-Expression (Get-WorkspaceScript $Workspace clone)

    if (([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
      $parentAcl = Get-Acl (Get-Item (Split-Path $WorkspacePath -Parent))
      Set-Acl -Path $WorkspacePath -AclObject $parentAcl
      Get-ChildItem $WorkspacePath -Recurse -Force | `
        ForEach-Object { Set-Acl -Path $_.FullName -AclObject $parentAcl }
    }
  }
  else {
    Set-Location $WorkspacePath
  }

  if (Get-WorkspaceScript $Workspace cd) {
    Invoke-Expression (Get-WorkspaceScript $Workspace cd)
  }
}

Export-ModuleMember Get-Workspaces
Export-ModuleMember Get-WorkspacePath
Export-ModuleMember Get-WorkspaceScript
Export-ModuleMember Enter-Workspace
