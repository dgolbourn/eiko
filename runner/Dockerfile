FROM mcr.microsoft.com/devcontainers/base:ubuntu
WORKDIR /app

RUN useradd -m docker
USER docker

COPY .devcontainer/ devcontainer
RUN chmod +x devcontainer/scripts/install_lua.sh
RUN devcontainer/scripts/install_lua.sh

COPY runner/ runner
RUN chmod +x runner/scripts/install.sh
RUN runner/scripts/install.sh

RUN chown -R docker ./actions-runner


ENTRYPOINT ["./scripts/start.sh"]
