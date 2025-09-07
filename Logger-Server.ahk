;Save_To_Sql=1
;Keep_Versions=5
;@Ahk2Exe-Let U_FileVersion=0.1.0.0
;@Ahk2Exe-SetFileVersion %U_FileVersion%
;@Ahk2Exe-Let U_C=KAH - Logger de Execução de Sistemas
;@Ahk2Exe-SetDescription %U_C%
;@Ahk2Exe-SetMainIcon C:\AHK\icones\dashboard.ico
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

#SingleInstance Force
#Include C:\Autohotkey 2024\Root\Libs\socket.ahk
#Include C:\AutoHotkey\class\functions.ahk

; Configurações globais
global PORTA := 4041
global DEFAULT_FILTER := {DEBUG: 1, INFO: 1, WARN: 1, ERROR: 1, LOAD: 1}
global TimestampFormat := "yyyy-MM-dd HH:mm:ss"
global g_aLogs := []
global SearchText := ""  ; Variável global para o texto de busca
global ActiveScripts := [] ; Array para rastrear scripts ativos
global SelectedScripts := {} ; Hash para rastrear scripts selecionados

DebugLogSmart("[SERVER] Script inicializado.")

; Criar GUI com abas e controles
Gui, +Resize +MinSize680x300 +AlwaysOnTop
Gui, Color, FFFFFF
Gui, Font, s10, Segoe UI

Gui, Add, Text, x10 y10 w300, Servidor de Log (Porta: %PORTA%)
Gui, Add, Button, x+10 w80 h25 gClearLogs, Limpar
Gui, Add, Button, x+10 w100 h25 gExportLogs, Exportar Logs

Gui, Add, GroupBox, x10 y40 w210 h115, Filtros

Gui, Add, Checkbox, x20 y60 w80 h20 vChkDEBUG gApplyFilters Checked, DEBUG
Gui, Add, Checkbox, x+5 w80 h20 vChkINFO gApplyFilters Checked, INFO
Gui, Add, Checkbox, x20 y80 w80 h20 vChkWARN gApplyFilters Checked, WARN
Gui, Add, Checkbox, x+5 w80 h20 vChkERROR gApplyFilters Checked, ERROR
Gui, Add, Checkbox, x20 y100 w80 h20 vChkLOAD gApplyFilters Checked, LOAD

Gui, Add, Text, x20 y125 w60, Buscar:
Gui, Add, Edit, x80 y122 w130 h20 vSearchText gSearchChanged, 

Gui, Add, GroupBox, x230 y40 w810 h115, Estatísticas
Gui, Add, Text, x240 y60 w790 vStatsTextGlobal, Scripts conectados: 0 | Logs recebidos: 0
Gui, Add, Text, x240 y85 w790 h2 0x10
Gui, Add, Text, x240 y95 w790 h50 vStatsTextScript, Selecione scripts para ver estatísticas específicas

; Adicionar ListView para scripts na esquerda
Gui, Add, GroupBox, x10 y165 w200 h350, Scripts Conectados
Gui, Add, ListView, x15 y185 w190 h325 vScriptListView gScriptListViewClick Checked0 AltSubmit Grid, Software

; Adicionar o item "Todos" na ListView
Gui, ListView, ScriptListView
LV_Add("", "Todos")
SelectedScripts["Todos"] := 1  ; Marcar "Todos" como selecionado por padrão

; Adicionar ListView para logs na direita
Gui, Add, ListView, x220 y165 w820 r20 vLogView -Multi Grid, Timestamp|Socket|IP|Tipo|Script|Mensagem

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

Gui, Show, x%serverX% y%serverY% w1050 h550, Logger Server v1.1.3

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
    Global ActiveScripts, ScriptStats
    if (scriptName = "N/A" || scriptName = "")
        return
    if (!ActiveScripts.HasKey(scriptName)) {
        ActiveScripts[scriptName]	:= 1
        ScriptStats[scriptName]		:= {DEBUG: 0, INFO: 0, WARN: 0, ERROR: 0, LOAD: 0, total: 0}
		Gui, ListView, ScriptListView
        LV_Add("", scriptName)
		OutputDebug, % scriptname
        SB_SetText("Scripts únicos: " . ActiveScripts.Length(), 3)
    }
}

