// KINFX Input 設定 (Windows). Same settings, about, help and donate link as the other shells:
// settings-spec.json and app-info.json sit next to this exe. Writes settings.json, then
// KxDeploy() in KINFXInput.dll rebuilds so every app picks the change up on next focus.
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Text;
using System.Web.Script.Serialization;
using System.Windows.Forms;

static class KxSettings {
  [DllImport("KINFXInput.dll")] static extern int KxDeploy();

  static string Dir = AppDomain.CurrentDomain.BaseDirectory;
  static string UserDir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "KINFX Input");
  static string SettingsPath = Path.Combine(UserDir, "settings.json");
  static JavaScriptSerializer Json = new JavaScriptSerializer();

  static Dictionary<string, object> Read(string path) {
    try { return Json.Deserialize<Dictionary<string, object>>(File.ReadAllText(path, Encoding.UTF8)); }
    catch { return new Dictionary<string, object>(); }
  }

  static string Str(object o) { return o is bool ? ((bool)o ? "true" : "false") : Convert.ToString(o); }

  [STAThread]
  static void Main(string[] args) {
    if (args.Contains("--deploy")) { Directory.CreateDirectory(UserDir); Environment.Exit(KxDeploy() == 1 ? 0 : 1); }
    Application.EnableVisualStyles();
    var spec = ((System.Collections.ArrayList)Read(Path.Combine(Dir, "settings-spec.json"))["settings"]).Cast<Dictionary<string, object>>().ToList();
    var info = Read(Path.Combine(Dir, "app-info.json"));
    var cur = Read(SettingsPath);

    var f = new Form { Text = "KINFX Input 設定", FormBorderStyle = FormBorderStyle.FixedDialog, MaximizeBox = false,
                       AutoSize = true, AutoSizeMode = AutoSizeMode.GrowAndShrink, Padding = new Padding(16),
                       Font = new Font("Microsoft JhengHei UI", 10), StartPosition = FormStartPosition.CenterScreen };
    try { f.Icon = Icon.ExtractAssociatedIcon(Application.ExecutablePath); } catch { }
    var grid = new TableLayoutPanel { ColumnCount = 2, AutoSize = true, Dock = DockStyle.Top };
    var combos = new Dictionary<string, ComboBox>();
    var status = new Label { Text = "變更即時生效。", AutoSize = true, ForeColor = SystemColors.GrayText, Margin = new Padding(3, 10, 3, 6) };

    Action save = () => {
      var obj = new Dictionary<string, object>();
      foreach (var s in spec) {
        string key = (string)s["key"];
        var opts = (System.Collections.ArrayList)s["options"];
        string v = (string)((System.Collections.ArrayList)opts[Math.Max(0, combos[key].SelectedIndex)])[0];
        obj[key] = key == "page_size" ? (object)int.Parse(v) : key == "association" ? (object)(v == "true") : v;
      }
      try {
        Directory.CreateDirectory(UserDir);
        File.WriteAllText(SettingsPath + ".tmp", Json.Serialize(obj), new UTF8Encoding(false));
        if (File.Exists(SettingsPath)) File.Replace(SettingsPath + ".tmp", SettingsPath, null); else File.Move(SettingsPath + ".tmp", SettingsPath);
        status.Text = KxDeploy() == 1 ? "已套用。" : "已儲存，但重建失敗。";
      } catch (Exception e) { status.Text = "儲存失敗：" + e.Message; }
    };

    foreach (var s in spec) {
      string key = (string)s["key"];
      var opts = ((System.Collections.ArrayList)s["options"]).Cast<System.Collections.ArrayList>().ToList();
      var cb = new ComboBox { DropDownStyle = ComboBoxStyle.DropDownList, Width = 160, AccessibleName = (string)s["label"] };
      foreach (var o in opts) cb.Items.Add((string)o[1]);
      object have;
      int idx = cur.TryGetValue(key, out have) ? opts.FindIndex(o => (string)o[0] == Str(have)) : 0;
      cb.SelectedIndex = idx < 0 ? 0 : idx;
      cb.SelectedIndexChanged += (a, b) => save();
      combos[key] = cb;
      grid.Controls.Add(new Label { Text = (string)s["label"], AutoSize = true, Anchor = AnchorStyles.Right, Margin = new Padding(3, 8, 8, 3) });
      grid.Controls.Add(cb);
    }

    var help = string.Join("\n", ((System.Collections.ArrayList)info["help"]).Cast<string>().Select(h => "• " + h));
    var buttons = new FlowLayoutPanel { AutoSize = true, Dock = DockStyle.Top };
    Func<string, Action, Button> btn = (t, a) => { var b = new Button { Text = t, AutoSize = true }; b.Click += (x, y) => a(); return b; };
    buttons.Controls.Add(btn("說明", () => MessageBox.Show(f, help, "KINFX Input 說明")));
    buttons.Controls.Add(btn("關於", () => MessageBox.Show(f, (string)info["about"] + "\n\n授權：" + Str(info.ContainsKey("license") ? info["license"] : ""),
                                                          "KINFX Input " + Str(info["version"]))));
    buttons.Controls.Add(btn("支持", () => {
      string url = Str(info.ContainsKey("donate_url") ? info["donate_url"] : "").Trim();
      if (url.StartsWith("https://") || url.StartsWith("http://")) Process.Start(new ProcessStartInfo(url) { UseShellExecute = true });
      else MessageBox.Show(f, "支持連結尚未設定。", "支持");
    }));

    var stack = new FlowLayoutPanel { FlowDirection = FlowDirection.TopDown, AutoSize = true, WrapContents = false };
    stack.Controls.Add(grid);
    stack.Controls.Add(status);
    stack.Controls.Add(buttons);
    f.Controls.Add(stack);
    Application.Run(f);
  }
}
