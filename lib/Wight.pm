package Wight;
use strict;
use warnings;
use 5.008_001;
use Wight::Node;

use Test::TCP qw(empty_port);

use Coro;
use Coro::AnyEvent;
use AnyEvent;
use AnyEvent::Socket;
use AnyEvent::Handle;
use AnyEvent::Util;
use Twiggy::Server;
use Plack::Request;

use Protocol::WebSocket::Handshake::Server;
use Protocol::WebSocket::Frame;
use JSON::XS;

use File::Basename qw(dirname);
use File::Spec::Functions qw(catfile updir);
use File::ShareDir qw(dist_file);

use URI;

use Carp;
use Sub::Name;
use Scalar::Util qw(blessed);

use Class::Accessor::Lite::Lazy (
    rw => [
        'psgi_port',
        'client_cv',
        'phantomjs',
        'on_confirm',
        'on_prompt',
    ],
    ro => [
        'handle',
        'ws_handshake',
        'ws_port',
    ],
    rw_lazy => [
        'cookie_jar',
        'base_url',
    ],
);

our $VERSION = '0.01';

our @METHODS = qw(
    execute evaluate render
    body source reset resize push_frame pop_frame
);
# within_frame

our @CARP_NOT = 'Wight::Node';

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

sub phantomjs_args {
    my $self = shift;
    if (@_) {
        $self->{phantomjs_args} = [ @_ ];
    }
    return @{ $self->{phantomjs_args} || [] };
}

sub new {
    my ($class, %args) = @_;

    $args{ws_port} ||= empty_port();

    my $autorun = exists $args{autorun} ? delete $args{autorun} : 1;
    my $cookie  = delete $args{cookie};

    my $self = bless \%args, $class;
    $self->cookie_jar if $cookie; # build
    $self->handshake if $autorun;

    return $self;
}

sub _psgi_app {
    my $self = shift;

    return sub {
        my $env = shift;
        my $req = Plack::Request->new($env);

        if ($req->header('Connection') eq 'Upgrade'
                && $req->header('Upgrade') eq 'WebSocket') {

            $self->{ws_handshake}
                = Protocol::WebSocket::Handshake::Server->new_from_psgi($env);

            my $frame = $self->_new_ws_frame;

            my $fh = $env->{'psgix.io'};
            $self->{handle} = AnyEvent::Handle->new(
                fh => $fh,
                on_read => sub {
                    $frame->append($_[0]->rbuf);
                    while (my $message = $frame->next) {
                        my $data = JSON::XS->new->decode($message);
                        $self->debug('message in:', $data);
                        if (my $error = $data->{error}) {
                            if (ref $error eq 'HASH') {
                                $error = Wight::Exception->new(
                                    name => $error->{name},
                                    args => $error->{args},
                                );
                            }
                            if ($self->client_cv) {
                                $self->client_cv->croak($error);
                            }
                            # $self->{handle}->destroy;
                            # return;
                        }
                        $self->client_cv->send($data) if $self->client_cv;
                    }
                },
                on_error => sub {
                    my ($handle, $fatal, $msg) = @_;
                    $handle->destroy;
                    if ($self->client_cv) {
                        $self->client_cv->croak($msg);
                    }
                },
                on_eof => sub {
                    my ($handle) = @_;
                    $handle->destroy;
                    if ($self->client_cv) {
                        $self->client_cv->croak(Wight::Exception->eof);
                    }
                }
            );

            $self->ws_handshake->parse($fh) or do {
                warn $self->ws_handshake->error;
                return [ 400, [], [ $self->ws_handshake->error ] ];
            };

            return sub {
                my $respond = shift;
                $self->handle->push_write($self->ws_handshake->to_string);
            };
        } elsif (my ($action) = $req->path_info =~ m<^/(confirm|prompt)$>) {
            my $args = eval { decode_json($req->parameters->{args}) } || [];
            my $response = ( $self->{"on_$action"} || sub { return undef } )->($self, @$args);
            $response = $response ? \1 : \0 if $action eq 'confirm'; # force to boolean
            return [
                200, [
                    'Access-Control-Allow-Origin' => '*',
                    'Content-Type' => 'application/json; charset=utf-8',
                ],
                [ encode_json +{ response => $response } ],
            ];
        } else {
            return [ 501, [] , [] ];
        }
    };
}

