# OsuTaikoAlign

Please stop scattering the notes all over the place when mapping taiko.

# Usage

1. Open a taiko beatmap in osu editor
2. Click on File > Open .osu in Notepad
3. Select all text in the opened Notepad window and press Ctrl+C
4. Open OsuTaikoAlign
5. Select your desired align method
6. Go back to Notepad, select all and press Ctrl+V
7. Press Ctrl+S
8. Go back to osu, press Ctrl+L
9. Click yes on popup message.

This tool reads the beatmap through your clipboard. This usage method is more convenient than manually browing through your osu song folder and selecting the beatmap you want to modify.

The tool will just fail if it cannot detect osu beatmap data in your clipboard.

# Building

0. Have Odin installed on your system
1. Open terminal at project directory
2. `odin build .`

Note: Windows only

# License

MIT
