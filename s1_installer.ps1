# Configuration Variables
# Replace with the actual Steam App ID for "Schedule I"
$appId = "3164500"  # TODO: Update this with the correct App ID

# GitHub repository URL for the mods
$gitRepoUrl = "https://github.com/NickScheffel/Schedule1Mods.git"

# MelonLoader installer download URL
$melonLoaderUrl = "https://github.com/LavaGang/MelonLoader.Installer/releases/latest/download/MelonLoader.Installer.exe"
$melonInstallerPath = "$env:TEMP\MelonLoader.Installer.exe"

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

# Function to Install Mods Directly into Mods Folder
# Function to Install Mods Directly into Mods Folder
function Install-Mods {
    param ([string]$modsFolder, [string]$gitRepoUrl)
    Write-Host "Info: Synchronizing repository files directly into $modsFolder..."
    $tempDir = New-Item -ItemType Directory -Path ([System.IO.Path]::GetTempPath()) -Name ("git_clone_" + [guid]::NewGuid())
    try {
        # Clone the repository into the temporary directory
        git clone $gitRepoUrl $tempDir 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw "Git clone failed with exit code $LASTEXITCODE"
        }
        # Remove all existing files and subfolders in the Mods folder
        Remove-Item -Path "$modsFolder\*" -Recurse -Force
        # Copy all files and folders (excluding .git) from the temp directory directly into Mods
        Copy-Item -Path "$tempDir\*" -Destination $modsFolder -Recurse -Force -Exclude ".git"
        Write-Host "Success: Repository files synchronized into $modsFolder"
    } catch {
        Write-Host "Error: Failed to clone and synchronize repository. $_"
        Write-Host "Note: Ensure Git is installed and you have internet access."
    } finally {
        # Clean up the temporary directory
        Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# Function to Ensure Git is Installed
function Ensure-GitInstalled {
    if (Get-Command git -ErrorAction SilentlyContinue) {
        Write-Host "Git is already installed."
        return
    }
    Write-Host "Git is not installed. Proceeding to install Git."
    
    try {
        # Fetch the latest Git for Windows release info from GitHub API
        $releaseInfo = Invoke-RestMethod -Uri "https://api.github.com/repos/git-for-windows/git/releases/latest"
        $asset = $releaseInfo.assets | Where-Object { $_.name -like "*-64-bit.exe" } | Select-Object -First 1
        if (-not $asset) {
            throw "Could not find 64-bit installer asset."
        }
        $installerUrl = $asset.browser_download_url
        $installerPath = "$env:TEMP\Git-Installer.exe"
        
        # Download the Git installer
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
            throw "Git installation directory not found."
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
Write-Host "Ensuring Git is installed before proceeding..."
Ensure-GitInstalled

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
        Install-Mods -modsFolder $modsFolder -gitRepoUrl $gitRepoUrl
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
                    Install-Mods -modsFolder $modsFolder -gitRepoUrl $gitRepoUrl
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
    Write-Host "Error: Schedule I is not installed or could not be found."
    Write-Host "Please verify the App ID ($appId) and ensure the game is installed via Steam."
}