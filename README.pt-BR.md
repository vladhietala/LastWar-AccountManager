# LastWar Account Manager

Um sistema de gerenciamento de Registro do Windows baseado em PowerShell para alternar entre múltiplas contas no "The Last War: Survival Game".

## Recursos

- **Suporte Multi-Conta**: Alterne facilmente entre diferentes contas do jogo
- **Backup Automático**: Cria backups com timestamp e deduplicação SHA256
- **Gerenciamento de Registro**: Lida com importação/exportação de configurações de registro do jogo
- **Monitoramento de Processo**: Inicia automaticamente o jogo e monitora o ciclo de vida do processo
- **Log de Erros**: Tratamento abrangente de erros e logging

## Requisitos

- Windows OS
- PowerShell Core
- The Last War: Survival Game instalado em `%LOCALAPPDATA%\FunFly\Last War-Survival Game\`
- Não é necessário executar o gerenciador como administrador.

## Início Rápido

### Uso Básico

```powershell
# Iniciar jogo com conta específica
.\Start-LastWar.ps1 -Account NomeDaConta

# Iniciar com retenção de backup personalizada
.\Start-LastWar.ps1 -Account NomeDaConta -MaxBackups 15

# Iniciar com log de erros
.\Tools\Launch-LastWar.ps1 -Account NomeDaConta
```

### Adicionando uma Nova Conta

1. Exporte as configurações de registro do jogo para um arquivo `.reg`
2. Coloque o arquivo na pasta `Accounts/` com um nome descritivo
3. O script detectará automaticamente como uma conta disponível

## Estrutura do Projeto

```
.
├── Accounts/           # Arquivos de registro de conta (.reg)
├── Backups/           # Backups automáticos com timestamp (organizados por conta)
├── Tools/             # Scripts utilitários
│   ├── Compare-LastWarKeys.ps1    # Utilitário de comparação de registro
│   ├── ConvertFrom-RegHex.ps1     # Decodificador de valores hex do registro
│   └── Launch-LastWar.ps1         # Wrapper com log de erros
├── Start-LastWar.ps1              # Script principal
├── Start-LastWar.Functions.ps1    # Funções compartilhadas
├── Create-Shortcuts.ps1           # Gerenciador de atalhos do Menu Iniciar
└── CLAUDE.md                      # Documentação para desenvolvedores
```

## Como Funciona

1. **Backup**: Cria backup do estado atual da conta (com deduplicação)
2. **Import**: Carrega as configurações de registro da conta selecionada
3. **Launch**: Inicia o launcher do jogo
4. **Monitor**: Aguarda o processo do jogo iniciar e finalizar
5. **Export**: Salva quaisquer alterações de registro de volta ao arquivo da conta

## Utilitários

### Comparar Chaves de Registro

```powershell
.\Tools\Compare-LastWarKeys.ps1 -KeyPath1 "HKCU:\Software\FunFly\LastWar-Account1" `
                                -KeyPath2 "HKCU:\Software\FunFly\LastWar-Account2" `
                                -OutRegFile "C:\Backups\Diff.reg"
```

### Decodificar Valores Hex do Registro

```powershell
.\Tools\ConvertFrom-RegHex.ps1 -RegFilePath ".\Accounts\Account.reg"
.\Tools\ConvertFrom-RegHex.ps1 -RegFilePath ".\Accounts\Account.reg" -OutputFormat Json
```

### Criar/Atualizar Atalhos do Menu Iniciar

```powershell
.\Create-Shortcuts.ps1
.\Create-Shortcuts.ps1 -IconPath "C:\Icons\game.ico"
.\Create-Shortcuts.ps1 -PinToStart
```

## Configuração

Constantes principais são definidas em `Start-LastWar.ps1`:
- Caminho do Registro: `HKEY_CURRENT_USER\Software\FunFly\Last War-Survival Game`
- Launcher do Jogo: `%LOCALAPPDATA%\FunFly\Last War-Survival Game\LastWarLauncher.exe`
- Max Backups Padrão: 20 por conta

## Nota de Segurança

⚠️ **Importante**: Arquivos de registro podem conter dados sensíveis da conta do jogo. O `.gitignore` está configurado para excluir arquivos `Accounts/*.reg` por padrão. Tenha cuidado para não fazer commit de dados sensíveis em repositórios públicos.

## Desenvolvimento

Para arquitetura detalhada e orientação de desenvolvimento, veja [CLAUDE.md](CLAUDE.md).

## Licença

Este projeto é uma ferramenta pessoal. Use por sua conta e risco.

## Autor

#1306 [SOF]Vlad Țepeș ঌ (retired)
