package Http::Static::Server;
use strict;
use warnings FATAL => 'all';

our $VERSION = '0.0.1';

use Mouse;
use IO::Socket::INET;
use IO::File;
use IO::Async::Loop;
use IO::Async::Handle;
use File::Spec::Functions qw(catfile);
use Cwd;
use URI::Escape qw(uri_unescape);
use HTTP::Date qw(time2str);

use FindBin;
use lib "$FindBin::Bin/../lib";

use Http::Utils qw(
    parse_get_url
    get_mimetype
    is_method_allowed
    parse_http_request_from);

has 'server_name',   is => 'rw', required => 1;
has 'document_root', is => 'rw', required => 1;
has 'index',         is => 'rw', default => 'index.html', required => 1;

has 'port',          is => 'rw', default => 80, required => 1;
has 'host',          is => 'rw', default => '0.0.0.0', required => 1;
has 'cpu_limit',     is => 'rw', default => 4, required => 1;
has 'thread_limit',  is => 'rw', default => 128, required => 1;
has 'proto',         is => 'rw', default => 'tcp', required => 1;
has 'autoflush',     is => 'rw', default => 1, required => 1;

has 'timeout',       is => 'rw';
has 'conn_state',    is => 'rw', default => 'Keep-Alive', required => 1;

has 'server',        is => 'rw';
has 'buffer_size',   is => 'rw', default => 128;
has 'loop',          is => 'rw', default => sub { IO::Async::Loop->new };
has 'log_fh',        is => 'rw', default => sub { \*STDOUT };

$IO::Async::Loop::LOOP = 'EV,Epoll,Poll';

sub BUILD {
    my $self = shift;

    my $server = IO::Socket::INET->new(
        LocalHost => $self->host,
        LocalPort => $self->port,
        Proto     => $self->proto,
        Listen    => $self->thread_limit * $self->cpu_limit,
        Timeout   => $self->timeout,
        ReuseAddr => 1,
        Blocking  => 0,
    ) or die("Can't bind to '${\$self->host}:${\$self->port}': $!\n");
    $self->server($server);

    my $socket = IO::Async::Handle->new(
        handle => $self->server,
        on_read_ready => sub {
            my $client = $self->server->accept;
            $client->autoflush(1);
            $self->_subscribe_quit_events('INT', 'TERM', 'QUIT', 'HUP');
            $self->log('New connection from: ' . $client->peerhost . ':' . $client->peerport);
            $self->serve_static($client);
        },
        on_write_ready => sub {},
    );
    $self->loop->add($socket);
}

sub _print_403 {
    my ($self, $client) = @_;
    print $client 'HTTP/1.1 403 Permission Denied' . Socket::CRLF;
    $self->print_headers($client);
    print $client Socket::CRLF;
}

sub _print_404 {
    my ($self, $client) = @_;
    print $client 'HTTP/1.1 404 Not Found' . Socket::CRLF;
    $self->print_headers($client);
    print $client Socket::CRLF;
}

sub _print_405 {
    my ($self, $client) = @_;
    print $client 'HTTP/1.1 405 Method Not Allowed' . Socket::CRLF;
    $self->print_headers($client);
    print $client Socket::CRLF;
}

sub _print_200 {
    my ($self, $client, $realpath) = @_;

    my $content_length = -s $realpath;
    my $mimetype = get_mimetype($realpath);

    print $client 'HTTP/1.1 200 OK' . Socket::CRLF;
    $self->print_headers($client);
    print $client 'Content-Type: ' . $mimetype . Socket::CRLF;
    print $client 'Content-Length: ' . $content_length . Socket::CRLF;
    print $client Socket::CRLF;
}

sub _subscribe_quit_events {
    my $self = shift;
    foreach my $sig (@_) {
        $self->loop->attach_signal(
             $sig, sub {
                $self->loop->stop;
            }
        );
    }
}

sub run {
    my ($self) = @_;

    $self->_subscribe_quit_events('INT', 'TERM', 'QUIT', 'HUP');
    $self->log(sprintf "Server listening on %s:%s", $self->host, $self->port);
    $self->loop->run;
}

sub stop {
    my ($self) = @_;
    $self->log('Server stopping...');
    $self->loop->stop;
}

sub serve_static {
    my ($self, $client) = @_;
    my $base = $self->document_root // q{.};
    my $realbase = Cwd::realpath($base) or die 'Wrong base dir: ' . $base;
    my $request = parse_http_request_from($client) or return 0;

    unless (is_method_allowed($request->{METHOD})) {
        $self->_print_405($client);
        $self->log($request->{METHOD}, $request->{URL}, '-> 405');
        return 0;
    }

    my $path = $request->{URL};
    $path =~ s{^https?://([^/:]+)(:\d+)?/}{/};
    ($path) = split /\?/, $path;
    $path = URI::Escape::uri_unescape($path);
    if (substr($path, -1) eq '/') {
        $path .= $self->index;
    }
    my @parts = split q{/+}, $path;
    my $fullpath = catfile( $realbase, @parts );

    if (not -f $fullpath and -d catfile($realbase, split q{/+}, $request->{URL})) {
        $self->_print_403($client);
        $self->log($request->{METHOD}, $request->{URL}, '-> 403 (', $fullpath // $path, ')');
        return 0;
    }

    my $realpath = Cwd::realpath($fullpath);
    unless ($realpath and -f $realpath and $realpath =~ m/^\Q$realbase\E/) {
        $self->_print_404($client);
        $self->log($request->{METHOD}, $request->{URL}, '-> 404 (', $fullpath // $path, ')');
        return 0;
    }

    my $fh = IO::File->new();
    $fh->open($realpath) or die $!;
    binmode $fh;
    binmode $self->server;
    $self->_print_200($client, $realpath);
    if ($request->{METHOD} ne 'HEAD') {
        my $buffer;
        while (read($fh, $buffer, $self->buffer_size)) {
            print $client $buffer;
        }
    }
    $self->log($request->{METHOD}, $request->{URL}, "-> 200 ($realpath)");
    return 1;
}

sub log {
    my $self = shift;
    my $handler = $self->log_fh;
    print $handler join(' ', @_) . "\n" if $handler;
}

sub print_headers {
    my ($self, $fh) = @_;

    my $date = time2str(time);
    print  $fh 'Date: ' . $date . Socket::CRLF;
    print  $fh 'Connection: ' . $self->conn_state . Socket::CRLF;
    printf $fh 'Server: %s(%s) (%s)' . Socket::CRLF, $self->server_name, $VERSION, $^O;
}

1;