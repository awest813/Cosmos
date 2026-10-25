# SimCity 3000 Unlimited: installer to game EXE

The workflow is ready for an installer EXE you already have. The installer and
game have not been run in this Linux workspace; gameplay remains untested.
Like Ports, this guided flow targets Apple Silicon and macOS 14.6 or later.

PR CI produces a `cosmos-arm64-preview` artifact containing an ad-hoc signed
Cosmos app. This is a development preview; public-release notarization and real
SimCity gameplay remain unverified. Wine downloads during normal first setup.

## In Cosmos

1. Open **Tools → Add Non-Steam Games → Install Classic Game**. Use Advanced to
   show Tools. Steam setup is optional.
2. Choose the installer EXE and enter **SimCity 3000 Unlimited** as the title.
3. Terminal opens. Choose a folder for the installed game. The workflow prints
   its Windows destination: a `C:` path inside the environment, or `Z:` for an
   external Mac folder.
4. Select that same destination in the Windows installer, leave its Launch Game
   option unchecked if offered, finish setup, and close it. Keep companion setup
   `.bin` files beside the installer if present.
5. Choose the installed game EXE. It is often `Apps/SC3U.exe`; confirm the actual
   filename for your edition. Select the game rather than setup/uninstall.
6. Cosmos detects its architecture, creates a port, and launches that game EXE.
   Use the Ports tab to launch it again later.

The dedicated environment is `game-simcity-3000-unlimited`: WoW64 for 32-bit
programs, Windows 10 as the initial installation baseline, Retina off, and
WineD3D. This baseline does not need Spock, DXMT, CNC-DDRAW, or D3DMetal. Do not
force `WINEARCH=win32` on a WoW64-only runtime.

The installer stays interactive because its type/release is not identified.
Cosmos assumes no unattended destination flags and does not move installed files
after setup. Choose the same folder in both the Mac chooser and installer.

## Terminal

Prepare only the environment definition and default folder, without running an
EXE or downloading Wine:

```bash
./scripts/install_program.command prepare --name "SimCity 3000 Unlimited"
```

Run the guided installation:

```bash
./scripts/install_program.command install "/path/to/setup_simcity.exe" \
  --name "SimCity 3000 Unlimited"
```

Optionally add `--install-dir "/path/to/SimCity 3000 Unlimited"`, or use
`--install-dir "drive_c/Games/simcity-3000-unlimited"` for the environment's C: drive.

If setup completed but game selection was interrupted, resume without reinstalling:

```bash
./scripts/install_program.command resume --name "SimCity 3000 Unlimited" \
  --install-dir "drive_c/Games/simcity-3000-unlimited" \
  --game-exe "drive_c/Games/simcity-3000-unlimited/Apps/SC3U.exe"
```

Use your actual folder and EXE. Add `--no-launch` to only register, or `--make-app`
to create a Mac app in `~/Applications/Cosmos Ports` too. Existing ports are
preserved; open one with `./port.command launch simcity-3000-unlimited`.

Confirm the menu, opening/creating a city, save/load, exit, and relaunch before
calling it playable. A successful launch handoff does not confirm gameplay.
