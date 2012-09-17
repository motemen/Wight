use strict;
use warnings;
use Test::More;

use Test::Wight;

my $wight = Test::Wight->new;

my $app = sub {
    return [ 200, [ 'Content-Type' => 'text/html' ], [ <<HTML ] ];
<html>
  <head>
    <title></title>
  </head>
  <body>
    <p><button id="button-prompt" onclick="lastPrompt = prompt('hi', 'there')">prompt</button></p>
    <p><button id="button-confirm" onclick="lastConfirm = confirm('hello')">confirm</button></p>
  </body>
</html>
HTML
};

my $port = $wight->spawn_psgi($app);

$wight->handshake;

$wight->visit("http://localhost:$port/");

$wight->find('id("button-prompt")')->click;
is $wight->evaluate('lastPrompt'), undef, 'default on_prompt';

$wight->find('id("button-confirm")')->click;
is $wight->evaluate('lastConfirm'), 0;

my (@prompt_args, @confirm_args);
$wight->on_prompt(sub {
    (undef, @prompt_args) = @_;
    return 'hiya';
});

$wight->on_confirm(sub {
    (undef, @confirm_args) = @_;
    return 1;
});

$wight->find('id("button-prompt")')->click;
is $wight->evaluate('lastPrompt'), 'hiya', 'custom on_prompt';
is_deeply \@prompt_args, [ 'hi', 'there' ];

$wight->find('id("button-confirm")')->click;
is $wight->evaluate('lastConfirm'), 1;
is_deeply \@confirm_args, [ 'hello' ];

done_testing;
