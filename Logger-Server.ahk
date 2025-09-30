;Save_To_Sql=1
;Keep_Versions=5
;@Ahk2Exe-Let U_FileVersion=0.1.3.1
;@Ahk2Exe-SetFileVersion %U_FileVersion%
;@Ahk2Exe-Let U_C=KAH - Logger de Execução de Sistemas
;@Ahk2Exe-SetDescription %U_C%
;@Ahk2Exe-SetMainIcon C:\AHK\icones\dashboard.ico

; ===== Logger-Server.ahk =====
; Servidor para recebimento, exibição e filtragem de logs
; Data: 2025-09-09
; Autor: Dieisson Code
; Repositório: https://github.com/DieissonCode/ahk-debugger

#SingleInstance Force
#Include C:\Autohotkey 2024\Root\Libs\socket.ahk
#Include C:\AutoHotkey\class\functions.ahk

global g_Server
g_Server := new LoggerServer(4041)
g_Server.Start()
Return

; ========================== LABELS (Wrapper para métodos) ==========================
	Server_ProcessPendingUpdates:
		g_Server.ProcessPendingUpdates()
		Return
	Server_ShowWarnErrorBuffer:
		g_Server.ShowWarnErrorBuffer()
		Return
	Server_FilterWarnError:
		g_Server.FilterWarnErrorList()
		Return
	Server_ExportWarnError:
		g_Server.ExportWarnError()
		Return
	Server_ClearWarnError:
		g_Server.ClearWarnErrorBuffer()
		Return
	Server_CloseWarnError:
		g_Server.CloseWarnErrorWindow()
		Return
	Server_TogglePauseListView:
		g_Server.TogglePauseListView()
		Return
	Server_ApplyMaxLogs:
		g_Server.ApplyMaxLogs()
		Return
	Server_UpdateMaxLogs:
		g_Server.UpdateMaxLogs()
		Return
	Server_ToggleVirtualMode:
		g_Server.ToggleVirtualMode()
		Return
	Server_ClearLogs:
		g_Server.ClearLogs()
		Return
	Server_ExportLogs:
		g_Server.ExportLogs()
		Return
	Server_ScriptsListViewChanged:
		g_Server.ScriptsListViewChanged()
		Return
	Server_SearchChanged:
		g_Server.SearchChanged()
		Return
	Server_ApplyFiltersTimer:
		g_Server.ApplyFiltersTimer()
		Return
	Server_ApplyFilters:
		g_Server.ApplyFilters()
		Return
	Server_LogViewEvent:
		g_Server.LogViewEvent()
		Return
	Server_ShowMotionDetection:
		g_Server.ShowMotionDetectionGui()
		Return
	Server_RefreshMotionDetection:
		g_Server.RefreshMotionDetectionList()
		Return
	MotionDetection_GuiSize:
		g_Server.MotionDetectionGuiSize()
		Return
	MotionDetection_Close:
		g_Server.CloseMotionDetectionGui()
		Return
	GuiSize:
		g_Server.GuiSize()
		Return
	GuiClose:
		g_Server.GuiClose()
		Return

	SocketEventHandler(sEvent, iSocket, sName, sAddr, sPort, ByRef bData, bDataLength) {
		global g_Server
		g_Server.HandleSocketEvent(sEvent, iSocket, sName, sAddr, sPort, bData, bDataLength)
	}

