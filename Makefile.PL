use inc::Module::Install;

name 'Wight';
all_from 'lib/Wight.pm';

tests 't/*.t';
author_tests 'xt';

test_requires 'Test::More';

auto_set_repository;
auto_include_deps;

readme_from 'lib/Wight.pm';

WriteAll;
