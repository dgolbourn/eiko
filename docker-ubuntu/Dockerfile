FROM ubuntu:latest

COPY ../.devcontainer/scripts/install_lua.sh /tmp/scripts/install_lua.sh
RUN /tmp/scripts/install_lua.sh

COPY ../.devcontainer/scripts/packages.txt /tmp/scripts/packages.txt
RUN xargs sudo apt install -y < /tmp/scripts/packages.txt

RUN luarocks make --local --server rocks
