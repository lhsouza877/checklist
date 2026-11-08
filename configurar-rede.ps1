$ErrorActionPreference = 'Stop'
$port = 8080
$url = "http://+:$port/"
$account = "$env:USERDOMAIN\$env:USERNAME"

Write-Host "Configurando acesso pela rede local na porta $port..."
& netsh http add urlacl "url=$url" "user=$account"
if ($LASTEXITCODE -ne 0) {
    throw 'Não foi possível reservar o endereço HTTP. Execute este arquivo como administrador.'
}

$ruleName = 'Checklist Empilhadeira TCP 8080'
$existingRule = Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue
if (-not $existingRule) {
    New-NetFirewallRule `
        -DisplayName $ruleName `
        -Direction Inbound `
        -Action Allow `
        -Protocol TCP `
        -LocalPort $port `
        -RemoteAddress LocalSubnet `
        -Profile Private,Domain | Out-Null
}

Write-Host 'Acesso local configurado. Execute start.bat para iniciar o servidor.' -ForegroundColor Green
Read-Host 'Pressione Enter para fechar'
