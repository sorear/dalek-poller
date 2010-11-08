package modules::local::parrotticketlog;
use strict;
use warnings;
use utf8;

use XML::RAI;
use HTML::Entities;

use base 'modules::local::karmalog';

# Parse RSS generated from trac's "timeline" page (filtered to show only tickets).

my $url  = 'https://trac.parrot.org/parrot/timeline?ticket=on&format=rss';
my $lastrev;

sub fetch_feed {
    my $response = ::fetch_url($url);
    if (defined $response) {
        my $feed = XML::RAI->parse_string($response);
        process_feed($feed);
    }
}

sub process_feed {
    my $feed = shift;
    my @items = @{$feed->items};
    @items = sort { $a->created cmp $b->created } @items; # ascending order

    # skip the first run, to prevent new installs from flooding the channel
    foreach my $item (@items) {
        my $rev = $item->identifier;
        ::try_item(__PACKAGE__, "", [["magnet", "#parrot"]], $rev, $item);
    }
    ::mark_feed_started(__PACKAGE__, "");
}


sub format_item {
    my ($self, $feeedid, $rev, $item) = @_;
    my $user    = $item->creator;
    my $desc    = $item->title;

    $desc =~ s/<[^>]+>//g;
    $desc =~ s|…|...|g;
    decode_entities($desc);
    if($desc =~ /^Ticket \#(\d+) \((.+)\) (\S+)\s*$/) {
        my ($ticket, $summary, $action) = ($1, $2, $3);
        main::lprint("parrotticketlog: ticket $ticket $action");
        return $self->format_ticket_karma(
            prefix  => 'TT #',
            ticket  => $ticket,
            action  => $action,
            user    => $user,
            summary => $summary,
            url => "http://trac.parrot.org/parrot/ticket/$ticket"
        );
    } else {
        main::lprint("parrotticketlog: regex failed on $desc");
        return [];
    }
}

1;
