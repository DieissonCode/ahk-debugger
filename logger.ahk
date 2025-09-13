; Logger.ahk - Simple and robust logger with reverse connection support, buffer, flush, reconnection and command response
#Include C:\Autohotkey 2024\Root\Libs\socket.ahk
#Include C:\AutoHotkey\class\functions.ahk

class Logger {
    static DEFAULT_HOST := "192.9.100.100"
    static DEFAULT_PORT := 4041
    static REVERSE_PORT := 5041
    static socket := -1
    static reverseSocket := -1
    static scriptName := ""
    static isConnected := false
    static reconnectInterval := 5000
    static lastConnectAttempt := 0
    static maxReconnectAttempts := 9999999999999
    static reconnectAttempts := 0
    static localBuffer := []
    static maxBufferSize := 100
    static offlineMode := false
    static autoReconnect := true

    __New(obj := "") {
        this.scriptName := (obj != "" && obj.HasKey("name")) ? obj.name : (A_IPAddress1 . " - " . A_ScriptName)
        this.host := (obj != "" && obj.HasKey("host")) ? obj.host : Logger.DEFAULT_HOST
        this.port := (obj != "" && obj.HasKey("port")) ? obj.port : Logger.DEFAULT_PORT
        DebugLogSmart("[LOGGER] Initializing for script: " . this.scriptName)
        this.connect()
        this.startReverseListener()
        SetTimer, LoggerReconnectTimer, % Logger.reconnectInterval
    }

    connect() {
        currentTime := A_TickCount
        if (currentTime - Logger.lastConnectAttempt < Logger.reconnectInterval)
            return false
        Logger.lastConnectAttempt := currentTime

        if (Logger.reconnectAttempts >= Logger.maxReconnectAttempts) {
            if (!Logger.offlineMode) {
                DebugLogSmart("[LOGGER] Entering offline mode after " . Logger.maxReconnectAttempts . " failed attempts")
                Logger.offlineMode := true
            }
            return false
        }
        DebugLogSmart("[LOGGER] Attempting to connect to server at " . this.host . ":" . this.port . " (attempt " . (Logger.reconnectAttempts + 1) . ")")
        err := AHKsock_Connect(this.host, this.port, "LoggerSocketHandler")
        if (err) {
            Logger.reconnectAttempts++
            DebugLogSmart("[LOGGER] Failed to connect. Error: " . err . " (attempt " . Logger.reconnectAttempts . ")")
            return false
        }
        DebugLogSmart("[LOGGER] Connection request sent")
        return true
    }

    forceReconnect() {
        DebugLogSmart("[LOGGER] Force reconnect requested by server")
        this.disconnect()
        Logger.reconnectAttempts := 0
        Logger.offlineMode := false
        Logger.lastConnectAttempt := 0
        Logger.autoReconnect := true
        return this.connect()
    }

    disconnect() {
        if (Logger.socket != -1) {
            AHKsock_Close(Logger.socket)
            Logger.socket := -1
        }
        Logger.isConnected := false
        DebugLogSmart("[LOGGER] Manually disconnected")
    }

    log(message, level := "INFO") {
        if (!Logger.isConnected && !Logger.offlineMode && Logger.autoReconnect)
            this.connect()

        if (!Logger.isConnected) {
            this.addToLocalBuffer(message, level)
            return false
        }
        success := this.sendLog(message, level)
        if (!success) {
            Logger.isConnected := false
            this.addToLocalBuffer(message, level)
        }
        return success
    }

    sendLog(message, level) {
        dataStr := "type=" . level . "||scriptName=" . this.scriptName . "||message=" . message . "&&"
        DebugLogSmart("[LOGGER] Sending: " . dataStr)
        VarSetCapacity(utf8, StrPut(dataStr, "UTF-8"))
        StrPut(dataStr, &utf8, "UTF-8")
        bytesToSend := StrPut(dataStr, "UTF-8") - 1
        err := AHKsock_ForceSend(Logger.socket, &utf8, bytesToSend)
        if (err) {
            DebugLogSmart("[LOGGER] Error sending: " . err)
            Logger.isConnected := false
            return false
        }
        DebugLogSmart("[LOGGER] Log sent successfully")
        return true
    }

    addToLocalBuffer(message, level) {
        FormatTime, timestamp,, yyyy-MM-dd HH:mm:ss
        logEntry := {timestamp: timestamp, level: level, message: message}
        Logger.localBuffer.Push(logEntry)
        while (Logger.localBuffer.Length() > Logger.maxBufferSize)
            Logger.localBuffer.RemoveAt(1)
        DebugLogSmart("[LOGGER-OFFLINE] Buffered " . level . ": " . message)
    }

