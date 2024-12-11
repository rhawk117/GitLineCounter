param(
    [Parameter(Mandatory = $false)]
    [switch]$help,

    [Parameter(Mandatory = $false)]
    [string]$a,

    [Parameter(Mandatory = $false)]
    [string]$path,

    [Parameter(Mandatory = $false)]
    [string]$program_path,

    [Parameter(Mandatory = $false)]
    [switch]$Verbose
)

function Show-Help {
    Write-Host "Man I love git measuring with my friends!"
    Write-Host "Usage:"
    Write-Host "  -help"
    Write-Host "      Display this help message."
    Write-Host
    Write-Host "  -program_path <Directory>"
    Write-Host "      Adds the specified directory to the PATH environment variable."
    Write-Host
    Write-Host "  -a <Author> -path <GitRepositoryPath> [-Verbose]"
    Write-Host "      Counts the total lines added and removed by the specified author."
    Write-Host "      If -Verbose is used, also shows average insertions/deletions per commit and the ratio."
    Write-Host
    Write-Host "Example Usage:"
    Write-Host "  .\git-measuring.ps1 -help"
    Write-Host "  .\git-measuring.ps1 -a 'Freak Bob' -path 'C:\Projects\MyApp'"
    Write-Host "  .\git-measuring.ps1 -a 'Freak Bob' -path 'C:\Projects\MyApp' -Verbose"
    Write-Host "  .\git-measuring.ps1 -program_path 'C:\MyTools'"
}

function Set-ProgramPath($ProgramPath) {
    if (-not (Test-Path $ProgramPath)) {
        Write-Error "The specified directory '$ProgramPath' does not exist."
        exit 1
    }
    $currentPath = [System.Environment]::GetEnvironmentVariable('Path', 'User')
    if ($currentPath -notlike "*$ProgramPath*") {
        $newPath = "$currentPath;$ProgramPath"
        [System.Environment]::SetEnvironmentVariable('Path', $newPath, 'User')
        Write-Host "'$ProgramPath' has been added to your PATH."
        Write-Host "You may need to restart your terminal/session for changes to take effect."
    }
    else {
        Write-Host "'$ProgramPath' is already in your PATH."
    }
}

function Get-AllAuthorStats($ProjectPath) {
    if (-not (Test-Path $ProjectPath)) {
        Write-Error "The specified path '$ProjectPath' does not exist."
        exit 1
    }

    Push-Location $ProjectPath
    if (-not (Test-Path ".git")) {
        Pop-Location
        Write-Error "The specified directory '$ProjectPath' is not a Git repository."
        exit 1
    }

    $logOutput = git log --pretty=tformat:"---commit---`n%aN" --numstat

    Pop-Location

    if (-not $logOutput) {
        return @{}
    }

    # { AuthorName => {Added, Deleted, Commits} }
    $authorData = [ordered]@{}

    $currentAuthor = $null
    $inCommit = $false

    foreach ($line in $logOutput) {
        if ($line -eq "---commit---") {
            $inCommit = $true
            continue
        }

        if ($inCommit) {
            $currentAuthor = $line
            if (-not $authorData.ContainsKey($currentAuthor)) {
                $authorData[$currentAuthor] = [ordered]@{
                    Added   = 0
                    Deleted = 0
                    Commits = 0
                }
            }
            $authorData[$currentAuthor].Commits += 1
            $inCommit = $false
            continue
        }
        $fields = $line -split "`t"
        if ($fields.Count -eq 3) {
            $add = [int]$fields[0]
            $del = [int]$fields[1]

            $authorData[$currentAuthor].Added += $add
            $authorData[$currentAuthor].Deleted += $del
        }
    }
    return $authorData
}

function Get-LinesCountForAuthor($Author, $ProjectPath) {
    $data = Get-AllAuthorStats $ProjectPath
    if ($data.ContainsKey($Author)) {
        $res = $data[$Author]
        return [pscustomobject]@{
            Author       = $Author
            Path         = $ProjectPath
            Added        = $res.Added
            Deleted      = $res.Deleted
            Net          = $res.Added - $res.Deleted
            Commits      = $res.Commits
            FoundContrib = $true
            AllAuthors   = $data
        }
    }
    return [pscustomobject]@{
        Author       = $Author
        Path         = $ProjectPath
        Added        = 0
        Deleted      = 0
        Net          = 0
        Commits      = 0
        FoundContrib = $false
        AllAuthors   = @{}
    }
}

function Get-AuthorRank($Author, $AllAuthors) {
    $ranking = $AllAuthors.GetEnumerator() | ForEach-Object {
        [pscustomobject]@{
            Author = $_.Key
            Net    = $_.Value.Added - $_.Value.Deleted
        }
    } | Sort-Object Net -Descending

    $i = 1
    foreach ($r in $ranking) {
        if ($r.Author -eq $Author) {
            return $i
        }
        $i++
    }
    return $null
}

function Show-Output($Result, $VerboseMode) {
    if (-not $Result.FoundContrib) {
        Write-Host "No contributions found for '$($Result.Author)' in '$($Result.Path)'."
        return
    }

    Write-Host "a:                    $($Result.Author)"
    Write-Host "path:                 $($Result.Path)"
    Write-Host "Total lines added:    $($Result.Added)"
    Write-Host "Total lines deleted:  $($Result.Deleted)"
    Write-Host "Net contribution:     $($Result.Net)"

    if ($VerboseMode -and $Result.Commits -gt 0) {
        $avgAdd = [math]::Round($Result.Added / $Result.Commits, 2)
        $avgDel = [math]::Round($Result.Deleted / $Result.Commits, 2)
        $ratio = if ($Result.Deleted -eq 0) { "N/A" } else { [math]::Round($Result.Added / $Result.Deleted, 2) }

        Write-Host "Commits by author:    $($Result.Commits)"
        Write-Host "Avg insertions/commit:$avgAdd"
        Write-Host "Avg deletions/commit: $avgDel"
        Write-Host "Ratio (Lines:Del):    $ratio"
    }

    if ($null -ne $rank) {
        Write-Host "[Ranking] (by net contribution) - $rank"
    }
    else {
        Write-Host "Author rank could not be determined."
    }
}

if ($help) {
    Show-Help
    exit 0
}

if ($program_path) {
    Set-ProgramPath $program_path
    exit 0
}

if ($a -and $path) {
    $result = Get-LinesCountForAuthor -Author $a -ProjectPath $path
    Show-Output $result $Verbose
    exit 0
}

Show-Help
exit 0
