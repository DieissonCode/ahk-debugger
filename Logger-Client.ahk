#SingleInstance Force
#Include socket.ahk

global HOST := "127.0.0.1"
global PORTA := 4041
global g_Socket := -1

OutputDebug, [CLIENT] Script inicializado.

; Criar uma GUI simples para testar envios de logs
Gui, +AlwaysOnTop
Gui, Add, Text, x10 y10, Mensagem:
Gui, Add, Edit, x10 y30 w350 h60 vMensagemLog, Teste de log
Gui, Add, Button, x10 y100 w80 h30 gEnviarDEBUG, DEBUG
Gui, Add, Button, x100 y100 w80 h30 gEnviarINFO, INFO
Gui, Add, Button, x190 y100 w80 h30 gEnviarWARN, WARN
Gui, Add, Button, x280 y100 w80 h30 gEnviarERROR, ERROR

Gui, Add, GroupBox, x10 y140 w350 h130, Testes Rápidos
Gui, Add, Button, x20 y160 w330 h25 gTesteLoginSucesso, Simular Login Bem-sucedido
Gui, Add, Button, x20 y190 w330 h25 gTesteLoginFalha, Simular Login Com Falha
Gui, Add, Button, x20 y220 w330 h25 gTesteSequencia, Sequência de Logs (Todos os Tipos)
Gui, Add, Button, x20 y250 w330 h25 gTesteErroGrave, Simular Erro Crítico

Gui, Show, w370 h280, Logger Client - Teste de Logs

