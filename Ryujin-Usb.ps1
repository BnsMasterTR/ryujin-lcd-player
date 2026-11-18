$ErrorActionPreference = 'Stop'

function Get-InterfacePath($Device, $Guid) {
    $listing = pnputil /enum-devices /connected /deviceid $Device /interfaces
    $match = [regex]::Match(($listing -join "`n"), '\\\\\?\\\S+#\{' + $Guid + '\}', 'IgnoreCase')
    if (!$match.Success) { throw "Missing interface: $Device" }
    $match.Value
}

Add-Type @"
using System;
using System.IO;
using System.ComponentModel;
using System.Collections.Generic;


using System.Security.Cryptography;
using System.Threading.Tasks;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

public static class RyujinLcd {
    [DllImport("kernel32.dll", EntryPoint="CreateFileW", CharSet=CharSet.Unicode, SetLastError=true)]
    static extern SafeFileHandle CreateFile(string path, uint access, uint share, IntPtr sec, uint mode, uint flags, IntPtr template);
    [DllImport("winusb.dll", SetLastError=true)]
    static extern bool WinUsb_Initialize(SafeFileHandle file, out IntPtr usb);
    [DllImport("winusb.dll")]
    static extern bool WinUsb_Free(IntPtr usb);
    [DllImport("winusb.dll", SetLastError=true)]
    static extern bool WinUsb_SetPipePolicy(IntPtr usb, byte pipe, uint policy, uint length, ref uint value);
    [DllImport("winusb.dll", SetLastError=true)]
    static extern bool WinUsb_WritePipe(IntPtr usb, byte pipe, byte[] data, uint size, out uint written, IntPtr overlapped);

    static SafeFileHandle Open(string path) {
        var handle = CreateFile(path, 0xC0000000, 3, IntPtr.Zero, 3, 0x40000000, IntPtr.Zero);
        if (handle.IsInvalid) throw new Win32Exception(Marshal.GetLastWin32Error(), "Cannot open " + path);
        return handle;
    }

    static void Send(HidConnection hid, params byte[] command) {
        hid.LastCommand = BitConverter.ToString(command);
        var report = new byte[65];
        report[0] = 0xEC;
        Array.Copy(command, 0, report, 1, command.Length);
        var write = hid.Stream.WriteAsync(report, 0, report.Length);
        if (!write.Wait(4000)) throw new TimeoutException("HID write timed out");
    }

    sealed class HidConnection : IDisposable {
        public string LastCommand = "";
        public string LastReceived = "";
        public readonly FileStream Stream;
        public readonly List<byte[]> Inbox = new List<byte[]>();
        public Task<int> Pending;
        public byte[] Buffer;
        public HidConnection(SafeFileHandle file) {
            Stream = new FileStream(file, FileAccess.ReadWrite, 1, true);
        }
        public void Dispose() { Stream.Dispose(); }
    }

    static bool Matches(byte[] report, byte id, byte command, int eventValue, int eventStatus) {
        return report.Length >= 4 && report[0] == id && report[1] == command &&
            (eventValue < 0 || ((eventStatus < 0 || report[2] == eventStatus) && report[3] == eventValue));
    }

    static byte[] WaitFor(HidConnection hid, byte id, byte command, int eventValue = -1, int eventStatus = 0) {
        var deadline = System.Diagnostics.Stopwatch.StartNew();
        while (deadline.ElapsedMilliseconds < 12000) {
            for (int index = 0; index < hid.Inbox.Count; index++) {
                var report = hid.Inbox[index];
                if (Matches(report, id, command, eventValue, eventStatus)) {
                    hid.Inbox.RemoveAt(index);
                    return report;
                }
            }
            if (hid.Pending == null) {
                hid.Buffer = new byte[65];
                hid.Pending = hid.Stream.ReadAsync(hid.Buffer, 0, hid.Buffer.Length);
            }
            if (!hid.Pending.Wait(Math.Max(1, 12000 - (int)deadline.ElapsedMilliseconds))) break;
            int count = hid.Pending.GetAwaiter().GetResult();
            hid.Pending = null;
            if (count == 0) throw new IOException("LCD disconnected.");
            var received = new byte[count];
            Array.Copy(hid.Buffer, received, count);
            hid.LastReceived = BitConverter.ToString(received, 0, Math.Min(received.Length, 12));
            if (received[0] == 0xEC || received[0] == 0xEE) hid.Inbox.Add(received);
            if (hid.Inbox.Count > 128) hid.Inbox.RemoveAt(0);
        }
        throw new TimeoutException(String.Format(
            "LCD timeout waiting for {0:X2} {1:X2}, operation {2:X2}. Last command {3}. Last reply {4}. Close other Ryujin apps and retry.",
            id, command, eventValue, hid.LastCommand, hid.LastReceived));
    }

