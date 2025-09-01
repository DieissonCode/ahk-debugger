#SingleInstance Force
#Include Logger.ahk

; Inicializar
OutputDebug, =============== TESTE DO LOGGER ===============

; Criar uma instância do Logger diretamente
logger := new Logger("ExemploScript")

; Aguardar um pouco para a conexão ser estabelecida
Sleep, 1000

; Enviar logs de diferentes tipos
logger.Debug("Teste de mensagem DEBUG")
Sleep, 500

logger.Info("Sistema inicializado com sucesso")
Sleep, 500

logger.Warn("Aviso: pouca memória disponível")
Sleep, 500

logger.Error("Erro: arquivo não encontrado")
Sleep, 500

; Verificar status
MsgBox, % "Teste concluído!`n"
        . "Status da conexão: " . (logger.isConnected ? "Conectado" : "Desconectado")

OutputDebug, =============== FIM DO TESTE ===============