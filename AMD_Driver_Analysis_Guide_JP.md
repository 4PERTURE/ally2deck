# AMD カスタムドライバー解析・パッチ手順書

## 概要

このドキュメントは、AMDグラフィックドライバーを別のデバイス向けに改造する際の
解析・パッチ手順をまとめたものです。

実例：ROG Ally用ドライバー → Steam Deck用カスタムドライバー

---

## 1. 問題の特定

### 1.1 デバイスマネージャーでエラー確認

ドライバーインストール後、デバイスマネージャーでGPUの状態を確認：

```powershell
Get-PnpDevice | Where-Object { $_.FriendlyName -like "*AMD*" -or $_.FriendlyName -like "*Radeon*" } | Select-Object FriendlyName, Status, Problem
```

よくあるエラーコード：
- `CM_PROB_FAILED_START` (Code 43) - デバイス初期化失敗
- `CM_PROB_FAILED_POST_START` - 起動後の初期化失敗
- `CM_PROB_DRIVER_FAILED_LOAD` - ドライバーロード失敗

### 1.2 イベントログからエラー詳細を取得

```powershell
# AMD関連のイベントを検索
Get-WinEvent -LogName System | Where-Object { $_.ProviderName -like "*amd*" -or $_.Message -like "*amdkmdag*" } | Select-Object -First 20 TimeCreated, Id, Message
```

### 1.3 エラーメッセージのデコード

イベントID 3085などでMessageが空の場合、Propertiesからデータを取得：

```powershell
Get-WinEvent -LogName System | Where-Object { $_.Id -eq 3085 } | Select-Object -First 1 | ForEach-Object { $_.Properties | ForEach-Object { $_.Value } }
```

出力が数字の羅列の場合、ASCIIコードなので変換：

```powershell
# 数字列をASCIIに変換
$bytes = @(65,77,68,71,67,70,32,118,101,114,105,102,105,99,97,116,105,111,110)
[System.Text.Encoding]::ASCII.GetString($bytes)
# 結果: "AMDGCF verification"
```

---

## 2. ドライバーバイナリの解析

### 2.1 エラー文字列の検索

ドライバーファイル（amdkmdag.sys）内でエラーメッセージを検索：

```powershell
$path = "C:\path\to\amdkmdag.sys"
Select-String -Path $path -Pattern "AMDGCF" -Encoding ascii
```

### 2.2 文字列のファイルオフセットを特定

```powershell
$bytes = [System.IO.File]::ReadAllBytes($path)
$pattern = [System.Text.Encoding]::ASCII.GetBytes("AMDGCF verification failed")

for ($i = 0; $i -lt $bytes.Length - $pattern.Length; $i++) {
    $match = $true
    for ($j = 0; $j -lt $pattern.Length; $j++) {
        if ($bytes[$i + $j] -ne $pattern[$j]) { $match = $false; break }
    }
    if ($match) { 
        Write-Host "String found at file offset: 0x$($i.ToString('X'))"
        break 
    }
}
```

### 2.3 PEセクション情報の取得

Ghidraで正しい仮想アドレスを計算するためにセクション情報を確認：

```powershell
$bytes = [System.IO.File]::ReadAllBytes($path)
$e_lfanew = [BitConverter]::ToInt32($bytes, 0x3C)
$sizeOfOptionalHeader = [BitConverter]::ToInt16($bytes, $e_lfanew + 4 + 16)
$sectionHeadersStart = $e_lfanew + 4 + 20 + $sizeOfOptionalHeader
$numberOfSections = [BitConverter]::ToInt16($bytes, $e_lfanew + 4 + 2)

Write-Host "Sections:"
for ($i = 0; $i -lt $numberOfSections; $i++) {
    $sectionOffset = $sectionHeadersStart + ($i * 40)
    $name = [System.Text.Encoding]::ASCII.GetString($bytes[$sectionOffset..($sectionOffset+7)]).TrimEnd([char]0)
    $virtualAddress = [BitConverter]::ToInt32($bytes, $sectionOffset + 12)
    $rawAddress = [BitConverter]::ToInt32($bytes, $sectionOffset + 20)
    Write-Host "  $name : VA=0x$($virtualAddress.ToString('X')) Raw=0x$($rawAddress.ToString('X'))"
}
```

---

## 3. Ghidraでの解析

### 3.1 インストールと準備

1. Java 17以上をインストール: https://adoptium.net/
2. Ghidraをダウンロード: https://ghidra-sre.org/
3. `ghidraRun.bat` で起動

### 3.2 ファイルのインポート

1. File → New Project → Non-Shared Project
2. File → Import File → amdkmdag.sys を選択
3. フォーマットは自動検出（PE形式）
4. ダブルクリックでCodeBrowserを開く
5. 「Analyze?」で Yes → Analyze（数分かかる）

