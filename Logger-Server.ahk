;Save_To_Sql=1
;Keep_Versions=5
;@Ahk2Exe-Let U_FileVersion=0.1.0.0
;@Ahk2Exe-SetFileVersion %U_FileVersion%
;@Ahk2Exe-Let U_C=KAH - Logger de Execução de Sistemas
;@Ahk2Exe-SetDescription %U_C%
;@Ahk2Exe-SetMainIcon C:\AHK\icones\dashboard.ico

; ===== Logger-Server.ahk =====
; Servidor para recebimento, exibição e filtragem de logs
; Versão: 1.1.2
; Data: 2025-09-01
; Autor: Dieisson Code
; Repositório: https://github.com/DieissonCode/ahk-debugger
;
; === Descrição ===
; Este servidor recebe logs enviados pela biblioteca logger.ahk, exibe-os
; em uma interface gráfica organizada e permite filtrar por tipo, script e texto.
; Também oferece estatísticas sobre os logs recebidos e exportação para CSV.
;
; === Níveis de Log ===
; - DEBUG: Informações detalhadas para debugging e desenvolvimento
; - INFO: Mensagens informativas sobre o fluxo normal de execução
; - WARN: Alertas que não impedem a execução, mas merecem atenção
; - ERROR: Erros que afetam a funcionalidade, mas não interrompem o script
;
; === Uso ===
; 1. Inicie este servidor antes de qualquer cliente que use logger.ahk
; 2. Use os controles de filtro para focar em logs específicos
; 3. Exporte os logs filtrados para CSV quando necessário

#SingleInstance Force
#Include socket.ahk
#Include C:\AutoHotkey\class\functions.ahk

; Configurações globais
global PORTA := 4041
global DEFAULT_FILTER := {DEBUG: 1, INFO: 1, WARN: 1, ERROR: 1, LOAD: 1}
global TimestampFormat := "yyyy-MM-dd HH:mm:ss"
global g_aLogs := []
global SearchText := ""  ; Variável global para o texto de busca
global ActiveScripts := [] ; Array para rastrear scripts ativos
global SelectedScript := "Todos" ; Script selecionado para filtragem

DebugLogSmart("[SERVER] Script inicializado.")

; Criar GUI com abas e controles
Gui, +Resize +MinSize480x300 +AlwaysOnTop
Gui, Color, FFFFFF
Gui, Font, s10, Segoe UI

Gui, Add, Text, x10 y10 w300, Servidor de Log (Porta: %PORTA%)
Gui, Add, Button, x+10 w80 h25 gClearLogs, Limpar
Gui, Add, Button, x+10 w100 h25 gExportLogs, Exportar Logs

Gui, Add, GroupBox, x10 y40 w410 h115, Filtros

Gui, Add, Checkbox, x20 y60 w80 h20 vChkDEBUG gApplyFilters Checked, DEBUG
Gui, Add, Checkbox, x+5 w80 h20 vChkINFO gApplyFilters Checked, INFO
Gui, Add, Checkbox, x+5 w80 h20 vChkWARN gApplyFilters Checked, WARN
Gui, Add, Checkbox, x+5 w80 h20 vChkERROR gApplyFilters Checked, ERROR
Gui, Add, Checkbox, x+5 w50 h20 vChkLOAD gApplyFilters Checked, LOAD

Gui, Add, Text, x20 y90 w60, Buscar:
Gui, Add, Edit, x+5 w200 h20 vSearchText gSearchChanged, 
Gui, Add, Text, x20 y115 w60, Script:
Gui, Add, ComboBox, x+5 w200 h20 R10 vSelectedScript gScriptSelected, Todos||

Gui, Add, GroupBox, x440 y40 w600 h115, Estatísticas
Gui, Add, Text, x460 y60 w580 vStatsTextGlobal, Scripts conectados: 0 | Logs recebidos: 0
Gui, Add, Text, x460 y85 w580 h2 0x10
Gui, Add, Text, x460 y95 w580 h50 vStatsTextScript, Selecione um script para ver estatísticas específicas

Gui, Add, ListView, x10 y165 w960 r20 vLogView -Multi Grid, Timestamp|Socket|IP|Tipo|Script|Mensagem

ResizeListViewColumns()

Gui, Add, StatusBar
SB_SetParts(200, 150, 200)
SB_SetText("Logs recebidos: 0", 1)
SB_SetText("Clientes conectados: 0", 2)
SB_SetText("Scripts únicos: 0", 3)

global iConnectedClients := 0
global iLogsReceived := 0
global ScriptStats := {}  ; Estatísticas por script

SysGet, MonitorWorkArea, MonitorWorkArea
serverX := 10
serverY := MonitorWorkAreaBottom - 500