; ============================== CLASSE PRINCIPAL =================================
	class LoggerServer {
		__New(port := 4041) {
			this.port := port
			this.timestampFormat := "yyyy-MM-dd HH:mm:ss"
			this.defaultFilter := {DEBUG: 1, INFO: 1, WARN: 1, ERROR: 1, LOAD: 1}
			this.logs := []
			this.filteredLogs := []
			this.searchText := ""
			this.activeScripts := []
			this.selectedScripts := {}
			this.maxLogsPerScript := 10
			this.logCounts := {}                     ; logCounts[script][tipo]
			this.connectedClients := 0
			this.logsReceived := 0
			this.scriptStats := {}
			this.virtualMode := true
			this.lastScrollPos := 1
			this.lastSelectedScript := ""
			this.updateThreshold := 15
			this.pendingUpdate := false
			this.lastFilterChange := 0
			this.listViewPaused := false
			this.warnErrorBuffer := []
			this.maxWarnErrorBuffer := 50
			this.warnErrorWindowOpen := false
			this.lastContextIP := ""
			this.motionDetectionStats := {}          ; motionDetectionStats[ip] := {name: <>, count: N}
			this.motionDetectionWindowOpen := false
			DebugLogSmart("[SERVER] Instância LoggerServer criada (porta: " . this.port . ")")
		}

		Start() {
			this.InitGUI()
			this.StartListening()
			SetTimer, Server_ProcessPendingUpdates, 500
		}

		InitGUI() {
			global
			Gui, +Resize +MinSize580x420
			Gui, Color, FFFFFF
			Gui, Font, s10, Segoe UI
			Gui, Add, Text, x10 y10 w350 h25,% "Servidor de Log (Porta: " . this.port . ")"
			Gui, Add, Button, x+15 w90 h35 gServer_ClearLogs, Limpar
			Gui, Add, Button, x+10 w120 h35 gServer_ExportLogs, Exportar Logs
			Gui, Add, Button, x+10 w140 h35 gServer_ShowWarnErrorBuffer, Analisar WARN/ERROR
			Gui, Add, Button, x+10 w170 h35 gServer_ShowMotionDetection, Motion Detection
			Gui, Add, GroupBox, x10 y55 w520 h180, Filtros e Configurações
			Gui, Add, Checkbox, x20 y80 w85 h25 vChkDEBUG gServer_ApplyFilters Checked, DEBUG
			Gui, Add, Checkbox, x+5 w85 h25 vChkINFO gServer_ApplyFilters Checked, INFO
			Gui, Add, Checkbox, x+5 w85 h25 vChkWARN gServer_ApplyFilters Checked, WARN
			Gui, Add, Checkbox, x+5 w85 h25 vChkERROR gServer_ApplyFilters Checked, ERROR
			Gui, Add, Checkbox, x+5 w60 h25 vChkLOAD gServer_ApplyFilters Checked, LOAD
			Gui, Add, Text, x20 y110 w70 h25, Buscar:
			Gui, Add, Edit, x95 y107 w370 h25 vSearchText gServer_SearchChanged,
			Gui, Add, Text, x20 y140 w160 h25,% "Limite por tipo/script:"
			Gui, Add, Edit, x185 y137 w80 h25 vMaxLogsInput gServer_UpdateMaxLogs Number,% this.maxLogsPerScript
			Gui, Add, Button, x270 y136 w70 h27 gServer_ApplyMaxLogs, Aplicar
			Gui, Add, Checkbox, x20 y170 w160 h25 vVirtualMode gServer_ToggleVirtualMode Checked, Modo Virtualizado
			Gui, Add, Checkbox, x200 y170 w180 h25 vPauseListView gServer_TogglePauseListView, Pausar atualização
			Gui, Add, Text, x390 y170 w120 h25 vPauseIndicator Center +Border, PAUSADO
			GuiControl, Hide, PauseIndicator
			Gui, Add, ListView, x10 y245 w250 r18 vScriptsListView +Checked +LV0x10000 gServer_ScriptsListViewChanged AltSubmit, Scripts
			LV_Add("", "Todos")
			this.selectedScripts["Todos"] := 0
			Gui, Add, GroupBox, x550 y55 w650 h180, Estatísticas
			Gui, Add, Text, x570 y80 w620 h45 vStatsTextGlobal, Scripts conectados: 0 | Logs armazenados: 0 (processados: 0)
			Gui, Add, Text, x570 y130 w620 h2 0x10
			Gui, Add, Text, x570 y140 w620 h85 vStatsTextScript, Selecione um script específico para ver estatísticas detalhadas
			Gui, Add, ListView, x270 y245 w880 r18 vLogView -Multi +Grid +LV0x10000 gServer_LogViewEvent AltSubmit, Timestamp|Socket|IP|Tipo|Script|Mensagem
			this.ResizeListViewColumns()
			Gui, Add, StatusBar
			SB_SetParts(200, 150, 200, 230)
			SB_SetText("Logs exibidos: 0", 1)
			SB_SetText("Clientes conectados: 0", 2)
			SB_SetText("Scripts únicos: 0", 3)
			SB_SetText("Status: Ativo | WARN/ERROR: 0", 4)
			SysGet, MonitorWorkArea, MonitorWorkArea
			serverX := 10
			serverY := MonitorWorkAreaBottom - 700
			Gui, Show, x%serverX% y%serverY% w1220 h700, Logger Server v1.3.1
		}

		; ===================== MOTION DETECTION GUI =====================
			ShowMotionDetectionGui() {
				Global
				if (this.motionDetectionWindowOpen) {
					WinActivate, Motion Detection
						Return
				}
				
				this.motionDetectionWindowOpen := true
				Gui, motionDetection:+Resize +MinSize400x300
				Gui, motionDetection:Color, FFFFFF
				Gui, motionDetection:Font, s10, Segoe UI
				Gui, motionDetection:Add, Text, x10 y10 w480 h25 Center,% "Monitoramento de Detecção de Movimento"
				Gui, motionDetection:Add, ListView, x10 y40 w480 r15 vMotionListView +Grid, IP|Nome|Detecções
				Gui, motionDetection:Add, Button, x390 y300 w100 h30 gMotionDetection_Close vMotionCloseBtn, Fechar
				Gui, motionDetection:Show, w500 h340, Motion Detection
				this.RefreshMotionDetectionList()
				SetTimer, Server_RefreshMotionDetection, 5000
			}

			RefreshMotionDetectionList() {
				if (!this.motionDetectionWindowOpen)
						Return
				Gui, motionDetection:ListView, MotionListView
				LV_Delete()
				for ip, cam in this.motionDetectionStats
					LV_Add("", ip, cam.name, cam.count)
				LV_ModifyCol(1, 120)
				LV_ModifyCol(2, 200)
				LV_ModifyCol(3, 100)
			}

			MotionDetectionGuiSize() {
				if (!this.motionDetectionWindowOpen)
						Return
				Gui, motionDetection:Default
				WinGetPos,,, w, h, Motion Detection
				listTop := 40
				listLeft := 10
				listWidth := w - 20
				buttonHeight := 34
				margin := 10
				listHeight := h - listTop - buttonHeight - (margin * 2)
				if (listHeight < 80)
					listHeight := 80
				GuiControl, Move, MotionListView,% "x" listLeft " y" listTop " w" listWidth " h" listHeight
				btnY := listTop + listHeight + 5
				btnX := w - 110
				GuiControl, Move, MotionCloseBtn,% "x" btnX " y" btnY " w100 h" (buttonHeight - 4)
			}

			CloseMotionDetectionGui() {
				SetTimer, Server_RefreshMotionDetection, Off
				Gui, motionDetection:Destroy
				this.motionDetectionWindowOpen := false
			}

			TryRegisterMotionDetection(newMsg) {
				if (newMsg.tipo != "DEBUG")
						Return
				if !(SubStr(newMsg.mensagem, 1, 13) = "CheckImages - ")
						Return
				; Padrão: CheckImages - <IP> - <Nome> - ...
				if (RegExMatch(newMsg.mensagem, "CheckImages - ([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+) - ([^ ]]+)", r1)) {
					ip := r11
					nome := r12
				} else if (RegExMatch(newMsg.mensagem, "CheckImages - ([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)", r2)) {
					ip := r21
					nome := "CAM-" . ip
				} else {
						Return
				}
				if (!this.motionDetectionStats.HasKey(ip))
					this.motionDetectionStats[ip] := {name: nome, count: 0}
				this.motionDetectionStats[ip].name := nome
				this.motionDetectionStats[ip].count += 1
			}

		; ===================== SOCKET / RECEPÇÃO =======================
			StartListening() {
				err := AHKsock_Listen(this.port, "SocketEventHandler")
				if (err) {
					MsgBox, 16, Erro,% "Falha ao iniciar o servidor na porta " . this.port . ".`nErro AHKsock: " . err . "`nErrorLevel: " . ErrorLevel
					ExitApp
				}
			}

			HandleSocketEvent(sEvent, iSocket, sName, sAddr, sPort, ByRef bData, bDataLength) {
				if (sEvent = "ACCEPTED") {
					this.connectedClients++
					SB_SetText("Clientes conectados: " . this.connectedClients, 2)
				} else if (sEvent = "RECEIVED") {
					dataStr := StrGet(&bData, bDataLength, "UTF-8")
					partes := StrSplit(dataStr, "||")
					tipo := "N/A", scriptName := "N/A", mensagem := "N/A"
					for _, parte in partes {
						if (SubStr(parte, 1, 5) = "tipo=" || SubStr(parte, 1, 5) = "type=")
							tipo := SubStr(parte, 6)
						else if (SubStr(parte, 1, 11) = "scriptName=")
							scriptName := SubStr(parte, 12)
						else if (SubStr(parte, 1, 9) = "mensagem=" || SubStr(parte, 1, 8) = "message=")
							mensagem := SubStr(parte, InStr(parte, "=") + 1)
					}
					;If	!A_IsCompiled && InStr(dataStr, "18 - mdkah")
						;msgbox, %dataStr%
					this.AddScriptToRegistry(scriptName)
					this.UpdateScriptStats(scriptName, tipo)
					FormatTime, timestamp,, % this.timestampFormat
					this.logsReceived++
					newMsg := {timestamp: timestamp, socket: iSocket, ip: sAddr, tipo: tipo, script: scriptName, mensagem: mensagem}
					this.AddToWarnErrorBuffer(newMsg)
					wasRemoved := this.AddLogWithLimit(newMsg)
					this.TryRegisterMotionDetection(newMsg)
					if (!this.listViewPaused)
						this.ApplyFiltersSmartUpdate(newMsg, wasRemoved)
					this.UpdateScriptSpecificStatsIfSelected(scriptName)
					this.UpdateStatsDisplay()
				} else if (sEvent = "DISCONNECTED") {
					this.connectedClients--
					if (this.connectedClients < 0)
						this.connectedClients := 0
					SB_SetText("Clientes conectados: " . this.connectedClients, 2)
					scriptName := ""
					for _, item in this.logs
						if (item.socket = iSocket && item.ip = sAddr && item.script != "N/A") {
							scriptName := item.script
							break
						}
					FormatTime, timestamp,, % this.timestampFormat
					disconnectMsg := {timestamp: timestamp, socket: iSocket, ip: sAddr, tipo: "INFO", script: scriptName, mensagem: "Script desconectado"}
					wasRemoved := this.AddLogWithLimit(disconnectMsg)
					if (!this.listViewPaused)
						this.ApplyFiltersSmartUpdate(disconnectMsg, wasRemoved)
					this.UpdateStatsDisplay()
				}
			}

		; ===================== CONTEXT MENU / IP EXTRAÇÃO =====================
			LogViewEvent() {
				if (A_GuiEvent = "R") {
					row := A_EventInfo
					if (row > 0) {
						Gui, ListView, LogView
						LV_GetText(fullMsg, row, 6)
						ip := this.ExtractIPFromMessage(fullMsg)
						this.lastContextIP := ip
						if (ip != "")
							g_Server.OpenIPInEdge()
					}
				}
			}

			ExtractIPFromMessage(msg) {
				ipPattern := "((?:(?:25[0-5]|2[0-4]\d|1?\d?\d)\.){3}(?:25[0-5]|2[0-4]\d|1?\d?\d))(?:\:\d+)?"
				if RegExMatch(msg, ipPattern, m)
						Return m1
				simplePattern := "(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})(:\d+)?"
				if RegExMatch(msg, simplePattern, m2)
						Return m21
					Return ""
			}

			OpenIPInEdge() {
				ip := this.lastContextIP
				if (!ip || ip = "")
						Return
				url := ip
				if !(SubStr(url, 1, 7) = "http://" || SubStr(url, 1, 8) = "https://")
					url := "http://" . url
				Run, % "microsoft-edge:" . url
			}

		; ===================== WARN / ERROR BUFFER =====================
			AddToWarnErrorBuffer(newMsg) {
				if (newMsg.tipo = "WARN" || newMsg.tipo = "ERROR") {
					this.warnErrorBuffer.InsertAt(1, newMsg)
					while (this.warnErrorBuffer.Length() > this.maxWarnErrorBuffer)
						this.warnErrorBuffer.RemoveAt(this.warnErrorBuffer.Length())
					this.UpdateWarnErrorCount()
				}
			}
			UpdateWarnErrorCount() {
				warnCount := 0, errorCount := 0
				for _, item in this.warnErrorBuffer {
					if (item.tipo = "WARN")
						warnCount++
					else if (item.tipo = "ERROR")
						errorCount++
				}
				statusText := "Status: " . (this.listViewPaused ? "Pausado" : "Ativo")
						. " | W:" . warnCount . "/E:" . errorCount . " (" . this.warnErrorBuffer.Length() . "/50)"
				SB_SetText(statusText, 4)
			}
			ShowWarnErrorBuffer() {
				if (this.warnErrorBuffer.Length() = 0) {
					MsgBox, 64, Buffer WARN/ERROR, Nenhum evento WARN ou ERROR foi registrado ainda.
						Return
				}
				this.warnErrorWindowOpen := true
				Gui, WarnError:+Resize +MinSize600x400
				Gui, WarnError:Color, FFFFFF
				Gui, WarnError:Font, s10, Segoe UI
				warnCount := 0, errorCount := 0
				for _, item in this.warnErrorBuffer {
					if (item.tipo = "WARN")
						warnCount++
					else if (item.tipo = "ERROR")
						errorCount++
				}
				titleText := "Análise de WARN/ERROR - Total: " . this.warnErrorBuffer.Length()
						. " (WARN: " . warnCount . " | ERROR: " . errorCount . ")"
				Gui, WarnError:Add, Text, x10 y10 w580 h25 Center,% titleText
				Gui, WarnError:Add, GroupBox, x10 y40 w580 h50, Filtros
				Gui, WarnError:Add, Checkbox, x20 y60 w80 h25 vWEChkWARN gServer_FilterWarnError Checked, WARN
				Gui, WarnError:Add, Checkbox, x+20 w80 h25 vWEChkERROR gServer_FilterWarnError Checked, ERROR
				Gui, WarnError:Add, Text, x+20 w60 h25, Script:
				Gui, WarnError:Add, ComboBox, x+5 w150 h200 vWEScriptFilter gServer_FilterWarnError, Todos
				scriptsInBuffer := {}
				for _, item in this.warnErrorBuffer
					scriptsInBuffer[item.script] := true
				for scriptName in scriptsInBuffer
					GuiControl, WarnError:, WEScriptFilter, %scriptName%
				Gui, WarnError:Add, ListView, x10 y100 w580 r20 vWELogView -Multi +Grid, Timestamp|Tipo|Script|Mensagem
				buttonY := 450
				Gui, WarnError:Add, Button, x10 y%buttonY% w100 h30 gServer_ExportWarnError, Exportar CSV
				Gui, WarnError:Add, Button, x120 y%buttonY% w100 h30 gServer_ClearWarnError, Limpar Buffer
				Gui, WarnError:Add, Button, x490 y%buttonY% w100 h30 gServer_CloseWarnError, Fechar
				totalHeight := buttonY + 45
				Gui, WarnError:Show, w600 h%totalHeight%, Análise WARN/ERROR
				this.FilterWarnErrorList()
			}
			FilterWarnErrorList() {
				if (!this.warnErrorWindowOpen)
						Return
				Gui, WarnError:Submit, NoHide
				Gui, WarnError:ListView, WELogView
				LV_Delete()
				for _, item in this.warnErrorBuffer {
					showItem := true
					if (item.tipo = "WARN" && !WEChkWARN)
						showItem := false
					if (item.tipo = "ERROR" && !WEChkERROR)
						showItem := false
					if (WEScriptFilter != "Todos" && item.script != WEScriptFilter)
						showItem := false
					if (showItem)
						LV_Add("", item.timestamp, item.tipo, item.script, item.mensagem)
				}
				LV_ModifyCol(1, 140)
				LV_ModifyCol(2, 60)
				LV_ModifyCol(3, 120)
				LV_ModifyCol(4, 240)
			}
			ExportWarnError() {
				FormatTime, timestamp,, yyyy-MM-dd_HHmmss
				FileSelectFile, outputFile, S16, %A_Desktop%\warn_error_analysis_%timestamp%.csv, Exportar WARN/ERROR, CSV Files (*.csv)
				if (outputFile = "")
						Return
				if !InStr(outputFile, ".csv")
					outputFile .= ".csv"
				fileContent := "Timestamp,Tipo,Script,Mensagem`n"
				for _, item in this.warnErrorBuffer {
					mensagemEscaped := RegExReplace(item.mensagem, """", """""")
					scriptEscaped := RegExReplace(item.script, """", """""")
					fileContent .= item.timestamp . "," . item.tipo . "," . """" . scriptEscaped . """" . "," . """" . mensagemEscaped . """`n"
				}
				FileDelete, %outputFile%
				FileAppend, %fileContent%, %outputFile%, UTF-8
				if (!ErrorLevel)
					MsgBox, 64, Exportação, Eventos WARN/ERROR exportados com sucesso!`n%outputFile%
			}
			ClearWarnErrorBuffer() {
				MsgBox, 36, Confirmação, Tem certeza que deseja limpar o buffer de WARN/ERROR?`n`nEsta ação não pode ser desfeita.
				IfMsgBox, Yes
				{
					this.warnErrorBuffer := []
					this.UpdateWarnErrorCount()
					this.FilterWarnErrorList()
				}
			}
			CloseWarnErrorWindow() {
				Gui, WarnError:Destroy
				this.warnErrorWindowOpen := false
			}

		; ===================== PAUSA / LISTVIEW =====================
			TogglePauseListView() {
				GuiControlGet, PauseListView
				this.listViewPaused := PauseListView
				if (this.listViewPaused) {
					GuiControl, Show, PauseIndicator
					GuiControl,, PauseIndicator, ⏸ PAUSADO
				} else {
					GuiControl, Hide, PauseIndicator
					this.ApplyFiltersOptimized(true)
				}
				this.UpdateWarnErrorCount()
			}

		; ===================== ATUALIZAÇÃO INTELIGENTE =====================
			ApplyFiltersSmartUpdate(newItem, wasLogRemoved := false) {
				if (this.listViewPaused)
						Return
				if (!this.virtualMode) {
					this.ApplyFiltersOptimized(true)
						Return
				}
				Gui, ListView, LogView
				if (wasLogRemoved)
					this.RemoveOldestFromListView(newItem.script, newItem.tipo)
				if (this.ShouldShowItem(newItem)) {
					LV_Insert(1, "", newItem.timestamp, newItem.socket, newItem.ip, newItem.tipo, newItem.script, newItem.mensagem)
					this.filteredLogs.InsertAt(1, newItem)
					SB_SetText("Logs exibidos: " . LV_GetCount() . " / " . this.logs.Length(), 1)
				}
			}
			RemoveOldestFromListView(scriptName, tipo) {
				Gui, ListView, LogView
				Loop, % LV_GetCount() {
					reverseIndex := LV_GetCount() - A_Index + 1
					LV_GetText(lvScript, reverseIndex, 5)
					LV_GetText(lvTipo, reverseIndex, 4)
					if (lvScript = scriptName && lvTipo = tipo) {
						LV_Delete(reverseIndex)
						if (reverseIndex <= this.filteredLogs.Length())
							this.filteredLogs.RemoveAt(reverseIndex)
						break
					}
				}
			}

		; ===================== LIMITE POR SCRIPT + TIPO =====================
			AddLogWithLimit(newMsg) {
				scriptName := newMsg.script
				tipo := newMsg.tipo
				if (!this.logCounts.HasKey(scriptName))
					this.logCounts[scriptName] := {}
				if (!this.logCounts[scriptName].HasKey(tipo))
					this.logCounts[scriptName][tipo] := 0
				wasRemoved := false
				if (this.logCounts[scriptName][tipo] >= this.maxLogsPerScript) {
					Loop, % this.logs.Length() {
						reverseIndex := this.logs.Length() - A_Index + 1
						tmp := this.logs[reverseIndex]
						if (tmp.script = scriptName && tmp.tipo = tipo) {
							this.logs.RemoveAt(reverseIndex)
							this.logCounts[scriptName][tipo]--
							wasRemoved := true
							break
						}
					}
				}
				this.logs.InsertAt(1, newMsg)
				this.logCounts[scriptName][tipo]++
				while (this.logCounts[scriptName][tipo] > this.maxLogsPerScript) {
					Loop, % this.logs.Length() {
						reverseIndex := this.logs.Length() - A_Index + 1
						tmp := this.logs[reverseIndex]
						if (tmp.script = scriptName && tmp.tipo = tipo) {
							this.logs.RemoveAt(reverseIndex)
							this.logCounts[scriptName][tipo]--
							wasRemoved := true
							if (this.logCounts[scriptName][tipo] <= this.maxLogsPerScript)
								break
						}
					}
				}
					Return wasRemoved
			}
			ApplyMaxLogs() {
				GuiControlGet, MaxLogsInput
				if (MaxLogsInput > 0 && MaxLogsInput <= 10000) {
					this.maxLogsPerScript := MaxLogsInput
					this.TrimLogsToLimit()
					if (!this.listViewPaused)
						this.ApplyFiltersOptimized(true)
					this.UpdateStatsDisplay()
				}
			}
			TrimLogsToLimit() {
				newLogs := []
				newCounts := {}
				for _, item in this.logs {
					s := item.script
					t := item.tipo
					if (!newCounts.HasKey(s))
						newCounts[s] := {}
					if (!newCounts[s].HasKey(t))
						newCounts[s][t] := 0
					if (newCounts[s][t] < this.maxLogsPerScript) {
						newLogs.Push(item)
						newCounts[s][t]++
					}
				}
				this.logs := newLogs
				this.logCounts := newCounts
				this.filteredLogs := []
			}
			UpdateMaxLogs() {
				GuiControlGet, MaxLogsInput
				if (MaxLogsInput > 0 && MaxLogsInput <= 10000) {
					this.maxLogsPerScript := MaxLogsInput
					this.UpdateStatsDisplay()
				}
			}

		; ===================== MODO VIRTUAL / SCHEDULE =====================
			ToggleVirtualMode() {
				GuiControlGet, VirtualMode
				this.virtualMode := VirtualMode
				this.UpdateWarnErrorCount()
				if (!this.listViewPaused)
					this.ScheduleUpdate()
			}
			ScheduleUpdate() {
				this.pendingUpdate := true
				this.lastFilterChange := A_TickCount
			}
			ProcessPendingUpdates() {
				if (this.pendingUpdate && A_TickCount - this.lastFilterChange > 800) {
					this.pendingUpdate := false
					this.ApplyFiltersOptimized(true)
				}
			}

		; ===================== AÇÕES GERAIS =====================
			ClearLogs() {
				Gui, ListView, LogView
				LV_Delete()
				this.logs := []
				this.filteredLogs := []
				this.logsReceived := 0
				this.logCounts := {}
				SB_SetText("Logs exibidos: 0", 1)
				this.UpdateStatsDisplay()
				GuiControl,, StatsTextScript, Selecione um script específico para ver estatísticas detalhadas
			}
			ExportLogs() {
				FormatTime, timestamp,, yyyy-MM-dd_HHmmss
				FileSelectFile, outputFile, S16, %A_Desktop%\logs_%timestamp%.csv, Salvar logs como CSV, CSV Files (*.csv)
				if (outputFile = "")
						Return
				if !InStr(outputFile, ".csv")
					outputFile .= ".csv"
				fileContent := "Timestamp,Socket,IP,Tipo,Script,Mensagem`n"
				for _, item in this.logs
					if (this.ShouldShowItem(item)) {
						mensagemEscaped := RegExReplace(item.mensagem, """", """""")
						scriptEscaped := RegExReplace(item.script, """", """""")
						fileContent .= item.timestamp . "," . item.socket . "," . item.ip . "," . item.tipo . ","
									. """" . scriptEscaped . """" . "," . """" . mensagemEscaped . """`n"
					}
				FileDelete, %outputFile%
				FileAppend, %fileContent%, %outputFile%, UTF-8
			}

		; ===================== SCRIPTS / ESTATÍSTICAS =====================
			AddScriptToRegistry(scriptName) {
				if (scriptName = "N/A" || scriptName = "")
						Return
				isNew := true
				for _, existing in this.activeScripts
					if (existing = scriptName)
						isNew := false
				if (isNew) {
					this.activeScripts.Push(scriptName)
					if (!this.scriptStats.HasKey(scriptName))
						this.scriptStats[scriptName] := {DEBUG: 0, INFO: 0, WARN: 0, ERROR: 0, LOAD: 0, total: 0}
					if (!this.logCounts.HasKey(scriptName))
						this.logCounts[scriptName] := {}
					Gui, ListView, ScriptsListView
					LV_Add("", scriptName)
					this.selectedScripts[scriptName] := 0
					SB_SetText("Scripts únicos: " . this.activeScripts.Length(), 3)
				}
			}
			UpdateScriptStats(scriptName, logType) {
				if (!this.scriptStats.HasKey(scriptName))
					this.scriptStats[scriptName] := {DEBUG: 0, INFO: 0, WARN: 0, ERROR: 0, LOAD: 0, total: 0}
				if (this.scriptStats[scriptName].HasKey(logType))
					this.scriptStats[scriptName, logType] += 1
				this.scriptStats[scriptName, "total"] += 1
			}
			UpdateScriptSpecificStatsIfSelected(scriptName) {
				selectedScript := ""
				for s, selected in this.selectedScripts
					if (s != "Todos" && selected = 1) {
						selectedScript := s
						break
					}
				if (selectedScript != "" && selectedScript = scriptName)
					this.UpdateScriptSpecificStats(scriptName)
			}
			UpdateStatsDisplay() {
				totalDebug := 0, totalInfo := 0, totalWarn := 0, totalError := 0, totalLoad := 0, totalProcessed := 0, totalStored := 0
				for _, scriptName in this.activeScripts
					if (this.scriptStats.HasKey(scriptName)) {
						totalDebug += this.scriptStats[scriptName, "DEBUG"]
						totalInfo += this.scriptStats[scriptName, "INFO"]
						totalWarn += this.scriptStats[scriptName, "WARN"]
						totalError += this.scriptStats[scriptName, "ERROR"]
						totalLoad += this.scriptStats[scriptName, "LOAD"]
						totalProcessed += this.scriptStats[scriptName, "total"]
					}
				for s, map in this.logCounts
					for t, cnt in map
						totalStored += cnt
				statsText := "Scripts conectados: " . this.activeScripts.Length()
						. " | Logs armazenados: " . totalStored . " (processados: " . totalProcessed . ")"
						. " | Limite: " . this.maxLogsPerScript . "/script/tipo"
						. "`nDEBUG=" . totalDebug
						. " | INFO=" . totalInfo
						. " | WARN=" . totalWarn
						. " | ERROR=" . totalError
						. " | LOAD=" . totalLoad
				GuiControl,, StatsTextGlobal,% statsText
			}
			UpdateScriptSpecificStats(scriptName) {
				this.lastSelectedScript := scriptName
				scriptStatsText := "Selecione um script específico para ver estatísticas detalhadas"
				if (scriptName && scriptName != "Todos" && this.scriptStats.HasKey(scriptName)) {
					debug := this.scriptStats[scriptName, "DEBUG"]
					info := this.scriptStats[scriptName, "INFO"]
					warn := this.scriptStats[scriptName, "WARN"]
					error := this.scriptStats[scriptName, "ERROR"]
					load := this.scriptStats[scriptName, "LOAD"]
					total := this.scriptStats[scriptName, "total"]
					storedDebug := (this.logCounts.HasKey(scriptName) && this.logCounts[scriptName].HasKey("DEBUG")) ? this.logCounts[scriptName]["DEBUG"] : 0
					storedInfo  := (this.logCounts.HasKey(scriptName) && this.logCounts[scriptName].HasKey("INFO"))  ? this.logCounts[scriptName]["INFO"]  : 0
					storedWarn  := (this.logCounts.HasKey(scriptName) && this.logCounts[scriptName].HasKey("WARN"))  ? this.logCounts[scriptName]["WARN"]  : 0
					storedError := (this.logCounts.HasKey(scriptName) && this.logCounts[scriptName].HasKey("ERROR")) ? this.logCounts[scriptName]["ERROR"] : 0
					storedLoad  := (this.logCounts.HasKey(scriptName) && this.logCounts[scriptName].HasKey("LOAD"))  ? this.logCounts[scriptName]["LOAD"]  : 0
					scriptStatsText := "Script: " . scriptName
									. " | Limite por tipo: " . this.maxLogsPerScript
									. " | Total processados: " . total
									. "`nArmazenados => D:" . storedDebug . " I:" . storedInfo . " W:" . storedWarn . " E:" . storedError . " L:" . storedLoad
					if (total > 0) {
						debugPct := Round((debug / total) * 100)
						infoPct := Round((info / total) * 100)
						warnPct := Round((warn / total) * 100)
						errorPct := Round((error / total) * 100)
						loadPct := Round((load / total) * 100)
						scriptStatsText .= "`nDistribuição % => D:" . debugPct . " I:" . infoPct . " W:" . warnPct . " E:" . errorPct . " L:" . loadPct
					}
				}
				GuiControl,, StatsTextScript,% scriptStatsText
			}

		; ===================== EVENTOS GUI =====================
			ScriptsListViewChanged() {
				if (A_GuiEvent != "C")
						Return
				Gui, Listview, ScriptsListView
				Loop % LV_GetCount() {
					rowScript := ""
					isChecked := LV_GetNext(A_Index - 1, "Checked")
					LV_GetText(rowScript, A_Index, 1)
					this.selectedScripts[rowScript] := (isChecked = A_Index ? 1 : 0)
				}
				Gui, ListView, ScriptsListView
				if (this.selectedScripts["Todos"] = 1) {
					Loop, % LV_GetCount()
						if (A_Index > 1) {
							LV_GetText(rowScript, A_Index)
							this.selectedScripts[rowScript] := 1
							LV_Modify(A_Index, "Check")
						}
					GuiControl,, StatsTextScript, Exibindo logs de todos os scripts selecionados
				} else {
					allChecked := true
					selectedScript := ""
					Loop, % LV_GetCount()
						if (A_Index > 1) {
							LV_GetText(rowScript, A_Index)
							if (this.selectedScripts[rowScript] = 0)
								allChecked := false
							else
								selectedScript := rowScript
						}
					if (!allChecked) {
						Loop, % LV_GetCount()
							if (A_Index > 1) {
								LV_GetText(rowScript, A_Index)
								if (this.selectedScripts[rowScript] = 0)
									LV_Modify(A_Index, "-Check")
							}
					}
					if (selectedScript != "")
						this.UpdateScriptSpecificStats(selectedScript)
					else
						GuiControl,, StatsTextScript, Selecione um script específico para ver estatísticas detalhadas
				}
				if (!this.listViewPaused)
					this.ScheduleUpdate()
			}
			SearchChanged() {
				GuiControlGet, SearchText
				this.searchText := SearchText
				if (!this.listViewPaused)
					SetTimer, Server_ApplyFiltersTimer, -500
			}
			ApplyFiltersTimer() {
				this.ScheduleUpdate()
			}
			ApplyFilters() {
				if (!this.listViewPaused)
					this.ScheduleUpdate()
			}

		; ===================== FILTRAGEM PRINCIPAL =====================
			ApplyFiltersOptimized(forceUpdate := false) {
				static lastSearchText := ""
				static lastChkDEBUG := ""
				static lastChkINFO := ""
				static lastChkWARN := ""
				static lastChkERROR := ""
				static lastChkLOAD := ""
				static lastLogsLength := 0
				static lastSelectedHash := ""
				static lastLogsSignature := ""
				if (this.listViewPaused && !forceUpdate)
						Return
				Gui, Submit, NoHide
				GuiControlGet, SearchText
				GuiControlGet, ChkDEBUG
				GuiControlGet, ChkINFO
				GuiControlGet, ChkWARN
				GuiControlGet, ChkERROR
				GuiControlGet, ChkLOAD
				this.searchText := SearchText
				selectedHash := ""
				for scriptName, isSel in this.selectedScripts
					selectedHash .= scriptName . ":" . isSel . "|"
				logsSignature := ""
				if (this.logs.Length() > 0)
					logsSignature := this.logs[1].timestamp . "|" . this.logs[1].script . "|" . this.logs.Length()
				needsUpdate := forceUpdate
				if (!needsUpdate) {
					if (SearchText != lastSearchText
					|| ChkDEBUG != lastChkDEBUG
					|| ChkINFO != lastChkINFO
					|| ChkWARN != lastChkWARN
					|| ChkERROR != lastChkERROR
					|| ChkLOAD != lastChkLOAD
					|| this.logs.Length() != lastLogsLength
					|| selectedHash != lastSelectedHash
					|| logsSignature != lastLogsSignature)
						needsUpdate := true
				}
				if (needsUpdate) {
					Gui, ListView, LogView
					currentFocus := LV_GetNext(0, "Focused")
					if (currentFocus > 0)
						this.lastScrollPos := currentFocus
					lastSearchText := SearchText
					lastChkDEBUG := ChkDEBUG
					lastChkINFO := ChkINFO
					lastChkWARN := ChkWARN
					lastChkERROR := ChkERROR
					lastChkLOAD := ChkLOAD
					lastLogsLength := this.logs.Length()
					lastSelectedHash := selectedHash
					lastLogsSignature := logsSignature
					if (this.virtualMode)
						this.UpdateVirtualListView()
					else
						this.UpdateStandardListView()
					SB_SetText("Logs exibidos: " . LV_GetCount() . " / " . this.logs.Length(), 1)
				}
			}
			UpdateVirtualListView() {
				this.filteredLogs := []
				for _, item in this.logs
					if (this.ShouldShowItem(item))
						this.filteredLogs.Push(item)
				Gui, ListView, LogView
				currentCount := LV_GetCount()
				newCount := this.filteredLogs.Length()
				if (Abs(newCount - currentCount) > this.updateThreshold || currentCount = 0) {
					this.RebuildListView()
				} else {
					firstThreeValid := true
					if (currentCount > 0 && newCount > 0) {
						Loop, 3
							if (A_Index <= currentCount && A_Index <= newCount) {
								LV_GetText(lvTimestamp, A_Index, 1)
								LV_GetText(lvScript, A_Index, 5)
								if (this.filteredLogs[A_Index].timestamp != lvTimestamp || this.filteredLogs[A_Index].script != lvScript) {
									firstThreeValid := false
									break
								}
							}
					}
					if (firstThreeValid)
						this.UpdateListViewIncremental()
					else
						this.RebuildListView()
				}
				if (this.lastScrollPos > 0 && this.lastScrollPos <= LV_GetCount())
					LV_Modify(this.lastScrollPos, "Focus")
			}
			UpdateStandardListView() {
				Gui, ListView, LogView
				LV_Delete()
				for _, item in this.logs
					if (this.ShouldShowItem(item))
						LV_Add("", item.timestamp, item.socket, item.ip, item.tipo, item.script, item.mensagem)
			}
			UpdateListViewIncremental() {
				Gui, ListView, LogView
				currentCount := LV_GetCount()
				targetCount := this.filteredLogs.Length()
				if (targetCount > currentCount) {
					itemsToAdd := targetCount - currentCount
					Loop, % itemsToAdd {
						item := this.filteredLogs[A_Index]
						LV_Insert(1, "", item.timestamp, item.socket, item.ip, item.tipo, item.script, item.mensagem)
					}
				} else if (targetCount < currentCount) {
					itemsToRemove := currentCount - targetCount
					Loop, % itemsToRemove
						LV_Delete(LV_GetCount())
				}
			}
			RebuildListView() {
				Gui, ListView, LogView
				LV_Delete()
				for _, item in this.filteredLogs
					LV_Add("", item.timestamp, item.socket, item.ip, item.tipo, item.script, item.mensagem)
			}
			ShouldShowItem(item) {
				global ChkDEBUG, ChkINFO, ChkWARN, ChkERROR, ChkLOAD
				showByType := ( (item.tipo = "DEBUG" && ChkDEBUG)
							|| (item.tipo = "INFO"  && ChkINFO)
							|| (item.tipo = "WARN"  && ChkWARN)
							|| (item.tipo = "ERROR" && ChkERROR)
							|| (item.tipo = "LOAD"  && ChkLOAD) )
				showByText := (this.searchText = "")
						|| InStr(item.mensagem, this.searchText, false)
						|| InStr(item.script, this.searchText, false)
				showByScript := (this.selectedScripts["Todos"] = 1) || (this.selectedScripts[item.script] = 1)
					Return (showByType && showByText && showByScript)
			}

		; ===================== GUI DIMENSIONAMENTO =====================
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
			GuiSize() {
				if (A_EventInfo = 1)
						Return
				scriptsListViewWidth := 250
				statusBarHeight := 25
				newLogViewWidth := A_GuiWidth - scriptsListViewWidth - 30
				newLogViewX := scriptsListViewWidth + 20
				newHeight := A_GuiHeight - 245 - statusBarHeight
				GuiControl, Move, ScriptsListView,% "w" . scriptsListViewWidth . " h" . newHeight
				GuiControl, Move, LogView,% "x" . newLogViewX . " w" . newLogViewWidth . " h" . newHeight
				Gui, ListView, LogView
				this.ResizeListViewColumns()
			}
			GuiClose() {
				AHKsock_Close()
				ExitApp
			}
	}