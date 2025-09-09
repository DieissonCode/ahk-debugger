;Save_To_Sql=1
;Keep_Versions=5
;@Ahk2Exe-Let U_FileVersion=0.1.3.0
;@Ahk2Exe-SetFileVersion %U_FileVersion%
;@Ahk2Exe-Let U_C=KAH - Logger de Execução de Sistemas
;@Ahk2Exe-SetDescription %U_C%
;@Ahk2Exe-SetMainIcon C:\AHK\icones\dashboard.ico

; ===== Logger-Server.ahk =====
; Servidor para recebimento, exibição e filtragem de logs
; Versão: 1.3.0 - Limite global/individual de logs por script
; Data: 2025-09-09
; Autor: Dieisson Code
; Repositório: https://github.com/DieissonCode/ahk-debugger

#SingleInstance Force
#Include C:\Autohotkey 2024\Root\Libs\socket.ahk
#Include C:\AutoHotkey\class\functions.ahk

; Configurações globais
global PORTA := 4041
global DEFAULT_FILTER := {DEBUG: 1, INFO: 1, WARN: 1, ERROR: 1, LOAD: 1}
global TimestampFormat := "yyyy-MM-dd HH:mm:ss"
global g_aLogs := []
global SearchText := ""
global ActiveScripts := []
global SelectedScripts := {}
global g_FilteredLogs := []
global g_MaxLogsPerScript := 300      ; Limite padrão de logs por script
global g_UseGlobalLimit := true       ; NOVO: Aplica limite global por padrão
global g_IndividualLimits := {}       ; NOVO: Limite individual por script
global g_LogCounts := {}              ; Contador de logs por script
global iConnectedClients := 0
global iLogsReceived := 0
global ScriptStats := {}
global g_VirtualMode := true
global g_LastScrollPos := 1

DebugLogSmart("[SERVER] Script inicializado.")

; GUI
Gui, +Resize +MinSize480x300 +AlwaysOnTop
Gui, Color, FFFFFF
Gui, Font, s10, Segoe UI

Gui, Add, Text, x10 y10 w300, Servidor de Log (Porta: %PORTA%)
Gui, Add, Button, x+10 w80 h25 gClearLogs, Limpar
Gui, Add, Button, x+10 w100 h25 gExportLogs, Exportar Logs

Gui, Add, GroupBox, x10 y40 w410 h160, Filtros e Configurações

Gui, Add, Checkbox, x20 y60 w80 h20 vChkDEBUG gApplyFilters Checked, DEBUG
Gui, Add, Checkbox, x+5 w80 h20 vChkINFO gApplyFilters Checked, INFO
Gui, Add, Checkbox, x+5 w80 h20 vChkWARN gApplyFilters Checked, WARN
Gui, Add, Checkbox, x+5 w80 h20 vChkERROR gApplyFilters Checked, ERROR
Gui, Add, Checkbox, x+5 w50 h20 vChkLOAD gApplyFilters Checked, LOAD

Gui, Add, Text, x20 y90 w60, Buscar:
Gui, Add, Edit, x+5 w200 h20 vSearchText gSearchChanged, 

Gui, Add, Text, x20 y115 w100, Limite logs/script:
Gui, Add, Edit, x125 y112 w60 h20 vMaxLogsInput gUpdateMaxLogs Number, %g_MaxLogsPerScript%
Gui, Add, Button, x190 y111 w50 h22 gApplyMaxLogs, Aplicar

; Limite global/individual
Gui, Add, Checkbox, x20 y140 w180 h20 vUseGlobalLimit gToggleGlobalLimit Checked, Limite global para todos os scripts
Gui, Add, Button, x210 y139 w90 h22 gConfigIndividualLimits, Configurar scripts...

Gui, Add, Checkbox, x310 y140 w140 h20 vVirtualMode gToggleVirtualMode Checked, Modo Virtualizado

Gui, Add, ListView, x10 y210 w200 r20 vScriptsListView +Checked gScriptsListViewChanged AltSubmit, Scripts
LV_Add("", "Todos")
SelectedScripts["Todos"] := 0

