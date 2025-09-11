; Script de teste em loop para Logger com reconexão automática e buffer local
; NÃO remova meus comentários do começo do arquivo!

#SingleInstance Force
#Include Logger.ahk

logger := new Logger({name: "LoggerLoopTest"})

global LoopCount := 0
global MaxLoops := 999999 ; Deixe rodando para testar 24/7

; Timer para reconexão automática
SetTimer, TryLoggerConnect, 2000

TryLoggerConnect:
    if (!logger.isConnected) {
        logger.connect()
    }
return

; Loop principal de envio de logs
SetTimer, LoggerTestLoop, 700

LoggerTestLoop:
    LoopCount++
    logger.debug("Loop " . LoopCount . ": DEBUG - Teste rotina automática")
    logger.info("Loop " . LoopCount . ": INFO - Processamento OK")
    logger.warn("Loop " . LoopCount . ": WARN - Detecção de uso elevado de recursos")
    logger.error("Loop " . LoopCount . ": ERROR - Falha simulada em processo " . LoopCount)
    logger.load("Loop " . LoopCount . ": LOAD - Dados carregados do ciclo " . LoopCount)

    ; Testar desconexão/reconexão manual
    if (mod(LoopCount, 50) = 0) {
        logger.info("Loop " . LoopCount . ": INFO - Simulando desconexão manual para teste de reconexão")
        logger.disconnect()
    }

    ; Testar buffer local
    if (mod(LoopCount, 75) = 0) {
        logger.info("Loop " . LoopCount . ": INFO - Simulando envio de logs sem conexão (buffer local)")
        logger.disconnect()
        Sleep, 500
        logger.info("Loop " . LoopCount . ": INFO - Este log vai para o buffer local")
        logger.debug("Loop " . LoopCount . ": DEBUG - Buffer local em ação")
        Sleep, 1000
        logger.connect() ; Força reconectar
    }

    ; Status para depuração
    if (mod(LoopCount, 20) = 0) {
        OutputDebug,% "TEST] Loop " LoopCount " - Status da conexão: " logger.isConnected
    }
return

; Fechar corretamente
GuiClose:
OnExit:
    ExitApp
return