sub run {
    my $self = shift;

#   $self->{tcp_server_guard} ||= tcp_server
#       undef, $self->ws_port, $self->_tcp_server_cb;

    return if $self->{twiggy};

    $self->{twiggy} = Twiggy::Server->new(
        port => $self->ws_port
    );
    $self->{twiggy}->register_service($self->_psgi_app);

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
        $self->{cookies_file} = $fh->filename;
    }

    my $cmd = $self->phantomjs || 'phantomjs';
    $self->{phantomjs_cv} = run_cmd [
        $cmd,
        '--disk-cache=yes',
#       '--load-images=no',
        $self->phantomjs_args,
        $self->{cookies_file} ? "--cookies-file=$self->{cookies_file}" : (),
        $self->script_file,
        $self->ws_port,
    ], '$$' => \$self->{phantomjs_pid};
    $self->{phantomjs_cv}->cb(sub {
        my $return = $_[0]->recv;
        die "$0: $cmd: Exited with value @{[$return >> 8]}\n" if $return;
    });
}

sub reload_cookie_jar {
    my $self = shift;
    my $file = $self->{cookies_file} or return undef;

    open my $fh, '<', $file or die $!;

    require HTTP::Cookies;
    my $jar = HTTP::Cookies->new;

    my $domain;
    while (<$fh>) {
        chomp;
        if (/^\[(.+)\]$/) {
            $domain = $1;
        } elsif (/^([^=]+?)=(.+)$/) {
            my ($key, $value) = ($1, $2);
            $value =~ s/^"(.+)"$/$1/;

            next unless $domain;
            $jar->set_cookie(
                '0',
                $key,
                $value,
                '/',
                $domain,
            );
        }
    }

    return $self->{cookie_jar} = $jar;
}

*walk = \&run;

sub _new_ws_frame {
    my ($self, $buffer) = @_;
    my $ws = $self->ws_handshake or croak "\$wight->handshake is not invoked?";
    return Protocol::WebSocket::Frame->new(
        version => $ws->version,
        buffer  => $buffer,
    );
}

sub handshake {
    my $self = shift;
    $self->run;
    $self->wait_until(sub { $self->ws_handshake && $self->ws_handshake->is_done });
}

sub _tcp_server_cb {
    my $self = shift;
    return sub {
        my $sock = shift;
        $self->{handle} = AnyEvent::Handle->new(
            fh => $sock,
            on_read => $self->_on_read_cb,
            on_error => sub {
                my ($handle, $fatal, $msg) = @_;
                $handle->destroy;
                if ($self->client_cv) {
                    $self->client_cv->croak($msg);
                }
            },
            on_eof => sub {
                my ($handle) = @_;
                $handle->destroy;
                if ($self->client_cv) {
                    $self->client_cv->croak(Wight::Exception->eof);
                }
            },
        );
    };
}

