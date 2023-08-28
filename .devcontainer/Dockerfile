FROM mcr.microsoft.com/devcontainers/base:ubuntu
RUN mkdir -p /app/scripts
WORKDIR /app
COPY ./scripts/* ./scripts/
RUN ./scripts/install_lua.sh
