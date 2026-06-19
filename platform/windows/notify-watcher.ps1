# notify-watcher.ps1
# Singleton background process.
# Polls foreground window + WT title every 500ms.
# When the foreground window is the WT host AND its title matches a queued entry,
# removes that entry from the queue and updates the badge.
# Exits when the queue is empty.

param(
  [string]$QueueFile = "$env:USERPROFILE\.copilot\notify-queue.json",
  [string]$WatcherPidFile = "$env:USERPROFILE\.copilot\notify-watcher.pid",
  [int]$PollIntervalMs = 500,
  [int]$EntryTtlMinutes = 60
)

$ErrorActionPreference = 'SilentlyContinue'

# --- singleton lock ---
if (Test-Path $WatcherPidFile) {
  $existingPid = Get-Content $WatcherPidFile -ErrorAction SilentlyContinue
  if ($existingPid -and (Get-Process -Id $existingPid -ErrorAction SilentlyContinue)) { exit 0 }
}
$PID | Set-Content -Path $WatcherPidFile -Encoding ascii

# --- C# helpers ---
Add-Type @"
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
using System.Text;

namespace Copilot.Notify.Watcher {
  [ComImport][Guid("ea1afb91-9e28-4b86-90e9-9e9f8a5eefaf")][InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  public interface ITaskbarList3 {
    [PreserveSig] int HrInit();
    [PreserveSig] int AddTab(IntPtr h);
    [PreserveSig] int DeleteTab(IntPtr h);
    [PreserveSig] int ActivateTab(IntPtr h);
    [PreserveSig] int SetActiveAlt(IntPtr h);
    [PreserveSig] int MarkFullscreenWindow(IntPtr h, [MarshalAs(UnmanagedType.Bool)] bool f);
    [PreserveSig] int SetProgressValue(IntPtr h, UInt64 c, UInt64 t);
    [PreserveSig] int SetProgressState(IntPtr h, int s);
    [PreserveSig] int RegisterTab(IntPtr a, IntPtr b);
    [PreserveSig] int UnregisterTab(IntPtr h);
    [PreserveSig] int SetTabOrder(IntPtr a, IntPtr b);
    [PreserveSig] int SetTabActive(IntPtr a, IntPtr b, uint c);
    [PreserveSig] int ThumbBarAddButtons(IntPtr h, uint c, IntPtr p);
    [PreserveSig] int ThumbBarUpdateButtons(IntPtr h, uint c, IntPtr p);
    [PreserveSig] int ThumbBarSetImageList(IntPtr h, IntPtr i);
    [PreserveSig] int SetOverlayIcon(IntPtr h, IntPtr icon, [MarshalAs(UnmanagedType.LPWStr)] string d);
    [PreserveSig] int SetThumbnailTooltip(IntPtr h, [MarshalAs(UnmanagedType.LPWStr)] string t);
    [PreserveSig] int SetThumbnailClip(IntPtr h, IntPtr p);
  }
  [ComImport][Guid("56fdf344-fd6d-11d0-958a-006097c9a090")][ClassInterface(ClassInterfaceType.None)]
  public class TaskbarList { }

  public static class Native {
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] public static extern int GetWindowTextLength(IntPtr h);
  }

  public static class Badger {
    public static int Set(IntPtr hwnd, int number) {
      IntPtr icon;
      using (var bmp = new Bitmap(32, 32, PixelFormat.Format32bppArgb))
      using (var g = Graphics.FromImage(bmp)) {
        g.SmoothingMode = SmoothingMode.AntiAlias;
        g.TextRenderingHint = System.Drawing.Text.TextRenderingHint.AntiAlias;
        g.Clear(Color.Transparent);
        using (var b = new SolidBrush(Color.FromArgb(220, 38, 38))) g.FillEllipse(b, 0, 0, 31, 31);
        using (var pen = new Pen(Color.White, 2)) g.DrawEllipse(pen, 1, 1, 29, 29);
        string txt = number > 99 ? "99+" : number.ToString();
        float size = (txt.Length == 1) ? 22f : (txt.Length == 2 ? 16f : 12f);
        using (var font = new Font("Segoe UI", size, FontStyle.Bold, GraphicsUnit.Pixel))
        using (var sf = new StringFormat { Alignment = StringAlignment.Center, LineAlignment = StringAlignment.Center })
          g.DrawString(txt, font, Brushes.White, new RectangleF(0, 0, 32, 32), sf);
        icon = bmp.GetHicon();
      }
      var tb = (ITaskbarList3)(new TaskbarList());
      int hr = tb.HrInit(); if (hr != 0) return hr;
      return tb.SetOverlayIcon(hwnd, icon, number + " pending");
    }
    public static int Clear(IntPtr hwnd) {
      var tb = (ITaskbarList3)(new TaskbarList());
      tb.HrInit();
      return tb.SetOverlayIcon(hwnd, IntPtr.Zero, "");
    }
    public static string GetTitle(IntPtr hwnd) {
      int len = Native.GetWindowTextLength(hwnd) + 1;
      var sb = new StringBuilder(len);
      Native.GetWindowText(hwnd, sb, len);
      return sb.ToString();
    }
  }
}
"@ -ReferencedAssemblies System.Drawing 2>$null

