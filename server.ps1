$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$script:ProjectRoot = $PSScriptRoot
$script:PublicRoot = Join-Path $script:ProjectRoot 'public'
$dataRoot = if ($env:CHECKLIST_DATA_DIR) { $env:CHECKLIST_DATA_DIR } else { Join-Path $script:ProjectRoot 'data' }
$script:DataRoot = [System.IO.Path]::GetFullPath($dataRoot)
$script:UsersPath = Join-Path $script:DataRoot 'users.json'
$script:ChecksPath = Join-Path $script:DataRoot 'checks.json'
$script:SessionCookie = 'checklist_session'
$script:SessionLifetime = [TimeSpan]::FromHours(8)
$script:Sessions = @{}
$script:LoginAttempts = @{}
$script:Questions = @(
    [pscustomobject]@{ id = 1; text = 'Verificar condições do motor' },
    [pscustomobject]@{ id = 2; text = 'Sistema hidráulico da torre sem vazamento?' },
    [pscustomobject]@{ id = 3; text = 'Estado geral dos pneus (desgaste, calibração, etc)' },
    [pscustomobject]@{ id = 4; text = 'A torre, corrente e garfos estão em boas condições de uso?' },
    [pscustomobject]@{ id = 5; text = 'Verificar freios de roda e estacionamento' },
    [pscustomobject]@{ id = 6; text = 'O sistema de refrigeração do motor (radiador) apresenta nível de água normal?' },
    [pscustomobject]@{ id = 7; text = 'Operador / Motorista é Habilitado e Qualificado?' },
    [pscustomobject]@{ id = 8; text = 'Funcionamento da torre e identificação do limite máximo de carga.' },
    [pscustomobject]@{ id = 9; text = 'Verificar buzinas e aviso sonoro (RÉ)' },
    [pscustomobject]@{ id = 10; text = 'Isento de vazamento de óleo?' },
    [pscustomobject]@{ id = 11; text = 'Extintor de incêndio (Carga e Validade)' },
    [pscustomobject]@{ id = 12; text = 'O sistema de frenagem, testado pelo operador no momento da inspeção, está funcionando sem problemas?' },
    [pscustomobject]@{ id = 13; text = 'O giroflex está funcionando?' },
    [pscustomobject]@{ id = 14; text = 'A empilhadeira está com os retrovisores em boas condições de uso?' },
    [pscustomobject]@{ id = 15; text = 'Norma operacional visível na área de trabalho' },
    [pscustomobject]@{ id = 16; text = 'Condições da cabine' },
    [pscustomobject]@{ id = 17; text = 'Cinto de segurança' },
    [pscustomobject]@{ id = 18; text = 'Buzina funcionando perfeitamente?' },
    [pscustomobject]@{ id = 19; text = 'Possui extintor de incêndio?' },
    [pscustomobject]@{ id = 20; text = 'Todo o sistema elétrico funciona sem improvisos' },
    [pscustomobject]@{ id = 21; text = 'Condição do Freio de Mão' },
    [pscustomobject]@{ id = 22; text = 'Condição do Garfo' },
    [pscustomobject]@{ id = 23; text = 'Condição de chave de partida' },
    [pscustomobject]@{ id = 24; text = 'Os faróis estão em boas condições?' },
    [pscustomobject]@{ id = 25; text = 'Operador preencheu a APR?' }
)
$script:SafetyQuestions = @(
    [pscustomobject]@{ id = 'helmet'; text = 'Capacete' },
    [pscustomobject]@{ id = 'glasses'; text = 'Óculos de proteção' },
    [pscustomobject]@{ id = 'hearing'; text = 'Protetor auricular' },
    [pscustomobject]@{ id = 'gloves'; text = 'Luvas' },
    [pscustomobject]@{ id = 'boots'; text = 'Botas de segurança' },
    [pscustomobject]@{ id = 'physical'; text = 'Estado físico do operador' },
    [pscustomobject]@{ id = 'psychological'; text = 'Estado psicológico do operador' }
)

function Read-JsonArray {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return ,@()
    }

    $content = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
    if ([string]::IsNullOrWhiteSpace($content)) {
        return ,@()
    }

    return ,@((ConvertFrom-Json -InputObject $content))
}

function Save-JsonArray {
    param(
        [string]$Path,
        [object[]]$Items
    )

    $json = ConvertTo-Json -InputObject @($Items) -Depth 12
    $tempPath = $Path + '.tmp'
    [System.IO.File]::WriteAllText($tempPath, $json, (New-Object System.Text.UTF8Encoding($false)))
    if (Test-Path -LiteralPath $Path) {
        [System.IO.File]::Replace($tempPath, $Path, ($Path + '.bak'))
    }
    else {
        [System.IO.File]::Move($tempPath, $Path)
    }
}

