AHKsock_Listen(sPort, sFunction = False) {

	;Check if there is already a socket listening on this port
	If (sktListen := AHKsock_Sockets("GetSocketFromNamePort", A_Space, sPort)) {

		;Check if we're stopping the listening
		If Not sFunction {
			AHKsock_Close(sktListen) ;Close the socket

			;Check if we're retrieving the current function
		} Else If (sFunction = "()") {
			Return AHKsock_Sockets("GetFunction", sktListen)

			;Check if it's a different function
		} Else If (sFunction <> AHKsock_Sockets("GetFunction", sktListen))
			AHKsock_Sockets("SetFunction", sktListen, sFunction) ;Update it

		Return ;We're done
	}

	;Make sure we even have a function
	If Not IsFunc(sFunction)
		Return 2 ;sFunction is not a valid function.

	;Make sure Winsock has been started up
	If (i := AHKsock_Startup())
		Return (i = 1) ? 3 ;The WSAStartup() call failed. The error is in ErrorLevel.
			: 4 ;The Winsock DLL does not support version 2.2.

	;Resolve the local address and port to be used by the server
	VarSetCapacity(aiHints, 16 + 4 * A_PtrSize, 0)
	NumPut(1, aiHints,  0, "Int") ;ai_flags = AI_PASSIVE
	NumPut(2, aiHints,  4, "Int") ;ai_family = AF_INET
	NumPut(1, aiHints,  8, "Int") ;ai_socktype = SOCK_STREAM
	NumPut(6, aiHints, 12, "Int") ;ai_protocol = IPPROTO_TCP
	iResult := DllCall("Ws2_32\GetAddrInfo", "Ptr", 0, "Ptr", &sPort, "Ptr", &aiHints, "Ptr*", aiResult)
	If (iResult != 0) Or ErrorLevel { ;Check for error
		ErrorLevel := ErrorLevel ? ErrorLevel : iResult
		Return 5 ;The getaddrinfo() call failed. The error is in ErrorLevel.
	}

	sktListen := -1 ;INVALID_SOCKET
	sktListen := DllCall("Ws2_32\socket", "Int", NumGet(aiResult+0, 04, "Int")
		, "Int", NumGet(aiResult+0, 08, "Int")
		, "Int", NumGet(aiResult+0, 12, "Int"), "Ptr")
	If (sktListen = -1) Or ErrorLevel { ;Check for INVALID_SOCKET
		sErrorLevel := ErrorLevel ? ErrorLevel : AHKsock_LastError()
		DllCall("Ws2_32\FreeAddrInfo", "Ptr", aiResult)
		ErrorLevel := sErrorLevel
		Return 6 ;The socket() call failed. The error is in ErrorLevel.
	}

	;Setup the TCP listening socket
	iResult := DllCall("Ws2_32\bind", "Ptr", sktListen, "Ptr", NumGet(aiResult+0, 16 + 2 * A_PtrSize), "Int", NumGet(aiResult+0, 16, "Ptr"))
	If (iResult = -1) Or ErrorLevel { ;Check for SOCKET_ERROR
		sErrorLevel := ErrorLevel ? ErrorLevel : AHKsock_LastError()
		DllCall("Ws2_32\closesocket",  "Ptr", sktListen)
		DllCall("Ws2_32\FreeAddrInfo", "Ptr", aiResult)
		ErrorLevel := sErrorLevel
		Return 7 ;The bind() call failed. The error is in ErrorLevel.
	}

	DllCall("Ws2_32\FreeAddrInfo", "Ptr", aiResult)

	;Add socket to array with A_Space for Name and IP to indicate that it's a listening socket
	AHKsock_Sockets("Add", sktListen, A_Space, A_Space, sPort, sFunction)

	;We must now actually register the socket
	If AHKsock_RegisterAsyncSelect(sktListen) {
		sErrorLevel := ErrorLevel
		DllCall("Ws2_32\closesocket", "Ptr", sktListen)
		AHKsock_Sockets("Delete", sktListen) ;Remove from array
		ErrorLevel := sErrorLevel
		Return 8 ;The WSAAsyncSelect() call failed. The error is in ErrorLevel.
	}

	;Start listening for incoming connections
	iResult := DllCall("Ws2_32\listen", "Ptr", sktListen, "Int", 0x7FFFFFFF) ;SOMAXCONN
	If (iResult = -1) Or ErrorLevel { ;Check for SOCKET_ERROR
		sErrorLevel := ErrorLevel ? ErrorLevel : AHKsock_LastError()
		DllCall("Ws2_32\closesocket", "Ptr", sktListen)
		AHKsock_Sockets("Delete", sktListen) ;Remove from array
		ErrorLevel := sErrorLevel
		Return 9 ;The listen() call failed. The error is in ErrorLevel.
	}
}

