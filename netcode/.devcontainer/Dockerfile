FROM mcr.microsoft.com/devcontainers/base:ubuntu

COPY scripts/install_lua.sh /tmp/scripts/install_lua.sh
RUN /tmp/scripts/install_lua.sh

COPY scripts/packages.txt /tmp/scripts/packages.txt
RUN xargs sudo apt install -y < /tmp/scripts/packages.txt
