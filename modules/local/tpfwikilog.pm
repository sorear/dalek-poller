package modules::local::tpfwikilog;
use strict;
use warnings;
use XML::RAI;
use HTML::Entities;

my $url     = 'http://www.perlfoundation.org/feed/workspace/perl6?category=Recent%20Changes';

sub fetch_feed {
    local $common::timeout = 30;
    my $response = common::fetch_url($url);
    if(defined $response) {
        my $rss = XML::RAI->parse_string($response);
        process_feed($rss);
    }
}

sub process_feed {
    my $rss = shift;
    my @items = @{$rss->items};
    my $newest = $items[0];
    # output new entries to channel
    foreach my $item (@items) {
        common::try_item(__PACKAGE__, 'perl6', [['freenode', '#perl6']],
            $item->created, $item);
    }
    common::mark_feed_started(__PACKAGE__, 'perl6');
}

sub format_item {
    my ($pkg, $feedid, $commit, $item) = @_;
    my $creator = $item->creator;
    my $link    = $item->link;
    my $title   = $item->title;
    [ "tpfwiki: $creator | $title",
      "tpfwiki: $link" ];
}

1;
