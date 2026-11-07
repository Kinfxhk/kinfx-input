// Test-only helper. Copy this file alongside interaction-acceptance.ps1.
using System;
using System.Text;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Windows.Forms;

public class InteractionBox : TextBox {
    public string ObservedPreedit = null;
    public bool CompositionObserved = false;
    public List<string> Commands = new List<string>();
    protected override bool ProcessCmdKey(ref Message msg, Keys keyData) {
        if ((keyData & Keys.Control) != 0) {
            Commands.Add(keyData.ToString());
            Keys k = keyData & Keys.KeyCode;
            // The test host provides non-destructive Save/Find/Location commands.
            if (k == Keys.S || k == Keys.F || k == Keys.L) return true;
        }
        return base.ProcessCmdKey(ref msg, keyData);
    }
    protected override void WndProc(ref Message m) {
        if (m.Msg == 0x10F && (m.LParam.ToInt64() & 8) != 0) {
            ObservedPreedit = InteractionNative.Composition(Handle);
            CompositionObserved = ObservedPreedit != null;
        }
        if (m.Msg == 0x10E && CompositionObserved) ObservedPreedit = "";
        base.WndProc(ref m);
    }
}
public static class InteractionNative {
    [StructLayout(LayoutKind.Sequential)] public struct KEYBDINPUT { public ushort vk,scan; public uint flags,time; public IntPtr extra; }
    [StructLayout(LayoutKind.Explicit, Size=40)] public struct INPUT { [FieldOffset(0)] public uint type; [FieldOffset(8)] public KEYBDINPUT ki; }
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int left,top,right,bottom; }
    [StructLayout(LayoutKind.Sequential)] public struct POINT { public int x,y; }
    [StructLayout(LayoutKind.Sequential)] public struct GUIINFO { public uint size,flags; public IntPtr active,focus,capture,menu,move,caret; public RECT rect; }
    public class WindowData { public long hwnd; public uint pid; public string className,title; public bool visible; public object rect; }
    [DllImport("user32.dll",SetLastError=true)] static extern uint SendInput(uint count, INPUT[] inputs, int size);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int x,int y);
    [DllImport("user32.dll")] static extern void mouse_event(uint flags,uint x,uint y,uint data,UIntPtr extra);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h,int command);
    [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr h,out RECT r);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h,out uint pid);
    [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern int GetClassName(IntPtr h,StringBuilder s,int n);
    [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern int GetWindowText(IntPtr h,StringBuilder s,int n);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
    delegate bool EnumProc(IntPtr h,IntPtr param);
    [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc proc,IntPtr param);
    [DllImport("user32.dll")] static extern bool GetGUIThreadInfo(uint thread,ref GUIINFO info);
    [DllImport("user32.dll")] static extern bool ClientToScreen(IntPtr h,ref POINT pt);
    [DllImport("imm32.dll")] static extern IntPtr ImmGetContext(IntPtr h);
    [DllImport("imm32.dll")] static extern bool ImmReleaseContext(IntPtr h,IntPtr context);
    [DllImport("imm32.dll",CharSet=CharSet.Unicode)] static extern int ImmGetCompositionStringW(IntPtr c,uint index,byte[] buf,uint len);
    public static string Composition(IntPtr h) {
        IntPtr c=ImmGetContext(h); if(c==IntPtr.Zero) return null;
        try { int n=ImmGetCompositionStringW(c,8,null,0); if(n<0) return null;
            byte[] b=new byte[n]; if(n>0 && ImmGetCompositionStringW(c,8,b,(uint)n)<0) return null;
            return Encoding.Unicode.GetString(b);
        } finally { ImmReleaseContext(h,c); }
    }
    public static object Preedit(InteractionBox box) {
        string current=Composition(box.Handle);
        if(!String.IsNullOrEmpty(current)) return new { value=current,backend="IMM32",unavailable=(string)null };
        if(box.CompositionObserved) return new { value=box.ObservedPreedit,backend="WM_IME_COMPOSITION/IMM32",unavailable=(string)null };
        return new { value=(string)null,backend="unavailable",unavailable="TSF-only composition is not exposed by this native EDIT host; no IMM composition evidence. Empty IMM buffer does not prove empty TSF preedit." };
    }
    public static void Key(ushort vk,bool shift,bool ctrl) {
        var inputs=new List<INPUT>();
        Action<ushort,uint> add=(v,f)=>{INPUT i=new INPUT(); i.type=1;i.ki.vk=v;i.ki.flags=f;inputs.Add(i);};
        if(ctrl)add(17,0);if(shift)add(16,0);add(vk,0);add(vk,2);if(shift)add(16,2);if(ctrl)add(17,2);
        uint n=SendInput((uint)inputs.Count,inputs.ToArray(),40);
        if(n!=inputs.Count)throw new InvalidOperationException("SendInput partial/failed: "+n+" Win32="+Marshal.GetLastWin32Error());
    }
    public static void Click(int x,int y) { if(!SetCursorPos(x,y))throw new Exception("SetCursorPos failed");mouse_event(2,0,0,0,UIntPtr.Zero);mouse_event(4,0,0,0,UIntPtr.Zero); }
    public static WindowData Window(IntPtr h) {
        uint pid;GetWindowThreadProcessId(h,out pid);var c=new StringBuilder(256);var t=new StringBuilder(512);
        GetClassName(h,c,256);GetWindowText(h,t,512);RECT r;bool ok=GetWindowRect(h,out r);
        return new WindowData { hwnd=h.ToInt64(),pid=pid,className=c.ToString(),title=t.ToString(),visible=IsWindowVisible(h),rect=ok?(object)r:null };
    }
    public static WindowData[] Candidates(uint pid) {
        var list=new List<WindowData>();
        EnumWindows((h,p)=>{var w=Window(h);if(w.pid==pid && w.className=="KINFXInputCand")list.Add(w);return true;},IntPtr.Zero);
        return list.ToArray();
    }
    public static object Caret() {
        uint pid;uint thread=GetWindowThreadProcessId(GetForegroundWindow(),out pid);
        GUIINFO g=new GUIINFO();g.size=(uint)Marshal.SizeOf(typeof(GUIINFO));
        if(!GetGUIThreadInfo(thread,ref g)||g.caret==IntPtr.Zero)return null;
        POINT a=new POINT {x=g.rect.left,y=g.rect.top},b=new POINT {x=g.rect.right,y=g.rect.bottom};
        if(!ClientToScreen(g.caret,ref a)||!ClientToScreen(g.caret,ref b))return null;
        return new RECT {left=a.x,top=a.y,right=b.x,bottom=b.y};
    }
    public static int Activate() {
        var m=(IInteractionProfile)Activator.CreateInstance(Type.GetTypeFromCLSID(new Guid("33C53A50-F456-4884-B049-85FD643ECFED")));
        try { Guid c=new Guid("42EBBC99-2AAD-4AF6-A8D9-2552AD948ED3"),p=new Guid("35BE04B0-E9E0-4E06-8438-10BFDCAE9E41");return m.ActivateProfile(1,0x404,ref c,ref p,IntPtr.Zero,0x10000000); }
        finally { Marshal.ReleaseComObject(m); }
    }
}
[ComImport,Guid("71c6e74c-0f28-11d8-a82a-00065b84435c"),InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IInteractionProfile { [PreserveSig]int ActivateProfile(uint type,ushort lang,ref Guid cls,ref Guid profile,IntPtr hkl,uint flags); }
