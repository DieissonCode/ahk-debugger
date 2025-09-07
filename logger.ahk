; Logger.ahk - Versão simples e robusta para envio de logs
#Include C:\Autohotkey 2024\Root\Libs\socket.ahk
#Include C:\AutoHotkey\class\functions.ahk

class Logger {
    static HOST := "192.9.100.100"
    static PORTA := 4041
    static g_Socket := -1
    static scriptName := ""
    static isConnected := false

    __New(obj="") {
        this.scriptName := obj.name ? obj.name : A_IPAddress1 " - " A_ScriptName
        this.HOST := obj.host ? obj.host : this.HOST
        DebugLogSmart("[Logger] Inicializando para script: " this.scriptName)
        this.Connect()
    }

    Connect() {
        DebugLogSmart("[Logger] Tentando conectar ao servidor em " this.HOST ":" this.PORTA)
        err := AHKsock_Connect(this.HOST, this.PORTA, "LoggerSocketHandler")
        if (err) {
            DebugLogSmart("[Logger] Falha ao conectar. Erro: " err)
            return false
        }
        DebugLogSmart("[Logger] Solicitação de conexão enviada")
        return true
    }

    Log(message, level := "INFO") {
        if (!this.isConnected) {
			Try this.Connect()
				if (!this.isConnected)	{
          			DebugLogSmart("[Logger] Não conectado.`n`ttipo=" . level . "||scriptName=" . StrReplace(StrReplace(this.scriptName, ".ahk"), ".exe") . "||mensagem=" . message)
            		return false
				}
        }
        
        dataStr := "tipo=" . level . "||scriptName=" . StrReplace(StrReplace(this.scriptName, ".ahk"), ".exe") . "||mensagem=" . message
        DebugLogSmart("[Logger] Enviando: " dataStr)

        VarSetCapacity(utf8, StrPut(dataStr, "UTF-8"))
        StrPut(dataStr, &utf8, "UTF-8")
        bytesToSend := StrPut(dataStr, "UTF-8") - 1
        
        err := AHKsock_ForceSend(this.g_Socket, &utf8, bytesToSend)
        
        if (err) {
            DebugLogSmart("[Logger] Erro ao enviar: " err)
            this.isConnected := false
            return false
        }
        
        DebugLogSmart("[Logger] Log enviado com sucesso")
        return true
    }

    Debug(message) {
        return this.Log(message, "DEBUG")
    }

    Error(message) {
        return this.Log(message, "ERROR")
    }

    Load(message) {
        return this.Log(message, "LOAD")
    }

    Info(message) {
        return this.Log(message, "INFO")
    }
    
    Warn(message) {
        return this.Log(message, "WARN")
    }
}

LoggerSocketHandler(sEvent, iSocket, sName, sAddr, sPort) {
    DebugLogSmart("[Logger] Evento: " sEvent " | Socket: " iSocket)
    
    if (sEvent = "CONNECTED") {
        if (iSocket != -1) {
            Logger.g_Socket := iSocket
            Logger.isConnected := true
            DebugLogSmart("[Logger] Conectado com sucesso! Socket: " iSocket)
        } else {
            Logger.isConnected := false
            DebugLogSmart("[Logger] Falha na conexão")
        }
    }
    else if (sEvent = "DISCONNECTED") {
        Logger.isConnected := false
        Logger.g_Socket := -1
        DebugLogSmart("[Logger] Desconectado do servidor")
    }
}