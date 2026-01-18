New-Item -ItemType Directory -Path "scripts" -Force

Write-Host "Building..."
c3c.exe build --trust=full

if ($LASTEXITCODE -ne 0) {
    Write-Host "Build failed"
    exit 1
}

$DestPath = "$HOME\c3build"

New-Item -ItemType Directory -Path "$DestPath" -Force
Copy-Item -Path "build/c3build.exe" -Destination "$DestPath\"

$UserPath = [Environment]::GetEnvironmentVariable('PATH', 'User')

if ($UserPath -split ';' -notcontains $DestPath) {
    [Environment]::SetEnvironmentVariable('PATH', "$UserPath;$DestPath", 'User')
	Write-Host "Added $DestPath to PATH"
else
    Write-Host "PATH already contains $DestPath"
}

Write-Host "Installed to $DestPath"

Write-Host "Rebuilding with c3build.exe"
build\c3build.exe install
