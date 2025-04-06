# Configuration Variables
# Script version for update checking
$scriptVersion = "1.1.0"

# Steam App ID for "Schedule I"
$appId = "3164500"

# GitHub repository URL for the mods
$gitRepoUrl = "https://github.com/NickScheffel/Schedule1Mods.git"

# MelonLoader installer download URL
$melonLoaderUrl = "https://github.com/LavaGang/MelonLoader.Installer/releases/latest/download/MelonLoader.Installer.exe"
$melonInstallerPath = "$env:TEMP\MelonLoader.Installer.exe"

# Script paths
$scriptPath = $MyInvocation.MyCommand.Path
$scriptName = Split-Path $scriptPath -Leaf

# Game executable name (adjust if different)
$gameExeName = "Schedule I.exe"

# Function to Get Steam Library Folders
function Get-SteamLibraryFolders {
    param ([string]$steamPath)
    $libraryFoldersFile = Join-Path $steamPath "steamapps\libraryfolders.vdf"
    if (-not (Test-Path $libraryFoldersFile)) {
        return @($steamPath)
    }
    $content = Get-Content $libraryFoldersFile -Raw
    $folders = @($steamPath)  # Default Steam folder
    $regex = '"\d+"\s+"([^"]+)"'
    $matches = [regex]::Matches($content, $regex)
    foreach ($match in $matches) {
        $folders += $match.Groups[1].Value -replace '\\\\', '\'
    }
    return $folders
}

# Function to Get Game Installation Path
function Get-GameInstallPath {
    param ([string[]]$libraryFolders, [string]$appId)
    foreach ($folder in $libraryFolders) {
        $manifestPath = Join-Path $folder "steamapps\appmanifest_$appId.acf"
        if (Test-Path $manifestPath) {
            $content = Get-Content $manifestPath -Raw
            $regex = '"installdir"\s+"([^"]+)"'
            $match = [regex]::Match($content, $regex)
            if ($match.Success) {
                $installDir = $match.Groups[1].Value
                $gamePath = Join-Path $folder "steamapps\common\$installDir"
                if (Test-Path $gamePath) {
                    return $gamePath
                }
            }
        }
    }
    return $null
}

# Function to Show Folder Selection Dialog
function Show-FolderSelectionDialog {
    Add-Type -AssemblyName System.Windows.Forms
    $folderBrowser = New-Object System.Windows.Forms.FolderBrowserDialog
    $folderBrowser.Description = "Select Schedule I installation folder"
    $folderBrowser.ShowNewFolderButton = $false
    
    if ($folderBrowser.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        return $folderBrowser.SelectedPath
    } else {
        return $null
    }
}

