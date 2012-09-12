use strict;
use warnings;
use Test::More;

use Test::Wight;

subtest "SPAWN_PSGI_METHOD - $_" => sub {
    local $Test::Wight::SPAWN_PSGI_METHOD = $_;

    my $wight = Test::Wight->new;

    my $app = sub {
        return [ 200, [ 'Content-Type' => 'text/html' ], [ <<HTML ] ];
<html>
  <head>
    <title>01_simple</title>
    <script type="text/javascript">
function show (id) {
    var elem = document.getElementById(id);
    elem.style.display = 'block';
}
    </script>
  </head>
  <body>
    <p><a href="/foo">foo</a></p>
    <p><span onclick="setTimeout(function () { show('hidden') }, 1500)">erase element</span></p>
    <p id="hidden" style="display: none">hello</p>
  </body>
</html>
HTML
    };

    my $port = $wight->spawn_psgi($app);

    $wight->handshake;

    $wight->visit("http://localhost:$port/");
    is $wight->evaluate('document.title'), '01_simple';

    isa_ok my $link = $wight->find('//p/a'), 'Wight::Node';
    is $link->text, 'foo';

    $link->click;
    is $wight->current_url, "http://localhost:$port/foo";

    my $hidden = $wight->find(q<id('hidden')>);
    ok !$hidden->is_visible;
    is $hidden->attribute('id'), 'hidden';

    $wight->find('//span[@onclick]')->click;
    ok $wight->wait_until(sub { $hidden->is_visible });
}
foreach 'fork', 'twiggy';

done_testing;
