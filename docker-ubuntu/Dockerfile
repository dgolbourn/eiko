FROM ubuntu:latest
COPY . /eiko
RUN chmod +x /eiko/docker-ubuntu/install.sh
RUN chmod +x /eiko/docker-ubuntu/run.sh
RUN /eiko/docker-ubuntu/install.sh
ENTRYPOINT ["/eiko/docker-ubuntu/run.sh"]
