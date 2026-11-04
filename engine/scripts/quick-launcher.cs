using System;
using System.Diagnostics;
using System.IO;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;

namespace CodexDynamicSkin {
  static class Program {
    [StructLayout(LayoutKind.Sequential)]
    struct JobLimits {
      public long PerProcessUserTimeLimit, PerJobUserTimeLimit;
      public uint LimitFlags;
      public UIntPtr MinimumWorkingSetSize, MaximumWorkingSetSize;
      public uint ActiveProcessLimit;
      public UIntPtr Affinity;
      public uint PriorityClass, SchedulingClass;
      public ulong ReadOperationCount, WriteOperationCount, OtherOperationCount;
      public ulong ReadTransferCount, WriteTransferCount, OtherTransferCount;
      public UIntPtr ProcessMemoryLimit, JobMemoryLimit, PeakProcessMemoryUsed, PeakJobMemoryUsed;
    }

    [DllImport("kernel32.dll", SetLastError = true)]
    static extern IntPtr CreateJobObject(IntPtr attributes, string name);
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool SetInformationJobObject(IntPtr job, int informationClass, ref JobLimits limits, uint length);
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool AssignProcessToJobObject(IntPtr job, IntPtr process);
    [DllImport("kernel32.dll")]
    static extern IntPtr GetCurrentProcess();

    [StructLayout(LayoutKind.Sequential)]
    struct StartupInfo {
      public int Size;
      public IntPtr Reserved, Desktop, Title;
      public int X, Y, Width, Height, XChars, YChars, Fill, Flags;
      public short ShowWindow, ReservedSize;
      public IntPtr ReservedBytes, StdInput, StdOutput, StdError;
    }

    [StructLayout(LayoutKind.Sequential)]
    struct ProcessInfo {
      public IntPtr Process, Thread;
      public uint ProcessId, ThreadId;
    }

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    static extern bool CreateProcess(string application, StringBuilder command, IntPtr processAttributes,
      IntPtr threadAttributes, bool inheritHandles, uint flags, IntPtr environment, string directory,
      ref StartupInfo startup, out ProcessInfo process);
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern uint ResumeThread(IntPtr thread);
    [DllImport("kernel32.dll")]
    static extern bool TerminateProcess(IntPtr process, uint exitCode);
    [DllImport("kernel32.dll")]
    static extern bool CloseHandle(IntPtr handle);

    static int RunMonitor(string shell, string arguments, string root) {
      IntPtr job = CreateJobObject(IntPtr.Zero, null);
      if (job == IntPtr.Zero) throw new Win32Exception();
      try {
        // Keep the monitor tied to the task. Its own children retain their
        // existing lifetimes, including Codex started after user confirmation.
        const uint KillOnClose = 0x2000, SilentBreakaway = 0x1000;
        var limits = new JobLimits { LimitFlags = KillOnClose };
        uint size = (uint)Marshal.SizeOf(typeof(JobLimits));
        if (!SetInformationJobObject(job, 9, ref limits, size) ||
            !AssignProcessToJobObject(job, GetCurrentProcess())) throw new Win32Exception();

        const uint Suspended = 0x4, NoConsole = 0x08000000;
        var startup = new StartupInfo { Size = Marshal.SizeOf(typeof(StartupInfo)) };
        ProcessInfo child;
        var command = new StringBuilder("\"" + shell + "\" " + arguments);
        if (!CreateProcess(shell, command, IntPtr.Zero, IntPtr.Zero, false, Suspended | NoConsole,
            IntPtr.Zero, root, ref startup, out child)) throw new Win32Exception();
        try {
          limits.LimitFlags |= SilentBreakaway;
          if (!SetInformationJobObject(job, 9, ref limits, size) || ResumeThread(child.Thread) == uint.MaxValue) {
            int error = Marshal.GetLastWin32Error();
            TerminateProcess(child.Process, 1);
            throw new Win32Exception(error);
          }
          using (var process = Process.GetProcessById((int)child.ProcessId)) {
            process.WaitForExit();
            return process.ExitCode;
          }
        } finally {
          CloseHandle(child.Thread);
          CloseHandle(child.Process);
        }
      } finally {
        // The launcher belongs to this job too. Let process teardown close
        // the handle so the launcher can return the monitor's exit code.
        GC.KeepAlive(job);
      }
    }

    [STAThread]
    static int Main(string[] args) {
      bool monitor = args.Length == 1 && args[0] == "--monitor";
      try {
        string launcherDirectory = AppDomain.CurrentDomain.BaseDirectory.TrimEnd(Path.DirectorySeparatorChar);
        string root = Directory.GetParent(launcherDirectory).Parent.FullName;
        string script = Path.Combine(root, "engine", "scripts", "launch-dream-skin.ps1");
        string arguments = "-NoProfile -WindowStyle Hidden -ExecutionPolicy RemoteSigned -File \"" + script + "\"";
        string shell = Path.Combine(Environment.SystemDirectory, "WindowsPowerShell", "v1.0", "powershell.exe");
        if (monitor) {
          script = Path.Combine(root, "engine", "scripts", "multi-instance.ps1");
          arguments = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File \"" + script + "\" -StateRoot \"" + root + "\"";
          return RunMonitor(shell, arguments, root);
        }
        var info = new ProcessStartInfo(shell, arguments);
        info.UseShellExecute = false;
        info.CreateNoWindow = true;
        info.WindowStyle = ProcessWindowStyle.Hidden;
        using (Process.Start(info)) { }
        return 0;
      } catch {
        return 1;
      }
    }
  }
}
