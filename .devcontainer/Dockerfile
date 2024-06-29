FROM mcr.microsoft.com/devcontainers/base:ubuntu
RUN mkdir -p /app/scripts
WORKDIR /app

COPY ./scripts/* ./scripts/
RUN chmod +x ./scripts/install_lua.sh
RUN ./scripts/install_lua.sh
