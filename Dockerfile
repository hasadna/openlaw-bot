FROM ubuntu:xenial

LABEL org.opencontainers.image.source="https://git.org.il/resource-il/openlaw-bot"
LABEL org.opencontainers.image.authors="Yehuda Deutsch <yeh@uda.co.il>, Zvi Devir"

WORKDIR /code

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
    && cpanm --notest \
        MediaWiki::Bot \
	MediaWiki::Bot::Plugin::Admin \
    && apt-get clean \
    && rm -Rf /var/lib/apt/lists/* \
    && useradd -m -s /bin/bash resource \
    && chown -R resource:resource /code

USER resource
COPY --chown=resource:resource *.pl *.pm LICENSE /code/
