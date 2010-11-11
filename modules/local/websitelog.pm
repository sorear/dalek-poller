package modules::local::websitelog;
use strict;
use warnings;
use XML::RAI;
use HTML::Entities;

my $url     = 'http://www.parrot.org/rss.xml';
my $lastpost;

sub numify_ts {
    my ($ts) = shift;
    $ts =~ s/[-T:\+]//g;
    return $ts;
}

sub fetch_feed {
    my $response = common::fetch_url($url);
    if (defined $response) {
        my $rss = XML::RAI->parse_string($response);
        process_rss($rss);
    }
}

sub process_rss {
    my $rss    = shift;
    my @items  = @{$rss->items};
    my $newest = $items[0];
    $newest    = $items[-1] if exists $ENV{TEST_RSS_PARSER};
    my $newts  = numify_ts($newest->created);
    my @newposts;
    
    # skip the first run, to prevent new installs from flooding the channel
    if(defined($lastpost)) {
        # output new entries to channel
        foreach my $item (@items) {
            my ($post) = numify_ts($item->created);
	    last if $post <= $lastpost;
	    unshift(@newposts,$item);
        }
        output_item($_) foreach (@newposts);
    }
    $lastpost = $newts;
}

sub output_item {
    my $item = shift;
    my $creator = $item->creator;
    my $link    = $item->link;
    my $title   = $item->title;
    put("website: $creator++ | $title");
    put("website: $link");
}

sub put {
    my $line = shift;
    common::send_privmsg("magnet", "#parrot", $line);
}

1;