    static byte[] ReadDisk(HidConnection hid) {
        for (int attempt = 0; attempt < 3; attempt++) {
            try {
                if (attempt == 0) {
                    Command(hid, 0x71, 0x71, 1, 1);
                    WaitFor(hid, 0xEE, 0x12, 0);
                }
                var disk = Command(hid, 0x71, 0xF1);
                if (disk.Length >= 27 && disk[2] == 0 && disk[3] == 1 && disk[22] == 16)
                    return disk;
            } catch (TimeoutException) {
                if (attempt == 2) throw;
            }
            System.Threading.Thread.Sleep(300);
        }
        throw new IOException("The LCD returned an incomplete storage table.");
    }
    static byte[] Command(HidConnection hid, byte reply, params byte[] command) {
        Send(hid, command);
        return WaitFor(hid, 0xEC, reply);
    }

    public sealed class StoredItem {
        public string Kind { get; set; }
        public int Slot { get; set; }
    }

    public sealed class StorageInfo {
        public long TotalBytes { get; set; }
        public long FreeBytes { get; set; }
        public List<StoredItem> Items { get; set; }
    }

    public static StorageInfo ParseStorage(byte[] disk) {
        if (disk.Length < 27 || disk[0] != 0xEC || disk[1] != 0x71 ||
            disk[2] != 0 || disk[3] != 1 || disk[17] != 16 || disk[22] != 16)
            throw new IOException("Invalid LCD storage table.");
        var result = new StorageInfo {
            TotalBytes = 1024L * BitConverter.ToUInt32(disk, 4),
            FreeBytes = 1024L * BitConverter.ToUInt32(disk, 8),
            Items = new List<StoredItem>()
        };
        if (result.FreeBytes > result.TotalBytes) throw new IOException("Invalid LCD storage sizes.");
        uint jpg = BitConverter.ToUInt32(disk, 18);
        uint gif = BitConverter.ToUInt32(disk, 23);
        for (int slot = 0; slot < 16; slot++) {
            if ((gif & (1u << slot)) != 0) result.Items.Add(new StoredItem { Kind = "GIF", Slot = slot });
            if ((jpg & (1u << slot)) != 0) result.Items.Add(new StoredItem { Kind = "JPG", Slot = slot });
        }
        return result;
    }

    public static Task<StorageInfo> StorageAsync(string hidPath) {
        return Task.Run(() => {
            using (var file = Open(hidPath))
            using (var hid = new HidConnection(file)) return ParseStorage(ReadDisk(hid));
        });
    }

    public static Task DeleteAsync(string hidPath, string kind, int[] slots) {
        if (kind != "GIF" && kind != "JPG") throw new ArgumentException("Unknown media kind.");
        foreach (int slot in slots) if (slot < 0 || slot >= 16) throw new ArgumentOutOfRangeException("slots");
        return Task.Run(() => {
            using (var file = Open(hidPath))
            using (var hid = new HidConnection(file)) {
                Command(hid, 0x51, 0x51, 0x21);
                foreach (int slot in slots) {
                    var before = ParseStorage(ReadDisk(hid));
                    if (!before.Items.Exists(item => item.Kind == kind && item.Slot == slot)) continue;
                    Command(hid, 0x72, 0x72, 1, kind == "GIF" ? (byte)2 : (byte)1, (byte)slot);
                    Command(hid, 0x73, 0x73, 3);
                    var response = WaitFor(hid, 0xEE, 0x13, 3, -1);
                    if (response[2] != 0 && response[2] != 0x10)
                        throw new IOException("LCD rejected deletion.");
                    if (ParseStorage(ReadDisk(hid)).Items.Exists(item => item.Kind == kind && item.Slot == slot))
                        throw new IOException("LCD did not confirm deletion of " + kind + " slot " + slot);
                    if (kind == "GIF") SaveSlot("", slot);
                }
            }
        });
    }

