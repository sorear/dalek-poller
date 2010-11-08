package modules::local::autofeed;
use strict;
use warnings;

use JSON;

use modules::local::githubparser;
use modules::local::gitoriousparser;
use modules::local::googlecodeparser;
#use modules::local::tracparser;
#use modules::local::bitbucketparser;

sub init { }

my @scrape = (
    'https://trac.parrot.org/parrot/wiki/Languages',
    'https://trac.parrot.org/parrot/wiki/Modules',
);

# Note: Please make sure you put links to raw JSON files here, not the pretty
# html versions that github generates.
my @json = (
    'https://github.com/perl6/mu/raw/master/misc/dalek-conf.json',
);

=head1 NAME

    modules::local::autofeed

=head1 DESCRIPTION

Botnix plugin to scrape the list of Parrot languages and automatically set up
rss/atom feed parsers for recognised hosting services.

This plugin scrapes a few web pages to find feeds to monitor.

Two Parrot pages are scraped:

    https://trac.parrot.org/parrot/wiki/Languages
    https://trac.parrot.org/parrot/wiki/Modules

And one perl6 page is parsed as JSON:

    http://github.com/perl6/mu/raw/master/misc/dalek-conf.json

For any links it finds in those, it sees whether it can recognize any of them
as well-known source repository hosting services (currently github, google code
and gitorious).  Any links it recognises, it sets up feed parsers for them
automatically.  The JSON parser has the additional benefit of being able to
specify which networks/channels it should output to, and optionally which
branches to monitor (for github only, at present).  For the other two scraped
pages, the resulting parsers emit karma messages to #parrot on MagNET, and for
git repos, the "master" branch is always used.

=head1 METHODS

=head2 fetch_metadata

    $self->fetch_metadata();

This calls scrape_pages and parse_pages to parse URLs from html and from json,
respectively.  This is the top level timer callback function.

=cut

our @jsonout;

sub fetch_metadata {
    my $package = shift;
    @jsonout = ();
    $package->adhoc();
    $package->parse_pages();
    $package->scrape_pages();
    open NEWJSON, ">new.json";
    my $json = JSON->new->canonical(1)->space_after(1)->indent(1);
    @jsonout = sort { $a->{url} cmp $b->{url} } @jsonout;
    print NEWJSON $json->encode(\@jsonout);
    close NEWJSON;
}


=head2 parse_pages

    $self->parse_pages();

This function parses JSON feed pages, and calls try_link on the links it
discovers.  The JSON may specify which networks/channels to output on, and/or
which branches to track.

This is the preferred mechanism of discovering feed links.  The scrape_pages
function (see below) is its predecessor, which I would like to phase out at
some point.

The expected JSON format looks like this:

    [
        {
            "url" : "http://github.com/perl6/mu/",
            "channels": [ ["freenode", "#perl6"] ],
            "branches": ["master", "ng"]
        },
        {
            "url" : "http://github.com/perl6/roast/",
            "channels": [
                ["freenode", "#perl6"]
            ]
        }
    ]

The "channels" and "branches" fields are optional.  If not specified, their
defaults are ["magnet","#parrot"] and ["master"], respectively.  The "url"
field is mandatory.  Any other fields are ignored at present.

=cut

sub parse_pages {
    my $package = shift;
    foreach my $link (@json) {
        my $content = ::fetch_url($link);
        next unless defined $content;
        my $json;
        eval { $json = decode_json($content); };
        next unless defined $json;
        foreach my $item (@$json) {
            my $channels = [['magnet','#parrot']];
            my $branches = ['master'];
            my $url      = $$item{url};
            $channels = $$item{channels} if exists $$item{channels};
            $branches = $$item{branches} if exists $$item{branches};
            next unless defined $url;
            next unless scalar @$channels;
            next unless scalar $branches;
            $package->try_link($url, $channels, $branches);
        }
    }
}


=head2 scrape_pages

    $self->scrape_pages();

