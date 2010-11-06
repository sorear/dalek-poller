package modules::local::adhoc;
use strict;
use warnings;

sub implements {
    return qw();
}

sub init {
    modules::local::githubparser->try_link(
        'https://github.com/masak/yapsi',
	['freenode', '#perl6'],
    );
    modules::local::githubparser->try_link(
	'https://github.com/ekiru/tree-optimization',
	['magnet', '#parrot'],
    );
    modules::local::googlecodeparser->try_link(
        'http://code.google.com/p/csmeta/',
        ['freenode', '#perl6'],
    );
    modules::local::gitoriousparser->try_link(
        'http://gitorious.org/parrot-plumage/parrot-plumage');
    modules::local::googlecodeparser->try_link(
        'http://code.google.com/p/java2perl6/',
        ['freenode', '#dbdi']
    );
    modules::local::githubparser->try_link(
        'https://github.com/jnthn/6model',
	['freenode', '#perl6'],
    );
    modules::local::githubparser->try_link(
        'https://github.com/hinrik/grok/',
        ['freenode', '#perl6']
    );
    modules::local::githubparser->try_link(
        'https://github.com/cardinal/cardinal/',
        ['magnet', '#cardinal']
    );
    modules::local::githubparser->try_link(
        'https://github.com/sorear/niecza',
	['freenode', '#perl6'],
    );
    modules::local::githubparser->try_link(
        'https://github.com/perl6/book',
        ['freenode', '#perl6']
    );
    modules::local::githubparser->try_link(
        'https://github.com/perl6/book',
        ['freenode', '#perl6book']
    );
    modules::local::githubparser->try_link(
        'https://github.com/viklund/november',
        ['freenode', '#november-wiki']
    );
    modules::local::githubparser->try_link(
        'https://github.com/viklund/november',
        ['freenode', '#perl6']
    );
    modules::local::githubparser->try_link(
        'https://github.com/rakudo/rakudo',
	['freenode', '#perl6'],
    );
    modules::local::githubparser->try_link(
        'https://github.com/perl6/nqp-rx',
    );
    modules::local::githubparser->try_link(
        'https://github.com/perl6/nqp-rx',
        ['freenode', '#perl6']
    );
    modules::local::githubparser->try_link(
        'https://github.com/rakudo/rakudo/tree/buf',
	['freenode', '#perl6'],
    );
    for my $url (qw{
https://github.com/perl6/bench-scripts
https://github.com/perl6/ecosystem
https://github.com/perl6/evalbot
https://github.com/perl6/misc
https://github.com/perl6/modules
https://github.com/perl6/mu
https://github.com/perl6/perl6.org
https://github.com/perl6/roast
https://github.com/perl6/specs
https://github.com/perl6/std
            }) {
        modules::local::githubparser->try_link($url, ['freenode', '#perl6']);
    }
}

1;