function New-PasswordRecord {
    param([string]$Password)

    $salt = New-Object byte[] 16
    $random = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $random.GetBytes($salt)
    }
    finally {
        $random.Dispose()
    }

    $iterations = 310000
    $derive = [System.Security.Cryptography.Rfc2898DeriveBytes]::new(
        $Password,
        $salt,
        $iterations,
        [System.Security.Cryptography.HashAlgorithmName]::SHA256
    )
    try {
        $hash = $derive.GetBytes(32)
    }
    finally {
        $derive.Dispose()
    }

    return @{
        salt = [Convert]::ToBase64String($salt)
        hash = [Convert]::ToBase64String($hash)
        iterations = $iterations
    }
}

function Test-Password {
    param(
        [string]$Password,
        [object]$User
    )

    $salt = [Convert]::FromBase64String([string]$User.passwordSalt)
    $expected = [Convert]::FromBase64String([string]$User.passwordHash)
    $derive = [System.Security.Cryptography.Rfc2898DeriveBytes]::new(
        $Password,
        $salt,
        [int]$User.passwordIterations,
        [System.Security.Cryptography.HashAlgorithmName]::SHA256
    )
    try {
        $actual = $derive.GetBytes($expected.Length)
    }
    finally {
        $derive.Dispose()
    }

    $difference = 0
    for ($i = 0; $i -lt $expected.Length; $i++) {
        $difference = $difference -bor ($expected[$i] -bxor $actual[$i])
    }
    return $difference -eq 0
}

function Read-Secret {
    param([string]$Prompt)

    $secure = Read-Host $Prompt -AsSecureString
    $pointer = [IntPtr]::Zero
    try {
        $pointer = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
        return [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
    }
    finally {
        if ($pointer -ne [IntPtr]::Zero) {
            [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer)
        }
    }
}

function Initialize-Admin {
    if ($script:Users.Count -gt 0) {
        return
    }

    Write-Host ''
    Write-Host 'Primeira execução: crie a conta de administrador.' -ForegroundColor Cyan
    $username = if ($env:CHECKLIST_BOOTSTRAP_USER) { $env:CHECKLIST_BOOTSTRAP_USER.Trim() } else { (Read-Host 'Usuário de administrador').Trim() }
    $displayName = if ($env:CHECKLIST_BOOTSTRAP_NAME) { $env:CHECKLIST_BOOTSTRAP_NAME.Trim() } else { (Read-Host 'Nome do administrador').Trim() }
    $password = if ($env:CHECKLIST_BOOTSTRAP_PASSWORD) { $env:CHECKLIST_BOOTSTRAP_PASSWORD } else { Read-Secret 'Senha inicial (mínimo 8 caracteres)' }

    if ($username -notmatch '^[a-zA-Z0-9._-]{3,30}$') {
        throw 'Usuário inválido. Use de 3 a 30 letras, números, ponto, hífen ou sublinhado.'
    }
    if ($displayName.Length -lt 2 -or $displayName.Length -gt 80) {
        throw 'O nome do administrador deve ter entre 2 e 80 caracteres.'
    }
    if ($password.Length -lt 8) {
        throw 'A senha inicial deve ter pelo menos 8 caracteres.'
    }

    $record = New-PasswordRecord -Password $password
    [void]$script:Users.Add([pscustomobject]@{
        id = [guid]::NewGuid().ToString('N')
        username = $username
        displayName = $displayName
        role = 'admin'
        passwordSalt = $record.salt
        passwordHash = $record.hash
        passwordIterations = $record.iterations
        mustChangePassword = $false
        createdAt = [DateTime]::UtcNow.ToString('o')
    })
    Save-JsonArray -Path $script:UsersPath -Items @($script:Users)
    [Environment]::SetEnvironmentVariable('CHECKLIST_BOOTSTRAP_USER', $null, 'Process')
    [Environment]::SetEnvironmentVariable('CHECKLIST_BOOTSTRAP_NAME', $null, 'Process')
    [Environment]::SetEnvironmentVariable('CHECKLIST_BOOTSTRAP_PASSWORD', $null, 'Process')
    Write-Host 'Conta de administrador criada.' -ForegroundColor Green
}

function Send-Json {
    param(
        [System.Net.HttpListenerContext]$Context,
        [int]$StatusCode,
        [object]$Value
    )

    $bytes = [System.Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject $Value -Depth 12 -Compress))
    $Context.Response.StatusCode = $StatusCode
    $Context.Response.ContentType = 'application/json; charset=utf-8'
    $Context.Response.ContentLength64 = $bytes.Length
    $Context.Response.OutputStream.Write($bytes, 0, $bytes.Length)
}

