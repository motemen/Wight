use strict;
use warnings;
use Test::More;
use Test::Fatal;

use Test::Wight;

my $app = sub {
    return [ 200, [ 'Content-Type' => 'text/html' ], [ <<HTML ] ];
<html>
  <head>
    <title></title>
  </head>
  <body>
    <p><button id="button-exception" onclick="throw 'exception'">throw</button></p>
    <p><button id="button-hidden" style="display: none">hidden</button></p>
  </body>
</html>
HTML
};

my $wight = Test::Wight->new;
my $port = $wight->spawn_psgi($app);

$wight->handshake;

$wight->visit("http://localhost:$port/");

my $e1 = exception {
    $wight->find('id("button-hidden")')->click;
};
ok $e1, 'exception: hidden button click';
note explain $e1;

my $e2 = exception {
    $wight->find('id("button-exception")')->click;
};
ok $e2, 'exception: caught exception';
note explain $e2;

done_testing;
