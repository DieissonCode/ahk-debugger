; Logger.ahk - Simple and robust logger with reverse connection support
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

    __New(obj := "") {
        this.scriptName := obj.name ? obj.name : A_IPAddress1 " - " A_ScriptName
        this.host := obj.host ? obj.host : Logger.DEFAULT_HOST
        this.port := obj.port ? obj.port : Logger.DEFAULT_PORT
        DebugLogSmart("[LOGGER] Initializing for script: " . this.scriptName)
        this.connect()
        this.startReverseListener()
    }

    connect() {
        DebugLogSmart("[LOGGER] Attempting to connect to server at " . this.host . ":" . this.port)
        err := AHKsock_Connect(this.host, this.port, "LoggerSocketHandler")
        if (err) {
            DebugLogSmart("[LOGGER] Failed to connect. Error: " . err)
            return false
        }
        DebugLogSmart("[LOGGER] Connection request sent")
        return true
    }

    startReverseListener() {
        err := AHKsock_Listen(Logger.REVERSE_PORT, "LoggerReverseHandler")
        if (err) {
            DebugLogSmart("[LOGGER] Failed to start reverse port. Error: " . err)
        } else {
            DebugLogSmart("[LOGGER] Listening on reverse port: " . Logger.REVERSE_PORT)
        }
    }

    log(message, level := "INFO") {
        if (!this.isConnected) {
            try this.connect()
            if (!this.isConnected) {
                DebugLogSmart("[LOGGER] Not connected.`n`ttype=" . level . "||scriptName=" . this.scriptName . "||message=" . message)
                return false
            }
        }
        
        dataStr := "type=" . level . "||scriptName=" . this.scriptName . "||message=" . message
        DebugLogSmart("[LOGGER] Sending: " . dataStr)

        VarSetCapacity(utf8, StrPut(dataStr, "UTF-8"))
        StrPut(dataStr, &utf8, "UTF-8")
        bytesToSend := StrPut(dataStr, "UTF-8") - 1
        
        err := AHKsock_ForceSend(Logger.socket, &utf8, bytesToSend)
        
        if (err) {
            DebugLogSmart("[LOGGER] Error sending: " . err)
            this.isConnected := false
            return false
        }
        
        DebugLogSmart("[LOGGER] Log sent successfully")
        return true
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
        ; Custom handler for reverse messages (commands from server)
        DebugLogSmart("[LOGGER-REVERSE] Processing message: " . message)
        ; Example: Show a MsgBox (can be replaced by custom logic)
        MsgBox, % "[LOGGER-REVERSE] Command received from server:`n" message
    }
}

LoggerSocketHandler(sEvent, iSocket, sName, sAddr, sPort) {
    DebugLogSmart("[LOGGER] Event: " . sEvent . " | Socket: " . iSocket)
    
    if (sEvent = "CONNECTED") {
        if (iSocket != -1) {
            Logger.socket := iSocket
            Logger.isConnected := true
            DebugLogSmart("[LOGGER] Successfully connected! Socket: " . iSocket)
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