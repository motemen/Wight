use strict;
use warnings;
use Test::More;

use Test::Wight;
use JSON;
use Plack::Request;

$Test::Wight::SPAWN_PSGI_METHOD = 'twiggy';

my $req;
my $app = sub {
    my $env = shift;
    $req = Plack::Request->new($env);
    return [ 204, [], [] ];
};

my $wight = Test::Wight->new;

$wight->spawn_psgi($app);

$wight->visit('/');

like $req->header('User-Agent'), qr/PhantomJS/;

$wight->set_headers({
    'User-Agent' => 'Wight',
    'X-Test-Wight' => 1,
});

$wight->visit('/');

is $req->header('User-Agent'), 'Wight';
is $req->header('X-Test-Wight'), 1;

done_testing;
