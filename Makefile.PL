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

requires 'Protocol::WebSocket';
requires 'JSON::XS';

requires 'File::Basename';
requires 'File::Spec::Functions';
requires 'File::ShareDir';

requires 'Carp';
requires 'Sub::Name';

requires 'Class::Accessor::Lite::Lazy';

# spawn_psgi
requires 'Plack::Runner';

# cookie support
requires 'HTTP::Cookies';
requires 'File::Temp';

test_requires 'Test::More';

auto_set_repository;
auto_include_deps;

readme_from 'lib/Wight.pm';

if ($Module::Install::AUTHOR) {
    require Path::Class;

    my $poltergeist = Path::Class::dir('poltergeist');
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
}

install_share 'share';

WriteAll;