UpdateScriptStats(scriptName, logType) {
    global ScriptStats, ActiveScripts
    
    if (!ScriptStats.HasKey(scriptName)) {
        ScriptStats[scriptName] := {DEBUG: 0, INFO: 0, WARN: 0, ERROR: 0, LOAD: 0, total: 0}
    }
    if (ScriptStats[scriptName].HasKey(logType))
        ScriptStats[scriptName, logType] += 1
    ScriptStats[scriptName, "total"] += 1

    UpdateStatsDisplay()
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
    GuiControl,, StatsTextGlobal, %statsText%
}

UpdateScriptSpecificStats() {
    global ScriptStats, SelectedScripts
    
    ; Verificar quais scripts estão selecionados
    selectedScriptCount := 0
    scriptStatsText := ""
    
    ; Se "Todos" estiver selecionado, mostrar estatísticas gerais
    if (SelectedScripts.HasKey("Todos") && SelectedScripts["Todos"]) {
        scriptStatsText := "Exibindo logs de todos os scripts"
    } else {
        ; Preparar estatísticas para scripts selecionados
        totalDebug := 0
        totalInfo := 0
        totalWarn := 0
        totalError := 0
        totalLoad := 0
        totalLogs := 0
        
        scriptNames := ""
        
        ; Iterar pelos scripts selecionados
        for scriptName, isSelected in SelectedScripts {
            if (isSelected && scriptName != "Todos" && ScriptStats.HasKey(scriptName)) {
                selectedScriptCount++
                
                totalDebug += ScriptStats[scriptName, "DEBUG"]
                totalInfo += ScriptStats[scriptName, "INFO"]
                totalWarn += ScriptStats[scriptName, "WARN"]
                totalError += ScriptStats[scriptName, "ERROR"]
                totalLoad += ScriptStats[scriptName, "LOAD"]
                totalLogs += ScriptStats[scriptName, "total"]
                
                if (scriptNames)
                    scriptNames .= ", "
                scriptNames .= scriptName
            }
        }
        
        if (selectedScriptCount > 0) {
            scriptStatsText := "Scripts selecionados: " . scriptNames
                           . "`nTotal de logs: " . totalLogs
                           . " | DEBUG: " . totalDebug
                           . " | INFO: " . totalInfo
                           . " | WARN: " . totalWarn
                           . " | ERROR: " . totalError
                           . " | LOAD: " . totalLoad
        } else {
            scriptStatsText := "Selecione um ou mais scripts para ver estatísticas"
        }
    }
    
    GuiControl,, StatsTextScript, %scriptStatsText%
}

