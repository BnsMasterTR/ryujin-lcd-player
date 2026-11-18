Add-Type -ReferencedAssemblies System.Management @"
using System;
using System.Collections.Generic;
using System.Globalization;
using System.Management;
using System.Runtime.InteropServices;
using System.Threading.Tasks;

public sealed class RyujinSensorFrame {
    public string[] Labels { get; set; }
    public string[] Values { get; set; }
}

public sealed class RyujinSensors {
    [DllImport("kernel32.dll", SetLastError=true)]
    static extern bool GetSystemTimes(out long idle, out long kernel, out long user);
    [StructLayout(LayoutKind.Sequential)]
    struct MemoryStatus {
        public uint Length, Load;
        public ulong Total, Available, PageTotal, PageAvailable, VirtualTotal, VirtualAvailable, Extended;
    }
    [DllImport("kernel32.dll", SetLastError=true)]
    static extern bool GlobalMemoryStatusEx(ref MemoryStatus status);
    long lastIdle, lastKernel, lastUser;
    string sensorNamespace;
    DateTime nextDiscovery = DateTime.MinValue;

    public RyujinSensors() { GetSystemTimes(out lastIdle, out lastKernel, out lastUser); }

    static string Display(double? value, string unit) {
        if (!value.HasValue || Double.IsNaN(value.Value) || Double.IsInfinity(value.Value)) return "N/A";
        return Math.Round(value.Value).ToString("0", CultureInfo.InvariantCulture) + unit;
    }

    static ManagementObjectCollection Query(string scope, string query) {
        var connection = new ConnectionOptions { Timeout = TimeSpan.FromSeconds(1) };
        var options = new EnumerationOptions { Timeout = TimeSpan.FromSeconds(1), ReturnImmediately = true };
        using (var search = new ManagementObjectSearcher(new ManagementScope(scope, connection), new ObjectQuery(query), options))
            return search.Get();
    }

    void Temperatures(out double? cpu, out double? gpu, out double? gpuLoad) {
        cpu = null; gpu = null; gpuLoad = null;
        string[] candidates = sensorNamespace != null ? new[] { sensorNamespace } :
            (DateTime.UtcNow >= nextDiscovery ? new[] { @"root\LibreHardwareMonitor", @"root\OpenHardwareMonitor" } : new string[0]);
        foreach (string scope in candidates) {
            try {
                using (var items = Query(scope, "SELECT Identifier, Name, SensorType, Value FROM Sensor")) {
                    foreach (ManagementObject item in items) using (item) {
                        if (item["Value"] == null) continue;
                        double value = Convert.ToDouble(item["Value"], CultureInfo.InvariantCulture);
                        string id = Convert.ToString(item["Identifier"]).ToLowerInvariant();
                        string type = Convert.ToString(item["SensorType"]);
                        string name = Convert.ToString(item["Name"]);
                        if (Double.IsNaN(value) || Double.IsInfinity(value)) continue;
                        if (type == "Temperature" && value >= -20 && value <= 150) {
                            if (id.Contains("cpu/")) cpu = !cpu.HasValue ? value : Math.Max(cpu.Value, value);
                            if (id.Contains("gpu")) gpu = !gpu.HasValue ? value : Math.Max(gpu.Value, value);
                        }
                        if (type == "Load" && id.Contains("gpu") && name.IndexOf("Core", StringComparison.OrdinalIgnoreCase) >= 0)
                            gpuLoad = Math.Max(0, Math.Min(100, value));
                    }
                }
                sensorNamespace = scope;
                return;
            } catch (ManagementException) { }
              catch (UnauthorizedAccessException) { }
              catch (System.Runtime.InteropServices.COMException) { }
        }
        sensorNamespace = null;
        if (candidates.Length > 0) nextDiscovery = DateTime.UtcNow.AddSeconds(30);
    }

    static double? GpuUsage() {
        try {
            var engines = new Dictionary<string, double>();
            using (var items = Query(@"root\cimv2",
                "SELECT Name, UtilizationPercentage FROM Win32_PerfFormattedData_GPUPerformanceCounters_GPUEngine")) {
                foreach (ManagementObject item in items) using (item) {
                    string name = Convert.ToString(item["Name"]);
                    if (name.IndexOf("engtype_3D", StringComparison.OrdinalIgnoreCase) < 0) continue;
                    int luid = name.IndexOf("luid_", StringComparison.OrdinalIgnoreCase);
                    string engine = luid >= 0 ? name.Substring(luid) : name;
                    double value = Convert.ToDouble(item["UtilizationPercentage"], CultureInfo.InvariantCulture);
                    if (!engines.ContainsKey(engine)) engines[engine] = 0;
                    engines[engine] += value;
                }
            }
            if (engines.Count == 0) return null;
            double maximum = 0;
            foreach (double value in engines.Values) maximum = Math.Max(maximum, value);
            return Math.Max(0, Math.Min(100, maximum));
        } catch (ManagementException) { return null; }
          catch (UnauthorizedAccessException) { return null; }
          catch (System.Runtime.InteropServices.COMException) { return null; }
    }

    public Task<RyujinSensorFrame> SampleAsync(int mode) {
        return Task.Run(() => {
            double? cpuUsage = null;
            long idle, kernel, user;
            if (GetSystemTimes(out idle, out kernel, out user)) {
                long elapsed = (kernel - lastKernel) + (user - lastUser);
                if (elapsed > 0) cpuUsage = Math.Max(0, Math.Min(100, 100.0 * (elapsed - (idle - lastIdle)) / elapsed));
                lastIdle = idle; lastKernel = kernel; lastUser = user;
            }
            var memory = new MemoryStatus { Length = (uint)Marshal.SizeOf(typeof(MemoryStatus)) };
            double? ram = GlobalMemoryStatusEx(ref memory) ? (double?)memory.Load : null;
            double? cpuTemp, gpuTemp, gpuUsage;
            Temperatures(out cpuTemp, out gpuTemp, out gpuUsage);
            if (mode == 1) return new RyujinSensorFrame {
                Labels = new[] { "CPU MAX TEMP", "GPU MAX TEMP", "RAM USAGE" },
                Values = new[] { Display(cpuTemp, " C"), Display(gpuTemp, " C"), Display(ram, "%") }
            };
            if (mode == 2) return new RyujinSensorFrame {
                Labels = new[] { "CPU USAGE", "CPU MAX TEMP", "RAM USAGE" },
                Values = new[] { Display(cpuUsage, "%"), Display(cpuTemp, " C"), Display(ram, "%") }
            };
            if (!gpuUsage.HasValue) gpuUsage = GpuUsage();
            return new RyujinSensorFrame {
                Labels = new[] { "CPU USAGE", "RAM USAGE", "GPU 3D USAGE" },
                Values = new[] { Display(cpuUsage, "%"), Display(ram, "%"), Display(gpuUsage, "%") }
            };
        });
    }
}
"@