function Get-WTWindow {
  $wt = Get-Process WindowsTerminal -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
  return $wt
}

function Read-Queue {
  if (-not (Test-Path $QueueFile)) { return @() }
  try {
    $raw = Get-Content $QueueFile -Raw
    if (-not $raw -or $raw.Trim() -eq '') { return @() }
    $p = $raw | ConvertFrom-Json
    if ($p -is [System.Array]) { return $p } else { return @($p) }
  } catch { return @() }
}

function Write-Queue([object[]]$entries) {
  $entries | ConvertTo-Json -Depth 5 -Compress | Set-Content -Path $QueueFile -Encoding utf8
}

function With-QueueLock([scriptblock]$action) {
  $lockPath = "$QueueFile.lock"
  for ($i = 0; $i -lt 50; $i++) {
    try { $fs = [System.IO.File]::Open($lockPath, 'OpenOrCreate', 'Write', 'None'); try { & $action } finally { $fs.Dispose() }; return }
    catch { Start-Sleep -Milliseconds 50 }
  }
  & $action
}

# --- main loop ---
$script:emptyTicks = 0
$script:maxEmptyTicks = [int](30000 / $PollIntervalMs)  # exit after 30s with no entries
$script:shouldExit = $false
$script:countAfter = -1

try {
  while ($true) {
    Start-Sleep -Milliseconds $PollIntervalMs

    # Read + modify + write must all happen under the lock to avoid clobbering helper writes
    $wt = Get-WTWindow
    $shouldExit = $false
    $countAfter = -1

    With-QueueLock {
      $queue = Read-Queue
      if ($queue.Count -eq 0) {
        $script:emptyTicks = ($script:emptyTicks + 1)
        $countAfter = 0
        if ($script:emptyTicks -ge $script:maxEmptyTicks) { $script:shouldExit = $true }
        return
      }
      $script:emptyTicks = 0

      $now = Get-Date
      $changed = $false
      $filtered = @($queue | Where-Object {
        try {
          $added = [datetime]::Parse($_.addedAt)
          if (($now - $added).TotalMinutes -gt $EntryTtlMinutes) { $changed = $true; $false } else { $true }
        } catch { $true }
      })

      if ($wt) {
        $wtHwnd = $wt.MainWindowHandle
        $fg = [Copilot.Notify.Watcher.Native]::GetForegroundWindow()
        if ($fg -eq $wtHwnd) {
          $title = [Copilot.Notify.Watcher.Badger]::GetTitle($wtHwnd)
          $before = $filtered.Count
          $filtered = @($filtered | Where-Object { $_.title -ne $title })
          if ($filtered.Count -ne $before) { $changed = $true }
        }
      }

      if ($changed) { Write-Queue $filtered }
      $script:countAfter = $filtered.Count
    }

    if ($shouldExit) {
      if ($wt) { try { [Copilot.Notify.Watcher.Badger]::Clear($wt.MainWindowHandle) | Out-Null } catch {} }
      break
    }

    if ($wt -and $countAfter -ge 0) {
      if ($countAfter -eq 0) {
        try { [Copilot.Notify.Watcher.Badger]::Clear($wt.MainWindowHandle) | Out-Null } catch {}
      } else {
        try { [Copilot.Notify.Watcher.Badger]::Set($wt.MainWindowHandle, $countAfter) | Out-Null } catch {}
      }
    }
  }
}
finally {
  Remove-Item $WatcherPidFile -ErrorAction SilentlyContinue
}
