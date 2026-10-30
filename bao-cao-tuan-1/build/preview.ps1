# Xuat PNG tung trang cua ban sao %TEMP%\bc-tuan1-build.docx vao build\preview\.
# Word treo khi export ca file mot lan -> moi khoang 8 trang chay export-range.ps1 trong 1 tien trinh rieng.
param([int]$pages)
$ErrorActionPreference = 'Stop'
$tmpDocx = Join-Path $env:TEMP 'bc-tuan1-build.docx'
$outDir = Join-Path $PSScriptRoot 'preview'
Remove-Item -LiteralPath $outDir -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force $outDir | Out-Null
for ($from = 1; $from -le $pages; $from += 8) {
    $to = [Math]::Min($from + 7, $pages)
    $pdf = Join-Path $env:TEMP ("bc-tuan1-{0:D2}.pdf" -f $from)
    powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'export-range.ps1') $tmpDocx $pdf $from $to
    & (Join-Path $PSScriptRoot 'pdf2png.ps1') $pdf (Join-Path $env:TEMP ("bc-tuan1-p{0:D2}" -f $from)) | ForEach-Object {
        $n = [int]([IO.Path]::GetFileNameWithoutExtension($_).Split('-')[-1]) + $from - 1
        Move-Item -LiteralPath $_ -Destination (Join-Path $outDir ("page-{0:D2}.png" -f $n)) -Force
    }
    "pages $from-$to ok"
}
