# HTTP-static-server
Simple http static server

## Start the server
```
$ git clone https://github.com/Nikita-Boyarskikh/HTTP-static-server.git
$ cd HTTP-static-server
$ docker build .
$ docker run -p 80:80 -v $HOME/Desktop/http-test-suite:/var/www/html:ro -v $HOME/Desktop/HTTP-static-server/etc:/var/www/etc:ro  --name http_perl -t http_perl
```
