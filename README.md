# Easy Robocopy interface - ERi-Backup-App · v1.7.1.1

A lightweight, modern Windows backup utility built with PowerShell and WinForms, powered by Microsoft's robust Robocopy engine.

## What it does

- Mirrors a source folder to a destination folder using Robocopy (`/MIR`), keeping the destination in perfect sync with the source — or copies a single file to a destination folder when running in file mode
- Runs the backup fully asynchronously — the UI stays responsive even when copying to slow or removable drives (USB sticks, external HDDs)
- Displays live Robocopy output in real time while the backup is running
- Optionally performs a SHA256 checksum verification after each backup to confirm every file was copied correctly (also runs in the background)
- Optionally wipes the destination folder or destination file before copying for a clean-slate backup
- Writes a detailed log file for every backup run, plus a separate checksum report when verification is enabled

## Additional features

- **Source mode toggle** — switch between folder mode (📁 `/MIR` sync) and single-file mode (📄) directly in the UI; the mode is reflected on the button label and persisted in profiles
- **Smart delete options** — three pre-backup delete options, context-aware per mode:
  - *Delete destination folder* — available in both modes; if checked in file mode, the single-file delete option is automatically disabled
  - *Delete destination file* — available in file mode only; grayed out in folder mode
- **Live path reachability check** — each configured path shows a color-coded indicator (● green = reachable, ● orange = not reachable); the *Start Backup* button is automatically disabled when any path is unreachable
- **Write-access test for source folder** — beyond checking existence, the app writes and immediately deletes a small test file to verify the source folder is truly accessible (e.g. detects encrypted/locked cloud folders that appear reachable but are not yet decrypted)
- **Split status bar** — general backup messages on the left, path status summary on the right, always visible at a glance
- **Settings dialog (⚙)** — configure language and default log path in one place; tooltip shows the dialog name in the active language
  - **Default LogFile Path** — optionally pre-fill the log folder path automatically on every app start and reset; toggle ON/OFF with a single checkbox
- **Profile filenames with mode prefix** — saved profiles are automatically prefixed with `Folder_` or `File_` based on the active source mode
- **Clean startup** — source and destination paths are always empty on launch; paths are only loaded via named profiles, avoiding stale or incorrect path combinations
- Save and load named backup profiles (source, destination, log folder, source mode, options) as `.ini` files — ideal for managing multiple backup jobs
- Full multi-language UI — English, German, French, Spanish and Italian, switchable at runtime via the ⚙ button
- Clean dark-themed interface with High-DPI support, works correctly on 4K and scaled displays
- Packages into a standalone `.exe` via PowerShell Studio — no installation required