function Send-StaticFile {
    param(
        [System.Net.HttpListenerContext]$Context,
        [string]$FileName,
        [string]$ContentType
    )

    $path = Join-Path $script:PublicRoot $FileName
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        Send-Json -Context $Context -StatusCode 404 -Value @{ error = 'Arquivo não encontrado.' }
        return
    }

    $bytes = [System.IO.File]::ReadAllBytes($path)
    $Context.Response.ContentType = $ContentType
    $Context.Response.ContentLength64 = $bytes.Length
    $Context.Response.OutputStream.Write($bytes, 0, $bytes.Length)
}

function Read-RequestJson {
    param([System.Net.HttpListenerContext]$Context)

    if ($Context.Request.ContentLength64 -gt 65536) {
        throw 'O conteúdo enviado excede o limite permitido.'
    }
    $reader = New-Object System.IO.StreamReader($Context.Request.InputStream, $Context.Request.ContentEncoding)
    try {
        $content = $reader.ReadToEnd()
    }
    finally {
        $reader.Dispose()
    }
    if ([string]::IsNullOrWhiteSpace($content)) {
        throw 'O corpo da solicitação está vazio.'
    }
    return ConvertFrom-Json -InputObject $content
}

function Get-JsonField {
    param(
        [object]$Object,
        [string]$Name
    )

    if ($null -eq $Object -or $null -eq $Object.PSObject.Properties[$Name]) {
        return $null
    }
    return $Object.PSObject.Properties[$Name].Value
}

function Get-CurrentUser {
    param([System.Net.HttpListenerContext]$Context)

    $cookie = $Context.Request.Cookies[$script:SessionCookie]
    if (-not $cookie -or -not $script:Sessions.ContainsKey($cookie.Value)) {
        return $null
    }

    $session = $script:Sessions[$cookie.Value]
    if ($session.expiresAt -le [DateTime]::UtcNow) {
        [void]$script:Sessions.Remove($cookie.Value)
        return $null
    }

    foreach ($user in $script:Users) {
        if ($user.id -eq $session.userId) {
            return $user
        }
    }
    return $null
}

function Set-SessionCookie {
    param(
        [System.Net.HttpListenerContext]$Context,
        [string]$Value,
        [bool]$Expired = $false
    )

    $header = "$($script:SessionCookie)=$Value; Path=/; HttpOnly; SameSite=Strict"
    if ($Expired) {
        $header += '; Max-Age=0; Expires=Thu, 01 Jan 1970 00:00:00 GMT'
    }
    else {
        $header += '; Max-Age=28800'
    }
    if ($Context.Request.IsSecureConnection) {
        $header += '; Secure'
    }
    $Context.Response.Headers.Add('Set-Cookie', $header)
}

function Get-PublicUser {
    param([object]$User)

    return [pscustomobject]@{
        id = $User.id
        username = $User.username
        displayName = $User.displayName
        role = $User.role
        mustChangePassword = [bool]$User.mustChangePassword
    }
}

function Test-RootAdmin {
    param([object]$User)

    return $User.role -eq 'admin' -and $User.username -ceq 'lucas.santiago'
}

function Test-RequestOrigin {
    param([System.Net.HttpListenerContext]$Context)

    $origin = $Context.Request.Headers['Origin']
    if (-not $origin) {
        return $true
    }
    return [string]::Equals(
        $origin.TrimEnd('/'),
        $Context.Request.Url.GetLeftPart([System.UriPartial]::Authority).TrimEnd('/'),
        [System.StringComparison]::OrdinalIgnoreCase
    )
}

function Require-User {
    param(
        [System.Net.HttpListenerContext]$Context,
        [string]$Role
    )

    $user = Get-CurrentUser -Context $Context
    if (-not $user) {
        Send-Json -Context $Context -StatusCode 401 -Value @{ error = 'Sua sessão expirou. Entre novamente.' }
        return $null
    }
    if ($Role -and $user.role -ne $Role) {
        Send-Json -Context $Context -StatusCode 403 -Value @{ error = 'Você não tem permissão para esta ação.' }
        return $null
    }
    return $user
}

