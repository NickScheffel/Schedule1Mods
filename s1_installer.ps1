# Configuration Variables
# Script version for update checking
$scriptVersion = "1.2.1"

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

# Function to search for game on all drives
function Find-GameOnAllDrives {
    param ([string]$gameExeName)
    
    Write-Host "Searching for $gameExeName on all available drives. This may take a moment..." -ForegroundColor Yellow
    
    # Get all available drives
    $drives = Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Free -gt 0 }
    
    # Common game installation paths to check on each drive
    $commonPaths = @(
        "\Games",
        "\Program Files\Steam\steamapps\common",
        "\Program Files (x86)\Steam\steamapps\common",
        "\SteamLibrary\steamapps\common",
        "\Steam\steamapps\common",
        "\Epic Games",
        "\GOG Games"
    )
    
    foreach ($drive in $drives) {
        Write-Host "Checking drive $($drive.Root)..." -ForegroundColor Cyan
        
        # First check root directories with "Schedule" in the name
        $rootDirs = Get-ChildItem -Path $drive.Root -Directory -ErrorAction SilentlyContinue |
                    Where-Object { $_.Name -like "*Schedule*" }
        
        foreach ($dir in $rootDirs) {
            # Recursively search for the game executable (limiting depth to prevent excessive searching)
            $gamePaths = Get-ChildItem -Path $dir.FullName -Filter $gameExeName -Recurse -Depth 3 -ErrorAction SilentlyContinue
            if ($gamePaths) {
                $gamePath = $gamePaths[0].DirectoryName
                Write-Host "Found game at: $gamePath" -ForegroundColor Green
                return $gamePath
            }
        }
        
        # Next, check common installation paths
        foreach ($path in $commonPaths) {
            $fullPath = $drive.Root + $path.TrimStart('\')
            if (Test-Path $fullPath) {
                # Look for Schedule I specific folders
                $scheduleFolders = Get-ChildItem -Path $fullPath -Directory -ErrorAction SilentlyContinue |
                                  Where-Object { $_.Name -like "*Schedule*" }
                
                foreach ($folder in $scheduleFolders) {
                    if (Test-Path (Join-Path $folder.FullName $gameExeName)) {
                        Write-Host "Found game at: $($folder.FullName)" -ForegroundColor Green
                        return $folder.FullName
                    }
                }
                
                # Direct search for the executable (in case the folder name doesn't contain "Schedule")
                $gamePaths = Get-ChildItem -Path $fullPath -Filter $gameExeName -Recurse -Depth 2 -ErrorAction SilentlyContinue
                if ($gamePaths) {
                    $gamePath = $gamePaths[0].DirectoryName
                    Write-Host "Found game at: $gamePath" -ForegroundColor Green
                    return $gamePath
                }
            }
        }
    }
    
    Write-Host "Game not found on any drive." -ForegroundColor Yellow
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
        
        # Clear the existing Mods folder before copying
        Write-Host "Clearing existing Mods folder: $modsFolder" -ForegroundColor Yellow
        Get-ChildItem -Path $modsFolder -Recurse | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        
        # Copy files from repository into the mods folder (excluding .git)
        Copy-Item -Path "$sourceFolder\*" -Destination $modsFolder -Recurse -Force -Exclude ".git"
        Write-Host "Success: Repository files synchronized into $modsFolder"
    } catch {
        Write-Host "Error: Failed to clone and synchronize repository. $_" -ForegroundColor Red
        Write-Host "Note: Ensure Git is installed and you have internet access."
        return $false
    } finally {
        # Clean up temporary directories
        Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    return $true
}

