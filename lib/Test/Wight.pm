package Test::Wight;
use strict;
use warnings;
use parent 'Wight';

use Test::Builder;
use Test::TCP qw(empty_port);
use URI;
use Carp;
use Plack::Runner;

sub test { Test::Builder->new }

sub test_tcp {
    my ($self, $cb) = @_;
    my $test_tcp = Test::TCP->new(
        code => $cb,
    );
    $self->{test_tcp}->{ $test_tcp->port } = $test_tcp; # keep reference
    return $test_tcp->port;
}

our $SPAWN_PSGI_METHOD = 'fork';

sub spawn_psgi {
    my $self = shift;
    my $spawn_psgi = "spawn_psgi_$SPAWN_PSGI_METHOD";
    return $self->$spawn_psgi(@_);
}

sub spawn_psgi_fork {
    my ($self, $app, %options) = @_;

    my $port = $self->test_tcp(
        sub {
            my $port = shift;

            my $runner = Plack::Runner->new(app => $app);
            $runner->parse_options('--port' => $port, '--env' => 'test');
            $runner->set_options(%options);
            $runner->run;
        }
    );

    $self->{psgi_port} ||= $port;

    return $port;
}

sub spawn_psgi_twiggy {
    my ($self, $app, %options) = @_;

    require Twiggy::Server;

    my $port = empty_port();

    my $runner = Plack::Runner->new;
    $runner->parse_options('--port' => $port, '--env' => 'test');
    $runner->set_options(%options);

    my $server = Twiggy::Server->new(@{ $runner->{options} });
    $server->register_service($app);

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