sub _on_read_cb {
    my $self = shift;
    my $frame;

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

        $frame ||= $self->_new_ws_frame;
        $frame->append($chunk);

        while (my $message = $frame->next) {
            my $data = JSON::XS->new->decode($message);
            $self->debug('message in:', $data);
            if (my $error = $data->{error}) {
                if ($self->client_cv) {
                    $self->client_cv->croak($error);
                }
                # $self->{handle}->destroy;
                # return;
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

    my $res = eval { $self->client_cv(AE::cv)->recv };

    if (my $e = $@) {
        if (blessed $e && $e->isa('Wight::Exception')) {
            if ($e->is_eof && $self->{exiting}) {
                $self->{twiggy}->{exit_guard}->send;
                undef $self->{twiggy};
                undef $self->{ws_handshake};
                return 1;
            } else {
                croak $e;
            }
        } else {
            croak $e;
        }
    }
    croak $res->{error} unless exists $res->{response};

    return $res->{response};
}

sub debug {
    my $self = shift;
}

sub sleep {
    my ($self, $n) = @_;
    Coro::AnyEvent::sleep($n);
}

sub visit {
    my ($self, $url) = @_;
    return $self->call(visit => $url);
}

sub current_url {
    my $self = shift;
    my $url = $self->call('current_url');
    return URI->new($url);
}

sub exit {
    my $self = shift;
    local $self->{exiting} = 1;
    return $self->call('exit');
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

package
    Wight::Exception;
use strict;
use warnings;
use overload
    '""' => 'stringify',
    fallback => 1;

use Class::Accessor::Lite (
    new => 1,
    ro  => [ 'name', 'message', 'args' ],
);

use constant EXCEPTION_MESSAGE_EOF => 'Unexpected end-of-file';

sub eof {
    my $class = shift;
    return $class->new(message => EXCEPTION_MESSAGE_EOF);
}

sub is_eof {
    my $self = shift;
    return ($self->message || '') eq EXCEPTION_MESSAGE_EOF;
}

sub stringify {
    my $self = shift;
    my $msg = join ': ', grep length $_, ( $self->name, $self->message );
    return "Wight exception $msg";
}

package Wight;

1;

__END__

=head1 NAME

Wight - Communicate with PhantomJS

=head1 SYNOPSIS

  use Wight;

  my $wight = Wight->new;

  $wight->spawn_psgi('app.psgi');

  $wight->visit('/');
  $wight->evaluate('document.title'); # => evaluates JavaScript expression

  $wight->find('//a[@rel="next"]')->click;

=head1 DESCRIPTION

Wight provides methods for operating PhantomJS from Perl,
especially intended to be used testing web application.

For client side scripting, uses L<poltergeist|https://github.com/jonleighton/poltergeist>'s JavaScript.

=head1 BROWSER METHODS

Every method croaks if the operation was failed.

=over 4

=item $wight->visit($path)

Opens a web page.

=item my $result = $wight->evaluate($javascript_expression)

Evaluates a JavaScript expression and returns its result.

=item $wight->execute($javascript_statement)

Executes JavaScript statements.

=item my $node  = $wight->find($xpath)

=item my @nodes = $wight->find($xpath)

Finds a node within current page and returns a (list of) L<Wight::Node>.

=item $wight->render($file)

Renders current page to local file.

=back

=head1 NODE METHODS

Every method croaks if the operation was failed.

=over 4

=item $node->click

=item my $text = $node->text

=item $node->set($value)

=back

=head1 INITIALIZATION METHODS

=over 4

=item my $port = $wight->spawn_psgi($file_or_code)

Forks and runs specified PSGI application.
Sets its C<base_url> to "http://localhost:I<$port>/".

=item $wight->handshake

Starts PhantomJS and waits for communication established.
After this, you can call BROWSER METHODS above.

=item $wight->base_url($url);

=back

=head1 UTILITY METHODS

=over 4

=item $wight->sleep($secs)

=item $wight->wait_until(\&code)

Stops execution until I<code> returns a true value.

=back

=head1 AUTHOR

motemen E<lt>motemen@gmail.comE<gt>

=head1 SEE ALSO

L<poltergeist|https://github.com/jonleighton/poltergeist>

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

For JavaScripts from poltergeist:

Copyright (c) 2011 Jonathan Leighton

Permission is hereby granted, free of charge, to any person obtaining
a copy of this software and associated documentation files (the
"Software"), to deal in the Software without restriction, including
without limitation the rights to use, copy, modify, merge, publish,
distribute, sublicense, and/or sell copies of the Software, and to
permit persons to whom the Software is furnished to do so, subject to
the following conditions:

The above copyright notice and this permission notice shall be
included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

=cut
