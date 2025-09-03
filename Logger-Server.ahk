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

; Configurações globais
global PORTA := 4041
global DEFAULT_FILTER := {DEBUG: 1, INFO: 1, WARN: 1, ERROR: 1}
global TimestampFormat := "yyyy-MM-dd HH:mm:ss"
global g_aLogs := []
global SearchText := ""  ; Variável global para o texto de busca
global ActiveScripts := [] ; Array para rastrear scripts ativos
global SelectedScript := "Todos" ; Script selecionado para filtragem

OutputDebug, [SERVER] Script inicializado.

; Criar GUI com abas e controles
Gui, +Resize +MinSize480x300 +AlwaysOnTop
Gui, Color, FFFFFF
Gui, Font, s10, Segoe UI

; Barra de ferramentas superior
Gui, Add, Text, x10 y10 w300, Servidor de Log (Porta: %PORTA%)
Gui, Add, Button, x+10 w80 h25 gClearLogs, Limpar
Gui, Add, Button, x+10 w100 h25 gExportLogs, Exportar Logs

; Filtros - Aumentei a altura da GroupBox para acomodar a ComboBox completamente
Gui, Add, GroupBox, x10 y40 w350 h115, Filtros

; Filtros de tipo
Gui, Add, Checkbox, x20 y60 w80 h20 vChkDEBUG gApplyFilters Checked, DEBUG
Gui, Add, Checkbox, x+5 w80 h20 vChkINFO gApplyFilters Checked, INFO
Gui, Add, Checkbox, x+5 w80 h20 vChkWARN gApplyFilters Checked, WARN
Gui, Add, Checkbox, x+5 w80 h20 vChkERROR gApplyFilters Checked, ERROR

; Busca e seleção de script (reorganizados dentro da GroupBox)
Gui, Add, Text, x20 y90 w60, Buscar:
Gui, Add, Edit, x+5 w200 h20 vSearchText gSearchChanged, 
Gui, Add, Text, x20 y115 w60, Script:
Gui, Add, ComboBox, x+5 w200 h20 R10 vSelectedScript gScriptSelected, Todos||

; Estatísticas - aumentei a altura para acomodar estatísticas por script
Gui, Add, GroupBox, x370 y40 w600 h115, Estatísticas
Gui, Add, Text, x380 y60 w580 vStatsTextGlobal, Scripts conectados: 0 | Logs recebidos: 0
; Linha separadora
Gui, Add, Text, x380 y85 w580 h2 0x10 ; Estilo 0x10 = SS_BLACKRECT
; Estatísticas específicas do script selecionado
Gui, Add, Text, x380 y95 w580 vStatsTextScript, Selecione um script para ver estatísticas específicas

; Lista de logs - ajustada para começar após as GroupBoxes maiores
Gui, Add, ListView, x10 y165 w860 r20 vLogView -Multi Grid, Timestamp|Socket|IP|Tipo|Script|Mensagem
LV_ModifyCol(1, 140), LV_ModifyCol(2, 60), LV_ModifyCol(3, 100)
LV_ModifyCol(4, 60), LV_ModifyCol(5, 120), LV_ModifyCol(6, 380)

; Barra de status
Gui, Add, StatusBar
SB_SetParts(200, 150, 200)
SB_SetText("Logs recebidos: 0", 1)
SB_SetText("Clientes conectados: 0", 2)
SB_SetText("Scripts únicos: 0", 3)

; Variáveis para controle
global iConnectedClients := 0
global iLogsReceived := 0
global ScriptStats := {}  ; Estatísticas por script

; Calcular posição para canto inferior esquerdo
SysGet, MonitorWorkArea, MonitorWorkArea
serverX := 10
serverY := MonitorWorkAreaBottom - 500

