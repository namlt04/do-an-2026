# Mo Bao-cao-tuan-1.docx bang Word, cap nhat Muc luc + Danh muc hinh roi luu lai.
# Word COM treo voi duong dan co dau -> xu ly tren ban sao o %TEMP% roi chep ve.
# -Preview: xuat PNG tung trang vao build\preview\ de kiem tra (phien Word rieng, read-only;
#           export ca file 1 lan bi treo -> xuat theo khoang 8 trang).
param([switch]$Preview)
$ErrorActionPreference = 'Stop'
$docx = (Resolve-Path (Join-Path $PSScriptRoot '..\Bao-cao-tuan-1.docx')).Path
$tmpDocx = Join-Path $env:TEMP 'bc-tuan1-build.docx'
Get-ChildItem -LiteralPath $env:TEMP -Filter '~$*tuan1*' -Force -ErrorAction SilentlyContinue | Remove-Item -Force
Copy-Item -LiteralPath $docx -Destination $tmpDocx -Force

function New-Word { $w = New-Object -ComObject Word.Application; $w.Visible = $false; $w.DisplayAlerts = 0; $w }

$word = New-Word
try {
    $d = $word.Documents.Open($tmpDocx, $false, $false)
    foreach ($t in $d.TablesOfContents) { $t.Update() }
    foreach ($t in $d.TablesOfFigures) { $t.Update() }
    $pages = $d.ComputeStatistics(2)
    "pages: $pages"
    $d.Save()
    $d.Close(0)
} finally {
    $word.Quit()
}
Copy-Item -LiteralPath $tmpDocx -Destination $docx -Force
"OK $docx"

if ($Preview) { & (Join-Path $PSScriptRoot 'preview.ps1') $pages }
