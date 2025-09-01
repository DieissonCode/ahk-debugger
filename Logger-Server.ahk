﻿#SingleInstance Force
#Include socket.ahk

; Configurações globais
global PORTA := 4041
global LOG_COLORS := {DEBUG: 0x2196F3, INFO: 0x4CAF50, WARN: 0xFFC107, ERROR: 0xF44336, DEFAULT: 0x000000}
global DEFAULT_FILTER := {DEBUG: 1, INFO: 1, WARN: 1, ERROR: 1}
global TimestampFormat := "yyyy-MM-dd HH:mm:ss"
global g_hWndListView
global g_aLogs := []

OutputDebug, [SERVER] Script inicializado.

; Criar GUI com abas e controles
Gui, +Resize +MinSize480x300
Gui, Color, FFFFFF
Gui, Font, s10, Segoe UI

; Barra de ferramentas superior
Gui, Add, Text, x10 y10 w300, Servidor de Log (Porta: %PORTA%)
Gui, Add, Button, x+10 w80 h25 gClearLogs, Limpar
Gui, Add, Button, x+10 w100 h25 gExportLogs, Exportar Logs

; Filtros
Gui, Add, GroupBox, x10 y40 w470 h60, Filtros
Gui, Add, Checkbox, x20 y60 w80 h20 vChkDEBUG gApplyFilters Checked, DEBUG
Gui, Add, Checkbox, x+5 w80 h20 vChkINFO gApplyFilters Checked, INFO
Gui, Add, Checkbox, x+5 w80 h20 vChkWARN gApplyFilters Checked, WARN
Gui, Add, Checkbox, x+5 w80 h20 vChkERROR gApplyFilters Checked, ERROR
Gui, Add, Text, x20 y85 w60, Buscar:
Gui, Add, Edit, x+5 w300 h20 vSearchText gApplyFilters

; Lista de logs com cores
Gui, Add, ListView, x10 y110 w880 r20 vLogView -Multi Grid hwndg_hWndListView, Timestamp|Socket|IP|Tipo|Script|Mensagem
LV_ModifyCol(1, 140), LV_ModifyCol(2, 60), LV_ModifyCol(3, 100)
LV_ModifyCol(4, 60), LV_ModifyCol(5, 120), LV_ModifyCol(6, 380)

; Ativar o modo Extended ListView para suportar colorização
SendMessage, 0x1036, 0, 0x200000, , ahk_id %g_hWndListView% ; LVM_SETEXTENDEDLISTVIEWSTYLE, LVS_EX_FULLROWSELECT

; Registrar callback para colorização
OnMessage(0x4E, "OnNotify") ; WM_NOTIFY

; Barra de status
Gui, Add, StatusBar
SB_SetParts(200, 150)
SB_SetText("Logs recebidos: 0", 1)
SB_SetText("Clientes conectados: 0", 2)

; Guardar as mensagens originais para filtrar
global iConnectedClients := 0
global iLogsReceived := 0

Gui, Show, x10 y10 w900 h500, Logger Server v1.1

; Iniciar o servidor
err := AHKsock_Listen(PORTA, "SocketEventHandler")
OutputDebug,% "[SERVER] AHKsock_Listen chamado. Porta: " PORTA " | Resultado: " (err ? err : "Ativado")
if (err) {
    OutputDebug, [SERVER] Falha ao iniciar servidor. ErrorLevel: %ErrorLevel%
    MsgBox, 16, Erro, Falha ao iniciar o servidor na porta %PORTA%.`nErro AHKsock: %err%`nErrorLevel: %ErrorLevel%
    ExitApp
}

Return

; Tratamento de eventos de socket
SocketEventHandler(sEvent, iSocket, sName, sAddr, sPort, ByRef bData, bDataLength) {
    global iConnectedClients, iLogsReceived, g_aLogs
    
    OutputDebug, [SERVER] Evento: %sEvent% | Socket: %iSocket% | IP: %sAddr%
    
    if (sEvent = "ACCEPTED") {
        iConnectedClients++
        OutputDebug, [SERVER] Cliente conectado. Socket: %iSocket% | IP: %sAddr%
        SB_SetText("Clientes conectados: " iConnectedClients, 2)
    }
    else if (sEvent = "RECEIVED") {
        dataStr := StrGet(&bData, bDataLength, "UTF-8")
        OutputDebug, [SERVER] RECEIVED | Socket: %iSocket% | IP: %sAddr% | Data: %dataStr%
        
        ; Parse dos dados
        tipo := RegexMatch(dataStr, "tipo=([^|]+)", m) ? m1 : "N/A"
        scriptName := RegexMatch(dataStr, "scriptName=([^|]+)", m) ? m1 : "N/A"
        mensagem := RegexMatch(dataStr, "mensagem=([^|]+)", m) ? m1 : "N/A"
        
        ; Gerar timestamp
        FormatTime, timestamp,, %TimestampFormat%
        
        ; Armazenar mensagem para filtros
        iLogsReceived++
        SB_SetText("Logs recebidos: " iLogsReceived, 1)
        
        ; Adicionar à array de mensagens
        newMsg := {timestamp: timestamp, socket: iSocket, ip: sAddr, tipo: tipo
                 , script: scriptName, mensagem: mensagem}
        g_aLogs.Push(newMsg)
        
        ; Adicionar ao ListView
        rowNum := LV_Add("", newMsg.timestamp, newMsg.socket, newMsg.ip, newMsg.tipo, newMsg.script, newMsg.mensagem)
        
        ; Aplicar filtros automaticamente para caso este log não seja visível
        ApplyFilters()
    }
    else if (sEvent = "DISCONNECTED") {
        iConnectedClients--
        if (iConnectedClients < 0)
            iConnectedClients := 0
        
        OutputDebug, [SERVER] Cliente desconectado. Socket: %iSocket% | IP: %sAddr%
        SB_SetText("Clientes conectados: " iConnectedClients, 2)
    }
}

