# Xuat mot khoang trang cua docx ra PDF (1 phien Word read-only).
param($docx, $pdf, $from, $to)
$w = New-Object -ComObject Word.Application; $w.Visible = $false; $w.DisplayAlerts = 0
try {
    $d = $w.Documents.Open($docx, $false, $true)
    $d.ExportAsFixedFormat($pdf, 17, $false, 1, 3, [int]$from, [int]$to)
    $d.Close(0)
} finally { $w.Quit() }
