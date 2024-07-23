#!/bin/bash
openssl req -nodes -x509 -newkey rsa:4096 -days 365 -keyout test/ca-key.pem -out test/ca-cert.pem -subj "/C=UK/ST=Hampshire/L=Winchester/O=Testing/OU=Testing/CN=*.golbourn.co.uk/emailAddress=golbourn@gmail.com"