Gui, Add, GroupBox, x440 y40 w600 h160, Estatísticas
Gui, Add, Text, x460 y60 w580 vStatsTextGlobal, Scripts conectados: 0 | Logs recebidos: 0
Gui, Add, Text, x460 y85 w580 h2 0x10
Gui, Add, Text, x460 y95 w580 h100 vStatsTextScript, Selecione um script para ver estatísticas específicas

Gui, Add, ListView, x220 y210 w750 r20 vLogView -Multi Grid, Timestamp|Socket|IP|Tipo|Script|Mensagem
ResizeListViewColumns()

Gui, Add, StatusBar
SB_SetParts(200, 150, 200, 150)
SB_SetText("Logs recebidos: 0", 1)
SB_SetText("Clientes conectados: 0", 2)
SB_SetText("Scripts únicos: 0", 3)
SB_SetText("Modo: Virtual", 4)

SysGet, MonitorWorkArea, MonitorWorkArea
serverX := 10
serverY := MonitorWorkAreaBottom - 570

Gui, Show, x%serverX% y%serverY% w1050 h570, Logger Server v1.3.0

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

    if (sEvent = "ACCEPTED") {
        iConnectedClients++
        SB_SetText("Clientes conectados: " iConnectedClients, 2)
    }
    else if (sEvent = "RECEIVED") {
        dataStr := StrGet(&bData, bDataLength, "UTF-8")

        partes := StrSplit(dataStr, "||")
        tipo := "N/A"
        scriptName := "N/A"
        mensagem := "N/A"

        for _, parte in partes {
            if (SubStr(parte, 1, 5) = "tipo=" || SubStr(parte, 1, 5) = "type=")
                tipo := SubStr(parte, 6)
            else if (SubStr(parte, 1, 11) = "scriptName=")
                scriptName := SubStr(parte, 12)
            else if (SubStr(parte, 1, 9) = "mensagem=" || SubStr(parte, 1, 8) = "message=")
                mensagem := SubStr(parte, InStr(parte, "=") + 1)
        }

        AddScriptToRegistry(scriptName)
        UpdateScriptStats(scriptName, tipo)
        FormatTime, timestamp,, %TimestampFormat%
        iLogsReceived++
        SB_SetText("Logs recebidos: " iLogsReceived, 1)
        
        newMsg := {timestamp: timestamp, socket: iSocket, ip: sAddr, tipo: tipo, script: scriptName, mensagem: mensagem}
        AddLogWithLimit(newMsg)
        ApplyFiltersOptimized(true)
    }
    else if (sEvent = "DISCONNECTED") {
        iConnectedClients--
        if (iConnectedClients < 0)
            iConnectedClients := 0
        SB_SetText("Clientes conectados: " iConnectedClients, 2)

        scriptName := ""
        for index, item in g_aLogs {
            if (item.socket = iSocket && item.ip = sAddr && item.script != "N/A") {
                scriptName := item.script
                break
            }
        }
        FormatTime, timestamp,, %TimestampFormat%
        disconnectMsg := {timestamp: timestamp, socket: iSocket, ip: sAddr, tipo: "INFO", script: scriptName, mensagem: "Script desconectado"}
        AddLogWithLimit(disconnectMsg)
        ApplyFiltersOptimized(true)
    }
}

; --------- Limite global/individual ---------
GetLimitForScript(scriptName) {
    global g_UseGlobalLimit, g_MaxLogsPerScript, g_IndividualLimits
    if (g_UseGlobalLimit)
        return g_MaxLogsPerScript
    else
        return g_IndividualLimits.HasKey(scriptName) ? g_IndividualLimits[scriptName] : 300
}

AddLogWithLimit(newMsg) {
    global g_aLogs, g_LogCounts

    scriptName := newMsg.script
    if (!g_LogCounts.HasKey(scriptName))
        g_LogCounts[scriptName] := 0

    g_aLogs.InsertAt(1, newMsg)
    g_LogCounts[scriptName]++

    limit := GetLimitForScript(scriptName)
    if (g_LogCounts[scriptName] > limit) {
        Loop, % g_aLogs.Length() {
            reverseIndex := g_aLogs.Length() - A_Index + 1
            if (g_aLogs[reverseIndex].script = scriptName) {
                g_aLogs.RemoveAt(reverseIndex)
                g_LogCounts[scriptName]--
                break
            }
        }
    }
}