# Function to Install Mods Directly into Mods Folder
function Install-Mods {
    param ([string]$modsFolder, [string]$gitRepoUrl)
    Write-Host "Info: Synchronizing repository files directly into $modsFolder..."
    $tempDir = New-Item -ItemType Directory -Path ([System.IO.Path]::GetTempPath()) -Name ("git_clone_" + [guid]::NewGuid())
    try {
        # Clone the repository into the temporary directory
        $cloneOutput = git clone $gitRepoUrl $tempDir 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "Git clone failed with exit code $LASTEXITCODE. Details: $cloneOutput"
        }
        
        # Check if the repo has a "mods" subfolder
        $repoModsFolder = Join-Path $tempDir "mods"
        $sourceFolder = if (Test-Path $repoModsFolder) { $repoModsFolder } else { $tempDir }
        
        # Create a backup of user's custom mods
        $customModsDir = New-Item -ItemType Directory -Path ([System.IO.Path]::GetTempPath()) -Name ("custom_mods_" + [guid]::NewGuid())
        $repoModsList = @()
        
        # Get list of files from the repository
        Get-ChildItem -Path $sourceFolder -Recurse -File | ForEach-Object {
            $relativePath = $_.FullName.Substring($sourceFolder.Length + 1)
            $repoModsList += $relativePath
        }
        
        # Back up custom mods (files not present in repo)
        Get-ChildItem -Path $modsFolder -Recurse -File | ForEach-Object {
            $relativePath = $_.FullName.Substring($modsFolder.Length + 1)
            if ($repoModsList -notcontains $relativePath) {
                # This is a custom mod - back it up
                $destPath = Join-Path $customModsDir $relativePath
                $destDir = Split-Path -Parent $destPath
                if (-not (Test-Path $destDir)) {
                    New-Item -ItemType Directory -Path $destDir -Force | Out-Null
                }
                Copy-Item -Path $_.FullName -Destination $destPath -Force
                Write-Host "Info: Preserved custom mod: $relativePath"
            }
        }
        
        # Remove all repo-managed files in the Mods folder
        Write-Host "Info: Removing repository-managed mods..."
        foreach ($mod in $repoModsList) {
            $modPath = Join-Path $modsFolder $mod
            if (Test-Path $modPath) {
                Remove-Item -Path $modPath -Force
            }
        }
        
        # Copy all files from the correct source folder into Mods
        Copy-Item -Path "$sourceFolder\*" -Destination $modsFolder -Recurse -Force -Exclude ".git"
        Write-Host "Success: Repository files synchronized into $modsFolder"
        
        # Restore custom mods
        if (Test-Path $customModsDir) {
            Get-ChildItem -Path $customModsDir -Recurse -File | ForEach-Object {
                $relativePath = $_.FullName.Substring($customModsDir.Length + 1)
                $destPath = Join-Path $modsFolder $relativePath
                $destDir = Split-Path -Parent $destPath
                if (-not (Test-Path $destDir)) {
                    New-Item -ItemType Directory -Path $destDir -Force | Out-Null
                }
                Copy-Item -Path $_.FullName -Destination $destPath -Force
            }
            Write-Host "Success: Restored custom mods"
        }
    } catch {
        Write-Host "Error: Failed to clone and synchronize repository. $_" -ForegroundColor Red
        Write-Host "Note: Ensure Git is installed and you have internet access."
        return $false
    } finally {
        # Clean up temporary directories
        Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -Path $customModsDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    return $true
}

