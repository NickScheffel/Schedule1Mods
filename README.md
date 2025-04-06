# Schedule I Mod Manager Script

This PowerShell script simplifies mod management for the game "Schedule I" by automating the installation and updating of mods from a GitHub repository. It ensures your "Mods" folder stays in sync with the repository, eliminating the need for manual downloads and updates.

## Features

- **Automatic Game Detection**: Finds the "Schedule I" installation path using its Steam App ID.
- **MelonLoader Setup**: Checks for MelonLoader (required for mods). If missing, it downloads and runs the installer.
- **Mod Synchronization**: Clones a specified GitHub repository and keeps the "Mods" folder identical to its contents.
- **Error Handling**: Displays helpful messages if something goes wrong, like missing game files or Git issues.

## Prerequisites

- **Schedule I**: Must be installed through Steam.
- **Git**: Required for cloning the mod repository. The script installs it if it’s not already on your system.

## How It Works

1. **Finds the Game**: Locates "Schedule I" using its Steam App ID.
2. **Verifies MelonLoader**: Looks for the "Mods" folder. If it’s not there, it installs MelonLoader automatically.
3. **Syncs Mods**: Downloads the mod repository from GitHub and updates the "Mods" folder to match it exactly, adding new files, overwriting old ones, and removing extras.

## Usage

1. **Run the Script**: Open PowerShell and execute the script.
2. **Follow Any Prompts**: If MelonLoader needs installing, the script will guide you through it.
3. **Done!**: Your mods will be installed and updated automatically.

**Important**: Close "Schedule I" before running the script to prevent file conflicts.

## Troubleshooting

- **"Game Not Found" Error**: Ensure "Schedule I" is installed via Steam and the App ID is correct.
- **Git Problems**: Check your internet connection and confirm Git is installed.
- **MelonLoader Issues**: When prompted, select the right game executable during installation.

If you run into problems, check the script’s error messages or reach out to the repository maintainer for help.
