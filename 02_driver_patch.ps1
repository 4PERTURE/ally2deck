# AMDGCF検証バイパスパッチ
$path = "C:\DRIVERS\Packages\Drivers\Display\WT6A_INF\B420718\amdkmdag.sys"
$backupPath = $path + ".bak"
$offset = 0x56550

# バックアップ作成
Copy-Item $path $backupPath -Force
Write-Host "Backup created: $backupPath"

# ファイル読み込み
$bytes = [System.IO.File]::ReadAllBytes($path)

# パッチ前のバイトを表示
Write-Host "Before patch:" ($bytes[$offset..($offset+4)] | ForEach-Object { $_.ToString('X2') }) -Separator ' '

# パッチ適用: xor eax,eax; ret; nop; nop
$patch = @(0x31, 0xC0, 0xC3, 0x90, 0x90)
for ($i = 0; $i -lt $patch.Length; $i++) {
    $bytes[$offset + $i] = $patch[$i]
}

# パッチ後のバイトを表示
Write-Host "After patch: " ($bytes[$offset..($offset+4)] | ForEach-Object { $_.ToString('X2') }) -Separator ' '

# ファイル書き込み
[System.IO.File]::WriteAllBytes($path, $bytes)
Write-Host "Patch applied successfully!"