    public static Task ShowStoredAsync(string hidPath, string kind, int slot) {
        if (slot < 0 || slot >= 16 || (kind != "GIF" && kind != "JPG"))
            throw new ArgumentException("Invalid LCD item.");
        if (kind == "GIF") return PlayAsync(hidPath, slot);
        return Task.Run(() => {
            using (var file = Open(hidPath))
            using (var hid = new HidConnection(file)) {
                Command(hid, 0x60, 0x60, 0, 1, 0x10, (byte)slot);
                Command(hid, 0x51, 0x51, 0x1F);
            }
        });
    }

    public static Task<int> FindExistingAsync(string hidPath, int preferredSlot, string[] paths) {
        return Task.Run(() => {
            using (var file = Open(hidPath))
            using (var hid = new HidConnection(file)) {
                uint occupied = BitConverter.ToUInt32(ReadDisk(hid), 23);
                foreach (string path in paths) {
                    if (!File.Exists(path)) continue;
                    string hash;
                    using (var sha = SHA256.Create())
                    using (var input = File.OpenRead(path))
                        hash = BitConverter.ToString(sha.ComputeHash(input)).Replace("-", "");
                    int slot = CachedSlot(hash, occupied);
                    if (slot >= 0) return slot;
                }
                if (preferredSlot >= 0 && preferredSlot < 10 && (occupied & (1u << preferredSlot)) != 0)
                    return preferredSlot;
                return -1;
            }
        });
    }

    public static System.Threading.Tasks.Task<int> UploadAsync(string hidPath, string usbPath, byte[] gif) {
        return System.Threading.Tasks.Task.Run(() => Upload(hidPath, usbPath, gif));
    }

