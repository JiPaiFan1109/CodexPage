using System;
using System.Diagnostics;
using System.IO;
using System.Threading;
using System.Windows.Forms;
using System.Reflection;

[assembly: AssemblyTitle("CodexPage")]
[assembly: AssemblyDescription("CodexPage")]
[assembly: AssemblyProduct("CodexPage")]
[assembly: AssemblyVersion("2.2.1.0")]
[assembly: AssemblyFileVersion("2.2.1.0")]

namespace CodexDynamicSkin {
  static class ManagerProgram {
    [STAThread]
    static int Main(string[] args) {
      bool created;
      using (var mutex = new Mutex(true, "CodexDynamicSkinManager", out created)) {
        if (!created) { MessageBox.Show("CodexPage 已打开。请从任务栏切换到已有窗口。", "CodexPage"); return 0; }
        try {
          string root = AppDomain.CurrentDomain.BaseDirectory.TrimEnd(Path.DirectorySeparatorChar);
          string script = Path.Combine(root, "scripts", "manage-background.ps1");
          if (!File.Exists(script)) throw new FileNotFoundException("安装文件不完整，请从项目发布页重新下载安装 CodexPage。", script);
          string arguments = "-NoProfile -STA -WindowStyle Hidden -ExecutionPolicy RemoteSigned -File \"" + script + "\" -InstallRoot \"" + root + "\"";
          if (args.Length == 2 && args[0] == "--update-ready") {
            Guid token;
            if (!Guid.TryParseExact(args[1], "N", out token)) throw new ArgumentException("Invalid update token");
            arguments += " -UpdateReadyToken " + token.ToString("N");
          }
          // Isolated package verification can open the real UI without changing Codex.
          if (args.Length == 1 && args[0] == "--prepare-only") arguments += " -PrepareOnly";
          var info = new ProcessStartInfo(Path.Combine(Environment.SystemDirectory, "WindowsPowerShell", "v1.0", "powershell.exe"), arguments);
          info.WorkingDirectory = root;
          info.UseShellExecute = false;
          info.CreateNoWindow = true;
          info.WindowStyle = ProcessWindowStyle.Hidden;
          using (var process = Process.Start(info)) {
            process.WaitForExit();
            if (process.ExitCode != 0) throw new Exception("CodexPage 无法启动。请重新打开；若仍失败，请从项目发布页重新下载安装。");
          }
          return 0;
        } catch (Exception error) {
          try { string logs = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "logs"); Directory.CreateDirectory(logs); File.AppendAllText(Path.Combine(logs, "manager-launcher.log"), DateTime.UtcNow.ToString("o") + " " + error.ToString() + Environment.NewLine); } catch { }
          MessageBox.Show("CodexPage 无法启动。请重新打开；若仍失败，请从项目发布页重新下载安装。", "CodexPage", MessageBoxButtons.OK, MessageBoxIcon.Warning);
          return 1;
        } finally { mutex.ReleaseMutex(); }
      }
    }
  }
}
