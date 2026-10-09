using System;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Windows.Forms;
[assembly: System.Reflection.AssemblyVersion("0.3.0.0")]
// SPDX-License-Identifier: GPL-3.0-only
public sealed class AC8Setup : Form {
    readonly RadioButton both = new RadioButton(), ui = new RadioButton(), hud = new RadioButton();
    readonly Button install = new Button(), uninstall = new Button(), full = new Button(), update = new Button(), steamOption = new Button(), browse = new Button();
    readonly Label status = new Label();
    readonly TextBox gamePath = new TextBox();
    readonly string autoMode;
    bool busy;
    static string Quote(string value) {
        var result = new StringBuilder("\""); int slashes = 0;
        foreach (char c in value) {
            if (c == '\\') { slashes++; continue; }
            if (c == '"') { result.Append('\\', slashes * 2 + 1); result.Append(c); }
            else { result.Append('\\', slashes); result.Append(c); }
            slashes = 0;
        }
        result.Append('\\', slashes * 2); result.Append('"'); return result.ToString();
    }
    static ProcessStartInfo PowerShell(string script, string extra) {
        return new ProcessStartInfo {
            FileName = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows), "System32", "WindowsPowerShell", "v1.0", "powershell.exe"),
            Arguments = "-NoProfile -ExecutionPolicy Bypass -File " + Quote(script) + extra,
            WorkingDirectory = AppDomain.CurrentDomain.BaseDirectory,
            UseShellExecute = false, CreateNoWindow = true
        };
    }
    static void SteamLaunch(string[] args) {
        string root = AppDomain.CurrentDomain.BaseDirectory;
        string statePath = Path.Combine(root, "install-state.json");
        if (!File.Exists(statePath)) throw new IOException("未找到汉化安装记录，请重新安装或清除 Steam 汉化启动选项。");
        string state = File.ReadAllText(statePath, Encoding.UTF8);
        if (!state.Contains("AC8ChineseMod:offline-v1")) throw new IOException("安装记录归属不明。");
        Process worker;
        if (Regex.IsMatch(state, "\"mode\"\\s*:\\s*\"None\"")) {
            // Uninstalled bridge forwards Steam's original command without loading any MOD.
            if (args.Length < 2) throw new IOException("Steam 原始启动命令缺失，请保留启动选项中的 %command%。");
            string bin = Directory.GetParent(root.TrimEnd(Path.DirectorySeparatorChar)).FullName;
            string game = Directory.GetParent(Directory.GetParent(Directory.GetParent(bin).FullName).FullName).FullName;
            string target = Path.GetFullPath(args[1]);
            if (!String.Equals(target, Path.Combine(game, "start_protected_game.exe"), StringComparison.OrdinalIgnoreCase) &&
                !String.Equals(target, Path.Combine(bin, "AceCombat8.exe"), StringComparison.OrdinalIgnoreCase))
                throw new IOException("Steam 原始启动路径与此游戏不符。");
            var forwarded = new StringBuilder();
            for (int i = 2; i < args.Length; i++) forwarded.Append(" ").Append(Quote(args[i]));
            worker = Process.Start(new ProcessStartInfo { FileName = target, Arguments = forwarded.ToString(),
                WorkingDirectory = Path.GetDirectoryName(target), UseShellExecute = false, WindowStyle = ProcessWindowStyle.Hidden });
        } else {
            string script = Path.Combine(root, "App", "Start-Chinese.ps1");
            worker = Process.Start(PowerShell(script, ""));
        }
        using (worker) { worker.WaitForExit(); Environment.ExitCode = worker.ExitCode; }
    }
    [STAThread] public static void Main(string[] args) {
        if (args.Length > 0 && args[0] == "--steam-launch") {
            try { SteamLaunch(args); }
            catch (Exception error) { MessageBox.Show(error.Message, "ACE COMBAT 8 简体汉化", MessageBoxButtons.OK, MessageBoxIcon.Error); Environment.ExitCode = 1; }
            return;
        }
        if (!File.Exists(Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "App", "Entry.ps1"))) {
            MessageBox.Show("此处仅保留 Steam 兼容入口。请从完整解压的汉化包中运行安装器，重新安装或完全卸载。", "ACE COMBAT 8 简体汉化"); return;
        }
        Application.EnableVisualStyles(); Application.SetCompatibleTextRenderingDefault(false);
        Application.Run(new AC8Setup(args));
    }
    AC8Setup(string[] args) {
        Text = "ACE COMBAT 8 简体汉化 · v0.3.0"; ClientSize = new Size(650, 470);
        FormBorderStyle = FormBorderStyle.FixedDialog; MaximizeBox = false; StartPosition = FormStartPosition.CenterScreen;
        Font = new Font("Microsoft YaHei UI", 10); AutoScaleMode = AutoScaleMode.Font;
        Controls.Add(new Label { Text = "游戏目录（自动搜索 Steam 库，也可手动选择）", Location = new Point(24, 20), AutoSize = true });
        gamePath.Location = new Point(24, 50); gamePath.Size = new Size(500, 28); Controls.Add(gamePath);
        browse.Text = "浏览…"; browse.Location = new Point(535, 47); browse.Size = new Size(90, 33);
        browse.Click += delegate { using (var dialog = new FolderBrowserDialog { Description = "请选择 ACE COMBAT 8 游戏文件夹" }) {
            if (dialog.ShowDialog(this) == DialogResult.OK) gamePath.Text = dialog.SelectedPath;
        }}; Controls.Add(browse);
        Controls.Add(new Label { Text = "选择汉化内容", Location = new Point(24, 96), AutoSize = true });
        both.Text = "全部汉化：游戏界面和 HUD"; both.Checked = true;
        ui.Text = "界面汉化：菜单、设置、机库、资料和结算";
        hud.Text = "HUD 汉化：仪表、雷达、目标名称和战斗提示";
        int y = 127; foreach (var choice in new[] {both, ui, hud}) { choice.Location = new Point(24, y); choice.Size = new Size(595, 30); Controls.Add(choice); y += 36; }
        Controls.Add(new Label { Text = "请先退出游戏。安装、更换、更新和卸载均不启动或关闭 Steam。\n首次使用需设置一次 Steam 启动选项；以后只需重启游戏。",
            Location = new Point(24, 245), Size = new Size(600, 48) });
        Button[] actions = {install, uninstall, full, update, steamOption};
        string[] labels = {"安装 / 更换汉化", "卸载汉化", "完全卸载", "检查更新", "复制 Steam 启动选项"};
        for (int i = 0; i < actions.Length; i++) {
            actions[i].Text = labels[i]; actions[i].Location = new Point(24 + (i % 3) * 204, i < 3 ? 310 : 359);
            actions[i].Size = new Size(i == 4 ? 396 : 192, 38); Controls.Add(actions[i]);
        }
        install.Click += delegate { Run("Install"); }; uninstall.Click += delegate { Run("Uninstall"); };
        full.Click += delegate { Run("FullUninstall"); }; update.Click += delegate { Run("Update"); };
        steamOption.Click += delegate { Run("SteamOptions"); };
        status.Text = "仅用于单机 · 简体中文 · GPLv3 · 游戏 1.1.2.0";
        status.Location = new Point(24, 425); status.Size = new Size(605, 28); Controls.Add(status);
        if (args.Length >= 3 && args[0] == "--apply-update" && (args[1] == "UI" || args[1] == "HUD" || args[1] == "Both")) {
            if (args.Length >= 4) {
                int parentId;
                if (Int32.TryParse(args[3], out parentId)) {
                    try { using (var parent = Process.GetProcessById(parentId)) { if (!parent.WaitForExit(15000)) throw new IOException("旧安装器仍在运行，请关闭后重试更新。"); } }
                    catch (ArgumentException) { /* Parent already exited. */ }
                }
            }
            autoMode = args[1]; gamePath.Text = args[2]; ui.Checked = autoMode == "UI"; hud.Checked = autoMode == "HUD"; both.Checked = autoMode == "Both";
            Shown += delegate { Run("Install"); };
        } else Shown += delegate { DetectGame(); };
        FormClosing += delegate(object sender, FormClosingEventArgs e) { if (busy) e.Cancel = true; };
    }
    void DetectGame() {
        ThreadPool.QueueUserWorkItem(delegate {
            try {
                var start = PowerShell(Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "App", "Detect-Game.ps1"), ""); start.RedirectStandardOutput = true; start.StandardOutputEncoding = Encoding.UTF8;
                using (var worker = Process.Start(start)) {
                    string path = worker.StandardOutput.ReadToEnd().Trim(); worker.WaitForExit();
                    if (worker.ExitCode == 0 && path.Length > 0 && Directory.Exists(path)) BeginInvoke(new Action(delegate { if (!busy && gamePath.Text.Length == 0) gamePath.Text = path; }));
                }
            } catch { /* Manual folder selection remains available. */ }
        });
    }
    void SetBusy(bool value) {
        busy = value;
        foreach (Control control in new Control[] {install, uninstall, full, update, steamOption, browse, gamePath, both, ui, hud}) control.Enabled = !value;
    }
    void Run(string operation) {
        string mode = ui.Checked ? "UI" : hud.Checked ? "HUD" : "Both";
        string extra = " -Operation " + operation + " -Mode " + mode + " -InstallerPid " + Process.GetCurrentProcess().Id;
        if (gamePath.Text.Trim().Length > 0) extra += " -GameDir " + Quote(gamePath.Text.Trim());
        try {
            var worker = Process.Start(PowerShell(Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "App", "Entry.ps1"), extra));
            if (operation == "FullUninstall") { worker.Dispose(); Close(); return; }
            SetBusy(true); status.Text = "正在处理，请稍候……";
            ThreadPool.QueueUserWorkItem(delegate {
                worker.WaitForExit(); int code = worker.ExitCode; worker.Dispose();
                BeginInvoke(new Action(delegate { SetBusy(false); if (code == 10) { Close(); return; } status.Text = code == 0 ? "操作完成。" : "操作未完成，请根据提示处理后重试。"; }));
            });
        } catch (Exception error) { MessageBox.Show(error.Message, Text, MessageBoxButtons.OK, MessageBoxIcon.Error); }
    }
}
