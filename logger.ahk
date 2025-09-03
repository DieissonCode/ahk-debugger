; Logger.ahk - Versão simples e robusta para envio de logs
#Include C:\Autohotkey 2024\Root\Libs\socket.ahk

class Logger {
    static HOST := "127.0.0.1"  ; Endereço do servidor
    static PORTA := 4041        ; Porta do servidor
    static g_Socket := -1       ; Socket de conexão
    static scriptName := ""     ; Nome do script 
    static isConnected := false ; Status da conexão
    
    ; Construtor - inicializa o logger com o nome do script
    __New(scriptName) {
        this.scriptName := scriptName
        OutputDebug, % "[Logger] Inicializando para script: " this.scriptName
        this.Connect()
    }
    
    ; Tenta conectar ao servidor
    Connect() {
        OutputDebug, % "[Logger] Tentando conectar ao servidor em " this.HOST ":" this.PORTA
        err := AHKsock_Connect(this.HOST, this.PORTA, "LoggerSocketHandler")
        if (err) {
            OutputDebug, % "[Logger] Falha ao conectar. Erro: " err
            return false
        }
        OutputDebug, % "[Logger] Solicitação de conexão enviada"
        return true
    }
    
    ; Método genérico para enviar logs
    Log(message, level := "INFO") {
        if (!this.isConnected) {
            OutputDebug, % "[Logger] Não conectado. Tentando reconectar..."
            if (!this.Connect())
                return false
            Sleep, 100 ; Pequena pausa para dar tempo à conexão
        }
        
        ; Formata a string EXATAMENTE como em Debug-Client.ahk
        dataStr := "tipo=" . level . "||scriptName=" . this.scriptName . "||mensagem=" . message
        OutputDebug, % "[Logger] Enviando: " dataStr
        
        ; Converte a string para UTF-8
        VarSetCapacity(utf8, StrPut(dataStr, "UTF-8"))
        StrPut(dataStr, &utf8, "UTF-8")
        bytesToSend := StrPut(dataStr, "UTF-8") - 1
        
        ; Envia usando o mesmo método do seu código original
        err := AHKsock_ForceSend(this.g_Socket, &utf8, bytesToSend)
        
        if (err) {
            OutputDebug, % "[Logger] Erro ao enviar: " err
            this.isConnected := false
            return false
        }
        
        OutputDebug, % "[Logger] Log enviado com sucesso"
        return true
    }
    
    ; Métodos de conveniência para diferentes níveis de log
    Debug(message) {
        return this.Log(message, "DEBUG")
    }
    
    Info(message) {
        return this.Log(message, "INFO")
    }
    
    Warn(message) {
        return this.Log(message, "WARN")
    }
    
    Error(message) {
        return this.Log(message, "ERROR")
    }
}

; Função para tratar eventos de socket (EXATAMENTE como DebugClientHandler)
LoggerSocketHandler(sEvent, iSocket, sName, sAddr, sPort) {
    OutputDebug, % "[Logger] Evento: " sEvent " | Socket: " iSocket
    
    if (sEvent = "CONNECTED") {
        if (iSocket != -1) {
            ; Conexão bem-sucedida
            Logger.g_Socket := iSocket
            Logger.isConnected := true
            OutputDebug, % "[Logger] Conectado com sucesso! Socket: " iSocket
        } else {
            ; Falha na conexão
            Logger.isConnected := false
            OutputDebug, % "[Logger] Falha na conexão"
        }
    }
    else if (sEvent = "DISCONNECTED") {
        ; Marca como desconectado
        Logger.isConnected := false
        Logger.g_Socket := -1
        OutputDebug, % "[Logger] Desconectado do servidor"
    }
}