Gui, Show, x%serverX% y%serverY% w980 h500, Logger Server v1.1.2

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
    global iConnectedClients, iLogsReceived, g_aLogs, ActiveScripts, ScriptStats
    
    OutputDebug, [SERVER] Evento: %sEvent% | Socket: %iSocket% | IP: %sAddr%
    
    if (sEvent = "ACCEPTED") {
        iConnectedClients++
        OutputDebug, [SERVER] Cliente conectado. Socket: %iSocket% | IP: %sAddr%
        SB_SetText("Clientes conectados: " iConnectedClients, 2)
    }
    else if (sEvent = "RECEIVED") {
        dataStr := StrGet(&bData, bDataLength, "UTF-8")
        OutputDebug, [SERVER] RECEIVED | Socket: %iSocket% | IP: %sAddr% | Data: %dataStr%
        
        ; Método melhorado para analisar a string: dividir por "||" e processar cada parte
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
        
        OutputDebug, [SERVER] Parseado | Tipo: %tipo% | Script: %scriptName% | Mensagem: %mensagem%
        
        ; Adicionar script à lista de scripts se for novo
        AddScriptToRegistry(scriptName)
        
        ; Atualizar estatísticas
        UpdateScriptStats(scriptName, tipo)
        
        ; Gerar timestamp
        FormatTime, timestamp,, %TimestampFormat%
        
        ; Armazenar mensagem para filtros
        iLogsReceived++
        SB_SetText("Logs recebidos: " iLogsReceived, 1)
        
        ; Adicionar à array de mensagens (no início para manter ordem cronológica invertida)
        newMsg := {timestamp: timestamp, socket: iSocket, ip: sAddr, tipo: tipo
                 , script: scriptName, mensagem: mensagem}
        g_aLogs.InsertAt(1, newMsg)  ; Inserir no início do array
        
        ; Adicionar ao ListView (na primeira linha)
        LV_Insert(1, "", newMsg.timestamp, newMsg.socket, newMsg.ip, newMsg.tipo, newMsg.script, newMsg.mensagem)
        
        ; Aplicar filtros automaticamente
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

; Adicionar um script ao registro quando detectado
AddScriptToRegistry(scriptName) {
    global ActiveScripts, ScriptStats
    
    ; Ignorar entradas inválidas
    if (scriptName = "N/A" || scriptName = "")
        return
    
    ; Verificar se já temos este script na lista
    isNew := true
    for i, existingScript in ActiveScripts {
        if (existingScript = scriptName) {
            isNew := false
            break
        }
    }
    
    ; Adicionar se for novo
    if (isNew) {
        ActiveScripts.Push(scriptName)
        
        ; Inicializar estatísticas
        if (!ScriptStats.HasKey(scriptName)) {
            ScriptStats[scriptName] := {DEBUG: 0, INFO: 0, WARN: 0, ERROR: 0, total: 0}
        }
        
        ; Atualizar ComboBox
        scriptList := "Todos|"
        for i, script in ActiveScripts {
            scriptList .= script . "|"
        }
        GuiControl,, SelectedScript, |%scriptList%
        GuiControl, Choose, SelectedScript, 1 ; Seleciona "Todos" por padrão
        
        ; Atualizar contagem na barra de status
        SB_SetText("Scripts únicos: " . ActiveScripts.Length(), 3)
    }
}

; Atualizar estatísticas quando um log é recebido
UpdateScriptStats(scriptName, logType) {
    global ScriptStats, SelectedScript
    
    ; Inicializar se necessário
    if (!ScriptStats.HasKey(scriptName)) {
        ScriptStats[scriptName] := {DEBUG: 0, INFO: 0, WARN: 0, ERROR: 0, total: 0}
    }
    
    ; Incrementar contadores
    if (ScriptStats[scriptName].HasKey(logType))
        ScriptStats[scriptName, logType] += 1
    ScriptStats[scriptName, "total"] += 1
    
    ; Atualizar exibição de estatísticas
    UpdateStatsDisplay()
    
    ; Se o script atual está selecionado, atualizar suas estatísticas específicas
    if (SelectedScript = scriptName || SelectedScript = "Todos")
        UpdateScriptSpecificStats()
}

; Atualizar a exibição de estatísticas na GUI
UpdateStatsDisplay() {
    global ScriptStats, ActiveScripts
    
    ; Total de logs por tipo
    totalDebug := 0, totalInfo := 0, totalWarn := 0, totalError := 0, totalLogs := 0
    
    ; Calcular totais
    for i, script in ActiveScripts {
        if (ScriptStats.HasKey(script)) {
            totalDebug += ScriptStats[script, "DEBUG"]
            totalInfo += ScriptStats[script, "INFO"]
            totalWarn += ScriptStats[script, "WARN"]
            totalError += ScriptStats[script, "ERROR"]
            totalLogs += ScriptStats[script, "total"]
        }
    }
    
    ; Atualizar texto na GUI
    statsText := "Scripts conectados: " . ActiveScripts.Length() 
              . " | Total de logs: " . totalLogs
              . " | DEBUG=" . totalDebug 
              . ", INFO=" . totalInfo 
              . ", WARN=" . totalWarn 
              . ", ERROR=" . totalError
    
    GuiControl,, StatsTextGlobal, %	"`n`t" statsText
}

; Atualizar estatísticas específicas do script selecionado
UpdateScriptSpecificStats() {
    global ScriptStats, SelectedScript
    
    if (SelectedScript = "Todos") {
        ; Mostrar um resumo de todos os scripts
        scriptStatsText := "Exibindo logs de todos os scripts"
    } else if (ScriptStats.HasKey(SelectedScript)) {
        ; Mostrar estatísticas do script selecionado
        debug := ScriptStats[SelectedScript, "DEBUG"]
        info := ScriptStats[SelectedScript, "INFO"]
        warn := ScriptStats[SelectedScript, "WARN"]
        error := ScriptStats[SelectedScript, "ERROR"]
        total := ScriptStats[SelectedScript, "total"]
        
        ; Calcular porcentagens
        debugPct := Round((debug / total) * 100)
        infoPct := Round((info / total) * 100)
        warnPct := Round((warn / total) * 100)
        errorPct := Round((error / total) * 100)
        
        scriptStatsText := "Script: " . SelectedScript 
                        . " | Total de logs: " . total
                        . " | DEBUG: " . debug . " (" . debugPct . "%)"
                        . ", INFO: " . info . " (" . infoPct . "%)"
                        . ", WARN: " . warn . " (" . warnPct . "%)"
                        . ", ERROR: " . error . " (" . errorPct . "%)"
    } else {
        scriptStatsText := "Selecione um script para ver estatísticas específicas"
    }
    
    GuiControl,, StatsTextScript, %scriptStatsText%
}

; Quando o usuário seleciona um script específico
ScriptSelected:
    Gui, Submit, NoHide
    OutputDebug, [SERVER] Script selecionado: '%SelectedScript%'
    UpdateScriptSpecificStats() ; Atualiza as estatísticas específicas do script
    ApplyFilters()
return

; Evento quando o texto de busca é alterado
SearchChanged:
    GuiControlGet, SearchText ; Captura o valor diretamente
    OutputDebug, [SERVER] SearchChanged chamado. Valor digitado: '%SearchText%'
    SetTimer, ApplyFiltersTimer, -300 ; Atrasa levemente para melhor desempenho
return

ApplyFiltersTimer:
    ApplyFilters()
return

; Filtrar as mensagens
ApplyFilters() {
    global g_aLogs, SearchText, SelectedScript
    static lastSearchText := ""
    static lastSelectedScript := ""
    static lastChkDEBUG := ""
    static lastChkINFO := ""
    static lastChkWARN := ""
    static lastChkERROR := ""

    ; Obter os valores de filtro de forma explícita
    Gui, Submit, NoHide
    GuiControlGet, SearchText
    GuiControlGet, SelectedScript
    GuiControlGet, ChkDEBUG
    GuiControlGet, ChkINFO
    GuiControlGet, ChkWARN
    GuiControlGet, ChkERROR

    ; Só atualiza se algum filtro mudou
    if (  SearchText        != lastSearchText
        || SelectedScript   != lastSelectedScript
        || ChkDEBUG         != lastChkDEBUG
        || ChkINFO          != lastChkINFO
        || ChkWARN          != lastChkWARN
        || ChkERROR         != lastChkERROR) 
    {
        ; Atualiza os últimos valores
        lastSearchText      := SearchText
        lastSelectedScript  := SelectedScript
        lastChkDEBUG        := ChkDEBUG
        lastChkINFO         := ChkINFO
        lastChkWARN         := ChkWARN
        lastChkERROR        := ChkERROR

        ; Limpar a lista atual
        LV_Delete()

        ; Aplicar os filtros
        filteredCount := 0

        for index, item in g_aLogs {
            ; Verificar filtro de tipo
            typeVar := "Chk" item.tipo
            showByType := %typeVar%

            ; Verificar filtro de texto (case insensitive)
            showByText := (SearchText = "") 
                       || InStr(item.mensagem, SearchText, false) 
                       || InStr(item.script, SearchText, false)

            ; Verificar filtro de script
            showByScript := (SelectedScript = "Todos") 
                         || (item.script = SelectedScript)

            ; Se passar em todos os filtros, mostrar
            if (showByType && showByText && showByScript) {
                LV_Insert(filteredCount + 1, "", item.timestamp, item.socket, item.ip, item.tipo, item.script, item.mensagem)
                filteredCount++
            }
        }

        ; Atualizar barra de status
        SB_SetText("Logs exibidos: " filteredCount " / " g_aLogs.Length(), 1)
    }
}

; Limpar todos os logs
ClearLogs:
    LV_Delete()
    g_aLogs := []
    iLogsReceived := 0
    SB_SetText("Logs recebidos: 0", 1)
    ; Manter a lista de scripts, mas zerar estatísticas
    for i, script in ActiveScripts {
        if (ScriptStats.HasKey(script)) {
            ScriptStats[script, "DEBUG"] := 0
            ScriptStats[script, "INFO"] := 0
            ScriptStats[script, "WARN"] := 0
            ScriptStats[script, "ERROR"] := 0
            ScriptStats[script, "total"] := 0
        }
    }
    UpdateStatsDisplay()
    UpdateScriptSpecificStats()
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
    
    ; Adicionar cada log filtrado
    for index, item in g_aLogs {
        ; Aplicar os mesmos filtros da visualização
        typeVar := "Chk" item.tipo
        showByType := %typeVar%
        
        showByText := (SearchText = "") 
                   || InStr(item.mensagem, SearchText, false) 
                   || InStr(item.script, SearchText, false)
        
        showByScript := (SelectedScript = "Todos") 
                     || (item.script = SelectedScript)
        
        ; Exportar apenas logs que correspondam aos filtros atuais
        if (showByType && showByText && showByScript) {
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
    
    ; Redimensionar controles - ajustado para a nova posição da ListView
    GuiControl, Move, LogView, % "w" . (A_GuiWidth - 20) . " h" . (A_GuiHeight - 175)
return

GuiClose:
    OutputDebug, [SERVER] Encerrando servidor. Fechando todos sockets...
    AHKsock_Close()
    ExitApp