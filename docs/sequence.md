# Authentication Sequence

User authenticates themselves with Authentication service using basic authentication. If successful, receives an user authentication token to use for further requests this session

```{plantuml}
    @startuml
    !theme mimeograph
    actor User
    User -> Client : [[https://github.com/dgolbourn/eiko/blob/main/res/schemas/user_login_request.json user_login_request]]
    Client --> Authenticator : TLS handshake
    Client -> Authenticator : [[https://github.com/dgolbourn/eiko/blob/main/res/schemas/authenticator_login_request.json authenticator_login_request]]
    Authenticator -> Client : [[https://github.com/dgolbourn/eiko/blob/main/res/schemas/authenticator_login_response.json authenticator_login_response]]
    Client <-- Authenticator : TLS connection closed
    Client -> User : [[https://github.com/dgolbourn/eiko/blob/main/res/schemas/user_login_response.json user_login_response]]
    @enduml
```

# Connection Sequence

The User makes a request to its Client to connect to a Server. The Client initiates a TLS handshake. Once complete, the Server responds with a server authentication token, asking the User to get the Authentication service to sign it on the User's behalf. The Client then gets the token signed by the Authentication service and returns it to the Server. The Server then takes this signed token to the Authentication service to verify it. On success, the Authentication service tells the Server the name and UUID of the User. The Server then sends to the Client a traffic key for decrypting inbound UDP traffic, and encrypting outbound UDP traffic. In order for the Server to identify the UDP address of the Client, it also sends an identification token. The client encrypts this and sends it back via UDP. The server listens for incoming UDP traffic from unknown peers, when it receives such traffic, it tries to decrypt it and if successful this identifies the User. The User and Server are now considered connected and TCP stream and UDP datagram messages then begin flowing from the Server as the Game sends updates.

```{plantuml}
    @startuml
    !theme mimeograph
    actor User
    User -> Client : [[https://github.com/dgolbourn/eiko/blob/main/res/schemas/user_connection_request.json user_connection_request]]
    Client --> Server : TLS handshake
    Server -> Client : [[https://github.com/dgolbourn/eiko/blob/main/res/schemas/server_authentication_request.json server_authentication_request]]
    Client --> Authenticator : TLS handshake
    Client -> Authenticator : [[https://github.com/dgolbourn/eiko/blob/main/res/schemas/authenticator_authorise_request.json authenticator_authorise_request]]
    Authenticator -> Client : [[https://github.com/dgolbourn/eiko/blob/main/res/schemas/authenticator_authorise_response.json authenticator_authorise_response]]
    Client <-- Authenticator : TLS connection closed
    Client -> Server : [[https://github.com/dgolbourn/eiko/blob/main/res/schemas/server_authentication_response.json server_authentication_response]]
    Server --> Authenticator : TLS handshake
    Server -> Authenticator : [[https://github.com/dgolbourn/eiko/blob/main/res/schemas/authenticator_verify_request.json authenticator_verify_request]]
    Authenticator -> Server : [[https://github.com/dgolbourn/eiko/blob/main/res/schemas/authenticator_verify_response.json authenticator_verify_response]]
    Server <-- Authenticator : TLS connection closed
    Server -> Client : [[https://github.com/dgolbourn/eiko/blob/main/res/schemas/server_stream_authentication_request.json server_stream_authentication_request]]
    Client -> Server : [[https://github.com/dgolbourn/eiko/blob/main/res/schemas/server_stream_authentication_response.json server_stream_authentication_response]]
    @enduml
```
