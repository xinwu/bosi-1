FROM ubuntu:14.04
MAINTAINER Aditya Vaja <aditya.vaja@bigswitch.com>

RUN apt-get update
RUN apt-get upgrade -y --no-install-recommends
RUN apt-get install -y --no-install-recommends \
    build-essential \
    git \
    python \
    python-dev \
    python-pip
RUN pip install twine
