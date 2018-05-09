FROM perl

MAINTAINER Nikita-Boyarskikh <N02@yandex.ru>

COPY ./requirements.txt /var/www/
WORKDIR /var/www/

RUN cpan install $(cat ./requirements.txt | xargs)

COPY ./bin ./bin
COPY ./lib ./lib

EXPOSE 80

ENTRYPOINT perl bin/main.pl -c etc/httpd.cfg
