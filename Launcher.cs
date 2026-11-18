using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Threading.Tasks;
using System.Threading;
using System.Windows.Forms;

internal static class Launcher
{
    [STAThread]
    private static int Main(string[] args)
    {
        bool created;
        using (var mutex = new Mutex(true, "Local\\RyujinLCD-" +
            System.Security.Principal.WindowsIdentity.GetCurrent().User.Value, out created))
        {
            if (!created) {
                MessageBox.Show("Ryujin LCD is already running. Open it from the system tray.", "Ryujin LCD");
                return 0;
            }
            try { return Run(args); }
            finally { mutex.ReleaseMutex(); }
        }
    }

    private static int Run(string[] args)
    {
        string folder = Path.Combine(Path.GetTempPath(), "RyujinLCD-" + Guid.NewGuid().ToString("N"));
        try
        {
            Directory.CreateDirectory(folder);
            Extract("Ryujin-Player.ps1", folder);
            Extract("Ryujin-Usb.ps1", folder);
            Extract("Ryujin-Storage.ps1", folder);
            Extract("Ryujin-Sensors.ps1", folder);
            Extract("Ryujin-Dashboard.jpg", folder);
            string powerShell = Path.Combine(Environment.SystemDirectory, @"WindowsPowerShell\v1.0\powershell.exe");
            var start = new ProcessStartInfo(powerShell)
            {
                Arguments = "-NoProfile -STA -ExecutionPolicy RemoteSigned -File \"" +
                    Path.Combine(folder, "Ryujin-Player.ps1") + "\"",
                UseShellExecute = false,
                CreateNoWindow = true,
                RedirectStandardOutput = true,
                RedirectStandardError = true
            };
            string localFfmpeg = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "ffmpeg.exe");
            start.EnvironmentVariables["RYUJIN_EXE"] = Application.ExecutablePath;
            if (Array.IndexOf(args, "--autostart") >= 0) start.Arguments += " -AutoStart";
            if (File.Exists(localFfmpeg))
                start.EnvironmentVariables["RYUJIN_FFMPEG"] = localFfmpeg;

            using (Process app = Process.Start(start))
            {
                Task<string> output = app.StandardOutput.ReadToEndAsync();
                Task<string> errors = app.StandardError.ReadToEndAsync();
                app.WaitForExit();
                Task.WaitAll(output, errors);
                if (app.ExitCode != 0)
                {
                    string details = string.IsNullOrWhiteSpace(errors.Result) ? output.Result : errors.Result;
                    if (string.IsNullOrWhiteSpace(details)) details = "PowerShell exited with code " + app.ExitCode;
                    MessageBox.Show(details.Trim(), "Ryujin LCD", MessageBoxButtons.OK, MessageBoxIcon.Error);
                }
                return app.ExitCode;
            }
        }
        catch (Exception error)
        {
            MessageBox.Show(error.Message, "Ryujin LCD", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
        finally
        {
            foreach (string name in new[] { "Ryujin-Player.ps1", "Ryujin-Usb.ps1", "Ryujin-Storage.ps1", "Ryujin-Sensors.ps1", "Ryujin-Dashboard.jpg" })
            {
                try { File.Delete(Path.Combine(folder, name)); } catch (IOException) { } catch (UnauthorizedAccessException) { }
            }
            try { Directory.Delete(folder); } catch (IOException) { } catch (UnauthorizedAccessException) { }
        }
    }

    private static void Extract(string name, string folder)
    {
        using (Stream source = Assembly.GetExecutingAssembly().GetManifestResourceStream(name))
        using (var target = new FileStream(Path.Combine(folder, name), FileMode.CreateNew, FileAccess.Write))
            source.CopyTo(target);
    }
}
