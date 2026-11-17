# Generates assets/exam.ico - a multi-size icon (16..256) drawn from code.
# Uses 32-bit DIB frames (best compatibility with the tray, shortcuts, Inno Setup).
# Committed output; run again only if the design changes.
#
#   powershell -NoProfile -STA -ExecutionPolicy Bypass -File .\tools\make-icon.ps1

[CmdletBinding()]
param(
    [string]$OutPath
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$root = Split-Path -Parent $PSScriptRoot
if (-not $root) { $root = (Get-Location).Path }
if (-not $OutPath) { $OutPath = Join-Path $root 'assets\exam.ico' }
$outDir = Split-Path -Parent $OutPath
if (-not (Test-Path -LiteralPath $outDir)) {
    New-Item -ItemType Directory -Path $outDir -Force | Out-Null
}

Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.IO;
using System.Runtime.InteropServices;

public static class IconMaker
{
    private static GraphicsPath RoundRect(RectangleF r, float radius)
    {
        float d = Math.Min(radius * 2f, Math.Min(r.Width, r.Height));
        var p = new GraphicsPath();
        p.AddArc(r.X, r.Y, d, d, 180, 90);
        p.AddArc(r.Right - d, r.Y, d, d, 270, 90);
        p.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90);
        p.AddArc(r.X, r.Bottom - d, d, d, 90, 90);
        p.CloseFigure();
        return p;
    }

    private static void Fill(Graphics g, RectangleF r, float radius, string hex)
    {
        using (var path = RoundRect(r, radius))
        using (var brush = new SolidBrush(ColorTranslator.FromHtml(hex)))
        {
            g.FillPath(brush, path);
        }
    }

    public static Bitmap Draw(int size)
    {
        var bmp = new Bitmap(size, size, PixelFormat.Format32bppArgb);
        using (var g = Graphics.FromImage(bmp))
        {
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.PixelOffsetMode = PixelOffsetMode.HighQuality;
            g.Clear(Color.Transparent);
            float s = size / 256f;

            var card = new RectangleF(6 * s, 6 * s, 244 * s, 244 * s);
            using (var path = RoundRect(card, 52 * s))
            {
                using (var brush = new SolidBrush(ColorTranslator.FromHtml("#11151A"))) g.FillPath(brush, path);
                using (var pen = new Pen(ColorTranslator.FromHtml("#2A323B"), Math.Max(1f, 4 * s))) g.DrawPath(pen, path);
            }

            Fill(g, new RectangleF(34 * s, 64 * s, 22 * s, 128 * s), 11 * s, "#F2577C");
            Fill(g, new RectangleF(78 * s, 64 * s, 118 * s, 26 * s), 13 * s, "#F3F7FA");
            Fill(g, new RectangleF(78 * s, 118 * s, 142 * s, 18 * s), 9 * s, "#8894A3");
            Fill(g, new RectangleF(78 * s, 154 * s, 128 * s, 18 * s), 9 * s, "#8894A3");
            Fill(g, new RectangleF(78 * s, 190 * s, 96 * s, 14 * s), 7 * s, "#5A6472");
        }
        return bmp;
    }

    private static byte[] DibFor(Bitmap bmp)
    {
        int w = bmp.Width, h = bmp.Height;
        using (var ms = new MemoryStream())
        using (var bw = new BinaryWriter(ms))
        {
            bw.Write(40);          // BITMAPINFOHEADER size
            bw.Write(w);           // width
            bw.Write(h * 2);       // height (XOR + AND mask)
            bw.Write((ushort)1);   // planes
            bw.Write((ushort)32);  // bpp
            bw.Write(0);           // BI_RGB
            bw.Write(w * h * 4);   // image size
            bw.Write(0);           // x pixels/meter
            bw.Write(0);           // y pixels/meter
            bw.Write(0);           // colors used
            bw.Write(0);           // important colors

            var rect = new Rectangle(0, 0, w, h);
            var data = bmp.LockBits(rect, ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
            try
            {
                int stride = Math.Abs(data.Stride);
                var row = new byte[stride];
                for (int y = h - 1; y >= 0; y--)
                {
                    Marshal.Copy(IntPtr.Add(data.Scan0, y * data.Stride), row, 0, stride);
                    bw.Write(row);
                }
            }
            finally
            {
                bmp.UnlockBits(data);
            }

            int maskStride = ((w + 31) / 32) * 4;
            bw.Write(new byte[maskStride * h]);
            bw.Flush();
            return ms.ToArray();
        }
    }

    public static void BuildIco(string path, int[] sizes)
    {
        var frames = new List<byte[]>();
        foreach (int size in sizes)
        {
            using (var bmp = Draw(size))
            {
                frames.Add(DibFor(bmp));
            }
        }

        using (var fs = File.Create(path))
        using (var bw = new BinaryWriter(fs))
        {
            bw.Write((ushort)0);
            bw.Write((ushort)1);
            bw.Write((ushort)sizes.Length);

            int offset = 6 + 16 * sizes.Length;
            for (int i = 0; i < sizes.Length; i++)
            {
                byte dim = (byte)(sizes[i] >= 256 ? 0 : sizes[i]);
                bw.Write(dim);
                bw.Write(dim);
                bw.Write((byte)0);
                bw.Write((byte)0);
                bw.Write((ushort)1);
                bw.Write((ushort)32);
                bw.Write((uint)frames[i].Length);
                bw.Write((uint)offset);
                offset += frames[i].Length;
            }

            foreach (var frame in frames) bw.Write(frame);
        }
    }
}
'@

$sizes = @(16, 24, 32, 48, 64, 128, 256)
[IconMaker]::BuildIco($OutPath, $sizes)

$check = New-Object System.Drawing.Icon($OutPath)
$bmp = $check.ToBitmap()
Write-Output ("icon: {0} ({1} bytes) frames={2} first={3}x{4}" -f $OutPath,
    (Get-Item -LiteralPath $OutPath).Length, $sizes.Count, $bmp.Width, $bmp.Height)
$bmp.Dispose()
$check.Dispose()

$big = New-Object System.Drawing.Icon($OutPath, 256, 256)
$bigBmp = $big.ToBitmap()
$preview = Join-Path $env:TEMP 'exam-widget-qa\icon-256.png'
if (-not (Test-Path -LiteralPath (Split-Path -Parent $preview))) {
    New-Item -ItemType Directory -Path (Split-Path -Parent $preview) -Force | Out-Null
}
$bigBmp.Save($preview, [System.Drawing.Imaging.ImageFormat]::Png)
$bigBmp.Dispose()
$big.Dispose()
Write-Output "preview: $preview"
