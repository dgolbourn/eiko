FROM ubuntu:latest
RUN mkdir /eiko
COPY . /eiko
RUN chmod +x /eiko/docker-ubuntu/install.sh
WORKDIR /eiko
RUN /eiko/docker-ubuntu/install.sh
