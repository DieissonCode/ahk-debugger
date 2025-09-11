;Save_To_Sql=1
;Keep_Versions=5
;@Ahk2Exe-Let U_FileVersion=0.1.3.1
;@Ahk2Exe-SetFileVersion %U_FileVersion%
;@Ahk2Exe-Let U_C=KAH - Logger de Execução de Sistemas
;@Ahk2Exe-SetDescription %U_C%
;@Ahk2Exe-SetMainIcon C:\AHK\icones\dashboard.ico

; ===== Logger-Server.ahk =====
; Servidor para recebimento, exibição e filtragem de logs
; Versão: 1.3.1 - Versão simplificada com limite global + Buffer WARN/ERROR
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
global g_MaxLogsPerScript := 10
global g_LogCounts := {}
global iConnectedClients := 0
global iLogsReceived := 0
global ScriptStats := {}
global g_VirtualMode := true
global g_LastScrollPos := 1
global g_LastSelectedScript := ""
global g_UpdateThreshold := 15
global g_PendingUpdate := false
global g_LastFilterChange := 0
global g_ListViewPaused := false
global g_WarnErrorBuffer := []
global g_MaxWarnErrorBuffer := 50

DebugLogSmart("[SERVER] Script inicializado.")

; GUI - Interface otimizada com espaçamento correto para StatusBar
Gui, +Resize +MinSize580x420 +AlwaysOnTop
Gui, Color, FFFFFF
Gui, Font, s10, Segoe UI

Gui, Add, Text, x10 y10 w350 h25, Servidor de Log (Porta: %PORTA%)
Gui, Add, Button, x+15 w90 h35 gClearLogs, Limpar
Gui, Add, Button, x+10 w120 h35 gExportLogs, Exportar Logs
Gui, Add, Button, x+10 w140 h35 gShowWarnErrorBuffer, Analisar WARN/ERROR

Gui, Add, GroupBox, x10 y55 w520 h180, Filtros e Configurações

; Filtros de tipo
Gui, Add, Checkbox, x20 y80 w85 h25 vChkDEBUG gApplyFilters Checked, DEBUG
Gui, Add, Checkbox, x+5 w85 h25 vChkINFO gApplyFilters Checked, INFO
Gui, Add, Checkbox, x+5 w85 h25 vChkWARN gApplyFilters Checked, WARN
Gui, Add, Checkbox, x+5 w85 h25 vChkERROR gApplyFilters Checked, ERROR
Gui, Add, Checkbox, x+5 w60 h25 vChkLOAD gApplyFilters Checked, LOAD

; Campo de busca
Gui, Add, Text, x20 y110 w70 h25, Buscar:
Gui, Add, Edit, x95 y107 w370 h25 vSearchText gSearchChanged, 

; Limite logs/script global
Gui, Add, Text, x20 y140 w120 h25, Limite logs/script:
Gui, Add, Edit, x145 y137 w80 h25 vMaxLogsInput gUpdateMaxLogs Number, %g_MaxLogsPerScript%
Gui, Add, Button, x230 y136 w70 h27 gApplyMaxLogs, Aplicar

; Modo virtualizado e PAUSA
Gui, Add, Checkbox, x20 y170 w160 h25 vVirtualMode gToggleVirtualMode Checked, Modo Virtualizado
Gui, Add, Checkbox, x200 y170 w180 h25 vPauseListView gTogglePauseListView, Pausar atualização

; Indicador visual de pausa
Gui, Add, Text, x390 y170 w120 h25 vPauseIndicator Center +Border, PAUSADO
GuiControl, Hide, PauseIndicator

; Scripts ListView
Gui, Add, ListView, x10 y245 w250 r18 vScriptsListView +Checked +LV0x10000 gScriptsListViewChanged AltSubmit, Scripts
LV_Add("", "Todos")
SelectedScripts["Todos"] := 0