### 3.3 エラー文字列の検索

1. Search → For Strings...
2. Minimum Length: 10
3. Search をクリック
4. Filter に「AMDGCF」と入力
5. 該当文字列をダブルクリック

### 3.4 参照元コードの特定

文字列の場所で以下を確認：

```
DAT_14079cdf0    XREF[1]:  FUN_140052c50:140052e74(*)
```

これは「関数 FUN_140052c50 のアドレス 140052e74 がこの文字列を参照」を意味する。

参照元にジャンプ：
1. Navigation → Go To... (または G キー)
2. 参照アドレス（例: 140052e74）を入力

### 3.5 デコンパイル結果の確認

右側のDecompileウィンドウで、C言語風のコードを確認：

```c
iVar14 = FUN_140056b50(param_1, ...);  // 検証関数
if (iVar14 < 0) {
    // 検証失敗 → エラーメッセージ
    FUN_14004e010(param_1, "AMDGCF verification failed...");
}
```

### 3.6 検証関数の分析

検証関数（例: FUN_140056b50）にジャンプして内容を確認：

```c
// amdgcf.dat を読み込み
iVar2 = FUN_1400e5b10(&local_48, L"amdgcf.dat", 0, 0);

// デバイスID / リビジョンのチェック
if (uVar6 == param_2) {           // Device IDチェック
    if (*(byte *)(...) == param_3) // Revisionチェック
        break;
}
```

---

## 4. パッチオフセットの計算

### 4.1 仮想アドレス → ファイルオフセット変換

Ghidraのアドレスは仮想アドレス（VA）。ファイルオフセットに変換が必要：

```
ファイルオフセット = VA - セクションVA + セクションRawAddress
```

例（.textセクションの場合）：
- 関数VA: 0x140056b50
- ImageBase: 0x140000000
- RVA: 0x56b50 (= VA - ImageBase)
- .text VA: 0x1000
- .text Raw: 0xA00

```
ファイルオフセット = 0x56b50 - 0x1000 + 0xA00 = 0x56550
```

### 4.2 PowerShellでの自動計算

```powershell
$bytes = [System.IO.File]::ReadAllBytes($path)
$rva = 0x56b50  # Ghidraのアドレス - ImageBase

$e_lfanew = [BitConverter]::ToInt32($bytes, 0x3C)
$numberOfSections = [BitConverter]::ToInt16($bytes, $e_lfanew + 4 + 2)
$sizeOfOptionalHeader = [BitConverter]::ToInt16($bytes, $e_lfanew + 4 + 16)
$sectionHeadersStart = $e_lfanew + 4 + 20 + $sizeOfOptionalHeader

for ($i = 0; $i -lt $numberOfSections; $i++) {
    $sectionOffset = $sectionHeadersStart + ($i * 40)
    $virtualAddress = [BitConverter]::ToInt32($bytes, $sectionOffset + 12)
    $virtualSize = [BitConverter]::ToInt32($bytes, $sectionOffset + 8)
    $rawAddress = [BitConverter]::ToInt32($bytes, $sectionOffset + 20)
    
    if ($rva -ge $virtualAddress -and $rva -lt ($virtualAddress + $virtualSize)) {
        $fileOffset = $rva - $virtualAddress + $rawAddress
        Write-Host "File offset: 0x$($fileOffset.ToString('X'))"
        Write-Host "Current bytes:"
        Write-Host ($bytes[$fileOffset..($fileOffset+4)] | ForEach-Object { $_.ToString('X2') }) -Separator ' '
        break
    }
}
```

---

## 5. パッチの適用

### 5.1 バイパスパッチの種類

**方法A: 関数を即座にリターン（推奨）**

検証関数の先頭を書き換え：

```asm
xor eax, eax    ; 31 C0  (戻り値 = 0 = 成功)
ret             ; C3     (即座にリターン)
nop             ; 90     (パディング)
nop             ; 90
```

バイト列: `31 C0 C3 90 90`

**方法B: 条件ジャンプの変更**

```asm
jnz FAIL  →  jmp FAIL  (常にジャンプ)
jnz FAIL  →  nop nop   (ジャンプしない)
```

### 5.2 PowerShellでのパッチ適用

```powershell
$path = "C:\path\to\amdkmdag.sys"
$backupPath = $path + ".bak"
$offset = 0x56550  # 計算したオフセット

# バックアップ
Copy-Item $path $backupPath -Force

# 読み込み
$bytes = [System.IO.File]::ReadAllBytes($path)

# パッチ前確認
Write-Host "Before:" ($bytes[$offset..($offset+4)] | ForEach-Object { $_.ToString('X2') }) -Separator ' '

# パッチ適用
$patch = [byte[]]@(0x31, 0xC0, 0xC3, 0x90, 0x90)
for ($i = 0; $i -lt $patch.Length; $i++) {
    $bytes[$offset + $i] = $patch[$i]
}

# 書き込み
[System.IO.File]::WriteAllBytes($path, $bytes)

# パッチ後確認
Write-Host "After: " ($bytes[$offset..($offset+4)] | ForEach-Object { $_.ToString('X2') }) -Separator ' '
```

