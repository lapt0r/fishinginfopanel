# FishingInfoPanel Release Shipping Script
# Automates the process of creating a release: version bump, patch notes, commit, tag, and push

param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("patch", "minor", "major")]
    [string]$ReleaseType,
    
    [Parameter(Mandatory=$false)]
    [string]$Description = ""
)

# Function to get current version from patch notes
function Get-CurrentVersion {
    $patchNotes = Get-Content "PATCH_NOTES.md" -Raw
    if ($patchNotes -match '## \[(\d+\.\d+\.\d+)\]') {
        return $matches[1]
    }
    Write-Error "Could not find current version in PATCH_NOTES.md"
    exit 1
}

# Function to increment version based on release type
function Get-NextVersion {
    param([string]$currentVersion, [string]$releaseType)
    
    $parts = $currentVersion -split '\.'
    $major = [int]$parts[0]
    $minor = [int]$parts[1]
    $patch = [int]$parts[2]
    
    switch ($releaseType) {
        "patch" { $patch++ }
        "minor" { $minor++; $patch = 0 }
        "major" { $major++; $minor = 0; $patch = 0 }
    }
    
    return "$major.$minor.$patch"
}

# Function to get today's date
function Get-TodayDate {
    return (Get-Date).ToString("yyyy-MM-dd")
}

# Function to update patch notes
function Update-PatchNotes {
    param([string]$newVersion, [string]$description)
    
    $content = Get-Content "PATCH_NOTES.md" -Raw
    $today = Get-TodayDate
    
    # Determine release type for changelog entry
    $changeType = switch ($ReleaseType) {
        "patch" { "[FIX]" }
        "minor" { "[FEATURE]" }
        "major" { "[BREAKING]" }
    }
    
    # Create new version entry
    $newEntry = @"
## [$newVersion] - $today

### $changeType
- Database versioning system implemented with migration support
$(if ($description) { "- $description" })

"@
    
    # Insert new entry after the title
    $updatedContent = $content -replace '(# Fishing Info Panel - Patch Notes\s*)', "`$1`n$newEntry"
    
    Set-Content "PATCH_NOTES.md" $updatedContent -NoNewline
    Write-Host "[OK] Updated PATCH_NOTES.md with version $newVersion" -ForegroundColor Green
}

# Main shipping process
try {
    Write-Host "[SHIP] Starting release process..." -ForegroundColor Cyan
    
    # Check if we're on main branch
    $currentBranch = git branch --show-current
    if ($currentBranch -ne "main") {
        Write-Error "Must be on main branch to ship. Currently on: $currentBranch"
        exit 1
    }
    
    # Check for uncommitted changes
    $status = git status --porcelain
    if ($status) {
        Write-Error "Working directory has uncommitted changes. Please commit or stash them first."
        exit 1
    }
    
    # Get current and next version
    $currentVersion = Get-CurrentVersion
    $nextVersion = Get-NextVersion $currentVersion $ReleaseType
    
    Write-Host "[VERSION] Bump: $currentVersion -> $nextVersion ($ReleaseType)" -ForegroundColor Yellow
    
    # Update patch notes
    Update-PatchNotes $nextVersion $Description
    
    # Stage patch notes
    git add "PATCH_NOTES.md"
    Write-Host "[OK] Staged PATCH_NOTES.md" -ForegroundColor Green
    
    # Create commit
    $commitMessage = "Version $nextVersion - $ReleaseType release`n`n"
    if ($Description) {
        $commitMessage += "- $Description`n"
    }
    $commitMessage += "- See PATCH_NOTES.md for details`n`n"
    $commitMessage += "🤖 Generated with Claude Code`n`n"
    $commitMessage += "Co-Authored-By: Claude &lt;noreply@anthropic.com&gt;"
    
    git commit -m $commitMessage
    Write-Host "[OK] Created commit for version $nextVersion" -ForegroundColor Green
    
    # Create tag
    git tag -a "v$nextVersion" -m "Version $nextVersion - $ReleaseType release"
    Write-Host "[OK] Created tag v$nextVersion" -ForegroundColor Green
    
    # Push to remote
    git push origin main --tags
    Write-Host "[OK] Pushed to origin with tags" -ForegroundColor Green
    
    Write-Host "[SUCCESS] Release $nextVersion shipped successfully!" -ForegroundColor Green
    Write-Host "[TAG] v$nextVersion" -ForegroundColor Cyan
    Write-Host "[URL] https://github.com/lapt0r/fishinginfopanel/releases/tag/v$nextVersion" -ForegroundColor Cyan
    
} catch {
    Write-Error "[ERROR] Shipping failed: $_"
    exit 1
}