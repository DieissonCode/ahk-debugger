#SingleInstance Force
#Include socket.ahk ; Inclui a biblioteca que você forneceu

global PORTA := 4041

OutputDebug, [SERVER] Script inicializado.

Gui, Add, ListView, r20 w900 vLogView, Socket|IP|Tipo|Script|Mensagem
LV_ModifyCol(1, 60), LV_ModifyCol(2, 120), LV_ModifyCol(3, 80), LV_ModifyCol(4, 160), LV_ModifyCol(5, "AutoHdr")
Gui, Show,x0 y445 , Servidor de Log (AHKsock - Porta %PORTA%)
OutputDebug, [SERVER] GUI iniciada.

err := AHKsock_Listen(PORTA, "SocketEventHandler")
OutputDebug,% "[SERVER] AHKsock_Listen chamado. Porta: " PORTA " | Resultado: " (err ? err : "Ativado")
if (err) {
    OutputDebug, [SERVER] Falha ao iniciar servidor. ErrorLevel: %ErrorLevel%
    MsgBox, 16, Erro, Falha ao iniciar o servidor na porta %PORTA%.`nErro AHKsock: %err%`nErrorLevel: %ErrorLevel%
    ExitApp
}
Run, Debug - Client.ahk
Return

SocketEventHandler(sEvent, iSocket, sName, sAddr, sPort, ByRef bData, bDataLength) {
    Gui, 1:Default

    OutputDebug, [SERVER] Evento: %sEvent% | Socket: %iSocket% | IP: %sAddr%

    if (sEvent = "ACCEPTED") {
        OutputDebug, [SERVER] Cliente conectado. Socket: %iSocket% | IP: %sAddr%
    }
    else if (sEvent = "RECEIVED") {
        dataStr := StrGet(&bData, bDataLength, "UTF-8")
        OutputDebug, [SERVER] RECEIVED | Socket: %iSocket% | IP: %sAddr% | Data: %dataStr%

        tipo := RegexMatch(dataStr, "tipo=([^|]+)", m) ? m1 : "N/A"
        scriptName := RegexMatch(dataStr, "scriptName=([^|]+)", m) ? m1 : "N/A"
        mensagem := RegexMatch(dataStr, "mensagem=([^|]+)", m) ? m1 : "N/A"

        OutputDebug, [SERVER] Parseado | Tipo: %tipo% | Script: %scriptName% | Mensagem: %mensagem%
        LV_Add("", iSocket, sAddr, tipo, scriptName, mensagem)
    }
    else if (sEvent = "DISCONNECTED") {
        OutputDebug, [SERVER] Cliente desconectado. Socket: %iSocket% | IP: %sAddr%
    }
}

GuiClose:
    OutputDebug, [SERVER] Encerrando servidor. Fechando todos sockets...
    AHKsock_Close()
    ExitApp