; Tenta conectar e define "ClientSocketHandler" para lidar com os eventos.
err := AHKsock_Connect(HOST, PORTA, "ClientSocketHandler")
OutputDebug, [CLIENT] Tentando conectar em %HOST%:%PORTA% | Resultado: %err%
if (err) {
    OutputDebug, [CLIENT] Falha ao iniciar conexão. ErrorLevel: %ErrorLevel%
    MsgBox, 16, Erro de Conexão, Não foi possível conectar ao servidor de logs.`nVerifique se o servidor está em execução.
    ExitApp
}
Return

ClientSocketHandler(sEvent, iSocket) {
    OutputDebug, [CLIENT] ClientSocketHandler chamado. Evento: %sEvent% | Socket: %iSocket%
    if (sEvent = "CONNECTED") {
        if (iSocket = -1) {
            OutputDebug, [CLIENT] Falha ao conectar ao servidor!
            MsgBox, 16, Erro de Conexão, Falha ao conectar ao servidor de logs.
            ExitApp
        } else {
            global g_Socket := iSocket
            OutputDebug, [CLIENT] Conectado com sucesso! Socket: %iSocket%
            
            ; Atualizar a GUI para mostrar que estamos conectados
            Gui +LastFound
            WinSetTitle, Logger Client - Conectado ao Servidor
        }
    }
    else if (sEvent = "DISCONNECTED") {
        OutputDebug, [CLIENT] Desconectado do servidor. Socket: %iSocket%
        global g_Socket := -1
        
        ; Atualizar a GUI para mostrar que estamos desconectados
        Gui +LastFound
        WinSetTitle, Logger Client - Desconectado
    }
}

; Hotkeys para testes rápidos
F1::EnviarLog("Teste de log DEBUG com F1", "DEBUG")
F2::EnviarLog("Teste de log INFO com F2", "INFO")
F3::EnviarLog("Teste de log WARN com F3", "WARN")
F4::EnviarLog("Teste de log ERROR com F4", "ERROR")

; Funções de envio da GUI
EnviarDEBUG:
    Gui, Submit, NoHide
    EnviarLog(MensagemLog, "DEBUG")
Return

EnviarINFO:
    Gui, Submit, NoHide
    EnviarLog(MensagemLog, "INFO")
Return

EnviarWARN:
    Gui, Submit, NoHide
    EnviarLog(MensagemLog, "WARN")
Return

EnviarERROR:
    Gui, Submit, NoHide
    EnviarLog(MensagemLog, "ERROR")
Return

; Funções de teste específicas
TesteLoginSucesso:
    EnviarLog("Usuário autenticado com sucesso", "INFO")
    Sleep 200
    EnviarLog("Permissões carregadas: Admin, Editor, Viewer", "DEBUG")
    Sleep 200
    EnviarLog("Login: usuario@exemplo.com", "DEBUG")
Return

TesteLoginFalha:
    EnviarLog("Tentativa de login - usuario: admin@sistema.com", "DEBUG")
    Sleep 200
    EnviarLog("Senha incorreta para o usuário admin@sistema.com", "WARN")
    Sleep 200
    EnviarLog("Falha na autenticação após 3 tentativas", "ERROR")
Return

TesteSequencia:
    EnviarLog("Iniciando processamento de dados...", "DEBUG")
    Sleep 300
    EnviarLog("Carregando configurações do sistema", "INFO")
    Sleep 300
    EnviarLog("Alguns arquivos estão desatualizados", "WARN")
    Sleep 300
    EnviarLog("Falha ao processar arquivo de configuração", "ERROR")
    Sleep 300
    EnviarLog("Tentando usar configurações padrão", "INFO")
    Sleep 300
    EnviarLog("Sistema inicializado com configurações padrão", "DEBUG")
Return

TesteErroGrave:
    EnviarLog("Verificando conexão com o banco de dados...", "INFO")
    Sleep 200
    EnviarLog("Timeout ao tentar conectar ao banco", "WARN")
    Sleep 200
    EnviarLog("Tentativa de reconexão 1/3", "WARN")
    Sleep 200
    EnviarLog("Tentativa de reconexão 2/3", "WARN")
    Sleep 200
    EnviarLog("Tentativa de reconexão 3/3", "WARN")
    Sleep 200
    EnviarLog("ERRO CRÍTICO: Não foi possível estabelecer conexão com o banco de dados!", "ERROR")
    Sleep 200
    EnviarLog("O sistema não pode continuar sem acesso ao banco de dados", "ERROR")
Return

EnviarLog(mensagem, tipo) {
    global g_Socket
    OutputDebug, [CLIENT] EnviarLog chamado. Socket: %g_Socket% | Mensagem: %mensagem% | Tipo: %tipo%
    if (g_Socket = -1) {
        OutputDebug, [CLIENT] Não conectado ao servidor. Não enviando log.
        MsgBox, 16, Erro, Não foi possível enviar log.`nNão há conexão com o servidor.
        return
    }

    ; Formata a string para envio (inclui scriptName para o server mostrar)
    dataStr := "tipo=" . tipo . "||scriptName=TesteCliente||mensagem=" . mensagem
    OutputDebug, [CLIENT] String formatada para envio: %dataStr%

    ; Converte a string para UTF-8
    VarSetCapacity(utf8, StrPut(dataStr, "UTF-8"))
    StrPut(dataStr, &utf8, "UTF-8")
    bytesToSend := StrPut(dataStr, "UTF-8") - 1
    OutputDebug, [CLIENT] Dados convertidos para UTF-8. Tamanho: %bytesToSend%

    ; Envia
    err := AHKsock_ForceSend(g_Socket, &utf8, bytesToSend)
    OutputDebug, [CLIENT] Resultado de AHKsock_ForceSend: %err%

    if (err) {
        OutputDebug, [CLIENT] Erro ao enviar log! Erro: %err%
        MsgBox, 16, Erro, Falha ao enviar log.`nErro: %err%
    } else {
        OutputDebug, [CLIENT] Log enviado com sucesso!
    }
}

GuiClose:
OnExit:
    OutputDebug, [CLIENT] Finalizando script. Fechando socket (se existir)...
    if (g_Socket != -1) {
        OutputDebug, [CLIENT] Chamando AHKsock_Close para o socket: %g_Socket%
        AHKsock_Close(g_Socket)
    }
    OutputDebug, [CLIENT] Encerrando aplicação.
    ExitApp