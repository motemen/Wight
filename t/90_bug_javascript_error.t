use strict;
use warnings;
use utf8;

use Test::More;
use Test::Fatal;
use Test::Wight;

my $html = do { local $/; <DATA> };
my $w = Test::Wight->new;
$w->spawn_psgi(
    sub {
        [ 200, [ 'Content-Length' => length($html) ], [$html] ];
    }
);
my $e = exception { $w->visit() };

pass 'does reach here';

isa_ok $e, 'Wight::Exception';

done_testing;

__DATA__
<!doctype html>
<html>
    <script type="text/javascript">
        unkown_function();
    </script>
</html>
