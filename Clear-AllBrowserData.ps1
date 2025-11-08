<# 
   Script: Clear-AllBrowserData.ps1
   Purpose: Deletes all browser history, cache, cookies, and bookmarks 
            for Edge, Chrome, and Firefox on Windows.
   Run: Open PowerShell as Administrator and paste this in.
#>

Write-Host "Closing all browsers..." -ForegroundColor Yellow
Get-Process "msedge","chrome","firefox" -ErrorAction SilentlyContinue | Stop-Process -Force

# Edge cleanup
$edgePaths = @(
    "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default",
    "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Profile*"
)
foreach ($path in $edgePaths) {
    if (Test-Path $path) {
        Write-Host "Cleaning Microsoft Edge at $path"
        Remove-Item "$path\History*" -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item "$path\Cookies*" -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item "$path\Cache*" -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item "$path\Bookmarks*" -Force -ErrorAction SilentlyContinue
        Remove-Item "$path\Favicons*" -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# Chrome cleanup
$chromePaths = @(
    "$env:LOCALAPPDATA\Google\Chrome\User Data\Default",
    "$env:LOCALAPPDATA\Google\Chrome\User Data\Profile*"
)
foreach ($path in $chromePaths) {
    if (Test-Path $path) {
        Write-Host "Cleaning Google Chrome at $path"
        Remove-Item "$path\History*" -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item "$path\Cookies*" -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item "$path\Cache*" -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item "$path\Bookmarks*" -Force -ErrorAction SilentlyContinue
        Remove-Item "$path\Favicons*" -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# Firefox cleanup
$firefoxProfiles = Get-ChildItem "$env:APPDATA\Mozilla\Firefox\Profiles" -Directory -ErrorAction SilentlyContinue
foreach ($profile in $firefoxProfiles) {
    Write-Host "Cleaning Firefox profile: $($profile.FullName)"
    Remove-Item "$($profile.FullName)\places.sqlite" -Force -ErrorAction SilentlyContinue  # history & bookmarks
    Remove-Item "$($profile.FullName)\favicons.sqlite" -Force -ErrorAction SilentlyContinue
    Remove-Item "$($profile.FullName)\cookies.sqlite" -Force -ErrorAction SilentlyContinue
    Remove-Item "$($profile.FullName)\cache2" -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "`n✅ All browser history, cookies, cache, and bookmarks have been deleted." -ForegroundColor Green
Write-Host "Restart your browsers to confirm cleanup." -ForegroundColor Cyan
