# 🎛️ REAPER QuickStemmer

**QuickStemmer** is a REAPER Lua script with a GUI that exports stems from your project while preserving and rebuilding the folder hierarchy. It's a fast and organized way to prep stems for delivery, collaboration, or archival.

---

## 🚀 Features

- 📁 Automatically renames tracks with structured numeric prefixes
- 🎙️ Optionally includes muted tracks in the export
- 🧼 Restores original track names after export
- 📤 Renders selected tracks to individual `.wav` files
- 📦 Re-imports rendered stems into a new project, preserving the folder structure
- 🧹 Can remove numeric prefixes from filenames after export
- 📂 Opens the export folder in your system's file browser

---

## 🛠️ Requirements

- REAPER (v6.0+ recommended)
- SWS Extensions (optional but useful for general REAPER scripting)
- [ReaImGui](https://github.com/cfillion/reaimgui) (for the GUI interface)

---

## 📦 Installation

1. Save the script as `quickstemmer.lua` inside your REAPER scripts directory.
2. Make sure ReaImGui is installed.
3. Open REAPER and run the script from the Action List or bind it to a toolbar button.

---

## 🎛️ How It Works

1. **Preparation**:  
   - Scans tracks, skipping muted ones (unless enabled).
   - Applies a hierarchical numeric prefix based on REAPER's folder structure (e.g., `01-02__Guitar`).
   - Selects only tracks that contain media items.

2. **Render Phase**:  
   - Renders each selected track as a separate `.wav` file using REAPER's render settings.
   - Saves stems in a timestamped folder (e.g., `/YourProject/Stems/2025-04-17_13-45-00/`).

3. **Import Phase**:  
   - Creates a new project and imports stems.
   - Reconstructs folders using the numeric prefix hierarchy.
   - Optionally allows you to remove those prefixes later.

---

## 🧪 UI Preview