# Function to Create Desktop Shortcut
function Create-Shortcut {
    param ([string]$targetPath)
    
    try {
        $desktopPath = [Environment]::GetFolderPath("Desktop")
        $shortcutPath = Join-Path $desktopPath "Schedule I Mod Installer.lnk"
        
        # Check if shortcut already exists
        if (Test-Path $shortcutPath) {
            Write-Host "Shortcut already exists at: $shortcutPath"
            return
        }
        
        $WshShell = New-Object -ComObject WScript.Shell
        $Shortcut = $WshShell.CreateShortcut($shortcutPath)
        $Shortcut.TargetPath = "powershell.exe"
        $Shortcut.Arguments = "-ExecutionPolicy Bypass -File `"$targetPath`""
        $Shortcut.WorkingDirectory = Split-Path $targetPath -Parent
        $Shortcut.IconLocation = "powershell.exe,0"
        $Shortcut.Description = "Run Schedule I Mod Installer"
        $Shortcut.Save()
        
        Write-Host "Shortcut created at: $shortcutPath" -ForegroundColor Green
    } catch {
        Write-Host "Error creating shortcut: $_" -ForegroundColor Red
    }
}

# Function to Check for Script Updates and Self-Update
function Update-Script {
    param ([string]$scriptPath, [string]$repoUrl, [string]$currentVersion)
    
    Write-Host "Checking for script updates from $repoUrl..."
    
    # Create temp directory for repo clone
    $tempDir = New-Item -ItemType Directory -Path ([System.IO.Path]::GetTempPath()) -Name ("update_check_" + [guid]::NewGuid())
    
    try {
        # Verify Git is available
        if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
            Write-Host "Error: Git not found in PATH, cannot check for updates" -ForegroundColor Red
            return $false
        }
        
        # Clone the repository into the temporary directory (depth 1 for speed)
        Write-Host "Cloning repository for update check..." -ForegroundColor Cyan
        $cloneOutput = git clone --depth 1 $repoUrl $tempDir 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Host "Warning: Unable to check for updates. Git clone failed with code $LASTEXITCODE" -ForegroundColor Yellow
            Write-Host "Clone output: $cloneOutput" -ForegroundColor Yellow
            return $false
        }
        
        # Get script name from path
        $scriptName = Split-Path $scriptPath -Leaf
        $repoScriptPath = Join-Path $tempDir $scriptName
        
        # Check if the script exists in the repo
        if (-not (Test-Path $repoScriptPath)) {
            Write-Host "Warning: Script file '$scriptName' not found in repository" -ForegroundColor Yellow
            
            # List files in repo root to help diagnose
            Write-Host "Files found in repository:" -ForegroundColor Yellow
            Get-ChildItem -Path $tempDir -File | ForEach-Object { Write-Host "  - $($_.Name)" }
            return $false
        }
        
        # Compare file hash instead of relying on version patterns
        # This is more reliable for detecting changes
        $localHash = (Get-FileHash -Path $scriptPath -Algorithm SHA256).Hash
        $repoHash = (Get-FileHash -Path $repoScriptPath -Algorithm SHA256).Hash
        
        if ($localHash -ne $repoHash) {
            Write-Host "New version found (files differ)" -ForegroundColor Cyan
            
            # Attempt to extract version from repo script
            $repoScriptContent = Get-Content $repoScriptPath -Raw
            $versionPattern = '\$scriptVersion\s*=\s*"([\d\.]+)"'  
            $versionMatch = [regex]::Match($repoScriptContent, $versionPattern)
            
            $repoVersion = "unknown"
            if ($versionMatch.Success) {
                $repoVersion = $versionMatch.Groups[1].Value
                Write-Host "Repository version: $repoVersion (current: $currentVersion)" -ForegroundColor Cyan
            } else {
                Write-Host "Repository version number not found, but content differs" -ForegroundColor Yellow
            }
            
            # Backup current script
            $backupPath = "$scriptPath.backup"
            Copy-Item -Path $scriptPath -Destination $backupPath -Force
            Write-Host "Backed up current script to: $backupPath"
            
            # Replace current script with new version
            Copy-Item -Path $repoScriptPath -Destination $scriptPath -Force
            Write-Host "Updated script (from repo version $repoVersion)" -ForegroundColor Green
            
            # Restart the script with the new version
            Write-Host "Restarting script with new version..."
            Start-Process powershell.exe -ArgumentList "-ExecutionPolicy Bypass -File `"$scriptPath`"" -NoNewWindow
            exit
        } else {
            Write-Host "Script is up to date (version $currentVersion)" -ForegroundColor Green
            return $true
        }
        
        # Handled in the file hash comparison section above
    } catch {
        Write-Host "Error checking for updates: $_" -ForegroundColor Red
        return $false
    } finally {
        # Clean up temporary directory
        Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# Function to Ensure Git is Installed
function Ensure-GitInstalled {
    if (Get-Command git -ErrorAction SilentlyContinue) {
        $gitVersion = (git --version) 2>&1
        Write-Host "Git is already installed: $gitVersion"
        return
    }
    Write-Host "Git is not installed. Proceeding to install Git."
    
    try {
        # Fetch the latest Git for Windows release info from GitHub API
        Write-Host "Fetching latest Git for Windows release information..."
        $releaseInfo = Invoke-RestMethod -Uri "https://api.github.com/repos/git-for-windows/git/releases/latest"
        $asset = $releaseInfo.assets | Where-Object { $_.name -like "*-64-bit.exe" } | Select-Object -First 1
        if (-not $asset) {
            throw "Could not find 64-bit installer asset."
        }
        $installerUrl = $asset.browser_download_url
        $installerPath = "$env:TEMP\Git-Installer.exe"
        
        # Download the Git installer
        Write-Host "Downloading Git installer from $installerUrl..."
        Invoke-WebRequest -Uri $installerUrl -OutFile $installerPath -UseBasicParsing
        if (-not (Test-Path $installerPath)) {
            throw "Failed to download Git installer."
        }
        
        # Install Git silently
        Write-Host "Installing Git silently..."
        Start-Process -FilePath $installerPath -ArgumentList "/VERYSILENT", "/NORESTART" -Wait
        
        # Add Git to the current session's PATH
        $gitCmdPath = "C:\Program Files\Git\cmd"
        if (Test-Path $gitCmdPath) {
            $env:PATH += ";$gitCmdPath"
            Write-Host "Git installed and added to PATH."
        } else {
            Write-Host "Warning: Expected Git path not found at $gitCmdPath" -ForegroundColor Yellow
            # Try to find Git elsewhere
            $possibleGitPaths = @(
                "C:\Program Files (x86)\Git\cmd",
                "$env:ProgramFiles\Git\cmd",
                "$env:ProgramFiles\Git\bin",
                "$env:ProgramFiles(x86)\Git\cmd",
                "$env:ProgramFiles(x86)\Git\bin"
            )
            
            $gitFound = $false
            foreach ($path in $possibleGitPaths) {
                if (Test-Path $path) {
                    $env:PATH += ";$path"
                    Write-Host "Found Git at $path and added to PATH."
                    $gitFound = $true
                    break
                }
            }
            
            if (-not $gitFound) {
                throw "Git installation directory not found."
            }
        }
        
        # Verify Git is now available
        if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
            throw "Git was installed but is not available in PATH."
        }
        
        # Clean up the installer file
        Remove-Item $installerPath -Force -ErrorAction SilentlyContinue
    } catch {
        Write-Host "Error installing Git: $_"
        exit 1
    }
}