; --------- GUI handlers ---------
ToggleGlobalLimit:
    GuiControlGet, UseGlobalLimit
    g_UseGlobalLimit := UseGlobalLimit
    ApplyFiltersOptimized(true)
    UpdateStatsDisplay()
return

ConfigIndividualLimits:
    global ActiveScripts, g_IndividualLimits
    scripts := ""
    for _, script in ActiveScripts {
        val := g_IndividualLimits.HasKey(script) ? g_IndividualLimits[script] : 300
        scripts .= script . "=" . val . "|"
    }
    InputBox, newLimits, Limite individual por script, Use o formato: script1=100|script2=50|..., , , , , , , %scripts%
    if (ErrorLevel)
        return
    changes := StrSplit(newLimits, "|")
    for _, part in changes {
        arr := StrSplit(part, "=")
        if (arr.Length() = 2 && arr[2] > 0)
            g_IndividualLimits[arr[1]] := arr[2]
    }
    ApplyFiltersOptimized(true)
    UpdateStatsDisplay()
return

ApplyMaxLogs:
    GuiControlGet, MaxLogsInput
    if (MaxLogsInput > 0 && MaxLogsInput <= 10000) {
        g_MaxLogsPerScript := MaxLogsInput
        TrimLogsToLimit()
        ApplyFiltersOptimized(true)
        UpdateStatsDisplay()
        MsgBox, 64, Sucesso, Limite de logs aplicado!
    } else {
        MsgBox, 16, Erro, Por favor, insira um valor entre 1 e 10000
    }
return

TrimLogsToLimit() {
    global g_aLogs, g_LogCounts, g_UseGlobalLimit, g_MaxLogsPerScript, g_IndividualLimits

    for script in g_LogCounts
        g_LogCounts[script] := 0
    newLogs := []
    for _, item in g_aLogs {
        scriptName := item.script
        limit := GetLimitForScript(scriptName)
        if (!g_LogCounts.HasKey(scriptName))
            g_LogCounts[scriptName] := 0
        if (g_LogCounts[scriptName] < limit) {
            newLogs.Push(item)
            g_LogCounts[scriptName]++
        }
    }
    g_aLogs := newLogs
}

UpdateMaxLogs:
    GuiControlGet, MaxLogsInput
    if (MaxLogsInput > 0 && MaxLogsInput <= 10000) {
        g_MaxLogsPerScript := MaxLogsInput
        UpdateStatsDisplay()
    }
return

ToggleVirtualMode:
    GuiControlGet, VirtualMode
    g_VirtualMode := VirtualMode
    SB_SetText("Modo: " . (g_VirtualMode ? "Virtual" : "Padrão"), 4)
    ApplyFiltersOptimized(true)
return