    public static System.Threading.Tasks.Task PlayAsync(string hidPath, int slot) {
        return System.Threading.Tasks.Task.Run(() => {
            using (var file = Open(hidPath))
            using (var hid = new HidConnection(file)) {
                Command(hid, 0x5D, 0x5D, 0, 1, 0x10, 1, (byte)slot, 5);
                Command(hid, 0x51, 0x51, 0x10, 1, (byte)slot);
                System.Threading.Thread.Sleep(1500);
                var display = Command(hid, 0x50, 0xD0);
                if (display[5] != 0x10 || display[6] != 1 || display[7] != slot)
                    throw new IOException("LCD did not report the requested GIF slot.");
            }
        });
    }
    static string CachePath {
        get {
            string folder = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "RyujinLCD");
            Directory.CreateDirectory(folder);
            return Path.Combine(folder, "media-slots.tsv");
        }
    }

    static string Hash(byte[] gif) {
        using (var sha = SHA256.Create()) return BitConverter.ToString(sha.ComputeHash(gif)).Replace("-", "");
    }

    static int CachedSlot(string hash, uint occupied) {
        if (!File.Exists(CachePath)) return -1;
        foreach (string line in File.ReadAllLines(CachePath)) {
            string[] fields = line.Split('\t');
            int slot;
            if (fields.Length == 2 && fields[0] == hash && Int32.TryParse(fields[1], out slot) &&
                slot >= 0 && slot < 10 && (occupied & (1u << slot)) != 0) return slot;
        }
        return -1;
    }

    static void SaveSlot(string hash, int slot) {
        var lines = new List<string>();
        if (File.Exists(CachePath)) {
            foreach (string line in File.ReadAllLines(CachePath)) {
                string[] fields = line.Split('\t');
                if (fields.Length == 2 && fields[0] != hash && fields[1] != slot.ToString())
                    lines.Add(line);
            }
        }
        lines.Add(hash + "\t" + slot);
        File.WriteAllLines(CachePath, lines.ToArray());
    }

    static int Upload(string hidPath, string usbPath, byte[] gif) {
        using (var usbFile = Open(usbPath))
        using (var hidFile = Open(hidPath))
        using (var hid = new HidConnection(hidFile)) {
            IntPtr usb;
            if (!WinUsb_Initialize(usbFile, out usb)) throw new Win32Exception(Marshal.GetLastWin32Error());
            try {
                uint timeout = 4000;
                if (!WinUsb_SetPipePolicy(usb, 1, 3, 4, ref timeout))
                    throw new Win32Exception(Marshal.GetLastWin32Error());

                var firmware = Command(hid, 0x02, 0x82);
                var version = System.Text.Encoding.ASCII.GetString(firmware, 3, 24).TrimEnd('\0');
                Console.WriteLine("Firmware: " + version);
                if (version != "AURJ2-S750-0108") throw new IOException("Test protocol was verified only with AURJ2-S750-0108.");

                var disk = ReadDisk(hid);
                if (disk[2] != 0 || disk[3] != 1 || disk[22] != 16)
                    throw new IOException("Unexpected disk table or insufficient space.");
                uint occupied = BitConverter.ToUInt32(disk, 23);
                string hash = Hash(gif);
                int cached = CachedSlot(hash, occupied);
                if (cached >= 0) return cached;
                if (gif.Length < 13) throw new IOException("Invalid GIF file.");
                long needed = (long)gif.Length + 8192;
                long total = 1024L * BitConverter.ToUInt32(disk, 4);
                long free = 1024L * BitConverter.ToUInt32(disk, 8);
                if (needed > total) throw new IOException(String.Format(
                    "Not enough LCD storage: GIF {0:F2} MB, total storage {1:F2} MB.",
                    needed / 1048576.0, total / 1048576.0));

                int slot = 0;
                while (slot < 10 && (occupied & (1u << slot)) != 0) slot++;
                if (needed > free)
                    throw new IOException(String.Format(
                        "Not enough LCD storage: GIF {0:F2} MB, free {1:F2} MB. Open Storage to review and delete old items.",
                        needed / 1048576.0, free / 1048576.0));
                if (slot == 10) throw new IOException("All GIF slots are occupied. Open LCD storage to review and delete selected old items.");
                Command(hid, 0x72, 0x72, 1, 2, (byte)slot);
                Exception uploadFailure = null;
                try {
                    Command(hid, 0x73, 0x73, 1);
                    WaitFor(hid, 0xEE, 0x13, 1);
                    var length = BitConverter.GetBytes(gif.Length);
                    var transfer = gif.Length <= UInt16.MaxValue
                        ? Command(hid, 0x7F, 0x7F, 2, length[0], length[1])
                        : Command(hid, 0x7F, 0x7F, 2, length[0], length[1], length[2], length[3]);
                    if (transfer[2] != 0 || BitConverter.ToUInt16(transfer, 3) != 4096)
                        throw new IOException("Unexpected upload chunk size.");
                    for (int offset = 0; offset < gif.Length; offset += 4096) {
                        var chunk = new byte[4096];
                        Array.Copy(gif, offset, chunk, 0, Math.Min(chunk.Length, gif.Length - offset));
                        uint written;
                        if (!WinUsb_WritePipe(usb, 1, chunk, (uint)chunk.Length, out written, IntPtr.Zero))
                            throw new Win32Exception(Marshal.GetLastWin32Error());
                        if (written != chunk.Length) throw new IOException("Short USB write.");
                        WaitFor(hid, 0xEE, 0x14, 0);
                    }
                } catch (Exception error) {
                    uploadFailure = error;
                    throw;
                } finally {
                    try {
                        Command(hid, 0x73, 0x73, 0xFF);
                        WaitFor(hid, 0xEE, 0x13, 0xFF);
                    } catch {
                        if (uploadFailure == null) throw;
                    }
                }

                try { SaveSlot(hash, slot); } catch (IOException) { } catch (UnauthorizedAccessException) { }
                return slot;
            } finally { WinUsb_Free(usb); }
        }
    }
}
"@










