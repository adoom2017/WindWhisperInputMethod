[CmdletBinding()]
param([Parameter(Mandatory)][string]$OutputPath)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$OutputPath = [IO.Path]::GetFullPath($OutputPath)
[IO.Directory]::CreateDirectory((Split-Path -Parent $OutputPath)) | Out-Null
$bitmap = [Drawing.Bitmap]::new(328, 628)
$graphics = [Drawing.Graphics]::FromImage($bitmap)
$glyphFont = [Drawing.Font]::new('Microsoft YaHei UI', 56,
    [Drawing.FontStyle]::Regular, [Drawing.GraphicsUnit]::Pixel)
$labelFont = [Drawing.Font]::new('Microsoft YaHei UI', 14,
    [Drawing.FontStyle]::Regular, [Drawing.GraphicsUnit]::Pixel)
$captionFont = [Drawing.Font]::new('Segoe UI', 10,
    [Drawing.FontStyle]::Regular, [Drawing.GraphicsUnit]::Pixel)
$accent = [Drawing.SolidBrush]::new([Drawing.ColorTranslator]::FromHtml('#2F6B8A'))
$text = [Drawing.SolidBrush]::new([Drawing.ColorTranslator]::FromHtml('#1F2023'))
$secondary = [Drawing.SolidBrush]::new([Drawing.ColorTranslator]::FromHtml('#6E7076'))
$border = [Drawing.Pen]::new([Drawing.ColorTranslator]::FromHtml('#DEDED9'))
$format = [Drawing.StringFormat]::new()
try {
    $graphics.Clear([Drawing.ColorTranslator]::FromHtml('#FAFAF8'))
    $graphics.ScaleTransform(2, 2)
    $graphics.TextRenderingHint = [Drawing.Text.TextRenderingHint]::AntiAliasGridFit
    $format.Alignment = [Drawing.StringAlignment]::Center
    $graphics.DrawString('风', $glyphFont, $accent,
        [Drawing.RectangleF]::new(0, 65, 164, 85), $format)
    $graphics.DrawString('风语输入法', $labelFont, $text,
        [Drawing.RectangleF]::new(0, 160, 164, 28), $format)
    $graphics.DrawString('WINDWHISPER', $captionFont, $secondary,
        [Drawing.RectangleF]::new(0, 192, 164, 20), $format)
    $graphics.DrawLine($border, 163, 0, 163, 314)
    $bitmap.Save($OutputPath, [Drawing.Imaging.ImageFormat]::Bmp)
} finally {
    $format.Dispose()
    $border.Dispose()
    $secondary.Dispose()
    $text.Dispose()
    $accent.Dispose()
    $captionFont.Dispose()
    $labelFont.Dispose()
    $glyphFont.Dispose()
    $graphics.Dispose()
    $bitmap.Dispose()
}
