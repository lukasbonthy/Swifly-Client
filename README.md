# Swifly Client ☄️

A custom Call of Duty: Black Ops III client project branded for **Swifly**.

---

## Quick Start

```bat
git clone --recurse-submodules https://github.com/lukasbonthy/Swifly-Client.git
cd Swifly-Client
generate.bat
```

Then open the generated Visual Studio solution and build the `client` project in `Release x64`.

---

## Client Download

Releases for Swifly Client should be published from this repository when builds are ready.

---

## Features

- Multiplayer and zombies support
- Server browser support
- Dedicated server launching support
- Custom maps and mods support
- Steam Workshop-related client tools where available
- Swifly-branded splash, watermark, metadata, and console text

---

## Command Line Arguments

| Argument | Description |
|:--|:--|
| `-dedicated` | Launch as a dedicated server |
| `-nointro` | Skip intro videos |
| `-console` | Enable developer console |
| `-port XXXX` | Set server port |
| `-noupdate` | Disable automatic updates |
| `-nobranding` | Disable Swifly watermark and console prefix |
| `-headless` | Run without normal UI |

Example:

```bat
boiii.exe -console -nointro
```

---

## Dedicated Server Notes

For a basic server:

1. Put the built client files into the Black Ops III folder or server folder you are using.
2. Configure the server cfg files.
3. Allow the server port through Windows Firewall.
4. Launch with:

```bat
boiii.exe -dedicated
```

Default server port is usually `27017` unless changed.

---

## Zombies Map Names

Common zombies map IDs:

- `zm_zod` - Shadows of Evil
- `zm_factory` - The Giant
- `zm_castle` - Der Eisendrache
- `zm_island` - Zetsubou No Shima
- `zm_stalingrad` - Gorod Krovi
- `zm_genesis` - Revelations

---

## Branding

This fork is branded as **Swifly Client**.

Visible labels should use:

- `Swifly`
- `Swifly Client`
- `Swifly Updater`
- `Swifly>` for console prefix text

Avoid using old Ezz branding in this fork.
