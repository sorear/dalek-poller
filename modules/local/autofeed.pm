package modules::local::autofeed;
use strict;
use warnings;

use JSON;

use modules::local::githubparser;
use modules::local::gitoriousparser;
use modules::local::googlecodeparser;

sub init { }

# Note: Please make sure you put links to raw JSON files here, not the pretty
# html versions that github generates.
my @json = (
    'https://github.com/perl6/mu/raw/master/misc/dalek-conf.json',
);

=head1 NAME

    modules::local::autofeed

=head1 DESCRIPTION

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

This function parses JSON feed pages, and calls try_link on the links it
discovers.  The JSON may specify which networks/channels to output on, and/or
which branches to track.

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

sub fetch_metadata {
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

    $backend->try_link($url, $_, $branches) for @$targets;
}

1;