Gui, Show, x%serverX% y%serverY% w1050 h500, Logger Server v1.1.2

err := AHKsock_Listen(PORTA, "SocketEventHandler")
DebugLogSmart("[SERVER] AHKsock_Listen chamado. Porta: " PORTA " | Resultado: " (err ? err : "Ativado"))
if (err) {
    DebugLogSmart("[SERVER] Falha ao iniciar servidor. ErrorLevel: " ErrorLevel)
    MsgBox, 16, Erro, Falha ao iniciar o servidor na porta %PORTA%.`nErro AHKsock: %err%`nErrorLevel: %ErrorLevel%
    ExitApp
}
Return

SocketEventHandler(sEvent, iSocket, sName, sAddr, sPort, ByRef bData, bDataLength) {
    global iConnectedClients, iLogsReceived, g_aLogs, ActiveScripts, ScriptStats

    DebugLogSmart("[SERVER] Evento: " sEvent " | Socket: " iSocket " | IP: " sAddr)

    if (sEvent = "ACCEPTED") {
        iConnectedClients++
        DebugLogSmart("[SERVER] Cliente conectado. Socket: " iSocket " | IP: " sAddr)
        SB_SetText("Clientes conectados: " iConnectedClients, 2)
    }
    else if (sEvent = "RECEIVED") {
        dataStr := StrGet(&bData, bDataLength, "UTF-8")
        DebugLogSmart("[SERVER] RECEIVED | Socket: " iSocket " | IP: " sAddr " | Data: " dataStr)

        partes := StrSplit(dataStr, "||")
        tipo := "N/A"
        scriptName := "N/A"
        mensagem := "N/A"

        for _, parte in partes {
            if (SubStr(parte, 1, 5) = "tipo=")
                tipo := SubStr(parte, 6)
            else if (SubStr(parte, 1, 11) = "scriptName=")
                scriptName := SubStr(parte, 12)
            else if (SubStr(parte, 1, 9) = "mensagem=")
                mensagem := SubStr(parte, 10)
        }

        DebugLogSmart("[SERVER] Parseado | Tipo: " tipo " | Script: " scriptName " | Mensagem: " mensagem)

        AddScriptToRegistry(scriptName)
        UpdateScriptStats(scriptName, tipo)
        FormatTime, timestamp,, %TimestampFormat%
        iLogsReceived++
        SB_SetText("Logs recebidos: " iLogsReceived, 1)
        newMsg := {timestamp: timestamp, socket: iSocket, ip: sAddr, tipo: tipo, script: scriptName, mensagem: mensagem}
        g_aLogs.InsertAt(1, newMsg)
        ; Não insira direto na ListView! Apenas chama ApplyFilters.
        ApplyFilters()
    }
    else if (sEvent = "DISCONNECTED") {
        iConnectedClients--
        if (iConnectedClients < 0)
            iConnectedClients := 0

        DebugLogSmart("[SERVER] Cliente desconectado. Socket: " iSocket " | IP: " sAddr)
        SB_SetText("Clientes conectados: " iConnectedClients, 2)

        ; Captura o último script conectado por esse socket/IP
        scriptName := ""
        for index, item in g_aLogs {
            if (item.socket = iSocket && item.ip = sAddr && item.script != "N/A") {
                scriptName := item.script
                break
            }
        }
        FormatTime, timestamp,, %TimestampFormat%
        disconnectMsg := {timestamp: timestamp, socket: iSocket, ip: sAddr, tipo: "INFO", script: scriptName, mensagem: "Script desconectado"}
        g_aLogs.InsertAt(1, disconnectMsg)
        ; Não insira direto na ListView! Apenas chama ApplyFilters.
        ApplyFilters()
    }
}

AddScriptToRegistry(scriptName) {
    global ActiveScripts, ScriptStats
    if (scriptName = "N/A" || scriptName = "")
        return
    isNew := true
    for i, existingScript in ActiveScripts {
        if (existingScript = scriptName) {
            isNew := false
            break
        }
    }
    if (isNew) {
        ActiveScripts.Push(scriptName)
        if (!ScriptStats.HasKey(scriptName)) {
            ScriptStats[scriptName] := {DEBUG: 0, INFO: 0, WARN: 0, ERROR: 0, LOAD: 0, total: 0}
        }
        scriptList := "Todos|"
        for i, script in ActiveScripts {
            scriptList .= script . "|"
        }
        GuiControl,, SelectedScript, |%scriptList%
        GuiControl, Choose, SelectedScript, 1
        SB_SetText("Scripts únicos: " . ActiveScripts.Length(), 3)
    }
}