function Invoke-Api {
    param([System.Net.HttpListenerContext]$Context)

    $request = $Context.Request
    $method = $request.HttpMethod
    $path = $request.Url.AbsolutePath

    if ($method -in @('POST', 'PUT', 'PATCH', 'DELETE') -and -not (Test-RequestOrigin -Context $Context)) {
        Send-Json -Context $Context -StatusCode 403 -Value @{ error = 'Origem da solicitação não autorizada.' }
        return
    }

    if ($method -eq 'GET' -and $path -eq '/api/questions') {
        Send-Json -Context $Context -StatusCode 200 -Value @{
            questions = @($script:Questions)
            safetyQuestions = @($script:SafetyQuestions)
        }
        return
    }

    if ($method -eq 'GET' -and $path -eq '/api/session') {
        $user = Get-CurrentUser -Context $Context
        if (-not $user) {
            Send-Json -Context $Context -StatusCode 200 -Value @{ user = $null }
        }
        else {
            Send-Json -Context $Context -StatusCode 200 -Value @{ user = (Get-PublicUser -User $user) }
        }
        return
    }

    if ($method -eq 'POST' -and $path -eq '/api/login') {
        $ip = $request.RemoteEndPoint.Address.ToString()
        if ($script:LoginAttempts.ContainsKey($ip) -and $script:LoginAttempts[$ip].blockedUntil -gt [DateTime]::UtcNow) {
            Send-Json -Context $Context -StatusCode 429 -Value @{ error = 'Muitas tentativas. Aguarde 10 minutos e tente novamente.' }
            return
        }

        $body = Read-RequestJson -Context $Context
        $username = ([string](Get-JsonField -Object $body -Name 'username')).Trim()
        $password = [string](Get-JsonField -Object $body -Name 'password')
        $user = $script:Users | Where-Object { $_.username -ceq $username } | Select-Object -First 1
        $valid = $false
        if ($user -and $password) {
            $valid = Test-Password -Password $password -User $user
        }
        if (-not $valid) {
            $attempt = if ($script:LoginAttempts.ContainsKey($ip)) { $script:LoginAttempts[$ip] } else { @{ count = 0; blockedUntil = [DateTime]::MinValue } }
            $attempt.count++
            if ($attempt.count -ge 10) {
                $attempt.count = 0
                $attempt.blockedUntil = [DateTime]::UtcNow.AddMinutes(10)
            }
            $script:LoginAttempts[$ip] = $attempt
            Send-Json -Context $Context -StatusCode 401 -Value @{ error = 'Usuário ou senha incorretos.' }
            return
        }

        [void]$script:LoginAttempts.Remove($ip)
        $token = [guid]::NewGuid().ToString('N')
        $script:Sessions[$token] = @{
            userId = $user.id
            expiresAt = [DateTime]::UtcNow.Add($script:SessionLifetime)
        }
        Set-SessionCookie -Context $Context -Value $token
        Send-Json -Context $Context -StatusCode 200 -Value @{ user = (Get-PublicUser -User $user) }
        return
    }

    if ($method -eq 'POST' -and $path -eq '/api/logout') {
        $cookie = $request.Cookies[$script:SessionCookie]
        if ($cookie) {
            [void]$script:Sessions.Remove($cookie.Value)
        }
        Set-SessionCookie -Context $Context -Value '' -Expired $true
        Send-Json -Context $Context -StatusCode 200 -Value @{ ok = $true }
        return
    }

    $currentUser = Require-User -Context $Context -Role $null
    if (-not $currentUser) {
        return
    }

    if ($method -eq 'POST' -and $path -eq '/api/password') {
        $body = Read-RequestJson -Context $Context
        $oldPassword = [string](Get-JsonField -Object $body -Name 'currentPassword')
        $newPassword = [string](Get-JsonField -Object $body -Name 'newPassword')
        if (-not (Test-Password -Password $oldPassword -User $currentUser)) {
            Send-Json -Context $Context -StatusCode 400 -Value @{ error = 'A senha atual está incorreta.' }
            return
        }
        if ($newPassword.Length -lt 8 -or $newPassword.Length -gt 200) {
            Send-Json -Context $Context -StatusCode 400 -Value @{ error = 'A nova senha deve ter entre 8 e 200 caracteres.' }
            return
        }
        $record = New-PasswordRecord -Password $newPassword
        $currentUser.passwordSalt = $record.salt
        $currentUser.passwordHash = $record.hash
        $currentUser.passwordIterations = $record.iterations
        $currentUser.mustChangePassword = $false
        Save-JsonArray -Path $script:UsersPath -Items @($script:Users)
        Send-Json -Context $Context -StatusCode 200 -Value @{ user = (Get-PublicUser -User $currentUser) }
        return
    }

    if ([bool]$currentUser.mustChangePassword -and -not ($method -eq 'GET' -and $path -eq '/api/session')) {
        Send-Json -Context $Context -StatusCode 403 -Value @{ error = 'Altere sua senha antes de continuar.' }
        return
    }

    if ($method -eq 'POST' -and $path -eq '/api/checks') {
        if ($currentUser.role -ne 'operator') {
            Send-Json -Context $Context -StatusCode 403 -Value @{ error = 'Somente operadores podem preencher o checklist.' }
            return
        }
        $body = Read-RequestJson -Context $Context
        $answerMap = @{}
        foreach ($answer in @((Get-JsonField -Object $body -Name 'answers'))) {
            $id = [string](Get-JsonField -Object $answer -Name 'itemId')
            if ($id -notmatch '^\d+$' -or $answerMap.ContainsKey($id)) {
                Send-Json -Context $Context -StatusCode 400 -Value @{ error = 'As respostas do checklist são inválidas.' }
                return
            }
            $value = [string](Get-JsonField -Object $answer -Name 'value')
            if ($value -notin @('ok', 'problem', 'na')) {
                Send-Json -Context $Context -StatusCode 400 -Value @{ error = 'Selecione uma resposta válida para cada item.' }
                return
            }
            $answerMap[$id] = $value
        }
        if ($answerMap.Count -ne $script:Questions.Count) {
            Send-Json -Context $Context -StatusCode 400 -Value @{ error = 'Responda todos os itens antes de enviar o checklist.' }
            return
        }

        $safetyAnswerMap = @{}
        foreach ($answer in @((Get-JsonField -Object $body -Name 'safetyAnswers'))) {
            $id = [string](Get-JsonField -Object $answer -Name 'itemId')
            if ([string]::IsNullOrWhiteSpace($id) -or $safetyAnswerMap.ContainsKey($id)) {
                Send-Json -Context $Context -StatusCode 400 -Value @{ error = 'As respostas da aba EPIs e condições são inválidas.' }
                return
            }
            $value = [string](Get-JsonField -Object $answer -Name 'value')
            if ($value -notin @('ok', 'problem')) {
                Send-Json -Context $Context -StatusCode 400 -Value @{ error = 'Selecione Conforme ou Não conforme para cada EPI e condição.' }
                return
            }
            $safetyAnswerMap[$id] = $value
        }
        if ($safetyAnswerMap.Count -ne $script:SafetyQuestions.Count) {
            Send-Json -Context $Context -StatusCode 400 -Value @{ error = 'Responda todos os EPIs e as condições físicas e psicológicas antes de registrar.' }
            return
        }
        foreach ($question in $script:SafetyQuestions) {
            if (-not $safetyAnswerMap.ContainsKey($question.id)) {
                Send-Json -Context $Context -StatusCode 400 -Value @{ error = 'Responda todos os EPIs e as condições físicas e psicológicas antes de registrar.' }
                return
            }
        }

        $answerRecords = @(
            foreach ($question in $script:Questions) {
                $key = [string]$question.id
                [pscustomobject]@{
                    itemId = $question.id
                    question = $question.text
                    value = $answerMap[$key]
                }
            }
        )
        $safetyAnswerRecords = @(
            foreach ($question in $script:SafetyQuestions) {
                [pscustomobject]@{
                    itemId = $question.id
                    question = $question.text
                    value = $safetyAnswerMap[$question.id]
                }
            }
        )
        $notes = [string](Get-JsonField -Object $body -Name 'notes')
        if ($notes.Length -gt 2000) {
            Send-Json -Context $Context -StatusCode 400 -Value @{ error = 'A observação deve ter no máximo 2.000 caracteres.' }
            return
        }

        $check = [pscustomobject]@{
            id = [guid]::NewGuid().ToString('N')
            createdAt = [DateTime]::UtcNow.ToString('o')
            operatorId = $currentUser.id
            operatorName = $currentUser.displayName
            answers = $answerRecords
            safetyAnswers = $safetyAnswerRecords
            notes = $notes.Trim()
        }
        [void]$script:Checks.Add($check)
        Save-JsonArray -Path $script:ChecksPath -Items @($script:Checks)
        Send-Json -Context $Context -StatusCode 201 -Value @{ check = $check }
        return
    }

    if ($method -eq 'GET' -and $path -eq '/api/checks') {
        if ($currentUser.role -eq 'admin') {
            $visibleChecks = @($script:Checks | Sort-Object -Property createdAt -Descending)
        }
        else {
            $visibleChecks = @($script:Checks | Where-Object { $_.operatorId -eq $currentUser.id } | Sort-Object -Property createdAt -Descending)
        }
        Send-Json -Context $Context -StatusCode 200 -Value @{ checks = $visibleChecks }
        return
    }

    if ($method -eq 'DELETE' -and $path -match '^/api/checks/([a-fA-F0-9]{32})$') {
        if (-not (Test-RootAdmin -User $currentUser)) {
            Send-Json -Context $Context -StatusCode 403 -Value @{ error = 'Somente lucas.santiago pode excluir históricos de inspeção.' }
            return
        }

        $checkId = $Matches[1]
        $checkIndex = -1
        for ($i = 0; $i -lt $script:Checks.Count; $i++) {
            if ($script:Checks[$i].id -ceq $checkId) {
                $checkIndex = $i
                break
            }
        }
        if ($checkIndex -lt 0) {
            Send-Json -Context $Context -StatusCode 404 -Value @{ error = 'Histórico de inspeção não encontrado.' }
            return
        }

        $deletedCheck = $script:Checks[$checkIndex]
        $remainingChecks = @(
            for ($i = 0; $i -lt $script:Checks.Count; $i++) {
                if ($i -ne $checkIndex) { $script:Checks[$i] }
            }
        )
        Save-JsonArray -Path $script:ChecksPath -Items $remainingChecks
        [void]$script:Checks.RemoveAt($checkIndex)
        Send-Json -Context $Context -StatusCode 200 -Value @{
            ok = $true
            operatorName = $deletedCheck.operatorName
        }
        return
    }

    if ($method -eq 'GET' -and $path -eq '/api/users') {
        if ($currentUser.role -ne 'admin') {
            Send-Json -Context $Context -StatusCode 403 -Value @{ error = 'Apenas o administrador pode consultar usuários.' }
            return
        }
        $publicUsers = @($script:Users | ForEach-Object { Get-PublicUser -User $_ } | Sort-Object -Property displayName)
        Send-Json -Context $Context -StatusCode 200 -Value @{
            users = $publicUsers
            canAssignRoles = (Test-RootAdmin -User $currentUser)
        }
        return
    }

    if ($method -eq 'POST' -and $path -eq '/api/users') {
        if ($currentUser.role -ne 'admin') {
            Send-Json -Context $Context -StatusCode 403 -Value @{ error = 'Apenas o administrador pode criar usuários.' }
            return
        }
        $body = Read-RequestJson -Context $Context
        $username = ([string](Get-JsonField -Object $body -Name 'username')).Trim()
        $displayName = ([string](Get-JsonField -Object $body -Name 'displayName')).Trim()
        $password = [string](Get-JsonField -Object $body -Name 'temporaryPassword')
        $requestedRole = Get-JsonField -Object $body -Name 'role'
        if ($null -eq $requestedRole -or [string]::IsNullOrWhiteSpace([string]$requestedRole)) {
            $requestedRole = 'operator'
        }
        $requestedRole = [string]$requestedRole
        if ($username -notmatch '^[a-zA-Z0-9._-]{3,30}$') {
            Send-Json -Context $Context -StatusCode 400 -Value @{ error = 'O usuário deve ter de 3 a 30 caracteres: letras, números, ponto, hífen ou sublinhado.' }
            return
        }
        if ($displayName.Length -lt 2 -or $displayName.Length -gt 80) {
            Send-Json -Context $Context -StatusCode 400 -Value @{ error = 'O nome deve ter entre 2 e 80 caracteres.' }
            return
        }
        if ($password.Length -lt 8 -or $password.Length -gt 200) {
            Send-Json -Context $Context -StatusCode 400 -Value @{ error = 'A senha temporária deve ter entre 8 e 200 caracteres.' }
            return
        }
        if ($requestedRole -notin @('operator', 'admin')) {
            Send-Json -Context $Context -StatusCode 400 -Value @{ error = 'Selecione um perfil válido.' }
            return
        }
        if ($requestedRole -eq 'admin' -and -not (Test-RootAdmin -User $currentUser)) {
            Send-Json -Context $Context -StatusCode 403 -Value @{ error = 'Somente lucas.santiago pode criar administradores.' }
            return
        }
        if ($script:Users | Where-Object { $_.username -ieq $username }) {
            Send-Json -Context $Context -StatusCode 409 -Value @{ error = 'Esse nome de usuário já existe.' }
            return
        }
        if ($requestedRole -eq 'operator' -and @($script:Users | Where-Object { $_.role -eq 'operator' }).Count -ge 5) {
            Send-Json -Context $Context -StatusCode 409 -Value @{ error = 'O limite de cinco operadores já foi atingido.' }
            return
        }

        $record = New-PasswordRecord -Password $password
        $newUser = [pscustomobject]@{
            id = [guid]::NewGuid().ToString('N')
            username = $username
            displayName = $displayName
            role = $requestedRole
            passwordSalt = $record.salt
            passwordHash = $record.hash
            passwordIterations = $record.iterations
            mustChangePassword = $true
            createdAt = [DateTime]::UtcNow.ToString('o')
        }
        [void]$script:Users.Add($newUser)
        Save-JsonArray -Path $script:UsersPath -Items @($script:Users)
        Send-Json -Context $Context -StatusCode 201 -Value @{ user = (Get-PublicUser -User $newUser) }
        return
    }

    if ($method -eq 'POST' -and $path -match '^/api/users/([a-fA-F0-9]{32})/reset-password$') {
        if ($currentUser.role -ne 'admin') {
            Send-Json -Context $Context -StatusCode 403 -Value @{ error = 'Apenas o administrador pode redefinir senhas.' }
            return
        }

        $userId = $Matches[1]
        $targetUser = $script:Users | Where-Object { $_.id -eq $userId -and $_.role -in @('operator', 'admin') } | Select-Object -First 1
        if (-not $targetUser) {
            Send-Json -Context $Context -StatusCode 404 -Value @{ error = 'Usuário não encontrado.' }
            return
        }
        if ($targetUser.role -eq 'admin' -and -not (Test-RootAdmin -User $currentUser)) {
            Send-Json -Context $Context -StatusCode 403 -Value @{ error = 'Somente lucas.santiago pode redefinir a senha de outro administrador.' }
            return
        }

        $body = Read-RequestJson -Context $Context
        $password = [string](Get-JsonField -Object $body -Name 'temporaryPassword')
        if ($password.Length -lt 8 -or $password.Length -gt 200) {
            Send-Json -Context $Context -StatusCode 400 -Value @{ error = 'A senha temporária deve ter entre 8 e 200 caracteres.' }
            return
        }

        $record = New-PasswordRecord -Password $password
        $targetUser.passwordSalt = $record.salt
        $targetUser.passwordHash = $record.hash
        $targetUser.passwordIterations = $record.iterations
        $targetUser.mustChangePassword = $true
        foreach ($token in @($script:Sessions.Keys)) {
            if ($script:Sessions[$token].userId -eq $targetUser.id) {
                [void]$script:Sessions.Remove($token)
            }
        }
        Save-JsonArray -Path $script:UsersPath -Items @($script:Users)
        Send-Json -Context $Context -StatusCode 200 -Value @{ user = (Get-PublicUser -User $targetUser) }
        return
    }

    if ($method -eq 'PATCH' -and $path -match '^/api/users/([a-fA-F0-9]{32})/role$') {
        if (-not (Test-RootAdmin -User $currentUser)) {
            Send-Json -Context $Context -StatusCode 403 -Value @{ error = 'Somente lucas.santiago pode atribuir perfis de operador e administrador.' }
            return
        }

        $userId = $Matches[1]
        $targetUser = $script:Users | Where-Object { $_.id -eq $userId } | Select-Object -First 1
        if (-not $targetUser) {
            Send-Json -Context $Context -StatusCode 404 -Value @{ error = 'Usuário não encontrado.' }
            return
        }
        if ($targetUser.username -ceq 'lucas.santiago') {
            Send-Json -Context $Context -StatusCode 403 -Value @{ error = 'O perfil do administrador principal não pode ser alterado.' }
            return
        }

        $body = Read-RequestJson -Context $Context
        $newRole = [string](Get-JsonField -Object $body -Name 'role')
        if ($newRole -notin @('operator', 'admin')) {
            Send-Json -Context $Context -StatusCode 400 -Value @{ error = 'Selecione um perfil válido.' }
            return
        }
        if ($newRole -eq $targetUser.role) {
            Send-Json -Context $Context -StatusCode 200 -Value @{ user = (Get-PublicUser -User $targetUser) }
            return
        }
        if ($newRole -eq 'operator' -and @($script:Users | Where-Object { $_.role -eq 'operator' }).Count -ge 5) {
            Send-Json -Context $Context -StatusCode 409 -Value @{ error = 'O limite de cinco operadores já foi atingido.' }
            return
        }

        $targetUser.role = $newRole
        foreach ($token in @($script:Sessions.Keys)) {
            if ($script:Sessions[$token].userId -eq $targetUser.id) {
                [void]$script:Sessions.Remove($token)
            }
        }
        Save-JsonArray -Path $script:UsersPath -Items @($script:Users)
        Send-Json -Context $Context -StatusCode 200 -Value @{ user = (Get-PublicUser -User $targetUser) }
        return
    }

    if ($method -eq 'DELETE' -and $path -match '^/api/users/([a-fA-F0-9]{32})$') {
        if ($currentUser.role -ne 'admin') {
            Send-Json -Context $Context -StatusCode 403 -Value @{ error = 'Apenas o administrador pode excluir operadores.' }
            return
        }

        $userId = $Matches[1]
        $userIndex = -1
        for ($i = 0; $i -lt $script:Users.Count; $i++) {
            if ($script:Users[$i].id -eq $userId) {
                $userIndex = $i
                break
            }
        }
        if ($userIndex -lt 0) {
            Send-Json -Context $Context -StatusCode 404 -Value @{ error = 'Usuário não encontrado.' }
            return
        }
        if ($script:Users[$userIndex].username -ceq 'lucas.santiago') {
            Send-Json -Context $Context -StatusCode 403 -Value @{ error = 'O administrador principal não pode ser excluído.' }
            return
        }
        if ($script:Users[$userIndex].role -eq 'admin' -and -not (Test-RootAdmin -User $currentUser)) {
            Send-Json -Context $Context -StatusCode 403 -Value @{ error = 'Somente lucas.santiago pode excluir outro administrador.' }
            return
        }

        $deletedUser = $script:Users[$userIndex]
        [void]$script:Users.RemoveAt($userIndex)
        foreach ($token in @($script:Sessions.Keys)) {
            if ($script:Sessions[$token].userId -eq $deletedUser.id) {
                [void]$script:Sessions.Remove($token)
            }
        }
        Save-JsonArray -Path $script:UsersPath -Items @($script:Users)
        Send-Json -Context $Context -StatusCode 200 -Value @{
            ok = $true
            displayName = $deletedUser.displayName
            historyPreserved = $true
        }
        return
    }

    Send-Json -Context $Context -StatusCode 404 -Value @{ error = 'Solicitação não encontrada.' }
}