; Estatísticas - Layout corrigido
Gui, Add, GroupBox, x550 y55 w650 h180, Estatísticas
Gui, Add, Text, x570 y80 w620 h45 vStatsTextGlobal, Scripts conectados: 0 | Logs armazenados: 0 (processados: 0)
Gui, Add, Text, x570 y130 w620 h2 0x10
Gui, Add, Text, x570 y140 w620 h85 vStatsTextScript, Selecione um script específico para ver estatísticas detalhadas

; ListView com espaço adequado para StatusBar (+5px)
Gui, Add, ListView, x270 y245 w880 r18 vLogView -Multi +Grid +LV0x10000, Timestamp|Socket|IP|Tipo|Script|Mensagem
ResizeListViewColumns()

Gui, Add, StatusBar
SB_SetParts(200, 150, 200, 180)
SB_SetText("Logs recebidos: 0", 1)
SB_SetText("Clientes conectados: 0", 2)
SB_SetText("Scripts únicos: 0", 3)
SB_SetText("Status: Ativo | WARN/ERROR: 0", 4)

SysGet, MonitorWorkArea, MonitorWorkArea
serverX := 10
serverY := MonitorWorkAreaBottom - 700

Gui, Show, x%serverX% y%serverY% w1220 h700, Logger Server v1.3.1

; Timer para processar updates pendentes
SetTimer, ProcessPendingUpdates, 500

err := AHKsock_Listen(PORTA, "SocketEventHandler")
DebugLogSmart("[SERVER] AHKsock_Listen chamado. Porta: " PORTA " | Resultado: " (err ? err : "Ativado"))
if (err) {
	DebugLogSmart("[SERVER] Falha ao iniciar servidor. ErrorLevel: " ErrorLevel)
	MsgBox, 16, Erro, Falha ao iniciar o servidor na porta %PORTA%.`nErro AHKsock: %err%`nErrorLevel: %ErrorLevel%
	ExitApp
}
Return

; Timer para processar updates pendentes (reduz rebuilds desnecessários)
ProcessPendingUpdates:
	global g_PendingUpdate, g_LastFilterChange
	if (g_PendingUpdate && A_TickCount - g_LastFilterChange > 800) {
		g_PendingUpdate := false
		ApplyFiltersOptimized(true)
	}
return

SocketEventHandler(sEvent, iSocket, sName, sAddr, sPort, ByRef bData, bDataLength) {
	global iConnectedClients, iLogsReceived, g_aLogs, ActiveScripts, ScriptStats

	if (sEvent = "ACCEPTED") {
		iConnectedClients++
		SB_SetText("Clientes conectados: " iConnectedClients, 2)
	}
	else if (sEvent = "RECEIVED") {
		dataStr := StrGet(&bData, bDataLength, "UTF-8")
		linhas := StrSplit(dataStr, "&&") ; separa por nova linha
		for _, linha in linhas {
			if (linha = "")
				continue

			partes := StrSplit(linha, "||")
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
			AddToWarnErrorBuffer(newMsg)
			wasRemoved := AddLogWithLimit(newMsg)
			if (!g_ListViewPaused) {
				ApplyFiltersSmartUpdate(newMsg, wasRemoved)
			}
			UpdateScriptSpecificStatsIfSelected(scriptName)
		}
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
		wasRemoved := AddLogWithLimit(disconnectMsg)

		if (!g_ListViewPaused) {
			ApplyFiltersSmartUpdate(disconnectMsg, wasRemoved)
		}
	}
}

; Adiciona WARN e ERROR ao buffer separado
AddToWarnErrorBuffer(newMsg) {
	global g_WarnErrorBuffer, g_MaxWarnErrorBuffer

	if (newMsg.tipo = "WARN" || newMsg.tipo = "ERROR") {
		; Adiciona no início do array
		g_WarnErrorBuffer.InsertAt(1, newMsg)
		
		; Remove excesso se necessário
		while (g_WarnErrorBuffer.Length() > g_MaxWarnErrorBuffer) {
			g_WarnErrorBuffer.RemoveAt(g_WarnErrorBuffer.Length())
		}
		
		; Atualiza StatusBar
		UpdateWarnErrorCount()
		DebugLogSmart("[SERVER] Adicionado ao buffer WARN/ERROR: " . newMsg.tipo . " - " . newMsg.script)
	}
}

