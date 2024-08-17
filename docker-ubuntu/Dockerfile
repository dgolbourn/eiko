FROM ubuntu:latest
RUN mkdir /eiko
COPY . /eiko
RUN ls -la /eiko
RUN chmod +x /eiko/docker-ubuntu/install.sh
RUN chmod +x /eiko/docker-ubuntu/run.sh
WORKDIR /eiko
RUN /eiko/docker-ubuntu/install.sh
ENTRYPOINT ["/eiko/docker-ubuntu/run.sh"]
