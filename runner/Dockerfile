FROM mcr.microsoft.com/devcontainers/base:ubuntu
WORKDIR /app

COPY .devcontainer/ devcontainer
RUN chmod +x devcontainer/scripts/install_lua.sh
RUN devcontainer/scripts/install_lua.sh

RUN ls
COPY runner/ runner
RUN ls runner/
RUN ls runner/scripts
RUN chmod +x runner/scripts/install_runner.sh
RUN runner/scripts/install_runner.sh

RUN useradd -m docker
RUN chown -R docker ./actions-runner
USER docker

ENTRYPOINT ["./scripts/start.sh"]