; Atualiza contador WARN/ERROR na StatusBar
UpdateWarnErrorCount() {
	global g_WarnErrorBuffer, g_ListViewPaused
	warnCount := 0
	errorCount := 0

	for _, item in g_WarnErrorBuffer {
		if (item.tipo = "WARN")
			warnCount++
		else if (item.tipo = "ERROR")
			errorCount++
	}

	statusText := "Status: " . (g_ListViewPaused ? "Pausado" : "Ativo") 
				. " | W:" . warnCount . "/E:" . errorCount . " (" . g_WarnErrorBuffer.Length() . "/50)"
	SB_SetText(statusText, 4)
}

; Exibe janela de análise de WARN/ERROR
ShowWarnErrorBuffer:
	global g_WarnErrorBuffer

	if (g_WarnErrorBuffer.Length() = 0) {
		MsgBox, 64, Buffer WARN/ERROR, Nenhum evento WARN ou ERROR foi registrado ainda.
		return
	}

	; Criar GUI de análise
	Gui, WarnError:+Resize +MinSize600x400 +AlwaysOnTop
	Gui, WarnError:Color, FFFFFF
	Gui, WarnError:Font, s10, Segoe UI

	; Título e estatísticas
	warnCount := 0
	errorCount := 0
	for _, item in g_WarnErrorBuffer {
		if (item.tipo = "WARN")
			warnCount++
		else if (item.tipo = "ERROR")
			errorCount++
	}

	titleText := "Análise de WARN/ERROR - Total: " . g_WarnErrorBuffer.Length() 
			   . " (WARN: " . warnCount . " | ERROR: " . errorCount . ")"
	Gui, WarnError:Add, Text, x10 y10 w580 h25 Center, %titleText%

	; Filtros específicos
	Gui, WarnError:Add, GroupBox, x10 y40 w580 h50, Filtros
	Gui, WarnError:Add, Checkbox, x20 y60 w80 h25 vWEChkWARN gFilterWarnError Checked, WARN
	Gui, WarnError:Add, Checkbox, x+20 w80 h25 vWEChkERROR gFilterWarnError Checked, ERROR
	Gui, WarnError:Add, Text, x+20 w60 h25, Script:
	Gui, WarnError:Add, ComboBox, x+5 w150 h200 vWEScriptFilter gFilterWarnError, Todos

	; Preencher ComboBox com scripts únicos
	scriptsInBuffer := {}
	for _, item in g_WarnErrorBuffer {
		scriptsInBuffer[item.script] := true
	}
	for script in scriptsInBuffer {
		GuiControl, WarnError:, WEScriptFilter, %script%
	}

	; ListView dos eventos - POSICIONAMENTO CORRETO
	Gui, WarnError:Add, ListView, x10 y100 w580 r20 vWELogView -Multi +Grid, Timestamp|Tipo|Script|Mensagem

	; Calcular posição Y correta para os botões
	; Y da ListView (100) + altura da ListView (20 linhas * 16px + header + bordas) ≈ 100 + 340 = 440
	buttonY := 450

	; Botões na posição correta
	Gui, WarnError:Add, Button, x10 y%buttonY% w100 h30 gExportWarnError, Exportar CSV
	Gui, WarnError:Add, Button, x120 y%buttonY% w100 h30 gClearWarnError, Limpar Buffer
	Gui, WarnError:Add, Button, x490 y%buttonY% w100 h30 gCloseWarnError, Fechar

	; Altura total da janela
	totalHeight := buttonY + 45

	; Posicionar janela
	Gui, WarnError:Show, w600 h%totalHeight%, Análise WARN/ERROR

	; Preencher ListView inicial
	FilterWarnErrorList()