ClearLogs:
    Gui, ListView, LogView
    LV_Delete()
    g_aLogs := []
    g_FilteredLogs := []
    iLogsReceived := 0
    SB_SetText("Logs recebidos: 0", 1)
    for script in g_LogCounts
        g_LogCounts[script] := 0
    for i, script in ActiveScripts
        if (ScriptStats.HasKey(script)) {
            ScriptStats[script, "DEBUG"] := 0
            ScriptStats[script, "INFO"] := 0
            ScriptStats[script, "WARN"] := 0
            ScriptStats[script, "ERROR"] := 0
            ScriptStats[script, "LOAD"] := 0
            ScriptStats[script, "total"] := 0
        }
    UpdateStatsDisplay()
    UpdateScriptSpecificStats("")
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
        if (ShouldShowItem(item)) {
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

; --------- Scripts, Filtros, ListView ---------
AddScriptToRegistry(scriptName) {
    global ActiveScripts, ScriptStats, SelectedScripts, g_LogCounts, g_IndividualLimits, g_UseGlobalLimit
    if (scriptName = "N/A" || scriptName = "")
        return
    isNew := true
    for i, existingScript in ActiveScripts
        if (existingScript = scriptName)
            isNew := false
    if (isNew) {
        ActiveScripts.Push(scriptName)
        if (!ScriptStats.HasKey(scriptName))
            ScriptStats[scriptName] := {DEBUG: 0, INFO: 0, WARN: 0, ERROR: 0, LOAD: 0, total: 0}
        if (!g_LogCounts.HasKey(scriptName))
            g_LogCounts[scriptName] := 0
        if (!g_UseGlobalLimit && !g_IndividualLimits.HasKey(scriptName))
            g_IndividualLimits[scriptName] := 300
        Gui, ListView, ScriptsListView
        LV_Add("", scriptName)
        SelectedScripts[scriptName] := 0
        SB_SetText("Scripts únicos: " . ActiveScripts.Length(), 3)
    }
}

UpdateScriptStats(scriptName, logType) {
    global ScriptStats
    if (!ScriptStats.HasKey(scriptName))
        ScriptStats[scriptName] := {DEBUG: 0, INFO: 0, WARN: 0, ERROR: 0, LOAD: 0, total: 0}
    if (ScriptStats[scriptName].HasKey(logType))
        ScriptStats[scriptName, logType] += 1
    ScriptStats[scriptName, "total"] += 1
    UpdateStatsDisplay()
    UpdateScriptSpecificStats(scriptName)
}

UpdateStatsDisplay() {
    global ScriptStats, ActiveScripts, g_LogCounts, g_MaxLogsPerScript, g_UseGlobalLimit, g_IndividualLimits
    totalDebug := 0, totalInfo := 0, totalWarn := 0, totalError := 0, totalLoad := 0, totalLogs := 0
    for i, script in ActiveScripts
        if (ScriptStats.HasKey(script)) {
            totalDebug += ScriptStats[script, "DEBUG"]
            totalInfo += ScriptStats[script, "INFO"]
            totalWarn += ScriptStats[script, "WARN"]
            totalError += ScriptStats[script, "ERROR"]
            totalLoad += ScriptStats[script, "LOAD"]
            totalLogs += ScriptStats[script, "total"]
        }
    if (g_UseGlobalLimit)
        limitInfo := " | Limite: " . g_MaxLogsPerScript . "/script (global)"
    else
        limitInfo := " | Limite: individual por script"
    statsText := "Scripts conectados: " . ActiveScripts.Length() 
              . " | Total de logs: " . totalLogs
              . limitInfo
              . " | DEBUG=" . totalDebug 
              . ", INFO=" . totalInfo 
              . ", WARN=" . totalWarn 
              . ", ERROR=" . totalError
              . ", LOAD=" . totalLoad
    GuiControl,, StatsTextGlobal, %statsText%
}

UpdateScriptSpecificStats(scriptName) {
    global ScriptStats, SelectedScripts, g_LogCounts, g_UseGlobalLimit, g_MaxLogsPerScript, g_IndividualLimits
    scriptStatsText := "Exibindo logs dos scripts selecionados"
    if (scriptName && scriptName != "Todos" && ScriptStats.HasKey(scriptName)) {
        debug := ScriptStats[scriptName, "DEBUG"]
        info := ScriptStats[scriptName, "INFO"]
        warn := ScriptStats[scriptName, "WARN"]
        error := ScriptStats[scriptName, "ERROR"]
        load := ScriptStats[scriptName, "LOAD"]
        total := ScriptStats[scriptName, "total"]
        currentCount := g_LogCounts.HasKey(scriptName) ? g_LogCounts[scriptName] : 0
        limit := GetLimitForScript(scriptName)
        if (total > 0) {
            debugPct := Round((debug / total) * 100)
            infoPct := Round((info / total) * 100)
            warnPct := Round((warn / total) * 100)
            errorPct := Round((error / total) * 100)
            loadPct := Round((load / total) * 100)
            scriptStatsText := "Script: " . scriptName 
                            . " | Logs armazenados: " . currentCount . "/" . limit
                            . " | Total processados: " . total
                            . "`nDEBUG: " . debug . " (" . debugPct . "%)"
                            . " | INFO: " . info . " (" . infoPct . "%)"
                            . " | WARN: " . warn . " (" . warnPct . "%)"
                            . " | ERROR: " . error . " (" . errorPct . "%)"
                            . " | LOAD: " . load . " (" . loadPct . "%)"
        }
    }
    GuiControl,, StatsTextScript, %scriptStatsText%
}

ScriptsListViewChanged:
    if (A_GuiEvent = "C") {
        LV_GetText(script, A_EventInfo)
        Gui, Listview, ScriptsListView
        Loop % LV_GetCount() {
            script := ""
            isChecked := LV_GetNext(A_Index - 1, "Checked")
            LV_GetText(script, A_Index, 1)
            SelectedScripts[script] := isChecked = A_Index ? 1 : 0
        }
        Gui, ListView, ScriptsListView
        if (SelectedScripts["Todos"] = 1) {
            Loop, % LV_GetCount() {
                if (A_Index > 1) {
                    LV_GetText(rowScript, A_Index)
                    SelectedScripts[rowScript] := 1
                    LV_Modify(A_Index, "Check")
                }
            }
        } else {
            allChecked := true
            Loop, % LV_GetCount() {
                if (A_Index > 1) {
                    LV_GetText(rowScript, A_Index)
                    if (SelectedScripts[rowScript] = 0) {
                        allChecked := false
                    }
                }
            }
            if (!allChecked) {
                Loop, % LV_GetCount() {
                    if (A_Index > 1) {
                        LV_GetText(rowScript, A_Index)
                        if (SelectedScripts[rowScript] = 0) {
                            LV_Modify(A_Index, "-Check")
                        }
                    }
                }
            }
        }
        UpdateScriptSpecificStats(script)
        ApplyFiltersOptimized(true)
    }
return

SearchChanged:
    GuiControlGet, SearchText
    SetTimer, ApplyFiltersTimer, -300
return

ApplyFiltersTimer:
    ApplyFiltersOptimized(true)
return

; --------- ListView / Virtualização ---------
ApplyFilters:
    ApplyFiltersOptimized(false)
return

ApplyFiltersOptimized(forceUpdate := false) {
    global g_aLogs, SearchText, SelectedScripts, g_FilteredLogs, g_VirtualMode, g_LastScrollPos
    static lastSearchText := ""
    static lastChkDEBUG := ""
    static lastChkINFO := ""
    static lastChkWARN := ""
    static lastChkERROR := ""
    static lastChkLOAD := ""
    static lastLogsLength := 0
    static lastSelectedHash := ""
    static lastLogsSignature := ""
    Gui, Submit, NoHide
    GuiControlGet, SearchText
    GuiControlGet, ChkDEBUG
    GuiControlGet, ChkINFO
    GuiControlGet, ChkWARN
    GuiControlGet, ChkERROR
    GuiControlGet, ChkLOAD
    selectedHash := ""
    for script, isSelected in SelectedScripts
        selectedHash .= script . ":" . isSelected . "|"
    logsSignature := ""
    if (g_aLogs.Length() > 0)
        logsSignature := g_aLogs[1].timestamp . "|" . g_aLogs[1].script . "|" . g_aLogs.Length()
    needsUpdate := forceUpdate
    if (!needsUpdate) {
        if (SearchText != lastSearchText
        || ChkDEBUG != lastChkDEBUG
        || ChkINFO != lastChkINFO
        || ChkWARN != lastChkWARN
        || ChkERROR != lastChkERROR
        || ChkLOAD != lastChkLOAD
        || g_aLogs.Length() != lastLogsLength
        || selectedHash != lastSelectedHash
        || logsSignature != lastLogsSignature)
            needsUpdate := true
    }
    if (needsUpdate) {
        Gui, ListView, LogView
        currentFocus := LV_GetNext(0, "Focused")
        if (currentFocus > 0)
            g_LastScrollPos := currentFocus
        lastSearchText := SearchText
        lastChkDEBUG := ChkDEBUG
        lastChkINFO := ChkINFO
        lastChkWARN := ChkWARN
        lastChkERROR := ChkERROR
        lastChkLOAD := ChkLOAD
        lastLogsLength := g_aLogs.Length()
        lastSelectedHash := selectedHash
        lastLogsSignature := logsSignature
        if (g_VirtualMode)
            UpdateVirtualListView()
        else
            UpdateStandardListView()
        SB_SetText("Logs exibidos: " . LV_GetCount() . " / " . g_aLogs.Length(), 1)
    }
}

UpdateVirtualListView() {
    global g_aLogs, g_FilteredLogs, SearchText, SelectedScripts, g_LastScrollPos
    g_FilteredLogs := []
    for index, item in g_aLogs
        if (ShouldShowItem(item))
            g_FilteredLogs.Push(item)
    Gui, ListView, LogView
    currentCount := LV_GetCount()
    newCount := g_FilteredLogs.Length()
    if (Abs(newCount - currentCount) > 5 || currentCount = 0)
        RebuildListView()
    else {
        firstItemValid := false
        if (currentCount > 0 && newCount > 0) {
            LV_GetText(lvTimestamp, 1, 1)
            LV_GetText(lvScript, 1, 5)
            firstItemValid := (g_FilteredLogs[1].timestamp = lvTimestamp && g_FilteredLogs[1].script = lvScript)
        }
        if (firstItemValid)
            UpdateListViewIncremental()
        else
            RebuildListView()
    }
    if (g_LastScrollPos > 0 && g_LastScrollPos <= LV_GetCount())
        LV_Modify(g_LastScrollPos, "Focus")
}

UpdateStandardListView() {
    global g_aLogs, SearchText, SelectedScripts
    Gui, ListView, LogView
    LV_Delete()
    for index, item in g_aLogs
        if (ShouldShowItem(item))
            LV_Add("", item.timestamp, item.socket, item.ip, item.tipo, item.script, item.mensagem)
}

UpdateListViewIncremental() {
    global g_FilteredLogs
    Gui, ListView, LogView
    currentCount := LV_GetCount()
    targetCount := g_FilteredLogs.Length()
    if (targetCount > currentCount) {
        itemsToAdd := targetCount - currentCount
        Loop, %itemsToAdd% {
            item := g_FilteredLogs[A_Index]
            LV_Insert(1, "", item.timestamp, item.socket, item.ip, item.tipo, item.script, item.mensagem)
        }
    }
    else if (targetCount < currentCount) {
        itemsToRemove := currentCount - targetCount
        Loop, %itemsToRemove% {
            LV_Delete(LV_GetCount())
        }
    }
}

RebuildListView() {
    global g_FilteredLogs
    Gui, ListView, LogView
    LV_Delete()
    for index, item in g_FilteredLogs
        LV_Add("", item.timestamp, item.socket, item.ip, item.tipo, item.script, item.mensagem)
}

ShouldShowItem(item) {
    global SearchText, SelectedScripts
    typeVar := "Chk" . item.tipo
    showByType := %typeVar%
    showByText := (SearchText = "") 
                || InStr(item.mensagem, SearchText, false) 
                || InStr(item.script, SearchText, false)
    showByScript := (SelectedScripts["Todos"] = 1) || (SelectedScripts[item.script] = 1)
    return (showByType && showByText && showByScript)
}

ResizeListViewColumns() {
    Gui, ListView, LogView
    col1Width := 140  ; Timestamp
    col2Width := 60   ; Socket  
    col3Width := 100  ; IP
    col4Width := 60   ; Tipo
    col5Width := 120  ; Script
    GuiControlGet, pos, Pos, LogView
    listViewWidth := posW
    scrollBarWidth := 20
    borderWidth := 4
    col6Width := listViewWidth - col1Width - col2Width - col3Width - col4Width - col5Width - scrollBarWidth - borderWidth
    if (col6Width < 100)
        col6Width := 100
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
    scriptsListViewWidth := 200
    newLogViewWidth := A_GuiWidth - scriptsListViewWidth - 30
    newLogViewX := scriptsListViewWidth + 20
    newHeight := A_GuiHeight - 210
    GuiControl, Move, ScriptsListView, % "w" . scriptsListViewWidth . " h" . newHeight
    GuiControl, Move, LogView, % "x" . newLogViewX . " w" . newLogViewWidth . " h" . newHeight
    Gui, ListView, LogView
    ResizeListViewColumns()
return

GuiClose:
    AHKsock_Close()
    ExitApp