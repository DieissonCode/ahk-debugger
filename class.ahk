; Cliente de Debug para ser incluído em scripts que desejam enviar logs
#Include socket.ahk

class DebugClient {
    static HOST := "127.0.0.1"  ; Endereço do servidor - use o IP da máquina remota se necessário
    static PORTA := 4041        ; Porta do servidor - deve corresponder à porta no servidor
    static g_Socket := -1       ; Socket de conexão
    static scriptName := ""     ; Nome do script cliente
    static isConnected := false ; Status da conexão
    
    __New(scriptName) {
        this.scriptName := scriptName
        this.Connect()
    }
    
    Connect() {
        ; Tenta conectar ao servidor de debug
        err := AHKsock_Connect(this.HOST, this.PORTA, "DebugClientHandler")
        if (err) {
            ; Falha na conexão
            return false
        }
        return true
    }
    
    Register(levels := "", columns := "") {
        if (!this.isConnected) {
            ; Tentar reconectar
            if (!this.Connect())
                return false
                
            ; Aguarda um pouco para a conexão estabelecer
            Sleep, 100
        }
        
        ; Formata a string para registro
        dataStr := "tipo=REGISTER||scriptName=" . this.scriptName
        
        ; Adiciona níveis e colunas se fornecidos
        if (levels)
            dataStr .= "||levels=" . levels
        if (columns)
            dataStr .= "||columns=" . columns
        
        ; Converte a string para UTF-8 para envio
        VarSetCapacity(utf8, StrPut(dataStr, "UTF-8"))
        StrPut(dataStr, &utf8, "UTF-8")
        bytesToSend := StrPut(dataStr, "UTF-8") - 1
        
        ; Envia os dados
        err := AHKsock_ForceSend(this.g_Socket, &utf8, bytesToSend)
        
        if (err) {
            ; Falha no envio
            this.isConnected := false
            return false
        }
        
        return true
    }
    
    ; Função genérica para enviar log
    Log(message, level := "INFO", functionName := "", lineNumber := "") {
        if (!this.isConnected) {
            ; Tentar reconectar
            if (!this.Connect())
                return false
                
            ; Aguarda um pouco para a conexão estabelecer
            Sleep, 100
        }
        
        ; Prepara os dados do log
        dataArray := [lineNumber, functionName, message]
        
        ; Formata a string para envio
        dataStr := "tipo=" . level . "||scriptName=" . this.scriptName . "||data="
        
        ; Adiciona os dados separados por |
        for index, value in dataArray {
            dataStr .= value . "|"
        }
        ; Remove o último |
        dataStr := RTrim(dataStr, "|")
        
        ; Converte a string para UTF-8 para envio
        VarSetCapacity(utf8, StrPut(dataStr, "UTF-8"))
        StrPut(dataStr, &utf8, "UTF-8")
        bytesToSend := StrPut(dataStr, "UTF-8") - 1
        
        ; Envia os dados
        err := AHKsock_ForceSend(this.g_Socket, &utf8, bytesToSend)
        
        if (err) {
            ; Falha no envio
            this.isConnected := false
            return false
        }
        
        return true
    }
    
    ; Métodos de conveniência para diferentes níveis de log
    Debug(message, functionName := "", lineNumber := "") {
        return this.Log(message, "DEBUG", functionName, lineNumber)
    }
    
    Info(message, functionName := "", lineNumber := "") {
        return this.Log(message, "INFO", functionName, lineNumber)
    }
    
    Warn(message, functionName := "", lineNumber := "") {
        return this.Log(message, "WARN", functionName, lineNumber)
    }
    
    Error(message, functionName := "", lineNumber := "") {
        return this.Log(message, "ERROR", functionName, lineNumber)
    }
}

; Função para tratar eventos de socket do cliente
DebugClientHandler(sEvent, iSocket, sName, sAddr, sPort) {
    if (sEvent = "CONNECTED") {
        if (iSocket != -1) {
            ; Conexão bem-sucedida
            DebugClient.g_Socket := iSocket
            DebugClient.isConnected := true
        } else {
            ; Falha na conexão
            DebugClient.isConnected := false
        }
    }
    else if (sEvent = "DISCONNECTED") {
        ; Marca como desconectado
        DebugClient.isConnected := false
        DebugClient.g_Socket := -1
    }
}