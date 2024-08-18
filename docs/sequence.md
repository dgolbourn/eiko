# Authentication Sequence

User authenticates themselves with Authentication service using basic authentication. If successful, receives an **User Authentication Token** to use for further requests this session

```{plantuml}
    @startuml
    User -> Client : [[https://github.com/dgolbourn/eiko/blob/main/res/schemas/user_login_request.json user_login_request]]
    Client --> Authenticator : TLS handshake
    Client -> Authenticator : [[https://github.com/dgolbourn/eiko/blob/main/res/schemas/authenticator_login_request.json authenticator_login_request]]
    Authenticator -> Client : [[https://github.com/dgolbourn/eiko/blob/main/res/schemas/authenticator_login_response.json authenticator_login_response]]
    Client -> User : [[https://github.com/dgolbourn/eiko/blob/main/res/schemas/user_login_response.json user_login_response]]
    @enduml
```

# Connection Sequence

User makes a request to connect to a server. Server responds with an authentication request asking the user to get the Authentication service to sign a server authentication token on the user's behalf. The Client then gets the token signed by the Authentication service and returns it to the server. The Server then takes this signed token to the Authentication service to verify it. On success, the Server sends to the Client a traffic key and a session token to sent back via UDP to establish the encrypted datagram seesion. The Client encrypts the session token with the key and sends it back via UDP. The server listens for incoming UDP traffic from unknown peers, tries to decrypt it and if successful establishes the connection. TCP stream and UDP datagram messages then begin flowing from the Server as the Game sends updates.
