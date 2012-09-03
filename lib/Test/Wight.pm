package Test::Wight;
use strict;
use warnings;
use parent 'Wight';

use Test::Builder;
use URI;
use Carp;

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

sub visit {
    my ($self, $url) = @_;
    return $self->SUPER::visit(URI->new_abs($url, $self->base_url)->as_string);
}

sub _build_base_url {
    my $self = shift;

    croak q('psgi_port' not set) unless defined $self->psgi_port;

    my $url = URI->new('http://localhost/');
       $url->port($self->psgi_port);
    return $url;
}

1;
