[CmdletBinding()]
param(
    [string]$ContextFile,
    [string]$Prompt,
    [string]$WorkDir,
    [switch]$Continue
)

# 1. カレントディレクトリを移動
if ($WorkDir -and (Test-Path -LiteralPath $WorkDir)) {
    Set-Location -LiteralPath $WorkDir
}

# 2. 直前のセッションを再開する場合
if ($Continue) {
    Write-Host "[Antigravity CLI] 直前のセッションを再開します..." -ForegroundColor Cyan
    agy -c
    exit
}

# 3. コンテキストファイルの読み込み
$contextText = ""
if ($ContextFile -and (Test-Path -LiteralPath $ContextFile)) {
    try {
        $contextText = Get-Content -LiteralPath $ContextFile -Raw -Encoding UTF8
    } catch {
        Write-Warning "コンテキストファイルの読み込みに失敗しました: $_"
    }
}

# 4. プロンプトの決定
$finalPrompt = $Prompt

if ([string]::IsNullOrWhiteSpace($finalPrompt)) {
    # Emacs側で指示が未入力だった場合、PowerShell画面上で対話入力
    Clear-Host
    Write-Host "========================================================================" -ForegroundColor Cyan
    Write-Host "  Antigravity CLI (agy) - Emacs 連携" -ForegroundColor Cyan
    if ($ContextFile -and $contextText) {
        $lines = ($contextText -split "`r?`n").Count
        $chars = $contextText.Length
        Write-Host "  Emacs からテキストを受信しました ($lines 行 / $chars 文字)" -ForegroundColor Yellow
    }
    Write-Host "  ※テキストはクリップボードにもコピー済みです (Ctrl+V で貼付可)" -ForegroundColor DarkGray
    Write-Host "========================================================================" -ForegroundColor Cyan
    Write-Host ""
    $inputPrompt = Read-Host "指示内容を入力してください (未入力のままEnterでテキストのみで起動)"
    Write-Host ""
    if (-not [string]::IsNullOrWhiteSpace($inputPrompt)) {
        $finalPrompt = $inputPrompt
    }
}

# 5. agy の起動
if (-not [string]::IsNullOrWhiteSpace($finalPrompt) -and -not [string]::IsNullOrWhiteSpace($contextText)) {
    if ($contextText.Length -gt 3000) {
        $combinedPrompt = "$finalPrompt`n`n(以下のファイルに記載されたコード/テキストを参照してください: $ContextFile)"
    } else {
        $combinedPrompt = "$finalPrompt`n`n$contextText"
    }
    agy -i $combinedPrompt
} elseif (-not [string]::IsNullOrWhiteSpace($contextText)) {
    if ($contextText.Length -gt 3000) {
        agy -i "以下のファイルに記載されたコード/テキストを参照してください: $ContextFile"
    } else {
        agy -i "以下のコード／テキストを参照してください:`n`n$contextText"
    }
} elseif (-not [string]::IsNullOrWhiteSpace($finalPrompt)) {
    agy -i $finalPrompt
} else {
    agy
}
