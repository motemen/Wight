use strict;
use warnings;
use Test::More;
use Wight;

unless ($ENV{TEST_LIVE}) {
    plan skip_all => 'TEST_LIVE not set';
}

my $wight = Wight->new;

pass 'handshaked';

$wight->visit('http://motemen.github.com/');

pass 'got motemen.github.com';

ok my $link = $wight->find('//a'), 'link found';

$wight->exit;

pass 'exited';

done_testing;