    flushLocalBuffer() {
        if (!Logger.isConnected || Logger.localBuffer.Length() = 0)
            return
        DebugLogSmart("[LOGGER] Flushing " . Logger.localBuffer.Length() . " buffered logs")
        sentCount := 0
        while (Logger.localBuffer.Length() > 0 && Logger.isConnected) {
            entry := Logger.localBuffer[1]
            Logger.localBuffer.RemoveAt(1)
            msg := "[RECOVERED] " . entry.message
            if (this.sendLog(msg, entry.level))
                sentCount++
            else {
                Logger.localBuffer.InsertAt(1, entry)
                Logger.isConnected := false
                break
            }
            Sleep, 30
        }
        if (sentCount > 0)
            DebugLogSmart("[LOGGER] Successfully flushed " . sentCount . " buffered logs")
    }

    startReverseListener() {
        err := AHKsock_Listen(Logger.REVERSE_PORT, "LoggerReverseHandler")
        if (err)
            DebugLogSmart("[LOGGER] Failed to start reverse port. Error: " . err)
        else
            DebugLogSmart("[LOGGER] Listening on reverse port: " . Logger.REVERSE_PORT)
    }

    debug(message) {
        return this.log(message, "DEBUG")
    }

    error(message) {
        return this.log(message, "ERROR")
    }

    load(message) {
        return this.log(message, "LOAD")
    }

    info(message) {
        return this.log(message, "INFO")
    }

    warn(message) {
        return this.log(message, "WARN")
    }

    processReverseMessage(message) {
        DebugLogSmart("[LOGGER-REVERSE] Processing message: " . message)
        resposta := "Comando " . message . " recebido"
        this.sendReverseResponse(resposta)
        if (InStr(message, "RELOAD")) {
            this.info("Script reload requested by server")
            Sleep, 500
            Reload
            return
        }
        if (InStr(message, "RECONNECT")) {
            this.forceReconnect()
            return
        }
        MsgBox, % "[LOGGER-REVERSE] Command received from server:`n" . message
    }

    sendReverseResponse(resposta) {
        if (Logger.reverseSocket != -1) {
            VarSetCapacity(utf8, StrPut(resposta, "UTF-8"))
            StrPut(resposta, &utf8, "UTF-8")
            bytesToSend := StrPut(resposta, "UTF-8") - 1
            err := AHKsock_ForceSend(Logger.reverseSocket, &utf8, bytesToSend)
            DebugLogSmart("[LOGGER-REVERSE] Resposta enviada ao server: " . resposta . " | Erro: " . err)
        }
    }
}

LoggerSocketHandler(sEvent, iSocket, sName, sAddr, sPort) {
    DebugLogSmart("[LOGGER] Event: " . sEvent . " | Socket: " . iSocket)
    if (sEvent = "CONNECTED") {
        if (iSocket != -1) {
            Logger.socket := iSocket
            Logger.isConnected := true
            Logger.reconnectAttempts := 0
            Logger.offlineMode := false
            DebugLogSmart("[LOGGER] Successfully connected! Socket: " . iSocket)
            Logger.flushLocalBuffer()
        } else {
            Logger.isConnected := false
            DebugLogSmart("[LOGGER] Connection failed")
        }
    }
    else if (sEvent = "DISCONNECTED") {
        Logger.isConnected := false
        Logger.socket := -1
        DebugLogSmart("[LOGGER] Disconnected from server")
    }
}

LoggerReverseHandler(sEvent, iSocket, sName, sAddr, sPort, ByRef bData := "", bDataLength := "") {
    DebugLogSmart("[LOGGER-REVERSE] Event: " . sEvent . " | Socket: " . iSocket . " | IP: " . sAddr)
    if (sEvent = "ACCEPTED") {
        Logger.reverseSocket := iSocket
        DebugLogSmart("[LOGGER-REVERSE] Server connected to reverse port.")
    }
    else if (sEvent = "RECEIVED") {
        dataStr := StrGet(&bData, bDataLength, "UTF-8")
        DebugLogSmart("[LOGGER-REVERSE] Message received: " . dataStr)
        logger := Logger
        logger.processReverseMessage(dataStr)
    }
    else if (sEvent = "DISCONNECTED") {
        Logger.reverseSocket := -1
        DebugLogSmart("[LOGGER-REVERSE] Server disconnected from reverse port.")
    }
}

LoggerReconnectTimer()	{
    if (!Logger.isConnected && !Logger.offlineMode && Logger.autoReconnect)
        Logger.connect()
}