if (-not (Test-Path -LiteralPath $script:DataRoot)) {
    [void](New-Item -ItemType Directory -Path $script:DataRoot -Force)
}
$script:Users = New-Object System.Collections.ArrayList
foreach ($user in (Read-JsonArray -Path $script:UsersPath)) {
    [void]$script:Users.Add($user)
}
$script:Checks = New-Object System.Collections.ArrayList
foreach ($check in (Read-JsonArray -Path $script:ChecksPath)) {
    [void]$script:Checks.Add($check)
}
Initialize-Admin

$prefix = if ($env:CHECKLIST_URL_PREFIX) { $env:CHECKLIST_URL_PREFIX } else { 'http://+:8080/' }
if (-not $prefix.EndsWith('/')) {
    $prefix += '/'
}
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add($prefix)
$listener.Start()

Write-Host ''
Write-Host "Checklist da empilhadeira disponível em $prefix" -ForegroundColor Green
Write-Host 'Pressione Ctrl+C para encerrar o servidor.'
Write-Host ''

try {
    while ($listener.IsListening) {
        $context = $listener.GetContext()
        $context.Response.Headers['X-Content-Type-Options'] = 'nosniff'
        $context.Response.Headers['X-Frame-Options'] = 'DENY'
        $context.Response.Headers['Referrer-Policy'] = 'no-referrer'
        $context.Response.Headers['Cache-Control'] = 'no-store'
        $context.Response.Headers['Content-Security-Policy'] = "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; base-uri 'none'; frame-ancestors 'none'; form-action 'self'"

        try {
            $path = $context.Request.Url.AbsolutePath
            if ($path -eq '/api' -or $path.StartsWith('/api/')) {
                Invoke-Api -Context $context
            }
            elseif ($context.Request.HttpMethod -eq 'GET' -and $path -eq '/') {
                Send-StaticFile -Context $context -FileName 'index.html' -ContentType 'text/html; charset=utf-8'
            }
            elseif ($context.Request.HttpMethod -eq 'GET' -and $path -eq '/app.js') {
                Send-StaticFile -Context $context -FileName 'app.js' -ContentType 'text/javascript; charset=utf-8'
            }
            elseif ($context.Request.HttpMethod -eq 'GET' -and $path -eq '/styles.css') {
                Send-StaticFile -Context $context -FileName 'styles.css' -ContentType 'text/css; charset=utf-8'
            }
            elseif ($context.Request.HttpMethod -eq 'GET' -and $path -eq '/logo-mizu.png') {
                Send-StaticFile -Context $context -FileName 'logo-mizu.png' -ContentType 'image/png'
            }
            else {
                Send-Json -Context $context -StatusCode 404 -Value @{ error = 'Página não encontrada.' }
            }
        }
        catch {
            Write-Host ("Erro ao atender solicitação {0}: {1}" -f $context.Request.Url.AbsolutePath, $_.Exception.GetType().Name) -ForegroundColor Red
            if (-not $context.Response.OutputStream.CanWrite) {
                continue
            }
            try {
                Send-Json -Context $context -StatusCode 500 -Value @{ error = 'Não foi possível concluir a solicitação. Tente novamente.' }
            }
            catch {
                Write-Host 'Não foi possível enviar a resposta de erro.' -ForegroundColor Red
            }
        }
        finally {
            $context.Response.Close()
        }
    }
}
finally {
    $listener.Stop()
    $listener.Close()
}
