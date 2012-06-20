# NAME

Wight - Communicate with PhantomJS

# SYNOPSIS

    use Wight;

    my $wight = Wight->new;

    $wight->spawn_psgi('app.psgi');
    $wight->handshake;

    $wight->visit('/');
    $wight->evaluate('document.title'); # => evaluates JavaScript expression

    $wight->find('//a[@rel="next"]')->click;

# DESCRIPTION

Wight provides methods for operating PhantomJS from Perl,
especially intended to be used testing web application.

For client side scripting, uses [poltergeist](https://github.com/jonleighton/poltergeist)'s JavaScript.

# BROWSER METHODS

Every method croaks if the operation was failed.

- $wight->visit($path)

Opens a web page.

- my $result = $wight->evaluate($javascript\_expression)

Evaluates a JavaScript expression and returns its result.

- $wight->execute($javascript\_statement)

Executes JavaScript statements.

- my $node  = $wight->find($xpath)
- my @nodes = $wight->find($xpath)

Finds a node within current page and returns a (list of) [Wight::Node](http://search.cpan.org/perldoc?Wight::Node).

- $wight->render($file)

Renders current page to local file.

# NODE METHODS

Every method croaks if the operation was failed.

- $node->click
- my $text = $node->text
- $node->set($value)

# INITIALIZATION METHODS

- my $port = $wight->spawn\_psgi($file\_or\_code)

Forks and runs specified PSGI application.
Sets its `base_url` to "http://localhost:_$port_/".

- $wight->handshake

Starts PhantomJS and waits for communication established.
After this, you can call BROWSER METHODS above.

- $wight->base\_url($url);

# UTILITY METHODS

- $wight->sleep($secs)
- $wight->wait\_until(\\&code)

Stops execution until `code` returns a true value.

# AUTHOR

motemen <motemen@gmail.com>

# SEE ALSO

[poltergeist](https://github.com/jonleighton/poltergeist)

# LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

For JavaScripts from poltergeist:

Copyright (c) 2011 Jonathan Leighton

Permission is hereby granted, free of charge, to any person obtaining
a copy of this software and associated documentation files (the
"Software"), to deal in the Software without restriction, including
without limitation the rights to use, copy, modify, merge, publish,
distribute, sublicense, and/or sell copies of the Software, and to
permit persons to whom the Software is furnished to do so, subject to
the following conditions:

The above copyright notice and this permission notice shall be
included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.