UpdateScriptStats(scriptName, logType) {
    global ScriptStats, SelectedScript
    if (!ScriptStats.HasKey(scriptName)) {
        ScriptStats[scriptName] := {DEBUG: 0, INFO: 0, WARN: 0, ERROR: 0, LOAD: 0, total: 0}
    }
    if (ScriptStats[scriptName].HasKey(logType))
        ScriptStats[scriptName, logType] += 1
    ScriptStats[scriptName, "total"] += 1
    UpdateStatsDisplay()
    if (SelectedScript = scriptName || SelectedScript = "Todos")
        UpdateScriptSpecificStats()
}

UpdateStatsDisplay() {
    global ScriptStats, ActiveScripts
    totalDebug := 0, totalInfo := 0, totalWarn := 0, totalError := 0, totalLoad := 0, totalLogs := 0
    for i, script in ActiveScripts {
        if (ScriptStats.HasKey(script)) {
            totalDebug += ScriptStats[script, "DEBUG"]
            totalInfo += ScriptStats[script, "INFO"]
            totalWarn += ScriptStats[script, "WARN"]
            totalError += ScriptStats[script, "ERROR"]
            totalLoad += ScriptStats[script, "LOAD"]
            totalLogs += ScriptStats[script, "total"]
        }
    }
    statsText := "Scripts conectados: " . ActiveScripts.Length() 
              . " | Total de logs: " . totalLogs
              . " | DEBUG=" . totalDebug 
              . ", INFO=" . totalInfo 
              . ", WARN=" . totalWarn 
              . ", ERROR=" . totalError
              . ", LOAD=" . totalLoad
    GuiControl,, StatsTextGlobal, %	statsText
}

UpdateScriptSpecificStats() {
    global ScriptStats, SelectedScript
    if (SelectedScript = "Todos") {
        scriptStatsText := "Exibindo logs de todos os scripts"
    } else if (ScriptStats.HasKey(SelectedScript)) {
        debug := ScriptStats[SelectedScript, "DEBUG"]
        info := ScriptStats[SelectedScript, "INFO"]
        warn := ScriptStats[SelectedScript, "WARN"]
        error := ScriptStats[SelectedScript, "ERROR"]
        load := ScriptStats[SelectedScript, "LOAD"]
        total := ScriptStats[SelectedScript, "total"]
        debugPct := Round((debug / total) * 100)
        infoPct := Round((info / total) * 100)
        warnPct := Round((warn / total) * 100)
        errorPct := Round((error / total) * 100)
        loadPct := Round((load / total) * 100)
        scriptStatsText := "Script: " . SelectedScript 
                        . " | Total de logs: " . total
                        . "`nDEBUG: " . debug . " (" . debugPct . "%)"
                        . " | INFO: " . info . " (" . infoPct . "%)"
                        . " | WARN: " . warn . " (" . warnPct . "%)"
                        . " | ERROR: " . error . " (" . errorPct . "%)"
                        . " | LOAD: " . load . " (" . loadPct . "%)"
    } else {
        scriptStatsText := "Selecione um script para ver estatísticas específicas"
    }
    GuiControl,, StatsTextScript, %scriptStatsText%
}

ScriptSelected:
    Gui, Submit, NoHide
    DebugLogSmart("[SERVER] Script selecionado: '" SelectedScript "'")
    UpdateScriptSpecificStats()
    ApplyFilters()
return

SearchChanged:
    GuiControlGet, SearchText
    DebugLogSmart("[SERVER] SearchChanged chamado. Valor digitado: '" SearchText "'")
    SetTimer, ApplyFiltersTimer, -300
return

ApplyFiltersTimer:
    ApplyFilters()
return

ApplyFilters() {
    global g_aLogs, SearchText, SelectedScript
    static lastSearchText := ""
    static lastSelectedScript := ""
    static lastChkDEBUG := ""
    static lastChkINFO := ""
    static lastChkWARN := ""
    static lastChkERROR := ""
    static lastChkLOAD := ""
    static lastLogsLength := 0

    Gui, Submit, NoHide
    GuiControlGet, SearchText
    GuiControlGet, SelectedScript
    GuiControlGet, ChkDEBUG
    GuiControlGet, ChkINFO
    GuiControlGet, ChkWARN
    GuiControlGet, ChkERROR
    GuiControlGet, ChkLOAD

    ; Só atualiza se filtro mudou OU chegou novo log
    if (  SearchText        != lastSearchText
        || SelectedScript   != lastSelectedScript
        || ChkDEBUG         != lastChkDEBUG
        || ChkINFO          != lastChkINFO
        || ChkWARN          != lastChkWARN
        || ChkERROR         != lastChkERROR
        || ChkLOAD          != lastChkLOAD
        || g_aLogs.Length() != lastLogsLength)
    {
        lastSearchText      := SearchText
        lastSelectedScript  := SelectedScript
        lastChkDEBUG        := ChkDEBUG
        lastChkINFO         := ChkINFO
        lastChkWARN         := ChkWARN
        lastChkERROR        := ChkERROR
        lastChkLOAD         := ChkLOAD
        lastLogsLength      := g_aLogs.Length()

        LV_Delete()
        filteredCount := 0

        for index, item in g_aLogs {
            typeVar := "Chk" item.tipo
            showByType := %typeVar%
            showByText := (SearchText = "") 
                       || InStr(item.mensagem, SearchText, false) 
                       || InStr(item.script, SearchText, false)
            showByScript := (SelectedScript = "Todos") 
                         || (item.script = SelectedScript)
            if (showByType && showByText && showByScript) {
                LV_Insert(filteredCount + 1, "", item.timestamp, item.socket, item.ip, item.tipo, item.script, item.mensagem)
                filteredCount++
            }
        }
        SB_SetText("Logs exibidos: " filteredCount " / " g_aLogs.Length(), 1)
    }
}

