# ---------------------------------------------------------------------------
# Exam Routine - PNG / PDF export
# ---------------------------------------------------------------------------
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Drawing

if (-not ('ExamPdf' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.IO.Compression;
using System.Text;
using System.Globalization;

public static class ExamPdf
{
    private static readonly CultureInfo Inv = CultureInfo.InvariantCulture;

    private static string F(double value)
    {
        return value.ToString("0.###", Inv);
    }

    private static void Ascii(Stream stream, string text)
    {
        byte[] bytes = Encoding.ASCII.GetBytes(text);
        stream.Write(bytes, 0, bytes.Length);
    }

    public static byte[] BgraToRgb(byte[] bgra, int width, int height)
    {
        int pixels = width * height;
        byte[] rgb = new byte[pixels * 3];
        for (int i = 0, j = 0; i < pixels; i++, j += 3)
        {
            int k = i * 4;
            rgb[j] = bgra[k + 2];
            rgb[j + 1] = bgra[k + 1];
            rgb[j + 2] = bgra[k];
        }
        return rgb;
    }

    private static byte[] Zlib(byte[] data)
    {
        using (MemoryStream output = new MemoryStream())
        {
            output.WriteByte(0x78);
            output.WriteByte(0x9C);
            using (DeflateStream deflate = new DeflateStream(output, CompressionMode.Compress, true))
            {
                deflate.Write(data, 0, data.Length);
            }

            uint a = 1;
            uint b = 0;
            for (int i = 0; i < data.Length; i++)
            {
                a = (a + data[i]) % 65521;
                b = (b + a) % 65521;
            }
            uint adler = (b << 16) | a;
            output.WriteByte((byte)((adler >> 24) & 0xFF));
            output.WriteByte((byte)((adler >> 16) & 0xFF));
            output.WriteByte((byte)((adler >> 8) & 0xFF));
            output.WriteByte((byte)(adler & 0xFF));
            return output.ToArray();
        }
    }

    public static byte[] Create(byte[] rgb, int pixelWidth, int pixelHeight,
        double pageWidth, double pageHeight,
        double drawWidth, double drawHeight, double x, double y)
    {
        byte[] image = Zlib(rgb);
        string content = "q\n" + F(drawWidth) + " 0 0 " + F(drawHeight) + " " + F(x) + " " + F(y) + " cm\n/Im0 Do\nQ\n";
        byte[] contentBytes = Encoding.ASCII.GetBytes(content);

        using (MemoryStream ms = new MemoryStream())
        {
            Ascii(ms, "%PDF-1.4\n");
            ms.Write(new byte[] { 0x25, 0xE2, 0xE3, 0xCF, 0xD3, 0x0A }, 0, 6);

            long[] offsets = new long[6];

            offsets[1] = ms.Position;
            Ascii(ms, "1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n");

            offsets[2] = ms.Position;
            Ascii(ms, "2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n");

            offsets[3] = ms.Position;
            Ascii(ms, "3 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 " + F(pageWidth) + " " + F(pageHeight) +
                "] /Resources << /XObject << /Im0 4 0 R >> >> /Contents 5 0 R >>\nendobj\n");

            offsets[4] = ms.Position;
            Ascii(ms, "4 0 obj\n<< /Type /XObject /Subtype /Image /Width " + pixelWidth +
                " /Height " + pixelHeight +
                " /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /FlateDecode /Length " + image.Length +
                " >>\nstream\n");
            ms.Write(image, 0, image.Length);
            Ascii(ms, "\nendstream\nendobj\n");

            offsets[5] = ms.Position;
            Ascii(ms, "5 0 obj\n<< /Length " + contentBytes.Length + " >>\nstream\n");
            ms.Write(contentBytes, 0, contentBytes.Length);
            Ascii(ms, "\nendstream\nendobj\n");

            long xref = ms.Position;
            Ascii(ms, "xref\n0 6\n0000000000 65535 f \n");
            for (int i = 1; i <= 5; i++)
            {
                Ascii(ms, offsets[i].ToString("D10", Inv) + " 00000 n \n");
            }
            Ascii(ms, "trailer\n<< /Size 6 /Root 1 0 R >>\nstartxref\n" + xref.ToString(Inv) + "\n%%EOF\n");
            return ms.ToArray();
        }
    }
}
'@
}

function New-ExportVisual {
    param(
        [object[]]$ExamList,
        [string]$TermText,
        [string]$TermCodeText,
        [string]$Accent,
        [string]$TitleText,
        [string]$FooterText,
        [ValidateSet('desktop', 'print')]
        [string]$Style = 'print'
    )

    $theme = if ($Style -eq 'print') { 'light' } else { 'dark' }
    $background = if ($Style -eq 'print') { '#FFFFFF' } else { '#0B0F14' }

    $card = Build-Card -ExamList $ExamList -TermText $TermText -TermCodeText $TermCodeText `
        -CardWidth 440 -Accent $Accent -TitleText $TitleText -FooterText $FooterText -Theme $theme

    $wrap = New-Object System.Windows.Controls.Border
    $wrap.Background = Br $background
    $wrap.Padding = Pad 28 28 28 28
    $wrap.Child = $card

    $width = 440 + 56
    $wrap.Measure([System.Windows.Size]::new($width, [double]::PositiveInfinity))
    $height = [math]::Ceiling($wrap.DesiredSize.Height)
    $wrap.Arrange([System.Windows.Rect]::new(0, 0, $width, $height))
    $wrap.UpdateLayout()

    [pscustomobject]@{
        Visual  = $wrap
        Width   = $width
        Height  = $height
        Scale   = 3.0
    }
}

function New-ExportBitmap {
    param([object]$ExportVisual)
    $scale = $ExportVisual.Scale
    $rtb = [System.Windows.Media.Imaging.RenderTargetBitmap]::new(
        [int]($ExportVisual.Width * $scale),
        [int]($ExportVisual.Height * $scale),
        96.0 * $scale,
        96.0 * $scale,
        [System.Windows.Media.PixelFormats]::Pbgra32)
    $rtb.Render($ExportVisual.Visual)
    return $rtb
}

function Export-RoutinePng {
    param(
        [string]$Path,
        [object]$ExportVisual
    )
    $rtb = New-ExportBitmap $ExportVisual
    $encoder = New-Object System.Windows.Media.Imaging.PngBitmapEncoder
    $encoder.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($rtb))
    $stream = [System.IO.File]::Create($Path)
    try { $encoder.Save($stream) }
    finally { $stream.Close() }
}

function Export-RoutinePdf {
    param(
        [string]$Path,
        [object]$ExportVisual,
        [ValidateSet('card', 'a4')]
        [string]$Page = 'a4'
    )

    $rtb = New-ExportBitmap $ExportVisual
    $stride = $rtb.PixelWidth * 4
    $bgra = New-Object byte[] ($stride * $rtb.PixelHeight)
    $rtb.CopyPixels($bgra, $stride, 0)
    $rgb = [ExamPdf]::BgraToRgb($bgra, $rtb.PixelWidth, $rtb.PixelHeight)

    $dipWidth = $rtb.PixelWidth / $ExportVisual.Scale
    $dipHeight = $rtb.PixelHeight / $ExportVisual.Scale
    $ptWidth = $dipWidth * 0.75
    $ptHeight = $dipHeight * 0.75

    if ($Page -eq 'a4') {
        $pageWidth = 595.276
        $pageHeight = 841.89
        $margin = 36.0
        $maxW = $pageWidth - ($margin * 2)
        $maxH = $pageHeight - ($margin * 2)
        $ratio = [math]::Min($maxW / $ptWidth, $maxH / $ptHeight)
        $drawWidth = $ptWidth * $ratio
        $drawHeight = $ptHeight * $ratio
        $x = ($pageWidth - $drawWidth) / 2
        $y = ($pageHeight - $drawHeight) / 2
    }
    else {
        $pageWidth = $ptWidth
        $pageHeight = $ptHeight
        $drawWidth = $ptWidth
        $drawHeight = $ptHeight
        $x = 0
        $y = 0
    }

    $bytes = [ExamPdf]::Create($rgb, $rtb.PixelWidth, $rtb.PixelHeight, $pageWidth, $pageHeight, $drawWidth, $drawHeight, $x, $y)
    [System.IO.File]::WriteAllBytes($Path, $bytes)
}

function Export-Routine {
    param(
        [string]$Path,
        [ValidateSet('png', 'pdf')]
        [string]$Format,
        [ValidateSet('desktop', 'print')]
        [string]$Style = 'print',
        [ValidateSet('card', 'a4')]
        [string]$Page = 'a4',
        [object[]]$ExamList,
        [string]$TermText,
        [string]$TermCodeText,
        [string]$Accent,
        [string]$TitleText,
        [string]$FooterText
    )

    $visual = New-ExportVisual -ExamList $ExamList -TermText $TermText -TermCodeText $TermCodeText `
        -Accent $Accent -TitleText $TitleText -FooterText $FooterText -Style $Style

    if ($Format -eq 'png') {
        Export-RoutinePng -Path $Path -ExportVisual $visual
    }
    else {
        Export-RoutinePdf -Path $Path -ExportVisual $visual -Page $Page
    }
    return $Path
}
