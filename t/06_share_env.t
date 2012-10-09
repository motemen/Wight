use strict;
use warnings;
use Test::More;
use Test::Wight;

$Test::Wight::SPAWN_PSGI_METHOD = 'twiggy';

my $wight = Test::Wight->new;

my $env;
my $app = sub { $env = $_[0]; [ 200, [], [] ] };

$wight->spawn_psgi($app);
$wight->visit('/hoge');

is $env->{PATH_INFO}, '/hoge';

done_testing;
