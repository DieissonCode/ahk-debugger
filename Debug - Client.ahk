#SingleInstance Force
#Include socket.ahk ; Inclui a biblioteca que você forneceu

global HOST := "127.0.0.1"
global PORTA := 4041
global g_Socket := -1

OutputDebug, [CLIENT] Script inicializado.

; Tenta conectar e define "ClientSocketHandler" para lidar com os eventos.
err := AHKsock_Connect(HOST, PORTA, "ClientSocketHandler")
OutputDebug, [CLIENT] Tentando conectar em %HOST%:%PORTA% | Resultado: %err%
if (err) {
    OutputDebug, [CLIENT] Falha ao iniciar conexão. ErrorLevel: %ErrorLevel%
    ExitApp
}
Return ; Fim da seção de auto-execução

ClientSocketHandler(sEvent, iSocket) {
    OutputDebug, [CLIENT] ClientSocketHandler chamado. Evento: %sEvent% | Socket: %iSocket%
    if (sEvent = "CONNECTED") {
        if (iSocket = -1) {
            OutputDebug, [CLIENT] Falha ao conectar ao servidor!
            ExitApp
        } else {
            global g_Socket := iSocket
            OutputDebug, [CLIENT] Conectado com sucesso! Socket: %iSocket%
        }
    }
    else if (sEvent = "DISCONNECTED") {
        OutputDebug, [CLIENT] Desconectado do servidor. Socket: %iSocket%
        global g_Socket := -1
    }
}

F1::
    OutputDebug, [CLIENT] F1 pressionado. Chamando EnviarLog.
    EnviarLog("O usuário pressionou F1!", "DEBUG")
return

EnviarLog(mensagem, tipo) {
    global g_Socket
    OutputDebug, [CLIENT] EnviarLog chamado. Socket: %g_Socket% | Mensagem: %mensagem% | Tipo: %tipo%
    if (g_Socket = -1) {
        OutputDebug, [CLIENT] Não conectado ao servidor. Não enviando log.
        return
    }

    ; Formata a string para envio (inclui scriptName para o server mostrar)
    dataStr := "tipo=" . tipo . "||scriptName=ClienteSimples||mensagem=" . mensagem
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