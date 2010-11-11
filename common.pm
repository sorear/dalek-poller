package common;
use warnings;
use strict;
use LWP::UserAgent;

sub lprint {
    print @_, "\n";
}

open QUEUE, ">>", "queue";
select QUEUE;
$| = 1;
select STDOUT;

=head2 longest_common_prefix

    my $prefix = longest_common_prefix(@files);

Given a list of filenames, like ("src/ops/perl6.ops", "src/classes/IO.pir"),
returns the common prefix portion.  For the example I just gave, the common
prefix would be "src/".
=cut

sub longest_common_prefix {
    my $prefix = shift;
    for (@_) {
        chop $prefix while (! /^\Q$prefix\E/);
    }
    return $prefix;
}
=head2 fetch_url

    my $pagedata = ::fetch_url($url);

Fetch the data using a 10 second timeout.  Return undef if an error or timeout
was encountered.

=cut

my $lwp = LWP::UserAgent->new();
$lwp->timeout(10);
$lwp->env_proxy();

sub fetch_url {
    my ($url) = @_;
    my $response = $lwp->get($url);
    if($response->is_success) {
        return $response->content;
    }
    lprint("fetch_url: failure fetching $url: " . $response->status_line);
    return undef;
}

sub send_privmsg {
    my ($net, $to, $msg) = @_;
    lprint("sending: $net $to $msg");
    print QUEUE "$net $to $msg\n";
}

sub put {
    my ($targets, @lines) = @_;
    for my $target (@$targets) {
        for my $line (@lines) {
            send_privmsg(@$target, $line);
        }
    }
}

my %seen;
my %started;

sub try_item {
    my ($pkg, $feedid, $targets, $commit, $token) = @_;

    if ($seen{$pkg}{$feedid}{$commit}++) {
    } else {
        if (!$started{$pkg}{$feedid}) {
            # Bootstrap *quietly*
        } else {
            lprint("Reporting $pkg - $feedid - $commit");
            put($targets, @{ $pkg->format_item($feedid, $commit, $token) });
        }
    }
}

sub mark_feed_started {
    my ($pkg, $feedid) = @_;
    lprint("Marking $pkg - $feedid started") unless $started{$pkg}{$feedid}++;
}

1;
