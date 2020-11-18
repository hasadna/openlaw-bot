FROM ubuntu:xenial

MAINTAINER Yehuda Deutsch <yeh@uda.co.il>

RUN apt-get update \
    && apt-get install -y \
        # Packages to keep
        poppler-utils \
        libimage-exiftool-perl \
        libmediawiki-api-perl \
        libhtml-treebuilder-xpath-perl \
        libroman-perl \
        # Packages needed for installation
        make \
        cpanminus \
    && cpanm --notest MediaWiki::Bot \
    && apt-get clean \
    && rm -Rf /var/lib/apt/lists/*

WORKDIR /code
COPY * /code/
