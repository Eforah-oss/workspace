$ErrorActionPreference = "Stop"

function Get-WorkspaceConfigPath {
  [CmdletBinding(PositionalBinding = $false)]
  param([Switch]$AllowMissing = $false)
  $Config = & {
    if ($env:WORKSPACE_CONFIG) {
      $env:WORKSPACE_CONFIG
    } elseif ($env:XDG_CONFIG_HOME) {
      "$env:XDG_CONFIG_HOME/workspace/config"
    } else {
      "$([Environment]::GetFolderPath('ApplicationData'))/workspace/config"
    } }
  if (!$AllowMissing -and !(Test-Path $Config)) {
    throw "No config, add a workspace first"
  }
  $Config
}

function Get-WorkspacePaths {
  $Paths = [System.Collections.Specialized.OrderedDictionary]::new(
    [System.StringComparer]::Ordinal
  )
  if ($null -eq $env:WORKSPACE_REPO_HOME) {
    if ($env:XDG_DATA_HOME) {
      $env:WORKSPACE_REPO_HOME = "$env:XDG_DATA_HOME/workspace"
    } else {
      $env:WORKSPACE_REPO_HOME = `
        "$([Environment]::GetFolderPath('LocalApplicationData'))/workspace"
    }
  }
  switch -Regex -File (Get-WorkspaceConfigPath) {
    "^## ?([^#][^ ]*)( (.*))?$" {
      $Name = $Matches[1]
      if ($Matches[3]) {
        $Path = (
          (
            $Matches[3] | Select-String -AllMatches `
              "([^$]*)(\`$(\{([^}]+)\}|[A-Za-z0-9_]+))?"
          ).Matches `
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
      } else {
        $Path = $Name
      }
      if (!(Split-Path $Path -IsAbsolute)) {
        $Path = Join-Path $env:WORKSPACE_REPO_HOME $Path
      }
      $Paths[$Name] = $Path
    }
  }
  $Paths
}

function Select-Workspaces {
  param([Parameter(Position = 0, Mandatory = $true)] [string]$Selector)
  $Paths = Get-WorkspacePaths
  switch -Regex ($Selector) {
    '^--all$' {
      $Paths.GetEnumerator()
      break
    }
    '^--name=(.*)$' {
      if ($Paths.Contains($Matches[1])) {
        , [PSCustomObject]@{ Name = $Matches[1]; Value = $Paths[$Matches[1]] }
      }
      break
    }
  }
}

function Convert-WorkspaceSelectorArgs {
  param([string[]]$Argv = @())
  if ($null -eq $Argv) {
    $Argv = @()
  }
  if ($Argv.Count -gt 0) {
    switch -Regex ($Argv[0]) {
      '^(--all|--name=.*)$' { break }
      '^--name$' {
        if ($Argv.Count -lt 2) {
          Write-Error "Usage: --name <name>"
          return
        }
        $Argv[1] = "--name=$($Argv[1])"
        $Argv = $Argv[1..($Argv.Count - 1)]
        break
      }
      '^--.*' {
        Write-Error "Error: Invalid workspace selection option: $($Argv[0])"
        return
      }
      '^$' { $Argv[0] = "--all"; break }
      default { $Argv[0] = "--name=$($Argv[0])"; break }
    }
  }
  return , $Argv
}

function Invoke-Args {
  param(
    [Parameter(
      Position = 0,
      Mandatory = $true,
      ValueFromRemainingArguments = $true
    )]
    [object[]]$Argv
  )

  $Arguments = @()
  if ($Argv.Count -gt 1) {
    $Arguments = $Argv[1..($Argv.Count - 1)]
  }

  & $Argv[0] @Arguments
}

function Invoke-ExpressionChecked {
  param([string]$Command)
  if (!($Command)) {
    return
  }
  $ErrorCount = $global:Error.Count
  $global:LASTEXITCODE = 0
  Invoke-Expression -ErrorAction Stop $Command
  if (($global:Error.Count -gt $ErrorCount) -or ($global:LASTEXITCODE -ne 0)) {
    throw [System.Exception]::new()
  }
}

function Get-WorkspaceScript {
  param($Workspace, $Action, $Shell = "powershell", $RemoveWorkspace)
  $CurrentWorkspace = "";
  $CurrentAction = "";
  $CurrentShell = "";
  (& { switch -File (Get-WorkspaceConfigPath) -Regex {
      "^## ?([^#][^ ]*)( (.*))?$" {
        $CurrentWorkspace = $Matches.1
        $CurrentAction = "clone"
        $CurrentShell = ""
      }
      "^### ?([^#].*|)$" { $CurrentAction = $Matches.1 }
      "^#### ?([^#].*|)$" { $CurrentShell = $Matches.1 }
      default {
        if (
          (($Workspace -eq $CurrentWorkspace) -or ($CurrentWorkspace -eq "")) `
            -and (($Action -eq $CurrentAction) -or ($CurrentAction -eq "")) `
            -and (($Shell -eq $CurrentShell) -or ($CurrentShell -eq ""))
        ) { $_ }
      }
    } }) -join "`n"
}

function Add-Workspace {
  param(
    [Parameter(Position = 0, Mandatory = $true)]
    $Url,
    [Parameter(Position = 1)]
    $Workspace = ($Url -replace '.*[:/]([-.\w]+?)(?:\.git)?/?$', '$1')
  )
  if (!($Workspace -match '^[-.\w]+$')) {
    Write-Error "ERROR: Invalid characters in workspace name: $Workspace"
    return
  }
  $ConfigPath = Get-WorkspaceConfigPath -AllowMissing
  if (
    (Test-Path $ConfigPath) `
      -and ((Get-WorkspacePaths).Keys -contains $Workspace)
  ) {
    Write-Error "ERROR: Already added"
    return
  }
  $null = New-Item -ItemType Directory -Force (& {
      $ConfigDir = Split-Path -Parent $ConfigPath
      if (!$ConfigDir) { $ConfigDir = "." }
      $ConfigDir
    })
  & {
    if (Test-Path $ConfigPath) {
      Write-Output ""
    }
    Write-Output "## $Workspace`ngit clone $Url ."
  } | Add-Content $ConfigPath

}

function Sync-Workspace {
  param(
    [Parameter(Position = 0, Mandatory = $true)]
    [ValidateScript( { $_ -in ((Get-WorkspacePaths).Keys) })]
    [ArgumentCompleter(
      {
        param($Command, $Parameter, $WordToComplete)
        ((Get-WorkspacePaths).Keys) -like "$WordToComplete*"
      }
    )]
    $Workspace
  )
  $WorkspacePath = ((Get-WorkspacePaths)[$Workspace])
  if (!(Test-Path -LiteralPath $WorkspacePath -PathType Container)) {
    $null = New-Item -Type Directory -Force $WorkspacePath
    Push-Location -StackName "Workspace" $WorkspacePath
    $Failed = $false
    try {
      Invoke-ExpressionChecked (Get-WorkspaceScript $Workspace clone)
    } catch {
      $Failed = $true
    } finally {
      Pop-Location -StackName "Workspace"
    }
    if ($Failed) {
      Remove-Item -Recurse -Force -LiteralPath $WorkspacePath
      Write-Error "ERROR: Could not initialize $Workspace"
    }
  }
}

function Enter-Workspace {
  param(
    [Parameter(Position = 0)]
    [ValidateScript( { $_ -in ((Get-WorkspacePaths).Keys) })]
    [ArgumentCompleter(
      {
        param($Command, $Parameter, $WordToComplete)
        ((Get-WorkspacePaths).Keys) -like "$WordToComplete*"
      }
    )]
    $Workspace
  )
  $Paths = (Get-WorkspacePaths)
  if (!$Workspace) {
    if (Get-Command -Name Invoke-Fzf -ErrorAction SilentlyContinue) {
      $Workspace = ($Paths.Keys | Invoke-Fzf)
      if (!$Workspace) {
        return
      }
    }
    elseif (Get-Command -Name fzf -ErrorAction SilentlyContinue) {
      $Workspace = ($Paths.Keys | fzf)
      if ($global:LASTEXITCODE -ne 0) {
        return
      }
    }
    else {
      throw "fzf not found. Install it to use the fuzzy finder functionality."
    }
  }
  Sync-Workspace $Workspace
  if (Test-Path $Paths[$Workspace]) {
    Set-Location $Paths[$Workspace]
    try {
      Invoke-ExpressionChecked (Get-WorkspaceScript $Workspace cd)
    } catch { }
  }
}

$script:WorkspaceCommands = @{
  add = {
    param([string[]]$Argv)
    if ($Argv.Count -lt 1) {
      Write-Error "Usage: workspace add <git-url> [name]"
      return
    }
    Add-Workspace @Argv
  }
  sync = {
    param([string[]]$Argv)
    if ($null -eq ($Argv = Convert-WorkspaceSelectorArgs $Argv)) { return }
    Select-Workspaces $(if ($Argv.Count) { $Argv[0] } else { "--all" }) `
    | ForEach-Object { Sync-Workspace $_.Name }
  }
  in = {
    param([string[]]$Argv)
    if ($null -eq ($Argv = Convert-WorkspaceSelectorArgs $Argv)) { return }
    if ($Argv.Count -le 1) {
      Write-Error "Usage: workspace in <selector> [exe...]"
      return
    }
    $Exe = $Argv[1..($Argv.Count - 1)]
    foreach ($Workspace in Select-Workspaces $Argv[0]) {
      Sync-Workspace $Workspace.Name
      Push-Location -StackName "Workspace"
      try {
        Set-Location $Workspace.Value -ErrorAction Stop
        $ErrorCount = $global:Error.Count
        Invoke-Args $Exe
        if (
          ($global:Error.Count -gt $ErrorCount) -or `
          (((Get-Command $Exe[0]).CommandType -eq "Application") -and `
            ($global:LASTEXITCODE -ne 0))
        ) {
          return
        }
      } catch {
        Write-Error $_
        return
      } finally {
        Pop-Location -StackName "Workspace"
      }
    }
  }
  info = {
    param([string[]]$Argv)
    if ($null -eq ($Argv = Convert-WorkspaceSelectorArgs $Argv)) { return }
    Select-Workspaces $(if ($Argv.Count) { $Argv[0] } else { "--all" }) `
    | ForEach-Object { "$($_.Name) $($_.Value)" }
  }
  'script-of' = {
    param([string[]]$Argv)
    Get-WorkspaceScript @Argv
  }
  help = {
    [Console]::Error.WriteLine(@(
        'Usage: workspace <command> [arguments...]'
        ''
        'Manage, initialize and quickly open workspaces.'
        ''
        'Commands:'
        '  add <git-url> [name]       Add new workspace (like `git clone`)'
        '  sync [selector]            Initialize given or all workspaces'
        '  in <selector> [exe...]     Run executable with args in workspaces'
        '  info [selector]            Info for workspaces: "name path\n"'
        '  script-of <name> <action>  Get script for workspace and action'
        ''
        'Selectors are a name of a workspace or ''--all'' for all workspaces'
      ) -join "`n")
  }
}

function workspace {
  [CmdletBinding()]
  param(
    [Parameter(Position = 0)]
    [ValidateScript( { $_ -in $script:WorkspaceCommands.Keys })]
    [ArgumentCompleter({
        param($cmd, $param, $wordToComplete)
        $script:WorkspaceCommands.Keys | Where-Object {
          $_ -like "$wordToComplete*"
        }
      })]
    [string]$Command = "help",

    [Parameter(Position = 1, ValueFromRemainingArguments = $true)]
    [string[]]$Argv
  )
  & $script:WorkspaceCommands[$Command] $Argv
}

Export-ModuleMember workspace
Export-ModuleMember Get-WorkspacePaths
Export-ModuleMember Get-WorkspaceScript
Export-ModuleMember Sync-Workspace
Export-ModuleMember Enter-Workspace