---

## 6. INFファイルの編集

### 6.1 デバイスHWIDの追加

対象デバイスのHWIDを確認：

```powershell
Get-PnpDevice | Where-Object { $_.Class -eq "Display" } | Get-PnpDeviceProperty -KeyName DEVPKEY_Device_HardwareIds | Select-Object -ExpandProperty Data
```

INFファイルの適切なセクションにエントリを追加：

```ini
"%AMD163F.2%" = ati2mtag_VanGogh, PCI\VEN_1002&DEV_163F&SUBSYS_01231002&REV_AE
```

---

## 7. ドライバー署名

### 7.1 自己署名証明書の作成

```powershell
$CertName = "AMD Driver Signing Certificate"
$Cert = New-SelfSignedCertificate `
    -Type CodeSigningCert `
    -Subject "CN=$CertName" `
    -KeyUsage DigitalSignature `
    -KeyAlgorithm RSA `
    -KeyLength 2048 `
    -CertStoreLocation "Cert:\CurrentUser\My" `
    -NotAfter (Get-Date).AddYears(5)
```

### 7.2 証明書を信頼ストアに追加

```powershell
$RootStore = New-Object System.Security.Cryptography.X509Certificates.X509Store("Root", "LocalMachine")
$RootStore.Open("ReadWrite")
$RootStore.Add($Cert)
$RootStore.Close()

$PublisherStore = New-Object System.Security.Cryptography.X509Certificates.X509Store("TrustedPublisher", "LocalMachine")
$PublisherStore.Open("ReadWrite")
$PublisherStore.Add($Cert)
$PublisherStore.Close()
```

### 7.3 ドライバーに署名

```powershell
$SignTool = "C:\Program Files (x86)\Windows Kits\10\bin\10.0.XXXXX.0\x64\signtool.exe"
$CertExportPath = "C:\DriverCert.pfx"
$CertPassword = "YourPassword"

# 証明書エクスポート
$SecurePassword = ConvertTo-SecureString -String $CertPassword -Force -AsPlainText
Export-PfxCertificate -Cert $Cert -FilePath $CertExportPath -Password $SecurePassword

# カタログファイルを削除（ハッシュ不一致を回避）
Remove-Item "u0420842.cat" -Force

# 署名
& $SignTool sign /fd SHA256 /f $CertExportPath /p $CertPassword /tr http://timestamp.digicert.com /td SHA256 "amdkmdag.sys"
```

---

## 8. インストールと起動

### 8.1 テスト署名モードの有効化

```cmd
bcdedit /set testsigning on
bcdedit /set nointegritychecks on
```

### 8.2 署名強制の一時無効化（初回テスト用）

```cmd
shutdown /r /o /t 0
```

再起動後：
1. トラブルシューティング
2. 詳細オプション
3. スタートアップ設定
4. 再起動
5. F7 - ドライバー署名の強制を無効にする

### 8.3 手動ドライバーインストール

1. デバイスマネージャーを開く
2. AMD Radeon Graphicsを右クリック
3. ドライバーの更新
4. コンピューターを参照してドライバーを検索
5. 一覧から選択 → ディスク使用
6. INFファイルを選択

---

## 9. トラブルシューティング

### 9.1 Code 43 が解消されない

- パッチオフセットが正しいか確認
- 他の検証ロジックが存在する可能性を調査

### 9.2 Code 52 (署名エラー)

- テスト署名モードが有効か確認: `bcdedit | findstr testsigning`
- メモリ整合性を無効化: 設定 → Windowsセキュリティ → デバイスセキュリティ → コア分離

### 9.3 Code 39 (ドライバーロード失敗)

- アプリケーション制御ポリシーをチェック
- `bcdedit /set nointegritychecks on` を実行

---

## 10. 参考: 今回のパッチ詳細

### Steam Deck + ROG Ally Driver の場合

| 項目 | 値 |
|------|-----|
| ドライバー | amdkmdag.sys (32.0.21025.27003) |
| 問題 | AMDGCF verification failed |
| 検証関数VA | 0x140056b50 |
| ファイルオフセット | 0x56550 (353616) |
| 元バイト | 48 89 5C 24 18 |
| パッチバイト | 31 C0 C3 90 90 |
| INF追加行 | "%AMD163F.2%" = ati2mtag_VanGogh, PCI\VEN_1002&DEV_163F&SUBSYS_01231002&REV_AE |

---

## 免責事項

この手順は技術研究目的で提供されています。
ドライバーの改変は自己責任で行ってください。
