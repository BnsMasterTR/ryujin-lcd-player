# Ryujin LCD Player

An unofficial Windows beta for the ASUS ROG Ryujin III 360 LCD.

Choose MP4 videos or animated GIFs, adjust the framing, and play a rotating list on the cooler's display. Videos are converted to GIF on the PC using FFmpeg and uploaded to the cooler.

## Download and run

1. Download **Ryujin-LCD-Player.exe** from the [Releases page](https://github.com/BnsMasterTR/ryujin-lcd-player/releases).
2. Install FFmpeg with `winget install --id Gyan.FFmpeg -e`. Alternatively, place `ffmpeg.exe` and `ffprobe.exe` beside the player executable.
3. Launch the player and accept its Windows administrator prompt.
4. Select **Add MP4 / GIF**, choose a file, and select **Upload & play**.

Windows x64, Windows PowerShell 5.1, .NET Framework 4.x, FFmpeg, and FFprobe are required. The executable is unsigned. The C# launcher embeds the PowerShell application and extracts its scripts to a temporary directory while running.

## Playback and framing

- Add multiple MP4/GIF files and arrange them with **Up / Down**.
- **Upload & play** starts the selected item. Playback continues through the list and repeats.
- **Stop rotation** stops switching items. The currently selected animation remains on the cooler.
- **Fit** preserves the whole image with padding.
- **Fill** fills the screen with cropping. Use **Horizontal / Vertical** to position the selected clip. **Center** resets its position.
- **Stretch** resizes the picture to the screen's proportions.

The application prepares the full clip duration at 320 x 240. Conversion starts at 10 FPS with a 64-color palette and may reduce frame rate and palette size to fit available storage. GIF playback has no audio. Memory capacity and file complexity can prevent a long clip from fitting.

The GIF preview currently shows a still frame. MP4 preview uses Windows media codecs, so a file can fail to preview even when FFmpeg can convert it.

## LCD storage

Open **LCD storage...** to read total/free storage and occupied GIF/JPG slots. Select an item and use **Show on LCD** to identify it. Ctrl-click selects multiple items for **Delete selected...**.

Deletion requires confirmation and permanently removes the selected files from the cooler. The protocol used here cannot download stored files for backup. Names come from local upload records. Older files may appear as unknown entries. Slot numbers start at zero.

The application checks its local records and previously prepared GIF variants before uploading again. Different crops and framing settings produce different animations. Changes made by another application can invalidate local records. Use **Refresh** to check occupied slots.

## Live system monitor

Use **Add system monitor** to insert a live monitoring page into the playlist, select the measurements, then press **Upload & play**. **Monitor seconds** controls how long the page stays visible before the next playlist item. A playlist containing only the monitor keeps it active.

- Windows supplies CPU and RAM usage.
- GPU 3D usage is read from available Windows performance counters.
- CPU/GPU temperatures require a running LibreHardwareMonitor or OpenHardwareMonitor WMI provider. Unavailable readings show **N/A**. Temperature entries show the maximum matching CPU/GPU sensor reading.

The default **Graphic monitor background with live values** option uses colored static frames and live numbers. Small labels and units are drawn into the JPEG to accommodate the LCD's fixed text size. Sensor updates replace only the short numeric values. Each measurement preset has its own small reusable JPEG background and uses one JPG slot when first loaded. The colored rings are decorative frames. A plain three-line monitoring mode is also available by disabling this option.

Updates are scheduled approximately every two seconds after the previous sensor/LCD operation finishes. The application must remain running for live updates.

Number positions account for digit count. If the LCD font spacing needs calibration, adjust **LCD digit width** and the **CPU position / GPU position** sliders while watching the display. Changes apply on the next sensor update and are saved locally. The window title identifies this development build as v17.

## Keep the playlist after restarting Windows

The playlist, crop settings, prepared GIFs, and upload records are stored under `%LOCALAPPDATA%\RyujinLCD`.

Enable **Start playlist when I sign in to Windows** to register a per-user Task Scheduler task. It starts the player with elevated privileges about 20 seconds after sign-in. Keep the executable and original media files at their saved locations. Disable the checkbox to remove the startup task.

Closing the window during playback minimizes the player to the system tray. Use the tray menu's **Exit** to quit. The application must remain running to rotate multiple items. A stored GIF can continue looping on the cooler after the player exits.

## Hardware and beta status

The current compatibility target is the standard ASUS ROG Ryujin III 360. The [compatibility reference](COMPATIBILITY.md) lists the shared USB product identifiers and protocol firmware requirements used by the application. Compatibility with White, EVA, Extreme and other variants has not been established.

Upload and playback were exercised on the development device. UI actions, framing calculations, persistence, storage-table parsing, selected HID response variants, native Windows sensor sampling, and monitoring packet construction received local checks. The latest graphical text placement, storage-management flow and Windows restart/startup flow still need end-to-end hardware validation.

Close the Armoury Crate Ryujin device page and other Ryujin-control applications if HID replies time out. Include the full error text, USB ID, firmware, and steps when reporting an issue. Review screenshots for personal information before posting them.

## Build from source

Run the following from the repository directory on Windows.

```powershell
powershell.exe -NoProfile -ExecutionPolicy RemoteSigned -File .\build.ps1
```

The executable is written to `dist\Ryujin-LCD-Player.exe`. FFmpeg is installed separately.

The source entry points are `Launcher.cs`, `Ryujin-Player.ps1`, `Ryujin-Storage.ps1`, `Ryujin-Sensors.ps1`, and `Ryujin-Usb.ps1`. `Ryujin-Dashboard.jpg` is the graphic monitor background. `app.manifest` requests administrator privileges for USB access.

## Credits and license

Protocol research and hardware observations were informed by [zaclanzon's ryujin-iii-lcd-linux project](https://github.com/zaclanzon/ryujin-iii-lcd-linux) and its [protocol documentation](https://github.com/zaclanzon/ryujin-iii-lcd-linux/blob/main/docs/protocol.md).

FFmpeg is a separate dependency with its own [licensing terms](https://ffmpeg.org/legal.html). ASUS and ROG are trademarks of their respective owners. This project is community software and is unaffiliated with ASUS.

MIT License. See [LICENSE](LICENSE).

## Turkce kisa kullanim

Releases bolumunden EXE'yi indir, FFmpeg'i kur ve uygulamayi yonetici olarak ac. **Add MP4 / GIF** ile dosya ekle, listeden sec ve **Upload & play** dugmesine bas. **Fill** modundaki kaydiricilarla kadraji ayarlayabilirsin.

**LCD storage...** cihazdaki dolu yuvalari ve bos alani gosterir. Eski dosyalari LCD'de goruntuleyerek tanimlayabilir, onay vererek silebilirsin. Silme kalicidir. Windows girisinde devam etmek icin acilis kutusunu isaretle. Bu surum betadir.

**Add system monitor** ile canli izleme ekleyebilirsin. Grafik arka plan secenegi renkli sabit cerceveler ve canli degerler kullanir. CPU/GPU sicakliklari icin WMI sensor saglayicisi gerekir. Okunamayan degerler N/A gorunur.