# Main Script Logic
Write-Host "========== Schedule I Mod Installer v$scriptVersion =========="

# First check for script updates
Write-Host "Ensuring Git is installed before proceeding..."
Ensure-GitInstalled

# Check for script updates
Update-Script -scriptPath $scriptPath -repoUrl $gitRepoUrl -currentVersion $scriptVersion

# Step 1: Locate Steam Installation
$steamPath = Get-ItemProperty -Path "HKLM:\SOFTWARE\WOW6432Node\Valve\Steam" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty InstallPath
if (-not $steamPath -or -not (Test-Path $steamPath)) {
    $steamPath = "$Env:ProgramFiles(x86)\Steam"
    Write-Host "Info: Using default Steam path: $steamPath"
}

# Step 2: Get Library Folders and Find Game
$libraryFolders = Get-SteamLibraryFolders -steamPath $steamPath
$scheduleFolder = Get-GameInstallPath -libraryFolders $libraryFolders -appId $appId

if ($scheduleFolder) {
    Write-Host "Success: Schedule I is installed at: $scheduleFolder"

    # Step 3: Define Mods Folder Path
    $modsFolder = Join-Path $scheduleFolder "Mods"

    # Step 4: Check for Mods Folder and Install Mods
    if (Test-Path $modsFolder) {
        $installSuccess = Install-Mods -modsFolder $modsFolder -gitRepoUrl $gitRepoUrl
        if ($installSuccess) {
            Write-Host "Mod installation completed successfully!" -ForegroundColor Green
        } else {
            Write-Host "Mod installation completed with errors." -ForegroundColor Yellow
        }
    } else {
        Write-Host "Info: 'Mods' folder not found. Downloading MelonLoader installer..."
        try {
            Invoke-WebRequest -Uri $melonLoaderUrl -OutFile $melonInstallerPath -UseBasicParsing
            if (Test-Path $melonInstallerPath) {
                Write-Host "Info: MelonLoader installer downloaded to $melonInstallerPath"
                Write-Host "Info: Launching MelonLoader installer. Please select '$gameExeName' when prompted."
                Start-Process $melonInstallerPath -Wait
                Write-Host "Info: MelonLoader installation complete."

                # Check if Mods folder was created
                if (Test-Path $modsFolder) {
                    $installSuccess = Install-Mods -modsFolder $modsFolder -gitRepoUrl $gitRepoUrl
        if ($installSuccess) {
            Write-Host "Mod installation completed successfully!" -ForegroundColor Green
        } else {
            Write-Host "Mod installation completed with errors." -ForegroundColor Yellow
        }
                } else {
                    Write-Host "Error: 'Mods' folder not found after installation."
                    Write-Host "Please ensure you selected the correct executable in MelonLoader."
                }
            } else {
                Write-Host "Error: MelonLoader installer not found at $melonInstallerPath after download."
            }
        } catch {
            Write-Host "Error downloading MelonLoader installer: $_"
            Write-Host "Note: Check your internet connection and try again."
        }
    }
} else {
    Write-Host "Schedule I installation not found automatically." -ForegroundColor Yellow
    Write-Host "Would you like to manually select the installation folder? (Y/N)" -ForegroundColor Cyan
    $response = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    
    if ($response.Character -eq 'Y' -or $response.Character -eq 'y') {
        Write-Host "Opening folder selection dialog..." -ForegroundColor Cyan
        $scheduleFolder = Show-FolderSelectionDialog
        
        if ($scheduleFolder -and (Test-Path $scheduleFolder)) {
            Write-Host "Success: Using manually selected path: $scheduleFolder" -ForegroundColor Green
        } else {
            Write-Host "Error: No valid folder selected." -ForegroundColor Red
            Write-Host "Installation cannot continue."
            
            # Create desktop shortcut anyway
            Create-Shortcut -targetPath $scriptPath
            
            # Show execution summary
            Write-Host "\n========== Summary ==========" -ForegroundColor Cyan
            Write-Host "Script version: $scriptVersion" -ForegroundColor Cyan
            Write-Host "Status: Failed - Game path not found or selected" -ForegroundColor Red
            Write-Host "Execution completed at: $(Get-Date)" -ForegroundColor Cyan
            Write-Host "============================" -ForegroundColor Cyan
            
            # Exit early
            Write-Host "Press any key to exit..." -ForegroundColor Yellow
            $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
            exit
        }
    } else {
        Write-Host "Installation canceled by user." -ForegroundColor Yellow
        
        # Create desktop shortcut anyway
        Create-Shortcut -targetPath $scriptPath
        
        # Show execution summary
        Write-Host "\n========== Summary ==========" -ForegroundColor Cyan
        Write-Host "Script version: $scriptVersion" -ForegroundColor Cyan
        Write-Host "Status: Canceled by user" -ForegroundColor Yellow
        Write-Host "Execution completed at: $(Get-Date)" -ForegroundColor Cyan
        Write-Host "============================" -ForegroundColor Cyan
        
        # Exit early
        Write-Host "Press any key to exit..." -ForegroundColor Yellow
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        exit
    }
}

# Create desktop shortcut
Create-Shortcut -targetPath $scriptPath

# Show execution summary
Write-Host "\n========== Summary ==========" -ForegroundColor Cyan
Write-Host "Script version: $scriptVersion" -ForegroundColor Cyan
if ($installSuccess) {
    Write-Host "Status: Installation Successful" -ForegroundColor Green
} else {
    Write-Host "Status: Installation Completed with errors" -ForegroundColor Yellow
}
Write-Host "Game Location: $scheduleFolder" -ForegroundColor Cyan
Write-Host "Execution completed at: $(Get-Date)" -ForegroundColor Cyan
Write-Host "============================" -ForegroundColor Cyan

# Launch game if installation was successful
if ($installSuccess -and (Test-Path $scheduleFolder)) {
    $gamePath = Join-Path $scheduleFolder $gameExeName
    if (Test-Path $gamePath) {
        Write-Host "Launching Schedule I..." -ForegroundColor Cyan
        Start-Process $gamePath
        Write-Host "Game launched successfully!" -ForegroundColor Green
    } else {
        Write-Host "Game executable not found at: $gamePath" -ForegroundColor Yellow
    }
}

# Keep console window open to see results
Write-Host "Press any key to exit..." -ForegroundColor Yellow
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")