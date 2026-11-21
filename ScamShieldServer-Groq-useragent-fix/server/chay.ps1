# ScamShield Server - doc cau hinh tu .env va chay bang Waitress
$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath $PSScriptRoot

$envFile = Join-Path $PSScriptRoot '.env'
$exampleFile = Join-Path $PSScriptRoot '.env.example'

if (-not (Test-Path -LiteralPath $envFile)) {
    if (-not (Test-Path -LiteralPath $exampleFile)) {
        throw 'Khong tim thay .env.example de tao file cau hinh.'
    }
    Copy-Item -LiteralPath $exampleFile -Destination $envFile
    Write-Host 'Da tao file .env tu .env.example.' -ForegroundColor Yellow
    Write-Host 'Hay mo .env, dien GROQ_API_KEY va ADMIN_KEY, sau do chay lai .\chay.ps1.' -ForegroundColor Yellow
    exit 1
}

# Nap cac bien trong .env vao rieng tien trinh nay; khong hien gia tri khoa ra man hinh.
$dotenvLines = [System.IO.File]::ReadAllLines($envFile, [System.Text.Encoding]::UTF8)
foreach ($line in $dotenvLines) {
    $trimmed = $line.Trim()
    if ([string]::IsNullOrWhiteSpace($trimmed) -or $trimmed.StartsWith('#')) { continue }
    if ($trimmed.StartsWith('export ')) { $trimmed = $trimmed.Substring(7).TrimStart() }

    $match = [regex]::Match($trimmed, '^([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$')
    if (-not $match.Success) { continue }

    $name = $match.Groups[1].Value
    $value = $match.Groups[2].Value.Trim()
    if ($value.Length -ge 2 -and (($value.StartsWith('"') -and $value.EndsWith('"')) -or ($value.StartsWith("'") -and $value.EndsWith("'")))) {
        $value = $value.Substring(1, $value.Length - 2)
    } else {
        $value = [regex]::Replace($value, '\s+#.*$', '').TrimEnd()
    }
    [Environment]::SetEnvironmentVariable($name, $value, 'Process')
}

$provider = $env:AI_PROVIDER
if ([string]::IsNullOrWhiteSpace($provider)) { $provider = 'groq' }
$provider = $provider.Trim().ToLowerInvariant()
$env:AI_PROVIDER = $provider

if ($provider -eq 'xai') {
    throw 'AI_PROVIDER=xai la Grok cua xAI, khong phai Groq. Hay doi thanh AI_PROVIDER=groq, XAI_API_KEY thanh GROQ_API_KEY va dung API key tao trong Groq Console.'
}

if ($provider -eq 'groq') {
    if ([string]::IsNullOrWhiteSpace($env:GROQ_API_KEY) -or $env:GROQ_API_KEY -match 'PASTE_|YOUR_|CHANGE_ME') {
        throw 'GROQ_API_KEY chua duoc dien trong file .env. Hay tao API key trong Groq Console > API Keys, dien vao .env roi chay lai.'
    }
} elseif ($provider -eq 'gemini') {
    if ([string]::IsNullOrWhiteSpace($env:GEMINI_API_KEY) -or $env:GEMINI_API_KEY -match 'PASTE_|YOUR_|CHANGE_ME') {
        throw 'GEMINI_API_KEY chua duoc dien trong file .env. Hay dien API key moi roi chay lai.'
    }
} elseif ($provider -eq 'openrouter') {
    if ([string]::IsNullOrWhiteSpace($env:OPENROUTER_API_KEY) -or $env:OPENROUTER_API_KEY -match 'PASTE_|YOUR_|CHANGE_ME') {
        throw 'OPENROUTER_API_KEY chua duoc dien trong file .env.'
    }
} elseif ($provider -ne 'rules') {
    throw 'AI_PROVIDER khong hop le. Hay chon groq, gemini, openrouter hoac rules.'
}

