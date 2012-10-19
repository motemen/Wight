use inc::Module::Install;

name 'Wight';
all_from 'lib/Wight.pm';

tests 't/*.t';
author_tests 'xt';

requires 'Test::Builder';
requires 'Test::TCP';

requires 'Coro';
requires 'Coro::AnyEvent';
requires 'AnyEvent';
requires 'AnyEvent::Socket';
requires 'AnyEvent::Handle';
requires 'AnyEvent::Util';

requires 'Twiggy';

requires 'Protocol::WebSocket';
requires 'JSON';

requires 'File::Basename';
requires 'File::Spec::Functions';
requires 'File::ShareDir';

requires 'URI';

requires 'Carp';
requires 'Sub::Name';

requires 'Class::Accessor::Lite::Lazy';

# spawn_psgi
requires 'Plack::Runner';

# cookie support
requires 'HTTP::Cookies';
requires 'File::Temp';

requires 'HTML::Selector::XPath';

test_requires 'Test::More';
test_requires 'Test::Requires';

requires_external_bin 'phantomjs';

auto_set_repository;
auto_include_deps;

readme_markdown_from 'lib/Wight.pm';

if ($Module::Install::AUTHOR) {
    # Insert LICENSE to javascripts

    require Path::Class;
    require Cwd;

    my $cwd = Cwd::cwd();

    my $poltergeist = Path::Class::dir('poltergeist');

    chdir "$poltergeist";
    system('rake compile') == 0 or die "rake compile: $!";
    chdir $cwd;

    my $share = Path::Class::dir('share');
    my $license = $poltergeist->file('LICENSE')->slurp;
    my $js_dir = $poltergeist->subdir(qw(
        lib capybara poltergeist client compiled
    ));
    foreach my $js ($js_dir->children) {
        my $out = $share->file($js->basename);
        $out->dir->mkpath(1);
        $out->openw->print(
            "/*\n$license*/\n\n",
            $js->slurp
        );
    }

    require File::Copy;
    File::Copy::mv('README.mkdn', 'README.md');
}

install_share 'share';

WriteAll;
