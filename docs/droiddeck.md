# DroidDeck on Android

NeoStation offers **Standalone DroidDeck** for the **Steam** and **Windows**
systems. This integration targets the standard DroidDeck package,
`com.droiddeck.launcher`.

This personal build downloads system updates from
`aaron4567891-prog/neostation-frontend` on `logo-list-personal`. Local JSON changes
must be committed and pushed there before installed builds can download them.
Changing the updater's source itself requires a new APK; a systems-only update
cannot change the updater code in an APK already installed on a device.

1. Install and set up [DroidDeck](https://github.com/Droid-Deck/DroidDeck),
   then install the games you want to launch in it.
2. Export the game's launch file from DroidDeck into the ROM folder you use
   for Steam or Windows in NeoStation. Current DroidDeck builds export `.steam`
   files; older `.droiddeck` launch files are also supported. These small text
   files contain the game's numeric Steam or added-game shortcut ID.
3. Scan that folder in NeoStation and select **Standalone DroidDeck** as the
   system's emulator, or as that game's emulator override.
4. Launch the game from NeoStation. DroidDeck receives the launch file, checks
   that the game is in its library, and starts or resumes its Steam session.

These launch files refer to games already installed in DroidDeck. Selecting
DroidDeck does not make it open arbitrary `.exe` files or other emulators'
shortcut files. Android folder-picker URIs are passed directly with read
permission; NeoStation does not copy the installed PC game.

The configuration uses DroidDeck's exported `MainActivity` with
`android.intent.action.VIEW`. The source contract is in
[`GameFiles.kt`](https://github.com/Droid-Deck/DroidDeck/blob/main/app/src/main/java/com/droiddeck/launcher/frontend/GameFiles.kt).
