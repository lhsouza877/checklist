# Checklist de empilhadeira

Aplicação web local para registrar a inspeção diária da empilhadeira antes de cada uso. Os 25 itens do equipamento vêm da aba **EMPILHADEIRA** da planilha `NR 12 Check List Equipamentos diversos`. O formulário também registra, em uma aba separada, os cinco EPIs (capacete, óculos, protetor auricular, luvas e botas) e as condições física e psicológica do operador.

## Requisitos

- Windows com Windows PowerShell 5.1 (já incluído no Windows).
- Não requer Node.js, Python, banco de dados ou instalação de pacotes.

## Primeira configuração

1. Abra `configurar-rede.bat` e confirme a solicitação de administrador do Windows. Ele reserva `localhost:8080` para o servidor e remove a regra de firewall de rede do checklist.
2. Execute `start.bat`. Na primeira execução, crie o nome de usuário e a senha do administrador (mínimo de 8 caracteres).
3. Abra `http://localhost:8080`, entre como administrador e cadastre os cinco operadores. Use uma senha temporária exclusiva para cada pessoa e entregue-a em particular.
4. No primeiro acesso, cada operador troca a senha temporária por uma senha pessoal.

O checklist fica acessível somente no computador em que o servidor está rodando; outros computadores e celulares da rede não podem acessá-lo. Mantenha a janela do PowerShell aberta enquanto o sistema estiver em uso. Para encerrar, pressione `Ctrl+C` nela. Os dados ficam em `data\users.json` e `data\checks.json`. Faça cópias de segurança regulares dessa pasta. A data e a hora são registradas pelo relógio do servidor; mantenha-o correto.

## Perfis e registros

- **Operador:** preenche os 25 itens da empilhadeira como Conforme, Não conforme ou Não se aplica e os sete itens de EPIs/condições como Conforme ou Não conforme. Todas as respostas são obrigatórias. Pode acrescentar observações, consulta somente o próprio histórico e, após registrar uma inspeção, baixa um relatório PDF com as 32 respostas ou abre uma conversa do WhatsApp para compartilhá-lo. Uma resposta Não conforme em qualquer seção indica que a inspeção requer atenção. Para o WhatsApp, informe o DDD e o número brasileiro ou um número com código do país. O operador precisa anexar o PDF baixado à conversa antes de enviar; o navegador não pode anexar documentos automaticamente a uma conversa.
- **Administrador:** consulta os registros de todos os operadores, filtra por operador e período e expande as respostas. Pode exportar os resultados apresentados para PDF; o relatório informa o operador selecionado, o período e inclui as inspeções correspondentes. Também cadastra acessos, redefine senhas (exigindo troca no próximo acesso) e remove contas preservando e mantendo filtráveis os históricos de inspeção.
- **Administrador principal (`lucas.santiago`):** escolhe se os novos usuários serão operadores ou administradores e pode alterar o perfil dos demais usuários. Não é possível alterar ou excluir o perfil principal. Mudanças de perfil encerram as sessões existentes da conta afetada.
- **Exclusão de históricos:** somente `lucas.santiago` pode excluir registros individuais pelo botão **Excluir histórico**. A exclusão é permanente e requer confirmação; os demais administradores podem consultar os históricos, mas não excluí-los.
- Outros administradores podem cadastrar e gerenciar operadores, mas não podem criar administradores nem alterar o perfil de usuários.
- O horário é capturado pelo servidor no momento em que o registro é recebido. Os registros são armazenados localmente e não são editáveis pela interface.
- Senhas são armazenadas como hashes PBKDF2-SHA256 com salt individual. As sessões expiram após oito horas e o acesso é limitado à rede local configurada.
- Senhas são armazenadas como hashes PBKDF2-SHA256 com salt individual. As sessões expiram após oito horas e o acesso é limitado ao próprio computador (`localhost`).

## Acesso local

O servidor escuta apenas em `localhost:8080`; não habilite encaminhamento de porta nem exponha esse serviço à rede ou à internet. O script de configuração remove a regra de firewall de rede criada anteriormente, se existir.

## Dados e resolução de problemas

- A porta padrão é `8080`. Para outra porta, altere `server.ps1` e `configurar-rede.ps1` antes de configurar a rede.
- A porta padrão é `8080`. Para outra porta, altere `server.ps1` e `configurar-rede.ps1` antes de executar a configuração local.
- Se outro programa já estiver usando a porta, encerre-o ou escolha outra porta e repita a configuração.
- Os arquivos de dados são criados automaticamente em `data`. Para manter os dados em outra pasta, defina `CHECKLIST_DATA_DIR` antes de iniciar `server.ps1`.
- Se a configuração local falhar, execute novamente `configurar-rede.bat` e confirme a solicitação de administrador do Windows.
- O administrador inicial é criado uma vez. Guarde os dados da pasta `data` com segurança; apagar `users.json` fará o programa solicitar a criação de um novo administrador na inicialização.
