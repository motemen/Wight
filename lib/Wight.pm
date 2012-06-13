package Wight;
use strict;
use warnings;
use 5.008_001;
use Wight::Node;

use Test::Builder;
use Test::TCP;

use Coro;
use Coro::AnyEvent;
use AnyEvent;
use AnyEvent::Socket;
use AnyEvent::Handle;
use AnyEvent::Util;

use Protocol::WebSocket::Handshake::Server;
use Protocol::WebSocket::Frame;
use JSON::XS;

use File::Basename qw(dirname);
use File::Spec::Functions qw(catfile updir);
use File::ShareDir qw(dist_file);

use Carp;
use Sub::Name;

use Class::Accessor::Lite::Lazy (
    rw => [
        'client_cv',
    ],
    ro => [
        'handle',
        'ws_handshake',
        'ws_port',
    ],
    rw_lazy => [
        'cookie_jar',
    ],
);

our $VERSION = '0.01';

our @METHODS = qw(
    visit execute evaluate current_url render
);
# TODO poltergeist has these methods:
# body, source, value, select_file, tag_name,
# within_frame, drag, select, trigger,
# reset, resize

sub _build_cookie_jar {
    require HTTP::Cookies;
    HTTP::Cookies->new;
}

sub script_file {
    my $file = catfile(
        dirname(__FILE__), updir,
        qw(share main.js),
    );
    return -e $file ? $file : dist_file(__PACKAGE__, 'main.js');
}

sub test { Test::Builder->new }

sub new {
    my ($class, %args) = @_;
    $args{ws_handshake} ||= Protocol::WebSocket::Handshake::Server->new;
    $args{ws_port} ||= empty_port();
    return bless \%args, $class;
}

sub run {
    my $self = shift;

    $self->{tcp_server_guard} = tcp_server
        undef, $self->ws_port, $self->_tcp_server_cb;

    my $cookies_file;
    if (exists $self->{cookie_jar}) {
        require File::Temp;
        my $fh = File::Temp->new(UNLINK => 0);
        my $cookies = {};
        $self->cookie_jar->scan(sub {
            my (undef, $key, $value, undef, $domain) = @_;
            push @{$cookies->{$domain}}, [ $key, $value ];
        });
        while (my ($domain, $pairs) = each %$cookies) {
            print $fh "[$domain]\n";
            foreach my $pair (@$pairs) {
                print $fh "$pair->[0]=$pair->[1]\n";
            }
        }
        close $fh;
        $cookies_file = $fh->filename;
    }

    $self->{phantomjs_cv} = run_cmd [
        'phantomjs',
        '--disk-cache=yes',
        '--load-images=no',
        $cookies_file ? "--cookies-file=$cookies_file" : (),
        $self->script_file,
        $self->ws_port,
    ], '$$' => \$self->{phantomjs_pid};
}

*walk = \&run;

sub _new_ws_frame {
    my ($self, $buffer) = @_;
    return Protocol::WebSocket::Frame->new(
        version => $self->ws_handshake->version,
        buffer  => $buffer,
    );
}

sub handshake {
    my $self = shift;
    $self->run;
    $self->wait_until(sub { $self->ws_handshake->is_done });
}

sub _tcp_server_cb {
    my $self = shift;
    return sub {
        my $sock = shift;
        $self->{handle} = AnyEvent::Handle->new(
            fh => $sock,
            on_read => $self->_on_read_cb,
        );
    };
}

sub _on_read_cb {
    my $self = shift;

    return unblock_sub {
        my $handle = shift;

        my $chunk = $handle->rbuf;
        undef $handle->{rbuf};

        my $handshake = $self->ws_handshake;
        if (not $handshake->is_done) {
            $handshake->parse($chunk);

            if ($handshake->is_done) {
                $handle->push_write($handshake->to_string);
                $self->debug('WebSocket handshaked');
                cede;
                return;
            }
        }

        my $frame = $self->_new_ws_frame;

        $frame->append($chunk);

        while (my $message = $frame->next) {
            my $data = JSON::XS->new->decode($message);
            $self->debug('message in:', $data);
            if (my $error = $data->{error}) {
                $self->test->diag("error: $error->{name}");
                $self->test->diag(
                    $self->test->explain($error->{args})
                );
                exit 1;
            }
            $self->client_cv->send($data) if $self->client_cv;
        }
    };
}

sub call {
    my ($self, $method, @args) = @_;

    my $message = { name => $method, args => \@args };

    $self->debug('message out:', $message);

    my $frame = $self->_new_ws_frame(encode_json $message);
    $self->handle->push_write($frame->to_bytes);

    my $res = $self->client_cv(AE::cv)->recv;

    unless (exists $res->{response}) {
        croak $self->test->explain($res->{error});
    }

    return $res->{response};
}

sub debug {
    my $self = shift;
}

sub sleep {
    my ($self, $n) = @_;
    Coro::AnyEvent::sleep($n);
}

foreach my $method (@METHODS) {
    my $code = sub {
        my ($self, @args) = @_;
        return $self->call($method => @args);
    };
    no strict 'refs';
    *$method = subname $method, $code;
}

sub find {
    my ($self, $selector) = @_;
    my $result = $self->call(find => $selector);
    my $ids = $result->{ids};
    return unless $ids && @$ids;

    my @nodes = map {
        Wight::Node->new(
            wight => $self,
            page_id => $result->{page_id},
            id => $_,
        );
    } @$ids;
    return wantarray ? @nodes : $nodes[0];
}

sub wait_until {
    my ($self, $code) = @_;
    my $result;
    $self->sleep(0.5) until $result = $code->();
    return $result;
}

sub spawn_psgi {
    my ($self, $app, %options) = @_;

    require Plack::Runner;

    $self->{test_tcp} = Test::TCP->new(
        code => sub {
            my $port = shift;

            my $runner = Plack::Runner->new(app => $app);
            $runner->parse_options('--port' => $port, '--env' => 'test');
            $runner->set_options(%options);
            $runner->run;
        }
    );

    return $self->{test_tcp}->port;
}

1;

__END__

=head1 NAME

Wight - 

=head1 SYNOPSIS

  use Wight;

=head1 DESCRIPTION

=head1 AUTHOR

motemen E<lt>motemen@gmail.comE<gt>

=head1 SEE ALSO

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
