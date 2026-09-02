[CmdletBinding()]
param(
    [string]$OutputPath = ''
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $repositoryRoot 'Resources\WindWhisperProfile.ico'
}
$OutputPath = [IO.Path]::GetFullPath($OutputPath)

$fontFamily = [Drawing.FontFamily]::new('Microsoft YaHei UI')
$pngImages = [Collections.Generic.List[byte[]]]::new()
$sizes = @(16, 20, 24, 32, 48, 256)

try {
    foreach ($size in $sizes) {
        $bitmap = [Drawing.Bitmap]::new($size, $size,
            [Drawing.Imaging.PixelFormat]::Format32bppArgb)
        try {
            $graphics = [Drawing.Graphics]::FromImage($bitmap)
            try {
                $graphics.Clear([Drawing.Color]::Transparent)
                $graphics.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::AntiAlias
                $graphics.PixelOffsetMode = [Drawing.Drawing2D.PixelOffsetMode]::HighQuality
                $graphics.TextRenderingHint =
                    [Drawing.Text.TextRenderingHint]::AntiAliasGridFit

                $path = [Drawing.Drawing2D.GraphicsPath]::new()
                try {
                    $emSize = [single]($size * 0.84)
                    $path.AddString('风', $fontFamily,
                        [int][Drawing.FontStyle]::Bold, $emSize,
                        [Drawing.PointF]::new(0, 0),
                        [Drawing.StringFormat]::GenericDefault)
                    $bounds = $path.GetBounds()
                    $matrix = [Drawing.Drawing2D.Matrix]::new()
                    try {
                        $matrix.Translate(
                            [single](($size - $bounds.Width) / 2 - $bounds.Left),
                            [single](($size - $bounds.Height) / 2 - $bounds.Top))
                        $path.Transform($matrix)
                    } finally {
                        $matrix.Dispose()
                    }

                    $shadowPath = $path.Clone()
                    $shadowMatrix = [Drawing.Drawing2D.Matrix]::new()
                    $shadow = [Drawing.SolidBrush]::new(
                        [Drawing.Color]::FromArgb(190, 18, 18, 18))
                    $fill = [Drawing.SolidBrush]::new([Drawing.Color]::White)
                    try {
                        $shadowOffset = [single][Math]::Max(0.65, $size * 0.025)
                        $shadowMatrix.Translate($shadowOffset, $shadowOffset)
                        $shadowPath.Transform($shadowMatrix)
                        $graphics.FillPath($shadow, $shadowPath)
                        $graphics.FillPath($fill, $path)
                    } finally {
                        $fill.Dispose()
                        $shadow.Dispose()
                        $shadowMatrix.Dispose()
                        $shadowPath.Dispose()
                    }
                } finally {
                    $path.Dispose()
                }
            } finally {
                $graphics.Dispose()
            }

            $stream = [IO.MemoryStream]::new()
            try {
                $bitmap.Save($stream, [Drawing.Imaging.ImageFormat]::Png)
                $pngImages.Add($stream.ToArray())
            } finally {
                $stream.Dispose()
            }
        } finally {
            $bitmap.Dispose()
        }
    }
} finally {
    $fontFamily.Dispose()
}

$parent = Split-Path -Parent $OutputPath
[IO.Directory]::CreateDirectory($parent) | Out-Null
$file = [IO.File]::Open($OutputPath, [IO.FileMode]::Create,
    [IO.FileAccess]::Write, [IO.FileShare]::None)
$writer = [IO.BinaryWriter]::new($file)
try {
    $writer.Write([uint16]0)
    $writer.Write([uint16]1)
    $writer.Write([uint16]$sizes.Count)
    $offset = 6 + 16 * $sizes.Count
    for ($index = 0; $index -lt $sizes.Count; $index++) {
        $size = $sizes[$index]
        $writer.Write([byte]$(if ($size -eq 256) { 0 } else { $size }))
        $writer.Write([byte]$(if ($size -eq 256) { 0 } else { $size }))
        $writer.Write([byte]0)
        $writer.Write([byte]0)
        $writer.Write([uint16]1)
        $writer.Write([uint16]32)
        $writer.Write([uint32]$pngImages[$index].Length)
        $writer.Write([uint32]$offset)
        $offset += $pngImages[$index].Length
    }
    foreach ($image in $pngImages) {
        $writer.Write($image)
    }
} finally {
    $writer.Dispose()
}

Write-Host $OutputPath
