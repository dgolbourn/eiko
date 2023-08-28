FROM mcr.microsoft.com/devcontainers/base:ubuntu
RUN mkdir -p /app/scripts
COPY ./scripts/* /app/scripts/
RUN app/scripts/install_lua.sh
