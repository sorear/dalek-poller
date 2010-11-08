package modules::local::tracwikilog;
use strict;
use warnings;
use XML::RAI;
use HTML::Entities;

# Parse RSS generated from trac's "revision log" page.

my $url  = 'https://trac.parrot.org/parrot/timeline?wiki=on&format=rss';
my $lastrev;

sub fetch_feed {
    my $response = ::fetch_url($url);
    if (defined $response) {
        my $feed = XML::RAI->parse_string($response);
        process_feed($feed);
    }
}

sub process_feed {
    my $rss = shift;
    my @items = @{$rss->items};
    @items = sort { $a->issued cmp $b->issued } @items; # ascending order
    my $newest = $items[-1];
    my $date   = $newest->issued;
    $date      = $items[0]->issued if exists $ENV{TEST_RSS_PARSER};

    # skip the first run, to prevent new installs from flooding the channel
    if(defined($lastrev)) {
        # output new entries to channel
        foreach my $item (@items) {
            my $this = $item->issued;
            output_item($item) if $this gt $lastrev;
        }
    }
    $lastrev = $date;
}

sub output_item {
    my $item = shift;
    my $creator = $item->creator;
    my $link    = $item->link . "&action=diff";
    my ($desc)  = $item->description =~ m|<p>\s*(.*?)\s*</p>|s;
    my ($rev)   = $link =~ /version=(\d+)/;
    my ($page)  = $link =~ m|/parrot/wiki/(.+)\?version=|;

    if(defined($rev)) {
        main::lprint("tracwikilog: output_item: output $page rev $rev");
        put("tracwiki: v$rev | $creator++ | $page");
    } else {
        main::lprint("tracwikilog: output_item: output unversioned item");
        # unversioned update, just output the title as-is.
        my $title = $item->title;
        put("tracwiki: $creator++ | $title");
    }
    if (defined($desc)) {
        $desc =~ s/<.*?>//;
        put("tracwiki: $desc") if ($desc ne "");
    }
    put("tracwiki: $link");
}

sub put {
    my $line = shift;
    main::send_privmsg("magnet", "#parrot", $line);
}

1;
