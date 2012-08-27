package Test::Wight;
use strict;
use warnings;
use parent 'Wight';

use Test::Builder;

sub test { Test::Builder->new }

sub test_tcp {
    my ($self, $cb) = @_;
    my $test_tcp = Test::TCP->new(
        code => $cb,
    );
    $self->{test_tcp}->{ $test_tcp->port } = $test_tcp; # keep reference
    return $test_tcp->port;
}

sub spawn_psgi {
    my ($self, $app, %options) = @_;

    my $port = $self->test_tcp(
        sub {
            my $port = shift;

            require Plack::Runner;
            my $runner = Plack::Runner->new(app => $app);
            $runner->parse_options('--port' => $port, '--env' => 'test');
            $runner->set_options(%options);
            $runner->run;
        }
    );

    $self->{psgi_port} ||= $port;

    return $port;
}

1;
