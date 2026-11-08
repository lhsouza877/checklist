$ErrorActionPreference = 'Stop'
$port = 8080
$localUrl = "http://localhost:$port/"
$networkUrl = "http://+:$port/"
$account = "$env:USERDOMAIN\$env:USERNAME"

Write-Host "Removendo acesso pela rede e configurando acesso somente local na porta $port..."
$networkReservation = & netsh http show urlacl "url=$networkUrl" 2>&1
if ($LASTEXITCODE -eq 0 -and (($networkReservation -join "`n") -match [regex]::Escape($networkUrl))) {
    & netsh http delete urlacl "url=$networkUrl"
    if ($LASTEXITCODE -ne 0) {
        throw 'Não foi possível remover a reserva HTTP de rede.'
    }
}

$localReservation = & netsh http show urlacl "url=$localUrl" 2>&1
if ($LASTEXITCODE -ne 0 -or (($localReservation -join "`n") -notmatch [regex]::Escape($localUrl))) {
    & netsh http add urlacl "url=$localUrl" "user=$account"
    if ($LASTEXITCODE -ne 0) {
        throw 'Não foi possível reservar o endereço HTTP local. Execute este arquivo como administrador.'
    }
}

$ruleName = 'Checklist Empilhadeira TCP 8080'
Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue | Remove-NetFirewallRule

Write-Host 'Acesso somente local configurado. Execute start.bat para iniciar o servidor.' -ForegroundColor Green
Read-Host 'Pressione Enter para fechar'
