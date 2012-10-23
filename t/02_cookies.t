use strict;
use warnings;
use Test::More;
use Test::Requires qw(
    Plack::Middleware::Session
    Plack::Session
    Plack::Request;
    LWP::Simple
);

use Test::Wight;

BEGIN {
    import LWP::Simple qw($ua);
};

my $app = sub {
    my $env = shift;
    my $req = Plack::Request->new($env);
    my $session = Plack::Session->new($env);
    my $res = $req->new_response(200);
    $res->content($session->id);
    return $res->finalize;
};
$app = Plack::Middleware::Session->new->wrap($app);

my $wight = Test::Wight->new(cookie => 1);

my $port = $wight->spawn_psgi($app);

$wight->visit("http://127.0.0.1:$port/");
my $session_id = $wight->evaluate('document.body.textContent');

$wight->visit("http://127.0.0.1:$port/");
is $wight->evaluate('document.body.textContent'), $session_id;

$ua->cookie_jar($wight->reload_cookie_jar);

my $res = $ua->get("http://127.0.0.1:$port/");
is $res->content, $session_id, 'session inherited';

done_testing;