return

; Filtros da janela WARN/ERROR
FilterWarnError:
	FilterWarnErrorList()
return

FilterWarnErrorList() {
	global g_WarnErrorBuffer

	Gui, WarnError:Submit, NoHide

	; CORRIGIDO: Definir a ListView correta antes de popular
	Gui, WarnError:ListView, WELogView
	LV_Delete()

	; Filtrar e adicionar itens
	for _, item in g_WarnErrorBuffer {
		showItem := true
		
		; Filtro por tipo
		if (item.tipo = "WARN" && !WEChkWARN)
			showItem := false
		if (item.tipo = "ERROR" && !WEChkERROR)
			showItem := false
		
		; Filtro por script
		if (WEScriptFilter != "Todos" && item.script != WEScriptFilter)
			showItem := false
		
		if (showItem) {
			LV_Add("", item.timestamp, item.tipo, item.script, item.mensagem)
		}
	}

	; Redimensionar colunas
	LV_ModifyCol(1, 140)  ; Timestamp
	LV_ModifyCol(2, 60)   ; Tipo
	LV_ModifyCol(3, 120)  ; Script
	LV_ModifyCol(4, 240)  ; Mensagem
}

; Exportar buffer WARN/ERROR
ExportWarnError:
	global g_WarnErrorBuffer

	FormatTime, timestamp,, yyyy-MM-dd_HHmmss
	FileSelectFile, outputFile, S16, %A_Desktop%\warn_error_analysis_%timestamp%.csv, Exportar WARN/ERROR, CSV Files (*.csv)
	if (outputFile = "")
		return
	if !InStr(outputFile, ".csv")
		outputFile .= ".csv"

	fileContent := "Timestamp,Tipo,Script,Mensagem`n"
	for _, item in g_WarnErrorBuffer {
		mensagemEscaped := RegExReplace(item.mensagem, """", """""")
		scriptEscaped := RegExReplace(item.script, """", """""")
		fileContent .= item.timestamp . ","
					. item.tipo . ","
					. """" . scriptEscaped . """" . ","
					. """" . mensagemEscaped . """`n"
	}

	FileDelete, %outputFile%
	FileAppend, %fileContent%, %outputFile%, UTF-8

	if (!ErrorLevel) {
		MsgBox, 64, Exportação, Eventos WARN/ERROR exportados com sucesso!`n%outputFile%
	}
return

; Limpar buffer WARN/ERROR
ClearWarnError:
	MsgBox, 36, Confirmação, Tem certeza que deseja limpar o buffer de WARN/ERROR?`n`nEsta ação não pode ser desfeita.
	IfMsgBox, Yes
	{
		g_WarnErrorBuffer := []
		UpdateWarnErrorCount()
		FilterWarnErrorList()
		DebugLogSmart("[SERVER] Buffer WARN/ERROR limpo")
	}
return

; Fechar janela de análise
CloseWarnError:
	Gui, WarnError:Destroy
return

; Toggle para pausar/despausar atualização da ListView
TogglePauseListView:
	GuiControlGet, PauseListView
	g_ListViewPaused := PauseListView

	if (g_ListViewPaused) {
		; Pausado - mostra indicador visual
		GuiControl, Show, PauseIndicator
		GuiControl,, PauseIndicator, ⏸ PAUSADO
		UpdateWarnErrorCount()
		DebugLogSmart("[SERVER] ListView pausada")
	} else {
		; Despausado - esconde indicador e força atualização
		GuiControl, Hide, PauseIndicator
		UpdateWarnErrorCount()
		DebugLogSmart("[SERVER] ListView despausada - forçando atualização")
		; Força rebuild completo para sincronizar com logs acumulados
		ApplyFiltersOptimized(true)
	}
return

; Update inteligente que limpa logs antigos sem rebuild
ApplyFiltersSmartUpdate(newItem, wasLogRemoved := false) {
	global g_aLogs, g_FilteredLogs, g_VirtualMode, g_ListViewPaused

	; Se pausado, não atualiza a ListView
	if (g_ListViewPaused) {
		return
	}

	if (!g_VirtualMode) {
		ApplyFiltersOptimized(true)
		return
	}

	Gui, ListView, LogView

	; Se um log foi removido dos dados, precisa sincronizar a ListView
	if (wasLogRemoved) {
		; Remove item mais antigo da ListView (se existir na visualização)
		RemoveOldestFromListView(newItem.script)
	}

	; Verifica se o novo log passaria pelos filtros atuais
	if (ShouldShowItem(newItem)) {
		; Adiciona o novo item no topo da ListView
		LV_Insert(1, "", newItem.timestamp, newItem.socket, newItem.ip, newItem.tipo, newItem.script, newItem.mensagem)
		g_FilteredLogs.InsertAt(1, newItem)
		
		; Atualiza status bar
		SB_SetText("Logs exibidos: " . LV_GetCount() . " / " . g_aLogs.Length(), 1)
	}
}

; Remove o item mais antigo do mesmo script da ListView
RemoveOldestFromListView(scriptName) {
	global g_FilteredLogs

	Gui, ListView, LogView

	; Procura o item mais antigo do mesmo script na ListView (de baixo para cima)
	Loop, % LV_GetCount() {
		reverseIndex := LV_GetCount() - A_Index + 1
		if (reverseIndex > 0) {
			LV_GetText(lvScript, reverseIndex, 5)  ; Coluna 5 = Script
			if (lvScript = scriptName) {
				; Remove da ListView e do array filtrado
				LV_Delete(reverseIndex)
				if (reverseIndex <= g_FilteredLogs.Length()) {
					g_FilteredLogs.RemoveAt(reverseIndex)
				}
				break
			}
		}
	}
}

; --------- Limite global simplificado ---------
AddLogWithLimit(newMsg) {
	global g_aLogs, g_LogCounts, g_MaxLogsPerScript

	scriptName := newMsg.script
	if (!g_LogCounts.HasKey(scriptName))
		g_LogCounts[scriptName] := 0

	wasRemoved := false

	; Remove logs antigos se necessário ANTES de adicionar
	if (g_LogCounts[scriptName] >= g_MaxLogsPerScript) {
		Loop, % g_aLogs.Length() {
			reverseIndex := g_aLogs.Length() - A_Index + 1
			if (reverseIndex > 0 && g_aLogs[reverseIndex].script = scriptName) {
				g_aLogs.RemoveAt(reverseIndex)
				g_LogCounts[scriptName]--
				wasRemoved := true
				break
			}
		}
	}

	; Adiciona o novo log
	g_aLogs.InsertAt(1, newMsg)
	g_LogCounts[scriptName]++

	; Verificação de segurança
	if (g_LogCounts[scriptName] > g_MaxLogsPerScript) {
		Loop, % g_aLogs.Length() {
			reverseIndex := g_aLogs.Length() - A_Index + 1
			if (reverseIndex > 0 && g_aLogs[reverseIndex].script = scriptName) {
				g_aLogs.RemoveAt(reverseIndex)
				g_LogCounts[scriptName]--
				wasRemoved := true
				if (g_LogCounts[scriptName] <= g_MaxLogsPerScript)
					break
			}
		}
	}

	return wasRemoved
}

; --------- GUI handlers ---------
ApplyMaxLogs:
	GuiControlGet, MaxLogsInput
	if (MaxLogsInput > 0 && MaxLogsInput <= 10000) {
		g_MaxLogsPerScript := MaxLogsInput
		TrimLogsToLimit()
		; Se não estiver pausado, atualiza a ListView
		if (!g_ListViewPaused) {
			ApplyFiltersOptimized(true)
		}
		UpdateStatsDisplay()
	}
return

TrimLogsToLimit() {
	global g_aLogs, g_LogCounts, g_MaxLogsPerScript, g_FilteredLogs

	; Reset contadores
	for script in g_LogCounts
		g_LogCounts[script] := 0

	newLogs := []
	for _, item in g_aLogs {
		scriptName := item.script
		if (!g_LogCounts.HasKey(scriptName))
			g_LogCounts[scriptName] := 0
		if (g_LogCounts[scriptName] < g_MaxLogsPerScript) {
			newLogs.Push(item)
			g_LogCounts[scriptName]++
		}
	}
	g_aLogs := newLogs

	; Limpa g_FilteredLogs para forçar reconstrução
	g_FilteredLogs := []
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
	UpdateWarnErrorCount()
	; Se não estiver pausado, aplica a mudança
	if (!g_ListViewPaused) {
		ScheduleUpdate()
	}
return

; Agenda atualização em vez de fazer imediatamente
ScheduleUpdate() {
	global g_PendingUpdate, g_LastFilterChange
	g_PendingUpdate := true
	g_LastFilterChange := A_TickCount
}

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
	GuiControl,, StatsTextScript, Selecione um script específico para ver estatísticas detalhadas
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
return

; --------- Scripts, Filtros, ListView ---------
AddScriptToRegistry(scriptName) {
	global ActiveScripts, ScriptStats, SelectedScripts, g_LogCounts
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
}

UpdateScriptSpecificStatsIfSelected(scriptName) {
	global SelectedScripts, g_LastSelectedScript

	selectedScript := ""
	for script, isSelected in SelectedScripts {
		if (script != "Todos" && isSelected = 1) {
			selectedScript := script
			break
		}
	}

	if (selectedScript != "" && selectedScript = scriptName) {
		UpdateScriptSpecificStats(scriptName)
	}
}

UpdateStatsDisplay() {
	global ScriptStats, ActiveScripts, g_LogCounts, g_MaxLogsPerScript
	totalDebug := 0, totalInfo := 0, totalWarn := 0, totalError := 0, totalLoad := 0, totalProcessed := 0
	totalStored := 0

	for i, script in ActiveScripts
		if (ScriptStats.HasKey(script)) {
			totalDebug += ScriptStats[script, "DEBUG"]
			totalInfo += ScriptStats[script, "INFO"]
			totalWarn += ScriptStats[script, "WARN"]
			totalError += ScriptStats[script, "ERROR"]
			totalLoad += ScriptStats[script, "LOAD"]
			totalProcessed += ScriptStats[script, "total"]
		}

	for script, count in g_LogCounts
		totalStored += count

	statsText := "Scripts conectados: " . ActiveScripts.Length() 
			  . " | Logs armazenados: " . totalStored . " (processados: " . totalProcessed . ")"
			  . " | Limite: " . g_MaxLogsPerScript . "/script"
			  . "`nDEBUG=" . totalDebug 
			  . " | INFO=" . totalInfo 
			  . " | WARN=" . totalWarn 
			  . " | ERROR=" . totalError
			  . " | LOAD=" . totalLoad
	GuiControl,, StatsTextGlobal, %statsText%
}

UpdateScriptSpecificStats(scriptName) {
	global ScriptStats, SelectedScripts, g_LogCounts, g_MaxLogsPerScript, g_LastSelectedScript

	g_LastSelectedScript := scriptName
	scriptStatsText := "Selecione um script específico para ver estatísticas detalhadas"

	if (scriptName && scriptName != "Todos" && ScriptStats.HasKey(scriptName)) {
		debug := ScriptStats[scriptName, "DEBUG"]
		info := ScriptStats[scriptName, "INFO"]
		warn := ScriptStats[scriptName, "WARN"]
		error := ScriptStats[scriptName, "ERROR"]
		load := ScriptStats[scriptName, "LOAD"]
		total := ScriptStats[scriptName, "total"]
		currentCount := g_LogCounts.HasKey(scriptName) ? g_LogCounts[scriptName] : 0
		if (total > 0) {
			debugPct := Round((debug / total) * 100)
			infoPct := Round((info / total) * 100)
			warnPct := Round((warn / total) * 100)
			errorPct := Round((error / total) * 100)
			loadPct := Round((load / total) * 100)
			scriptStatsText := "Script Selecionado: " . scriptName 
							. " | Logs armazenados: " . currentCount . "/" . g_MaxLogsPerScript
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
			GuiControl,, StatsTextScript, Exibindo logs de todos os scripts selecionados
		} else {
			allChecked := true
			selectedScript := ""
			Loop, % LV_GetCount() {
				if (A_Index > 1) {
					LV_GetText(rowScript, A_Index)
					if (SelectedScripts[rowScript] = 0) {
						allChecked := false
					} else {
						selectedScript := rowScript
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
			if (selectedScript != "") {
				UpdateScriptSpecificStats(selectedScript)
			} else {
				GuiControl,, StatsTextScript, Selecione um script específico para ver estatísticas detalhadas
			}
		}
		; Se não estiver pausado, aplica os filtros
		if (!g_ListViewPaused) {
			ScheduleUpdate()
		}
	}
return

SearchChanged:
	GuiControlGet, SearchText
	; Se não estiver pausado, agenda update
	if (!g_ListViewPaused) {
		SetTimer, ApplyFiltersTimer, -500
	}
return

ApplyFiltersTimer:
	ScheduleUpdate()
return

; --------- ListView / Virtualização ---------
ApplyFilters:
	; Se não estiver pausado, agenda update
	if (!g_ListViewPaused) {
		ScheduleUpdate()
	}
return

ApplyFiltersOptimized(forceUpdate := false) {
	global g_aLogs, SearchText, SelectedScripts, g_FilteredLogs, g_VirtualMode, g_LastScrollPos, g_UpdateThreshold, g_ListViewPaused
	static lastSearchText := ""
	static lastChkDEBUG := ""
	static lastChkINFO := ""
	static lastChkWARN := ""
	static lastChkERROR := ""
	static lastChkLOAD := ""
	static lastLogsLength := 0
	static lastSelectedHash := ""
	static lastLogsSignature := ""

	; Se pausado, não atualiza
	if (g_ListViewPaused && !forceUpdate) {
		return
	}

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
	global g_aLogs, g_FilteredLogs, SearchText, SelectedScripts, g_LastScrollPos, g_UpdateThreshold

	g_FilteredLogs := []
	for index, item in g_aLogs
		if (ShouldShowItem(item))
			g_FilteredLogs.Push(item)

	Gui, ListView, LogView
	currentCount := LV_GetCount()
	newCount := g_FilteredLogs.Length()

	if (Abs(newCount - currentCount) > g_UpdateThreshold || currentCount = 0) {
		RebuildListView()
	} else {
		firstThreeValid := true
		if (currentCount > 0 && newCount > 0) {
			Loop, 3 {
				if (A_Index <= currentCount && A_Index <= newCount) {
					LV_GetText(lvTimestamp, A_Index, 1)
					LV_GetText(lvScript, A_Index, 5)
					if (g_FilteredLogs[A_Index].timestamp != lvTimestamp || g_FilteredLogs[A_Index].script != lvScript) {
						firstThreeValid := false
						break
					}
				}
			}
		}
		
		if (firstThreeValid)
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
	col1Width := 140
	col2Width := 60
	col3Width := 100
	col4Width := 60
	col5Width := 120
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

	scriptsListViewWidth := 250
	statusBarHeight := 25
	newLogViewWidth := A_GuiWidth - scriptsListViewWidth - 30
	newLogViewX := scriptsListViewWidth + 20
	newHeight := A_GuiHeight - 245 - statusBarHeight

	GuiControl, Move, ScriptsListView, % "w" . scriptsListViewWidth . " h" . newHeight
	GuiControl, Move, LogView, % "x" . newLogViewX . " w" . newLogViewWidth . " h" . newHeight
	Gui, ListView, LogView
	ResizeListViewColumns()
return

GuiClose:
	AHKsock_Close()
	ExitApp