This function scrapes feed links from HTML (trac wiki) pages.  It grabs the
pages, scans them for links in the first column of the table.  For each link
it finds, the try_link() method is called to determine whether the link is
relevant.

Note, this is not currently doing an XML search, it is doing a substring search.
I could break it down into a hash tree using XML::TreePP and then enumerate
the rows in $$ref{html}{body}{div}[2]{div}[1]{div}{table}, but the result would
be brittle and would break if anyone added another paragraph before the table,
or changed the trac theme.

If anyone else knows a way to search for a data pattern at dynamic locations in
the xml tree, please feel free to replace this code.  It's not very big, I
promise.

=cut

sub scrape_pages {
    my $package = shift;
    foreach my $url (@scrape) {
        my $content = ::fetch_url($url);
        next unless defined $content;
        # this is nasty but straight-forward.
        my @links = split(/<tr[^>]*><td[^>]*><a(?: class=\S+) href="/, $content);
        shift @links;
        foreach my $link (@links) {
            if($link =~ /^(http[^"]+)"/) {
		eval {
	                $package->try_link($1);
		};
		warn "Scraping failure on $link" if $@;
            }
        }
    }
}


sub adhoc {
    my $self = shift;
    $self->try_link(
        'https://github.com/masak/yapsi',
        [['freenode', '#perl6']],
    );
    $self->try_link(
        'https://github.com/ekiru/tree-optimization',
        [['magnet', '#parrot']],
    );
    $self->try_link(
        'http://code.google.com/p/csmeta/',
        [['freenode', '#perl6']],
    );
    $self->try_link(
        'http://gitorious.org/parrot-plumage/parrot-plumage');
    $self->try_link(
        'http://code.google.com/p/java2perl6/',
        [['freenode', '#dbdi']]
    );
    $self->try_link(
        'https://github.com/jnthn/6model',
        [['freenode', '#perl6']],
    );
    $self->try_link(
        'https://github.com/hinrik/grok/',
        [['freenode', '#perl6']]
    );
    $self->try_link(
        'https://github.com/cardinal/cardinal/',
        [['magnet', '#cardinal']]
    );
    $self->try_link(
        'https://github.com/sorear/niecza',
        [['freenode', '#perl6']],
    );
    $self->try_link(
        'https://github.com/perl6/book',
        [['freenode', '#perl6']]
    );
    $self->try_link(
        'https://github.com/perl6/book',
        [['freenode', '#perl6book']]
    );
    $self->try_link(
        'https://github.com/viklund/november',
        [['freenode', '#november-wiki']]
    );
    $self->try_link(
        'https://github.com/viklund/november',
        [['freenode', '#perl6']]
    );
    $self->try_link(
        'https://github.com/rakudo/rakudo',
        [['freenode', '#perl6']],
    );
    $self->try_link(
        'https://github.com/perl6/nqp-rx',
    );
    $self->try_link(
        'https://github.com/perl6/nqp-rx',
        [['freenode', '#perl6']]
    );
    $self->try_link(
        'https://github.com/rakudo/rakudo/tree/buf',
        [['freenode', '#perl6']],
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
        $self->try_link($url, [['freenode', '#perl6']]);
    }
}

=head2 try_link

    $self->try_link($url, $target, $branches);

Figure out if the URL is to something worthwile.  Calls the parser modules to
do the dirty work.  If target and branches are specified, those are passed
through as well.  (Note: only the github parser supports the "branches" field
at present.  The field is ignored for other targets.)

=cut

sub try_link {
    my ($package, $url, $targets, $branches) = @_;
    my ($backend) = $url =~ /(github|gitorious|google)/;
    return unless $backend;
    $url =~ s|http://github|https://github|;
    $backend = "googlecode" if $backend eq "google";
    $backend = "modules::local::" . $backend . "parser";
    $targets //= [[ "magnet", "#parrot" ]];
    $branches //= ["master"];

    push @jsonout, { branches => $branches, channels => $targets, url => $url };

    $backend->try_link($url, $_, $branches) for @$targets;
}

1;