; Manipulador de notificações para colorir as linhas
OnNotify(wParam, lParam) {
    global g_hWndListView, LOG_COLORS, g_aLogs
    
    ; Obter informações da notificação
    Critical
    hwndFrom := NumGet(lParam+0, 0, "UPtr")
    
    ; Se não for do nosso ListView, ignorar
    if (hwndFrom != g_hWndListView)
        return
    
    ; Obter o código da notificação
    code := NumGet(lParam+0, A_PtrSize*2, "Int")
    
    ; NM_CUSTOMDRAW = -12
    if (code = -12) {
        ; Ponteiro para NMLVCUSTOMDRAW
        nmcd := lParam
        
        ; Obter o estágio de desenho
        drawStage := NumGet(nmcd+0, A_PtrSize*2 + 4, "UInt")
        
        ; CDDS_PREPAINT = 1
        if (drawStage = 1) {
            ; Informar que queremos notificações para cada item
            return 0x20 ; CDRF_NOTIFYITEMDRAW
        }
        ; CDDS_ITEMPREPAINT = 0x10001
        else if (drawStage = 0x10001) {
            ; Obter o índice do item (linha)
            iItem := NumGet(nmcd+0, A_PtrSize*2 + 8, "Int") + 1 ; +1 porque AHK é 1-based
            
            ; Se o item existe nos nossos logs
            if (iItem <= g_aLogs.Length()) {
                ; Determinar cor com base no tipo de log
                log := g_aLogs[iItem]
                color := log.HasKey("tipo") && LOG_COLORS.HasKey(log.tipo) 
                      ? LOG_COLORS[log.tipo] : LOG_COLORS.DEFAULT
                
                ; Definir cores
                NumPut(color, nmcd+0, A_PtrSize*2 + 12 + 4, "UInt") ; clrText
                NumPut(0xFFFFFF, nmcd+0, A_PtrSize*2 + 12 + 8, "UInt") ; clrTextBk
                
                ; Informar que alteramos as cores
                return 0x4 ; CDRF_NEWFONT
            }
        }
    }
    return
}

; Filtrar as mensagens
ApplyFilters() {
    global g_aLogs
    
    ; Obter os valores de filtro
    Gui, Submit, NoHide
    
    ; Limpar a lista atual
    LV_Delete()
    
    ; Aplicar os filtros
    filteredCount := 0
    for index, item in g_aLogs {
        ; Verificar filtro de tipo
        typeVar := "Chk" item.tipo
        showByType := %typeVar%
        
        ; Verificar filtro de texto
        showByText := !SearchText || InStr(item.mensagem, SearchText) || InStr(item.script, SearchText)
        
        ; Se passar em ambos os filtros, mostrar
        if (showByType && showByText) {
            LV_Add("", item.timestamp, item.socket, item.ip, item.tipo, item.script, item.mensagem)
            filteredCount++
        }
    }
    
    ; Atualizar barra de status
    SB_SetText("Logs exibidos: " filteredCount " / " g_aLogs.Length(), 1)
}

; Limpar todos os logs
ClearLogs:
    LV_Delete()
    g_aLogs := []
    iLogsReceived := 0
    SB_SetText("Logs recebidos: 0", 1)
return

; Exportar logs para CSV
ExportLogs:
    ; Solicitar nome de arquivo
    FormatTime, timestamp,, yyyy-MM-dd_HHmmss
    FileSelectFile, outputFile, S16, %A_Desktop%\logs_%timestamp%.csv, Salvar logs como CSV, CSV Files (*.csv)
    if (outputFile = "")
        return
    
    ; Adicionar extensão .csv se não houver
    if !InStr(outputFile, ".csv")
        outputFile .= ".csv"
    
    ; Preparar arquivo CSV
    fileContent := "Timestamp,Socket,IP,Tipo,Script,Mensagem`n"
    
    ; Adicionar cada log
    for index, item in g_aLogs {
        ; Escapar aspas em campos
        mensagemEscaped := RegExReplace(item.mensagem, """", """""")
        scriptEscaped := RegExReplace(item.script, """", """""")
        
        ; Adicionar linha
        fileContent .= item.timestamp . ","
                    . item.socket . ","
                    . item.ip . ","
                    . item.tipo . ","
                    . """" . scriptEscaped . """" . ","
                    . """" . mensagemEscaped . """`n"
    }
    
    ; Salvar arquivo
    FileDelete, %outputFile%
    FileAppend, %fileContent%, %outputFile%, UTF-8
    
    if (ErrorLevel) {
        MsgBox, 16, Erro, Não foi possível salvar o arquivo de logs.
    } else {
        MsgBox, 64, Sucesso, Logs exportados com sucesso para:`n%outputFile%
    }
return

GuiSize:
    if (A_EventInfo = 1)  ; O aplicativo está sendo minimizado
        return
    
    ; Redimensionar controles
    GuiControl, Move, LogView, % "w" . (A_GuiWidth - 20) . " h" . (A_GuiHeight - 120)
return

GuiClose:
    OutputDebug, [SERVER] Encerrando servidor. Fechando todos sockets...
    AHKsock_Close()
    ExitApp