if ([string]::IsNullOrWhiteSpace($env:ADMIN_KEY) -or $env:ADMIN_KEY -match 'REPLACE_|CHANGE_ME|doi-thanh') {
    throw 'ADMIN_KEY chua duoc thay bang khoa rieng trong file .env.'
}
if ([string]::IsNullOrWhiteSpace($env:GEMINI_MODEL)) { $env:GEMINI_MODEL = 'gemini-3.8-flash' }
if ([string]::IsNullOrWhiteSpace($env:GROQ_MODEL)) { $env:GROQ_MODEL = 'openai/gpt-oss-20b' }
if ([string]::IsNullOrWhiteSpace($env:GROQ_VISION_MODEL)) { $env:GROQ_VISION_MODEL = 'qwen/qwen3.8-27b' }
if ([string]::IsNullOrWhiteSpace($env:GROQ_TIMEOUT_SECONDS)) { $env:GROQ_TIMEOUT_SECONDS = '120' }

$python = Join-Path $PSScriptRoot '.venv\Scripts\python.exe'
if (-not (Test-Path -LiteralPath $python)) {
    $pyLauncher = Get-Command py -ErrorAction SilentlyContinue
    if ($pyLauncher) {
        Write-Host 'Dang tao moi truong Python .venv...' -ForegroundColor Yellow
        & $pyLauncher.Source -3 -m venv (Join-Path $PSScriptRoot '.venv')
    } else {
        $pythonCommand = Get-Command python -ErrorAction SilentlyContinue
        if (-not $pythonCommand) { throw 'Khong tim thay Python. Hay cai Python 3 va chon Add Python to PATH.' }
        Write-Host 'Dang tao moi truong Python .venv...' -ForegroundColor Yellow
        & $pythonCommand.Source -m venv (Join-Path $PSScriptRoot '.venv')
    }
    if ($LASTEXITCODE -ne 0) { throw 'Khong tao duoc .venv.' }
}
if (-not (Test-Path -LiteralPath $python)) { throw 'Khong tim thay Python trong .venv.' }

# Kiem tra thu vien ma khong tao NativeCommandError khi .venv moi chua co package.
# Python luon in danh sach package con thieu va tra ma 0 khi chi thieu package.
$missingModules = & $python -c "import importlib.util; names=('flask','jwt','waitress'); print(' '.join(name for name in names if importlib.util.find_spec(name) is None))"
if ($LASTEXITCODE -ne 0) {
    throw 'Khong the kiem tra thu vien Python trong .venv. Hay kiem tra lai ban cai Python.'
}
if (-not [string]::IsNullOrWhiteSpace(($missingModules -join ' ').Trim())) {
    Write-Host ("Thieu thu vien: " + ($missingModules -join ' ')) -ForegroundColor Yellow
    Write-Host 'Dang cai/cap nhat thu vien server...' -ForegroundColor Yellow
    & $python -m pip install --upgrade pip
    if ($LASTEXITCODE -ne 0) { throw 'Khong cap nhat duoc pip.' }
    & $python -m pip install -r (Join-Path $PSScriptRoot 'requirements.txt')
    if ($LASTEXITCODE -ne 0) { throw 'Cai dat requirements.txt that bai.' }
}

$model = $env:GROQ_MODEL
if ($provider -eq 'gemini') { $model = $env:GEMINI_MODEL }
if ($provider -eq 'groq') { $model = $env:GROQ_MODEL }
if ($provider -eq 'openrouter') { $model = 'openrouter/free' }
Write-Host ''
Write-Host 'SCAMSHIELD SERVER' -ForegroundColor Cyan
Write-Host "AI provider: $provider" -ForegroundColor Green
Write-Host "AI model: $model" -ForegroundColor Green
if ($provider -eq 'groq') { Write-Host "AI vision model: $env:GROQ_VISION_MODEL" -ForegroundColor Green }
Write-Host 'Trang quan tri: http://127.0.0.1:8000/admin' -ForegroundColor Cyan
Write-Host 'API health: http://127.0.0.1:8000/health' -ForegroundColor Cyan
Write-Host 'Server dung Waitress. Giu cua so nay mo; nhan Ctrl+C de dung.' -ForegroundColor Yellow
Write-Host ''

$serveCode = "import os; from waitress import serve; from server import app; serve(app, host='0.0.0.0', port=int(os.environ.get('PORT', '8000')), threads=16)"
& $python -c $serveCode
if ($LASTEXITCODE -ne 0) {
    throw "Server ket thuc voi ma loi $LASTEXITCODE."
}