ClearLogs:
    LV_Delete()
    g_aLogs := []
    iLogsReceived := 0
    SB_SetText("Logs recebidos: 0", 1)
    for i, script in ActiveScripts {
        if (ScriptStats.HasKey(script)) {
            ScriptStats[script, "DEBUG"] := 0
            ScriptStats[script, "INFO"] := 0
            ScriptStats[script, "WARN"] := 0
            ScriptStats[script, "ERROR"] := 0
			ScriptStats[script, "LOAD"] := 0
            ScriptStats[script, "total"] := 0
        }
    }
    UpdateStatsDisplay()
    UpdateScriptSpecificStats()
return

ExportLogs:
    FormatTime, timestamp,, yyyy-MM-dd_HHmmss
    FileSelectFile, outputFile, S16, %A_Desktop%\logs_%timestamp%.csv, Salvar logs como CSV, CSV Files (*.csv)
    if (outputFile = "")
        return
    if !InStr(outputFile, ".csv")
        outputFile .= ".csv"
    fileContent := "Timestamp,Socket,IP,Tipo,Script,Mensagem`n"
    for index, item in g_aLogs {
        typeVar := "Chk" item.tipo
        showByType := %typeVar%
        showByText := (SearchText = "") 
                   || InStr(item.mensagem, SearchText, false) 
                   || InStr(item.script, SearchText, false)
        showByScript := (SelectedScript = "Todos") 
                     || (item.script = SelectedScript)
        if (showByType && showByText && showByScript) {
            mensagemEscaped := RegExReplace(item.mensagem, """", """""")
            scriptEscaped := RegExReplace(item.script, """", """""")
            fileContent .= item.timestamp . ","
                        . item.socket . ","
                        . item.ip . ","
                        . item.tipo . ","
                        . """" . scriptEscaped . """" . ","
                        . """" . mensagemEscaped . """`n"
        }
    }
    FileDelete, %outputFile%
    FileAppend, %fileContent%, %outputFile%, UTF-8
    if (ErrorLevel) {
        MsgBox, 16, Erro, Não foi possível salvar o arquivo de logs.
    } else {
        MsgBox, 64, Sucesso, Logs exportados com sucesso para:`n%outputFile%
    }
	return

ResizeListViewColumns() {
    ; Larguras fixas das primeiras 5 colunas
    col1Width := 140  ; Timestamp
    col2Width := 60   ; Socket  
    col3Width := 100  ; IP
    col4Width := 60   ; Tipo
    col5Width := 120  ; Script
    
    ; Obter a largura atual da ListView
    GuiControlGet, pos, Pos, LogView
    listViewWidth := posW
    
    ; Calcular largura da última coluna (descontando scroll bar e bordas)
    scrollBarWidth := 20
    borderWidth := 4
    col6Width := listViewWidth - col1Width - col2Width - col3Width - col4Width - col5Width - scrollBarWidth - borderWidth
    
    ; Garantir largura mínima para a última coluna
    if (col6Width < 100)
        col6Width := 100
    
    ; Aplicar as larguras
    LV_ModifyCol(1, col1Width)
    LV_ModifyCol(2, col2Width) 
    LV_ModifyCol(3, col3Width)
    LV_ModifyCol(4, col4Width)
    LV_ModifyCol(5, col5Width)
    LV_ModifyCol(6, col6Width)
	}

GuiSize:
    if (A_EventInfo = 1)
        return
    
    ; Redimensionar a ListView
    GuiControl, Move, LogView, % "w" . (A_GuiWidth - 20) . " h" . (A_GuiHeight - 175)
    
    ; Redimensionar as colunas
    ResizeListViewColumns()
	return

GuiClose:
    DebugLogSmart("[SERVER] Encerrando servidor. Fechando todos sockets...")
    AHKsock_Close()
    ExitApp