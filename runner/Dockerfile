FROM mcr.microsoft.com/devcontainers/base:ubuntu
RUN mkdir -p /app/scripts
WORKDIR /app

COPY ../.devcontainer/scripts/* ./scripts/
RUN chmod +x ./scripts/install_lua.sh
RUN ./scripts/install_lua.sh

COPY ../runner/scripts/* ./scripts/
RUN chmod +x ./scripts/install_runner.sh
RUN ./scripts/install_runner.sh

RUN useradd -m docker
RUN chown -R docker ./actions-runner
USER docker

ENTRYPOINT ["./scripts/start.sh"]
