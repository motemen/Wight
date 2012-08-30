use strict;
use warnings;
use Test::More;
use Plack::Request;

use Test::Wight;

my $wight = Test::Wight->new;

my $app = sub {
    my $req = Plack::Request->new($_[0]);
    my $body = '1234567890' x ($req->parameters->{n} || 1);
    return [ 200, [ 'Content-Type' => 'text/html' ], [ <<HTML ] ];
<html>
  <head>
    <title>bug_large_html</title>
  </head>
  <body>$body</body>
</html>
HTML
};

my $port = $wight->spawn_psgi($app);

$wight->handshake;

$wight->visit("http://localhost:$port/");
is $wight->evaluate('document.body.innerHTML.replace(/\s+$/, "")'), '1234567890', '10 bytes';

$wight->visit("http://localhost:$port/?n=196");
is $wight->evaluate('document.body.innerHTML.replace(/\s+$/, "")'), '1234567890' x 196, '1960 bytes';

$wight->visit("http://localhost:$port/?n=1000");
is $wight->evaluate('document.body.innerHTML.replace(/\s+$/, "")'), '1234567890' x 1000 , '10000 bytes';

done_testing;