# Function to Create Desktop Shortcut
function Create-Shortcut {
    param ([string]$targetPath)
    
    try {
        $desktopPath = [Environment]::GetFolderPath("Desktop")
        $shortcutPath = Join-Path $desktopPath "Schedule I Mod Installer.lnk"
        
        $WshShell = New-Object -ComObject WScript.Shell
        $Shortcut = $WshShell.CreateShortcut($shortcutPath)
        $Shortcut.TargetPath = $targetPath
        $Shortcut.Description = "Update mods for Schedule I"
        $Shortcut.WorkingDirectory = Split-Path $targetPath -Parent
        $Shortcut.IconLocation = "powershell.exe,0"
        $Shortcut.Save()
        
        # Verify shortcut was created
        if (-not (Test-Path $shortcutPath)) {
            throw "Shortcut not created: $shortcutPath"
        }
        
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
        
        # Attempt to clone the repository
        git clone $repoUrl $tempDir 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Host "Error: Failed to clone repository for update check" -ForegroundColor Red
            return $false
        }
        
        # Find the script file in the cloned repository
        $scriptName = Split-Path $scriptPath -Leaf
        $repoScriptPath = Join-Path $tempDir $scriptName
        
        if (-not (Test-Path $repoScriptPath)) {
            Write-Host "Error: Could not find script in the repository" -ForegroundColor Red
            Write-Host "Contents of repository:"
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
            $versionMatch = [regex]::Match($repoScriptContent, '\$scriptVersion\s*=\s*"([\d\.]+)"')
            $repoVersion = if ($versionMatch.Success) { $versionMatch.Groups[1].Value } else { "unknown" }
            
            # Make backup of the current script
            $backupPath = "$scriptPath.backup"
            Write-Host "Backing up current script to $backupPath"
            Copy-Item -Path $scriptPath -Destination $backupPath -Force
            
            # Replace the script with the repository version
            Write-Host "Replacing script with version from repository"
            Copy-Item -Path $repoScriptPath -Destination $scriptPath -Force
            
            # Verify update was successful
            if (-not (Test-Path $scriptPath)) {
                Write-Host "Error: Failed to update script, restoring backup" -ForegroundColor Red
                Copy-Item -Path $backupPath -Destination $scriptPath -Force
                return $false
            }
            
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

# Function to ensure Git is installed
function Ensure-GitInstalled {
    if (Get-Command git -ErrorAction SilentlyContinue) {
        Write-Host "Git is already installed and available in PATH." -ForegroundColor Green
        return
    }
    
    Write-Host "Git is not found in PATH. Checking if Git is installed elsewhere..." -ForegroundColor Yellow
    
    # Common installation locations
    $commonPaths = @(
        "${env:ProgramFiles}\Git\bin\git.exe",
        "${env:ProgramFiles(x86)}\Git\bin\git.exe",
        "$env:LOCALAPPDATA\Programs\Git\bin\git.exe"
    )
    
    $gitFound = $false
    foreach ($path in $commonPaths) {
        if (Test-Path $path) {
            Write-Host "Git found at: $path" -ForegroundColor Green
            # Add git directory to PATH for this session
            $gitDir = Split-Path -Parent $path
            $env:Path += ";$gitDir"
            $gitFound = $true
            break
        }
    }
    
    if ($gitFound) {
        Write-Host "Added Git to PATH for this session." -ForegroundColor Green
        return
    }
    
    # Git not found, download and install
    Write-Host "Git not found. Downloading and installing Git..." -ForegroundColor Yellow
    
    # Download latest Git for Windows installer
    $installerUrl = "https://github.com/git-for-windows/git/releases/download/v2.41.0.windows.1/Git-2.41.0-64-bit.exe"
    $installerPath = "$env:TEMP\GitInstaller.exe"
    
    try {
        Invoke-WebRequest -Uri $installerUrl -OutFile $installerPath -UseBasicParsing
        Write-Host "Git installer downloaded successfully." -ForegroundColor Green
        
        # Run the installer
        Write-Host "Running Git installer... (this may take a few minutes)"
        Start-Process -FilePath $installerPath -ArgumentList "/VERYSILENT /NORESTART /NOCANCEL /SP- /CLOSEAPPLICATIONS /RESTARTAPPLICATIONS /o:AddGitToPath=true" -Wait
        
        # Verify installation
        if (Get-Command git -ErrorAction SilentlyContinue) {
            Write-Host "Git installed successfully!" -ForegroundColor Green
            return
        }
        
        # If git command still not available, refresh PATH
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
        
        if (Get-Command git -ErrorAction SilentlyContinue) {
            Write-Host "Git installed successfully (PATH refreshed)!" -ForegroundColor Green
            return
        }
        
        throw "Git was installed but is not available in PATH."
        
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
} else {
    Write-Host "Schedule I installation not found in Steam library folders." -ForegroundColor Yellow
    Write-Host "Searching other locations..." -ForegroundColor Cyan
    
    # Try to find the game on all drives
    $scheduleFolder = Find-GameOnAllDrives -gameExeName $gameExeName
    
    if (-not $scheduleFolder) {
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
    } else {
        Write-Host "Success: Schedule I is installed at: $scheduleFolder" -ForegroundColor Green
    }
}

# Step 3: Define Mods Folder Path
$modsFolder = Join-Path $scheduleFolder "Mods"

# Step 4: Check for Mods Folder and Install Mods
$installSuccess = $false
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

# Create desktop shortcut
Create-Shortcut -targetPath $scriptPath

# Show execution summary
Write-Host "`n========== Summary ==========" -ForegroundColor Cyan
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
