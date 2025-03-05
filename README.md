# OsuTaikoAlign

Stop scattering the notes all over the place when mapping taiko.

# Usage

https://github.com/user-attachments/assets/fe154608-0f6b-4c27-8dd7-a7594d92e037

1. Open taiko beatmap in editor
2. Click on `File` > `Open .osu in Notepad`
3. Click on Notepad, press Ctrl+A, Ctrl+C
4. Open OsuTaikoAlign
5. Select your desired align method
6. Go back to Notepad, press Ctrl+A, Ctrl+V, Ctrl+S
7. Go back to osu, press Ctrl+L
8. Click yes on popup message.

This tool reads the beatmap through your clipboard. This usage method is more convenient than manually browsing through your osu song folder and selecting the beatmap you want to modify.

The tool will just fail if it cannot detect beatmap data in your clipboard.

# Building

0. Have Odin installed on your system
1. Open terminal at project directory
2. `odin build .`

Note: Windows only

# License

MIT