ScriptListViewClick:
    if (A_GuiEvent = "I") {  ; Item changed
        LV_GetText(scriptName, A_EventInfo, 1)
        isChecked := LV_GetNext(A_EventInfo - 1, "Checked") = A_EventInfo
        
        DebugLogSmart("[SERVER] Script clicado: '" scriptName "', Checked: " isChecked)
        
        ; Atualizar o status de seleção do script
        SelectedScripts[scriptName] := isChecked
        
        ; Se "Todos" foi selecionado, marcar/desmarcar todos os outros scripts
        if (scriptName = "Todos" && isChecked) {
            ; Marcar todos os scripts
            Loop % LV_GetCount()
            {
                LV_Modify(A_Index, "Check")
                LV_GetText(currentScript, A_Index, 1)
                SelectedScripts[currentScript] := true
            }
        } 
        else if (scriptName = "Todos" && !isChecked) {
            Loop % LV_GetCount()
            {
                LV_Modify(A_Index, "-Check")
                LV_GetText(currentScript, A_Index, 1)
                SelectedScripts[currentScript] := false
            }
        }
        
        UpdateScriptSpecificStats()
        ApplyFilters()
    }
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
    global g_aLogs, SearchText, SelectedScripts
    static lastSearchText := ""
    static lastSelectedScripts := {}
    static lastChkDEBUG := ""
    static lastChkINFO := ""
    static lastChkWARN := ""
    static lastChkERROR := ""
    static lastChkLOAD := ""
    static lastLogsLength := 0
    
    Gui, Submit, NoHide
    GuiControlGet, SearchText
    GuiControlGet, ChkDEBUG
    GuiControlGet, ChkINFO
    GuiControlGet, ChkWARN
    GuiControlGet, ChkERROR
    GuiControlGet, ChkLOAD
    
    ; Verificar se algo mudou
    scriptsChanged := false
    if (SelectedScripts.Count() != lastSelectedScripts.Count()) {
        scriptsChanged := true
    } else {
        for script, isSelected in SelectedScripts {
            if (!lastSelectedScripts.HasKey(script) || lastSelectedScripts[script] != isSelected) {
                scriptsChanged := true
                break
            }
        }
    }
    
    ; Só atualiza se filtro mudou OU chegou novo log
    if (  SearchText        != lastSearchText
        || scriptsChanged
        || ChkDEBUG         != lastChkDEBUG
        || ChkINFO          != lastChkINFO
        || ChkWARN          != lastChkWARN
        || ChkERROR         != lastChkERROR
        || ChkLOAD          != lastChkLOAD
        || g_aLogs.Length() != lastLogsLength)
    {
        lastSearchText      := SearchText
        lastSelectedScripts := {}
        for script, isSelected in SelectedScripts {
            lastSelectedScripts[script] := isSelected
        }
        lastChkDEBUG        := ChkDEBUG
        lastChkINFO         := ChkINFO
        lastChkWARN         := ChkWARN
        lastChkERROR        := ChkERROR
        lastChkLOAD         := ChkLOAD
        lastLogsLength      := g_aLogs.Length()

		Gui, ListView, LogView
        LV_Delete()
        filteredCount := 0
        
        showAllScripts := SelectedScripts.HasKey("Todos") && SelectedScripts["Todos"]

        for index, item in g_aLogs {
            typeVar := "Chk" item.tipo
            showByType := %typeVar%
            showByText := (SearchText = "") 
                       || InStr(item.mensagem, SearchText, false) 
                       || InStr(item.script, SearchText, false)
            showByScript := showAllScripts 
                         || (SelectedScripts.HasKey(item.script) && SelectedScripts[item.script])
            
            if (showByType && showByText && showByScript) {
                LV_Add("", item.timestamp, item.socket, item.ip, item.tipo, item.script, item.mensagem)
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
    
    showAllScripts := SelectedScripts.HasKey("Todos") && SelectedScripts["Todos"]
    
    for index, item in g_aLogs {
        typeVar := "Chk" item.tipo
        showByType := %typeVar%
        showByText := (SearchText = "") 
                   || InStr(item.mensagem, SearchText, false) 
                   || InStr(item.script, SearchText, false)
        showByScript := showAllScripts 
                     || (SelectedScripts.HasKey(item.script) && SelectedScripts[item.script])
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
    if (A_EventInfo = 1)  ; Se a janela está minimizada, não fazer nada
        return
    
    ; Calcular novas dimensões
    newScriptListHeight := A_GuiHeight - 200  ; Altura da ListView de scripts
    newLogViewWidth := A_GuiWidth - 230       ; Largura da ListView de logs
    newLogViewHeight := A_GuiHeight - 175     ; Altura da ListView de logs
    
    ; Redimensionar a ListView de scripts
    GuiControl, Move, ScriptListView, h%newScriptListHeight%
    
    ; Redimensionar a ListView de logs
    GuiControl, Move, LogView, w%newLogViewWidth% h%newLogViewHeight%
    
    ; Redimensionar GroupBox
    GuiControl, Move, Estatísticas, w%newLogViewWidth%
    
    ; Redimensionar as colunas
    ResizeListViewColumns()
    return

GuiClose:
    DebugLogSmart("[SERVER] Encerrando servidor. Fechando todos sockets...")
    AHKsock_Close()
    ExitApp