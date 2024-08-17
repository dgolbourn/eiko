FROM ubuntu:latest
COPY . /eiko
RUN useradd -m -d /home/eiko eiko
RUN usermod -aG sudo eiko
RUN echo '%sudo ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers
RUN chown -R eiko /eiko
RUN chmod +x /eiko/docker-ubuntu/install.sh
RUN chmod +x /eiko/docker-ubuntu/run.sh
USER eiko
WORKDIR /eiko
RUN /eiko/docker-ubuntu/install.sh
WORKDIR /home/eiko
ENTRYPOINT ["/eiko/docker-ubuntu/run.sh"]
