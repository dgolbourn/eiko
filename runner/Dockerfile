FROM mcr.microsoft.com/devcontainers/base:ubuntu
RUN mkdir -p /app/scripts
WORKDIR /app

COPY ../.devcontainer/scripts/* ./scripts/
RUN ./scripts/install_lua.sh

COPY ./scripts/* ./scripts/
RUN ./scripts/install_runner.sh

ENTRYPOINT ["./scripts/start.sh"]