AHKsock_Connect(sName, sPort, sFunction) {
	Static aiResult, iPointer, bProcessing, iMessage
	Static sCurName, sCurPort, sCurFunction, sktConnect

	;Check if it's just to inquire whether or not a call is possible
	If (Not sName And Not sPort And Not sFunction)
		Return bProcessing

	;Check if we're busy
	If bProcessing And (sFunction != iMessage) {
		ErrorLevel := sCurName A_Tab sCurPort
		Return 1 ;AHKsock_Connect is still processing a connection attempt. ErrorLevel contains the name and the port,
		;delimited by a tab.
	} Else If bProcessing { ;sFunction = iMessage. The connect operation has finished.

		;Check if it was successful
		If (i := sPort >> 16) {

			;Close the socket that failed
			DllCall("Ws2_32\closesocket", "Ptr", sktConnect)

			;Get the next pointer. ai_next
			iPointer := NumGet(iPointer+0, 16 + 3 * A_PtrSize)

			;Check if we reached the end of the linked structs
			If (iPointer = 0) {

				;We can now free the chain of addrinfo structs
				DllCall("Ws2_32\FreeAddrInfo", "Ptr", aiResult)

				;This is to ensure that the user can call AHKsock_Connect() right away upon receiving the message.
				bProcessing := False

				;Raise an error (can't use Return 1 because we were called asynchronously)
				ErrorLevel := i
				AHKsock_RaiseError(1) ;The connect() call failed. The error is in ErrorLevel.

				;Call the function to signal that connection failed
				If IsFunc(sCurFunction)
					%sCurFunction%("CONNECTED", -1, sCurName, 0, sCurPort)

				Return
			}

		} Else { ;Successful connection!

			;Get the IP we successfully connected to
			sIP := DllCall("Ws2_32\inet_ntoa", "UInt", NumGet(NumGet(iPointer+0, 16 + 2 * A_PtrSize)+4, 0, "UInt"), "AStr")

			;We can now free the chain of ADDRINFO structs
			DllCall("Ws2_32\FreeAddrInfo", "Ptr", aiResult)

			;Add socket to array
			AHKsock_Sockets("Add", sktConnect, sCurName, sIP, sCurPort, sCurFunction)

			;This is to ensure that the user can call AHKsock_Connect() right away upon receiving the message.
			bProcessing := False

			;Do this small bit in Critical so that AHKsock_AsyncSelect doesn't receive
			;any FD messages before we call the user function
			Critical

			;We must now actually register the socket
			If AHKsock_RegisterAsyncSelect(sktConnect) {
				sErrorLevel := ErrorLevel ? ErrorLevel : AHKsock_LastError()
				DllCall("Ws2_32\closesocket", "Ptr", sktConnect)
				AHKsock_Sockets("Delete", sktConnect) ;Remove from array
				ErrorLevel := sErrorLevel
				AHKsock_RaiseError(2) ;The WSAAsyncSelect() call failed. The error is in ErrorLevel.

				If IsFunc(sCurFunction) ;Call the function to signal that connection failed
					%sCurFunction%("CONNECTED", -1, sCurName, 0, sCurPort)

			} Else If IsFunc(sCurFunction) ;Call the function to signal that connection was successful
				%sCurFunction%("CONNECTED", sktConnect, sCurName, sIP, sCurPort)

			Return
		}

	} Else { ;We were called

		;Make sure we even have a function
		If Not IsFunc(sFunction)
			Return 2 ;sFunction is not a valid function.

		bProcessing := True ;Block future calls to AHKsock_Connect() until we're done

		;Keep the values
		sCurName := sName
		sCurPort := sPort
		sCurFunction := sFunction

		;Make sure Winsock has been started up
		If (i := AHKsock_Startup()) {
			bProcessing := False
			Return (i = 1) ? 3 ;The WSAStartup() call failed. The error is in ErrorLevel.
				: 4 ;The Winsock DLL does not support version 2.2.
		}

		;Resolve the server address and port
		VarSetCapacity(aiHints, 16 + 4 * A_PtrSize, 0)
		NumPut(2, aiHints,  4, "Int") ;ai_family = AF_INET
		NumPut(1, aiHints,  8, "Int") ;ai_socktype = SOCK_STREAM
		NumPut(6, aiHints, 12, "Int") ;ai_protocol = IPPROTO_TCP
		iResult := DllCall("Ws2_32\GetAddrInfo", "Ptr", &sName, "Ptr", &sPort, "Ptr", &aiHints, "Ptr*", aiResult)
		If (iResult != 0) Or ErrorLevel { ;Check for error
			ErrorLevel := ErrorLevel ? ErrorLevel : iResult
			bProcessing := False
			Return 5 ;The getaddrinfo() call failed. The error is in ErrorLevel.
		}

		;Start with the first struct
		iPointer := aiResult
	}

	;Create a SOCKET for connecting to server
	sktConnect := DllCall("Ws2_32\socket", "Int", NumGet(iPointer+0, 04, "Int")
		, "Int", NumGet(iPointer+0, 08, "Int")
		, "Int", NumGet(iPointer+0, 12, "Int"), "Ptr")
	If (sktConnect = 0xFFFFFFFF) Or ErrorLevel { ;Check for INVALID_SOCKET
		sErrorLevel := ErrorLevel ? ErrorLevel : AHKsock_LastError()
		DllCall("Ws2_32\FreeAddrInfo", "Ptr", aiResult)
		bProcessing := False
		ErrorLevel := sErrorLevel
		If (sFunction = iMessage) { ;Check if we were called asynchronously
			AHKsock_RaiseError(3) ;The socket() call failed. The error is in ErrorLevel.

			;Call the function to signal that connection failed
			If IsFunc(sCurFunction)
				%sCurFunction%("CONNECTED", -1)
		}
		Return 6 ;The socket() call failed. The error is in ErrorLevel.
	}

	;Register the socket to know when the connect() function is done. FD_CONNECT = 16
	iMessage := AHKsock_Settings("Message") + 1
	If AHKsock_RegisterAsyncSelect(sktConnect, 16, "AHKsock_Connect", iMessage) {
		sErrorLevel := ErrorLevel
		DllCall("Ws2_32\FreeAddrInfo", "Ptr", aiResult)
		DllCall("Ws2_32\closesocket",  "Ptr", sktConnect)
		bProcessing := False
		ErrorLevel := sErrorLevel
		If (sFunction = iMessage) { ;Check if we were called asynchronously
			AHKsock_RaiseError(4) ;The WSAAsyncSelect() call failed. The error is in ErrorLevel.

			;Call the function to signal that connection failed
			If IsFunc(sCurFunction)
				%sCurFunction%("CONNECTED", -1)
		}
		Return 7 ;The WSAAsyncSelect() call failed. The error is in ErrorLevel.
	}

	;Connect to server (the connect() call also implicitly binds the socket to any host address and any port)
	iResult := DllCall("Ws2_32\connect", "Ptr", sktConnect, "Ptr", NumGet(iPointer+0, 16 + 2 * A_PtrSize), "Int", NumGet(iPointer+0, 16))
	If ErrorLevel Or ((iResult = -1) And (AHKsock_LastError() != 10035)) { ;Check for any error other than WSAEWOULDBLOCK
		sErrorLevel := ErrorLevel ? ErrorLevel : AHKsock_LastError()
		DllCall("Ws2_32\FreeAddrInfo", "Ptr", aiResult)
		DllCall("Ws2_32\closesocket",  "Ptr", sktConnect)
		bProcessing := False
		ErrorLevel := sErrorLevel
		If (sFunction = iMessage) { ;Check if we were called asynchronously
			AHKsock_RaiseError(5) ;The connect() call failed. The error is in ErrorLevel.

			;Call the function to signal that connection failed
			If IsFunc(sCurFunction)
				%sCurFunction%("CONNECTED", -1)
		}
		Return 8 ;The connect() call failed. The error is in ErrorLevel.
	}
}

AHKsock_Send(iSocket, ptrData = 0, iLength = 0) {

	;Make sure the socket is on record. Fail-safe
	If Not AHKsock_Sockets("Index", iSocket)
		Return -4 ;The socket specified in iSocket is not a recognized socket.

	;Make sure Winsock has been started up
	If Not AHKsock_Startup(1)
		Return -1 ;WSAStartup hasn't been called yet.

	;Make sure the socket is cleared for sending
	If Not AHKsock_Sockets("GetSend", iSocket)
		Return -5 ;The socket specified in iSocket is not cleared for sending.

	/*! Uncomment this block to simulate the possibility of an incomplete send()
	Random, iRand, 1, 100
	If (iRand <= 30) { ;Probability of failure of 30%
		Random, iRand, 1, iLength - 1 ;Randomize how much of the data will not be sent
		iLength -= iRand
	}
	*/

	iSendResult := DllCall("Ws2_32\send", "Ptr", iSocket, "Ptr", ptrData, "Int", iLength, "Int", 0)
	If (iSendResult = -1) And ((iErr := AHKsock_LastError()) = 10035) { ;Check specifically for WSAEWOULDBLOCK
		AHKsock_Sockets("SetSend", iSocket, False) ;Update socket's send status
		Return -2 ;Calling send() would have blocked the thread. Try again once you get the proper update.
	} Else If (iSendResult = -1) Or ErrorLevel {
		ErrorLevel := ErrorLevel ? ErrorLevel : iErr
		Return -3 ;The send() call failed. The error is in ErrorLevel.
	} Else Return iSendResult ;The send() operation was successful
}

AHKsock_ForceSend(iSocket, ptrData, iLength) {

	;Make sure Winsock has been started up
	If Not AHKsock_Startup(1)
		Return -1 ;WSAStartup hasn't been called yet

	;Make sure the socket is on record. Fail-safe
	If Not AHKsock_Sockets("Index", iSocket)
		Return -4

	;Make sure that we're not in Critical, or we won't be able to wait for FD_WRITE messages
	If A_IsCritical
		Return -5

	;Extra precaution to make sure FD_WRITE messages can make it
	Thread, Priority, 0

	;We need to make sure not to fill up the send buffer in one call, or we'll get a performance hit.
	;http://support.microsoft.com/kb/823764

	;Get the socket's send buffer size
	If ((iMaxChunk := AHKsock_SockOpt(iSocket, "SO_SNDBUF")) = -1)
		Return -6

	;Check if we'll be sending in chunks or not
	If (iMaxChunk <= 1) {

		;We'll be sending as much as possible everytime!

		Loop { ;Keep sending the data until we're done or until an error occurs

			;Wait until we can send data (ie. when FD_WRITE arrives)
			While Not AHKsock_Sockets("GetSend", iSocket)
				Sleep -1

			Loop { ;Keep sending the data until we get WSAEWOULDBLOCK or until an error occurs
				If ((iSendResult := AHKsock_Send(iSocket, ptrData, iLength)) < 0) {
					If (iSendResult = -2) ;Check specifically for WSAEWOULDBLOCK
						Break ;Calling send() would have blocked the thread. Break the loop and we'll try again after we
					;receive FD_WRITE
					Else Return iSendResult ;Something bad happened with AHKsock_Send. Return the same value we got.
				} Else {

					;AHKsock_Send was able to send bytes. Let's check if it sent only part of what we requested
					If (iSendResult < iLength) ;Move the offset up by what we were able to send
						ptrData += iSendResult, iLength -= iSendResult
					Else Return ;We're done sending all the data
				}
		}
		}
		} Else {

			;We'll be sending in chunks of just under the send buffer size to avoid the performance hit

			iMaxChunk -= 1 ;Reduce by 1 to be smaller than the send buffer
			Loop { ;Keep sending the data until we're done or until an error occurs

				;Wait until we can send data (ie. when FD_WRITE arrives)
				While Not AHKsock_Sockets("GetSend", iSocket)
					Sleep -1

				;Check if we have less than the max chunk to send
				If (iLength < iMaxChunk) {

					Loop { ;Keep sending the data until we get WSAEWOULDBLOCK or until an error occurs
						;Send using the traditional offset method
						If ((iSendResult := AHKsock_Send(iSocket, ptrData, iLength)) < 0) {
							If (iSendResult = -2) ;Check specifically for WSAEWOULDBLOCK
								Break ;Calling send() would have blocked the thread. Break the loop and we'll try again after we
							;receive FD_WRITE
							Else Return iSendResult ;Something bad happened with AHKsock_Send. Return the same value we got.
						} Else {

							;AHKsock_Send was able to send bytes. Let's check if it sent only part of what we requested
							If (iSendResult < iLength) ;Move the offset up by what we were able to send
								ptrData += iSendResult, iLength -= iSendResult
							Else Return ;We're done sending all the data
						}
				}
				} Else {

					;Send up to max chunk
					If ((iSendResult := AHKsock_Send(iSocket, ptrData, iMaxChunk)) < 0) {
						If (iSendResult = -2) ;Check specifically for WSAEWOULDBLOCK
							Continue ;Calling send() would have blocked the thread. Continue the loop and we'll try again after
						;we receive FD_WRITE
						Else Return iSendResult ;Something bad happened with AHKsock_Send. Return the same value we got.
					} Else ptrData += iSendResult, iLength -= iSendResult ;Move up offset by updating the pointer and length
				}
		}
	}
}

AHKsock_Close(iSocket = -1, iTimeout = 5000) {

	;Make sure Winsock has been started up
	If Not AHKsock_Startup(1)
		Return ;There's nothing to close

	If (iSocket = -1) { ;We need to close all the sockets

		;Check if we even have sockets to close
		If Not AHKsock_Sockets() {
			DllCall("Ws2_32\WSACleanup")
			AHKsock_Startup(2) ;Reset the value to show that we've turned off Winsock
			Return ;We're done!
		}

		;Take the current time (needed for time-outing)
		iStartClose := A_TickCount

		Loop % AHKsock_Sockets() ;Close all sockets and cleanup
			AHKsock_ShutdownSocket(AHKsock_Sockets("GetSocketFromIndex", A_Index))

		;Check if we're in the OnExit subroutine
		If Not A_ExitReason {

			A_IsCriticalOld := A_IsCritical

			;Make sure we can still receive FD_CLOSE msgs
			Critical, Off
			Thread, Priority, 0

			;We can try a graceful shutdown or wait for a timeout
			While (AHKsock_Sockets()) And (A_TickCount - iStartClose < iTimeout)
				Sleep, -1

			;Restore previous Critical
			Critical, %A_IsCriticalOld%
		}

		/*! Used for debugging purposes only
		If (i := AHKsock_Sockets()) {
			If (i = 1)
				OutputDebug, % "Cleaning up now, with the socket " AHKsock_Sockets("GetSocketFromIndex", 1) " remaining..."
			Else {
				OutputDebug, % "Cleaning up now, with the following sockets remaining:"
				Loop % AHKsock_Sockets() {
					OutputDebug, % AHKsock_Sockets("GetSocketFromIndex", A_Index)
				}
			}
		}
		*/

		DllCall("Ws2_32\WSACleanup")
		AHKsock_Startup(2) ;Reset the value to show that we've turned off Winsock

		;Close only one socket
	} Else If AHKsock_ShutdownSocket(iSocket) ;Error-checking
		Return 1 ;The shutdown() call failed. The error is in ErrorLevel.
}

AHKsock_GetAddrInfo(sHostName, ByRef sIPList, bOne = False) {

	;Make sure Winsock has been started up
	If (i := AHKsock_Startup())
		Return i ;Return the same error (error 1 and 2)

	;Resolve the address and port
	VarSetCapacity(aiHints, 16 + 4 * A_PtrSize, 0)
	NumPut(2, aiHints,  4, "Int") ;ai_family = AF_INET
	NumPut(1, aiHints,  8, "Int") ;ai_socktype = SOCK_STREAM
	NumPut(6, aiHints, 12, "Int") ;ai_protocol = IPPROTO_TCP
	iResult := DllCall("Ws2_32\GetAddrInfo", "Ptr", &sHostName, "Ptr", 0, "Ptr", &aiHints, "Ptr*", aiResult)
	If (iResult = 11001) ;Check specifically for WSAHOST_NOT_FOUND since it's the most common error
		Return 3 ;Received WSAHOST_NOT_FOUND. No such host is known.
	Else If (iResult != 0) Or ErrorLevel { ;Check for any other error
		ErrorLevel := ErrorLevel ? ErrorLevel : iResult
		Return 4 ;The getaddrinfo() call failed. The error is in ErrorLevel.
	}

	If bOne
		sIPList := DllCall("Ws2_32\inet_ntoa", "UInt", NumGet(NumGet(aiResult+0, 16 + 2 * A_PtrSize)+4, 0, "UInt"), "AStr")
	Else {

		;Start with the first addrinfo struct
		iPointer := aiResult, sIPList := ""
		While iPointer {
			s := DllCall("Ws2_32\inet_ntoa", "UInt", NumGet(NumGet(iPointer+0, 16 + 2 * A_PtrSize)+4, 0, "UInt"), "AStr")
			iPointer := NumGet(iPointer+0, 16 + 3 * A_PtrSize) ;Go to the next addrinfo struct
			sIPList .=  s (iPointer ? "`n" : "") ;Add newline only if it's not the last one
		}
	}

	;We're done
	DllCall("Ws2_32\FreeAddrInfo", "Ptr", aiResult)
}

AHKsock_GetNameInfo(sIP, ByRef sHostName, sPort = 0, ByRef sService = "") {

	;Make sure Winsock has been started up
	If (i := AHKsock_Startup())
		Return i ;Return the same error (error 1 and 2)

	;Translate to IN_ADDR
	iIP := DllCall("Ws2_32\inet_addr", "AStr", sIP, "UInt")
	If (iIP = 0 Or iIP = 0xFFFFFFFF) ;Check for INADDR_NONE or INADDR_ANY
		Return 3 ;The IP address supplied in sIP is invalid.

	;Construct a sockaddr struct
	VarSetCapacity(tSockAddr, 16, 0)
	NumPut(2,   tSockAddr, 0, "Short") ;ai_family = AF_INET
	NumPut(iIP, tSockAddr, 4, "UInt") ;Put in the IN_ADDR

	;Fill in the port field if we're also looking up the service name
	If sPort           ;Translate to network byte order
		NumPut(DllCall("Ws2_32\htons", "UShort", sPort, "UShort"), tSockAddr, 2, "UShort")

	;Prep vars
	VarSetCapacity(sHostName, 1025 * 2, 0) ;NI_MAXHOST
	If sPort
		VarSetCapacity(sService, 32 * 2, 0) ;NI_MAXSERV

	iResult := DllCall("Ws2_32\GetNameInfoW", "Ptr", &tSockAddr, "Int", 16, "Str", sHostName, "UInt", 1025 * 2
		, sPort ? "Str" : "UInt", sPort ? sService : 0, "UInt", 32 * 2, "Int", 0)
	If (iResult != 0) Or ErrorLevel {
		ErrorLevel := ErrorLevel ? ErrorLevel : DllCall("Ws2_32\WSAGetLastError")
		Return 4 ;The getnameinfo() call failed. The error is in ErrorLevel.
	}
}

AHKsock_SockOpt(iSocket, sOption, iValue = -1) {

	;Prep variable
	VarSetCapacity(iOptVal, iOptValLength := 4, 0)
	If (iValue <> -1)
		NumPut(iValue, iOptVal, 0, "UInt")

	If (sOption = "SO_KEEPALIVE") {
		intLevel := 0xFFFF ;SOL_SOCKET
		intOptName := 0x0008 ;SO_KEEPALIVE
	} Else If (sOption = "SO_SNDBUF") {
		intLevel := 0xFFFF ;SOL_SOCKET
		intOptName := 0x1001 ;SO_SNDBUF
	} Else If (sOption = "SO_RCVBUF") {
		intLevel := 0xFFFF ;SOL_SOCKET
		intOptName := 0x1002 ;SO_SNDBUF
	} Else If (sOption = "TCP_NODELAY") {
		intLevel := 6 ;IPPROTO_TCP
		intOptName := 0x0001 ;TCP_NODELAY
	}

	;Check if we're getting or setting
	If (iValue = -1) {
		iResult := DllCall("Ws2_32\getsockopt", "Ptr", iSocket, "Int", intLevel, "Int", intOptName
			, "UInt*", iOptVal, "Int*", iOptValLength)
		If (iResult = -1) Or ErrorLevel { ;Check for SOCKET_ERROR
			ErrorLevel := ErrorLevel ? ErrorLevel : AHKsock_LastError()
			Return -1
		} Else Return iOptVal
	} Else {
		iResult := DllCall("Ws2_32\setsockopt", "Ptr", iSocket, "Int", intLevel, "Int", intOptName
			, "Ptr", &iOptVal, "Int",  iOptValLength)
		If (iResult = -1) Or ErrorLevel { ;Check for SOCKET_ERROR
			ErrorLevel := ErrorLevel ? ErrorLevel : AHKsock_LastError()
			Return -2
		}
	}
}

/*******************\
 Support functions  |
				  */

AHKsock_Startup(iMode = 0) {
	Static bAlreadyStarted

	/*
	iMode = 0 ;Turns on WSAStartup()
	iMode = 1 ;Returns whether or not WSAStartup has been called
	iMode = 2 ;Resets the static variable to force another call next time iMode = 0
	*/

	If (iMode = 2)
		bAlreadyStarted := False
	Else If (iMode = 1)
		Return bAlreadyStarted
	Else If Not bAlreadyStarted { ;iMode = 0. Call the function only if it hasn't already been called.

		;Start it up - request version 2.2
		VarSetCapacity(wsaData, A_PtrSize = 4 ? 400 : 408, 0)
		iResult := DllCall("Ws2_32\WSAStartup", "UShort", 0x0202, "Ptr", &wsaData)
		If (iResult != 0) Or ErrorLevel {
			ErrorLevel := ErrorLevel ? ErrorLevel : iResult
			Return 1
		}

		;Make sure the Winsock DLL supports at least version 2.2
		If (NumGet(wsaData, 2, "UShort") < 0x0202) {
			DllCall("Ws2_32\WSACleanup") ;Abort
			ErrorLevel := "The Winsock DLL does not support version 2.2."
			Return 2
		}

		bAlreadyStarted := True
	}
}

AHKsock_ShutdownSocket(iSocket) {

	;Check if it's a listening socket
	sName := AHKsock_Sockets("GetName", iSocket)
	If (sName != A_Space) { ;It's not a listening socket. Shutdown send operations.
		iResult := DllCall("Ws2_32\shutdown", "Ptr", iSocket, "Int", 1) ;SD_SEND
		If (iResult = -1) Or ErrorLevel {
			sErrorLevel := ErrorLevel ? ErrorLevel : AHKsock_LastError()
			DllCall("Ws2_32\closesocket", "Ptr", iSocket)
			AHKsock_Sockets("Delete", iSocket)
			ErrorLevel := sErrorLevel
			Return 1
		}

		;Mark it
		AHKsock_Sockets("SetShutdown", iSocket)

	} Else {
		DllCall("Ws2_32\closesocket", "Ptr", iSocket) ;It's only a listening socket
		AHKsock_Sockets("Delete", iSocket) ;Remove it from the array
	}
}

/***********************\
 AsyncSelect functions  |
					  */
;FD_READ | FD_WRITE | FD_ACCEPT | FD_CLOSE
AHKsock_RegisterAsyncSelect(iSocket, fFlags = 43, sFunction = "AHKsock_AsyncSelect", iMsg = 0) {
	Static hwnd := False

	If Not hwnd { ;Use the main AHK window
		A_DetectHiddenWindowsOld := A_DetectHiddenWindows
		DetectHiddenWindows, On
		WinGet, hwnd, ID, % "ahk_pid " DllCall("GetCurrentProcessId") " ahk_class AutoHotkey"
		DetectHiddenWindows, %A_DetectHiddenWindowsOld%
	}

	iMsg := iMsg ? iMsg : AHKsock_Settings("Message")
	If (OnMessage(iMsg) <> sFunction)
		OnMessage(iMsg, sFunction)

	iResult := DllCall("Ws2_32\WSAAsyncSelect", "Ptr", iSocket, "Ptr", hwnd, "UInt", iMsg, "Int", fFlags)
	If (iResult = -1) Or ErrorLevel { ;Check for SOCKET_ERROR
		ErrorLevel := ErrorLevel ? ErrorLevel : AHKsock_LastError()
		Return 1
	}
}

AHKsock_AsyncSelect(wParam, lParam) {
	Critical ;So that messages are buffered

	;wParam parameter identifies the socket on which a network event has occurred
	;The low word of lParam specifies the network event that has occurred.
	;The high word of lParam contains any error code

	;Make sure the socket is on record. Fail-safe
	If Not AHKsock_Sockets("Index", wParam)
		Return

	iEvent := lParam & 0xFFFF, iErrorCode := lParam >> 16

	/*! Used for debugging purposes
	OutputDebug, % "AsyncSelect - A network event " iEvent " has occurred on socket " wParam
	If iErrorCode
		OutputDebug, % "AsyncSelect - Error code = " iErrorCode
	*/

	If (iEvent = 1) { ;FD_READ

		;Check for error
		If iErrorCode { ;WSAENETDOWN is the only possible
			ErrorLevel := iErrorCode
			;FD_READ event received with an error. The error is in ErrorLevel. The socket is in iSocket.
			AHKsock_RaiseError(6, wParam)
			Return
		}

		VarSetCapacity(bufReceived, bufReceivedLength := AHKsock_Settings("Buffer"), 0)
		iResult := DllCall("Ws2_32\recv", "UInt", wParam, "Ptr", &bufReceived, "Int", bufReceivedLength, "Int", 0)
		If (iResult > 0) { ;We received data!
			VarSetCapacity(bufReceived, -1) ;Update the internal length

			;Get associated function and call it
			If IsFunc(sFunc := AHKsock_Sockets("GetFunction", wParam))
				%sFunc%("RECEIVED", wParam, AHKsock_Sockets("GetName", wParam)
					, AHKsock_Sockets("GetAddr", wParam)
					, AHKsock_Sockets("GetPort", wParam), bufReceived, iResult)

			;Check for error other than WSAEWOULDBLOCK
		} Else If ErrorLevel Or ((iResult = -1) And Not ((iErrorCode := AHKsock_LastError()) = 10035)) {
			ErrorLevel := ErrorLevel ? ErrorLevel : iErrorCode
			AHKsock_RaiseError(7, wParam) ;The recv() call failed. The error is in ErrorLevel. The socket is in iSocket.
			iResult = -1 ;So that if it's a spoofed call from FD_CLOSE, we exit the loop and close the socket
		}

		;Here, we bother with returning a value in case it's a spoofed call from FD_CLOSE
		Return iResult

	} Else If (iEvent = 2) { ;FD_WRITE

		;Check for error
		If iErrorCode { ;WSAENETDOWN is the only possible
			ErrorLevel := iErrorCode
			;FD_WRITE event received with an error. The error is in ErrorLevel. The socket is in iSocket.
			AHKsock_RaiseError(8, wParam)
			Return
		}

		;Update socket's setting
		AHKsock_Sockets("SetSend", wParam, True)

		;Make sure the socket isn't already shut down
		If Not AHKsock_Sockets("GetShutdown", wParam)
			If IsFunc(sFunc := AHKsock_Sockets("GetFunction", wParam))
				%sFunc%("SEND", wParam, AHKsock_Sockets("GetName", wParam)
					, AHKsock_Sockets("GetAddr", wParam)
					, AHKsock_Sockets("GetPort", wParam))

	} Else If (iEvent = 8) { ;FD_ACCEPT

		;Check for error
		If iErrorCode { ;WSAENETDOWN is the only possible
			ErrorLevel := iErrorCode
			;FD_ACCEPT event received with an error. The error is in ErrorLevel. The socket is in iSocket.
			AHKsock_RaiseError(9, wParam)
			Return
		}

		;We need to accept the connection
		VarSetCapacity(tSockAddr, tSockAddrLength := 16, 0)
		sktClient := DllCall("Ws2_32\accept", "Ptr", wParam, "Ptr", &tSockAddr, "Int*", tSockAddrLength)
		If (sktClient = -1) And ((iErrorCode := AHKsock_LastError()) = 10035) ;Check specifically for WSAEWOULDBLOCK
			Return ;We'll be called again next time we can retry accept()
		Else If (sktClient = -1) Or ErrorLevel { ;Check for INVALID_SOCKET
			ErrorLevel := ErrorLevel ? ErrorLevel : iErrorCode
			;The accept() call failed. The error is in ErrorLevel. The listening socket is in iSocket.
			AHKsock_RaiseError(10, wParam)
			Return
		}

		;Add to array
		sName := ""
		sAddr := DllCall("Ws2_32\inet_ntoa", "UInt", NumGet(tSockAddr, 4, "UInt"), "AStr")
		sPort := AHKsock_Sockets("GetPort", wParam)
		sFunc := AHKsock_Sockets("GetFunction", wParam)
		AHKsock_Sockets("Add", sktClient, sName, sAddr, sPort, sFunc)

		;Go back to listening
		iResult := DllCall("Ws2_32\listen", "Ptr", wParam, "Int", 0x7FFFFFFF) ;SOMAXCONN
		If (iResult = -1) Or ErrorLevel { ;Check for SOCKET_ERROR
			sErrorLevel := ErrorLevel ? ErrorLevel : AHKsock_LastError()
			DllCall("Ws2_32\closesocket", "Ptr", wParam)
			AHKsock_Sockets("Delete", wParam) ;Remove from array
			ErrorLevel := sErrorLevel
			;The listen() call failed. The error is in ErrorLevel. The listening socket is in iSocket.
			AHKsock_RaiseError(12, wParam)
			Return
		}

		;Get associated function and call it
		If IsFunc(sFunc)
			%sFunc%("ACCEPTED", sktClient, sName, sAddr, sPort)

	} Else If (iEvent = 32) { ;FD_CLOSE

		;Keep receiving data before closing the socket by spoofing an FD_READ event to call recv()
		While (AHKsock_AsyncSelect(wParam, 1) > 0)
			Sleep, -1

		;Check if we initiated it
		If Not AHKsock_Sockets("GetShutdown", wParam) {

			;Last chance to send data. Get associated function and call it.
			If IsFunc(sFunc := AHKsock_Sockets("GetFunction", wParam))
				%sFunc%("SENDLAST", wParam, AHKsock_Sockets("GetName", wParam)
					, AHKsock_Sockets("GetAddr", wParam)
					, AHKsock_Sockets("GetPort", wParam))

			;Shutdown the socket. This is to attempt a graceful shutdown
			If AHKsock_ShutdownSocket(wParam) {
				;The shutdown() call failed. The error is in ErrorLevel. The socket is in iSocket.
				AHKsock_RaiseError(13, wParam)
				Return
			}
		}

		;We just have to close the socket then
		DllCall("Ws2_32\closesocket", "Ptr", wParam)

		;Get associated data before deleting
		sFunc := AHKsock_Sockets("GetFunction", wParam)
		sName := AHKsock_Sockets("GetName", wParam)
		sAddr := AHKsock_Sockets("GetAddr", wParam)
		sPort := AHKsock_Sockets("GetPort", wParam)

		;We can remove it from the array
		AHKsock_Sockets("Delete", wParam)

		If IsFunc(sFunc)
			%sFunc%("DISCONNECTED", wParam, sName, sAddr, sPort)
	}
}

/******************\
 Array controller  |
				 */

AHKsock_Sockets(sAction = "Count", iSocket = "", sName = "", sAddr = "", sPort = "", sFunction = "") {
	Static
	Static aSockets0 := 0
	Static iLastSocket := 0xFFFFFFFF ;Cache to lessen index lookups on the same socket
	Local i, ret, A_IsCriticalOld

	A_IsCriticalOld := A_IsCritical
	Critical

	If (sAction = "Count") {
		ret := aSockets0

	} Else If (sAction = "Add") {
		aSockets0 += 1 ;Expand array
		aSockets%aSockets0%_Sock := iSocket
		aSockets%aSockets0%_Name := sName
		aSockets%aSockets0%_Addr := sAddr
		aSockets%aSockets0%_Port := sPort
		aSockets%aSockets0%_Func := sFunction
		aSockets%aSockets0%_Shutdown := False
		aSockets%aSockets0%_Send := False

	} Else If (sAction = "Delete") {

		;First we need the index
		i := (iSocket = iLastSocket) ;Check cache
			? iLastSocketIndex
			: AHKsock_Sockets("Index", iSocket)

		If i {
			iLastSocket := 0xFFFF ;Clear cache
			If (i < aSockets0) { ;Let the last item overwrite this one
				aSockets%i%_Sock := aSockets%aSockets0%_Sock
				aSockets%i%_Name := aSockets%aSockets0%_Name
				aSockets%i%_Addr := aSockets%aSockets0%_Addr
				aSockets%i%_Port := aSockets%aSockets0%_Port
				aSockets%i%_Func := aSockets%aSockets0%_Func
				aSockets%i%_Shutdown := aSockets%aSockets0%_Shutdown
				aSockets%i%_Send := aSockets%aSockets0%_Send

			}
			aSockets0 -= 1 ;Remove element
		}

	} Else If (sAction = "GetName") {
		i := (iSocket = iLastSocket) ;Check cache
			? iLastSocketIndex
			: AHKsock_Sockets("Index", iSocket)
		ret := aSockets%i%_Name

	} Else If (sAction = "GetAddr") {
		i := (iSocket = iLastSocket) ;Check cache
			? iLastSocketIndex
			: AHKsock_Sockets("Index", iSocket)
		ret := aSockets%i%_Addr

	} Else If (sAction = "GetPort") {
		i := (iSocket = iLastSocket) ;Check cache
			? iLastSocketIndex
			: AHKsock_Sockets("Index", iSocket)
		ret := aSockets%i%_Port

	} Else If (sAction = "GetFunction") {
		i := (iSocket = iLastSocket) ;Check cache
			? iLastSocketIndex
			: AHKsock_Sockets("Index", iSocket)
		ret := aSockets%i%_Func

	} Else If (sAction = "SetFunction") {
		i := (iSocket = iLastSocket) ;Check cache
			? iLastSocketIndex
			: AHKsock_Sockets("Index", iSocket)
		aSockets%i%_Func := sName

	} Else If (sAction = "GetSend") {
		i := (iSocket = iLastSocket) ;Check cache
			? iLastSocketIndex
			: AHKsock_Sockets("Index", iSocket)
		ret := aSockets%i%_Send

	} Else If (sAction = "SetSend") {
		i := (iSocket = iLastSocket) ;Check cache
			? iLastSocketIndex
			: AHKsock_Sockets("Index", iSocket)
		aSockets%i%_Send := sName

	} Else If (sAction = "GetShutdown") {
		i := (iSocket = iLastSocket) ;Check cache
			? iLastSocketIndex
			: AHKsock_Sockets("Index", iSocket)
		ret := aSockets%i%_Shutdown

	} Else If (sAction = "SetShutdown") {
		i := (iSocket = iLastSocket) ;Check cache
			? iLastSocketIndex
			: AHKsock_Sockets("Index", iSocket)
		aSockets%i%_Shutdown := True

	} Else If (sAction = "GetSocketFromNamePort") {
		Loop % aSockets0 {
			If (aSockets%A_Index%_Name = iSocket)
				And (aSockets%A_Index%_Port = sName) {
				ret := aSockets%A_Index%_Sock
				Break
			}
		}

	} Else If (sAction = "GetSocketFromIndex") {
		ret := aSockets%iSocket%_Sock

	} Else If (sAction = "Index") {
		Loop % aSockets0 {
			If (aSockets%A_Index%_Sock = iSocket) {
				iLastSocketIndex := A_Index, iLastSocket := iSocket
				ret := A_Index
				Break
			}
		}
	}

	;Restore old Critical setting
	Critical %A_IsCriticalOld%
	Return ret
}

/*****************\
 Error Functions  |
				*/

AHKsock_LastError() {
	Return DllCall("Ws2_32\WSAGetLastError")
}

AHKsock_ErrorHandler(sFunction = """") {
	Static sCurrentFunction
	If (sFunction = """")
		Return sCurrentFunction
	Else sCurrentFunction := sFunction
}

AHKsock_RaiseError(iError, iSocket = -1) {
	If IsFunc(sFunc := AHKsock_ErrorHandler())
		%sFunc%(iError, iSocket)
}

/*******************\
 Settings Function  |
				  */

AHKsock_Settings(sSetting, sValue = "") {
	Static iMessage := 0x8000
	Static iBuffer := 65536

	If (sSetting = "Message") {
		If Not sValue
			Return iMessage
		Else iMessage := (sValue = "Reset") ? 0x8000 : sValue
	} Else If (sSetting = "Buffer") {
		If Not sValue
			Return iBuffer
		Else iBuffer := (sValue = "Reset") ? 65536 : sValue
	}
}