package Http::Utils;
use strict;
use warnings FATAL => 'all';

use Socket;

use base qw(Exporter);
our @EXPORT = qw(
    %ALLOWED_METHODS
    @mime_types
    $default_mime_type
    is_method_allowed
    parse_http_request_from
    get_mimetype
    parse_get_url
    parse_config_file
    );
our $VERSION = '0.0.1';

our @mime_types = (
    [ qr/\.htm(l)?$/ => 'text/html'                     ],
    [ qr/\.txt$/     => 'text/plain'                    ],
    [ qr/\.css$/     => 'text/css'                      ],
    [ qr/\.js$/      => 'application/javascript'        ],
    [ qr/\.gif$/     => 'image/gif'                     ],
    [ qr/\.jp(e)?g$/ => 'image/jpeg'                    ],
    [ qr/\.png$/     => 'image/png'                     ],
    [ qr/\.swf$/     => 'application/x-shockwave-flash' ],
);
our %ALLOWED_METHODS = (
    'GET'  => 1,
    'HEAD' => 1,
);
our $default_mime_type = 'application/binary';

sub parse_http_request_from {
    my ($client) = @_;
    my %request = ();

    local $/ = Socket::CRLF;
    while (<$client>) {
        chomp;
        if (/\s*(\w+)\s*([^\s]+)\s*HTTP\/(\d.\d)/) {
            # Main http request
            $request{METHOD} = uc $1;
            $request{URL} = $2;
            $request{HTTP_VERSION} = $3;
        } elsif (/:/) {
            # Standard headers
            (my $type, my $val) = split /:/, $_, 2;
            #$type =~ s/^\s+//;
            foreach ($type, $val) {
                s/^\s+//;
                s/\s+$//;
            }
            $request{lc $type} = $val;
        } elsif (/^$/) {
            # POST data
            read($client, $request{CONTENT}, $request{'content-length'})
                if defined $request{'content-length'};
            last;
        }
    }

    return ($request{URL} and $request{METHOD} and \%request);
}

sub get_mimetype {
    my ($path) = @_;

    for my $type (@mime_types) {
        if ($path =~ $type->[0]) {
            return $type->[1];
        }
    }

    return $default_mime_type;
}

sub is_method_allowed {
    exists $ALLOWED_METHODS{$_[0]};
}

sub parse_get_url {
    my $url = $_[0];
    my %data;
    foreach (split /&/, $url) {
        my ($key, $val) = split /=/;
        $val =~ s/\+/ /g;
        $val =~ s/%(..)/chr(hex($1))/eg;
        $data{$key} = $val;
    }
    return %data;
}

sub parse_config_file {
    my ($config) = @_;
    my %opts;
    while (<$config>) {
        s/#.*//; chomp;
        my ($key, $value) = split / /;
        $opts{$key} = $value if $key and $value;
    }
    return \%opts;
}

1;