#!/usr/bin/env perl

use strict;
use warnings FATAL => 'all';

use Getopt::Long::Any;
use Pod::Usage;

use FindBin;
use lib "$FindBin::Bin/../lib";

use Http::Static::Server;
use Http::Utils qw(parse_config_file);

sub main() {
    my $opts = parse_opts();
    my $static_server = Http::Static::Server->new(
        port          => $opts->{listen},
        host          => $opts->{host},
        proto         => $opts->{proto},
        server_name   => $opts->{server_name},
        document_root => $opts->{document_root},
        index         => $opts->{index},
        timeout       => $opts->{timeout},
        cpu_limit     => $opts->{cpu_limit},
        thread_limit  => $opts->{thread_limit},
        buffer_size   => $opts->{buffer_size},
        log_fh        => $opts->{log},
    );

    $static_server->run;
    $static_server->stop;
}

sub parse_opts {
    my $man = 0;
    my $help = 0;
    my %opts = (
        listen      => 80,
        host        => '0.0.0.0',
        proto       => 'tcp',
        buffer_size => 128,
        index       => 'index.html',
    );

    GetOptions(
        'listen|l=i'       => \$opts{listen},
        'host=s'           => \$opts{host},
        'proto|p=s'        => \$opts{proto},
        'server_name|n=s'  => \$opts{server_name},
        'root|r=s'         => \$opts{document_root},
        'index'            => \$opts{index},
        'timeout|t=i'      => \$opts{timeout},
        'cpu_limit=i'      => \$opts{cpu_limit},
        'thread_limit=i'   => \$opts{thread_limit},
        'buffet_size=i'    => \$opts{buffer_size},
        'log=s'            => \$opts{log},
        'config|c=s'       => \$opts{config},
        'help|h'           => \$help,
        'man'              => \$man,
    ) and @ARGV == 0 or pod2usage(2);
    pod2usage(-exitval => 0) if $help;
    pod2usage(-exitval => 0, -verbose => 2) if $man;

    if ($opts{config}) {
        open(my $config_fh, '<', $opts{config}) or die "Can't open to read config file: $!";
        %opts = (%opts, %{parse_config_file($config_fh)});
    }

    my %log_name_to_handler = (
        stdout => \*STDOUT,
        stderr => \*STDERR,
    );
    if ($opts{log}) {
        my $log = $log_name_to_handler{$opts{log}};
        if ($log) {
            $opts{log} = $log;
        } else {
            open(my $log_fh, '>>', $opts{log}) or die "Can't open to append log file: $!";
            $opts{log} = $log_fh;
        }
    }

    return \%opts;
}

main();

__END__

=pod

=cut