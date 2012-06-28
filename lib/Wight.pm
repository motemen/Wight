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

use URI;

use Carp;
use Sub::Name;

use Class::Accessor::Lite::Lazy (
    rw => [
        'psgi_port',
        'client_cv',
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
    body source reset resize push_frame pop_frame exit
);
# within_frame

our @CARP_NOT = 'Wight::Node';

sub _build_cookie_jar {
    require HTTP::Cookies;
    HTTP::Cookies->new;
}

sub _build_base_url {
    my $self = shift;

    croak q('psgi_port' not set) unless defined $self->psgi_port;

    my $url = URI->new('http://localhost/');
       $url->port($self->psgi_port);
    return $url;
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
        $self->phantomjs_args,
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
    croak $self->test->explain($@) if $@;

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

sub visit {
    my ($self, $url) = @_;
    return $self->call(
        visit => URI->new_abs($url, $self->base_url)->as_string
    );
}

sub current_url {
    my $self = shift;
    my $url = $self->call('current_url');
    return URI->new($url);
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

    my $port = $self->{test_tcp}->port;
    $self->{psgi_port} ||= $port;

    return $port;
}

1;

__END__

=head1 NAME

Wight - Communicate with PhantomJS

=head1 SYNOPSIS

  use Wight;

  my $wight = Wight->new;

  $wight->spawn_psgi('app.psgi');
  $wight->handshake;

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
