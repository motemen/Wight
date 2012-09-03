use strict;
use warnings;
use Test::More;
use Wight;

unless ($ENV{TEST_LIVE}) {
    plan skip_all => 'TEST_LIVE not set';
}

my $wight = Wight->new;
$wight->handshake;

pass 'handshaked';

$wight->visit('http://motemen.github.com/');

pass 'got motemen.github.com';

ok my $link = $wight->find('//a'), 'link found';

done_testing;
