use strict;
use warnings;
use Test::More;
use Wight;

my $wight = Wight->new;
$wight->handshake;

is $wight->evaluate('1 + 1'), 2;

$wight->exit;
$wight->handshake;

is $wight->evaluate('1 + 1'), 2;

done_testing;
