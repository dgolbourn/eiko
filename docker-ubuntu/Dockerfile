FROM ubuntu:latest
COPY . /eiko
RUN useradd -m -d /home/eiko eiko
RUN chown eiko /eiko
USER eiko
WORKDIR /eiko
RUN /eiko/docker-ubuntu/install.sh
WORKDIR /home/eiko
ENTRYPOINT ["/eiko/docker-ubuntu/run.sh"]
