package modules::local::gitoriousparser;
use strict;
use warnings;

use XML::Atom::Client;
use HTML::Entities;

use base 'modules::local::karmalog';

=head1 NAME

    modules::local::gitoriousparser

=head1 DESCRIPTION

This module is responsible for parsing ATOM feeds generated by gitorious.org.

=cut

# Tracks what feeds are being followed and where to output them
our %feeds;

=head1 METHODS

=head2 fetch_feed

This is a pseudomethod called as a timer callback.  It fetches the feed, parses
it into an XML::Atom::Feed object and passes that to process_feed().

This is the main entry point to this module.  Botnix does not use full class
instances, instead it just calls by package name.  This function maps from the
function name to a real $self object (stored in %objects_by_package).

=cut

sub fetch_feed {
    my $self = shift;
    for my $project (sort keys %feeds) {
        my $rss_link = "http://gitorious.org/$project.atom";
        my $atom = XML::Atom::Client->new();
        my $feed = $atom->getFeed($rss_link);
        $self->process_feed($project, $feed);
        ::mark_feed_started(__PACKAGE__, $project);
    }
}

=head2 process_feed

    $self->process_feed($project, $feed);

Enumerates the commits in the feed, emitting any events it hasn't seen before.

=cut

sub process_feed {
    my ($self, $project, $feed) = @_;
    my @items = $feed->entries;
    @items = sort { $a->updated cmp $b->updated } @items; # ascending order
    my $newest = $items[-1];
    my $latest = $newest->updated;

    # skip the first run, to prevent new installs from flooding the channel
    foreach my $item (@items) {
        my @revs = $item->content->body =~ m|/commit/([a-z0-9]{40})|g;
        for my $rev (reverse @revs) {
            ::try_item($self, $project, $feeds{$project}, $rev, $item);
        }
    }
}


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


=head2 try_link

    modules::local::gitoriousparser->try_link(
        $url,
        ['network', '#channel']
    );

This is called by autofeed.pm.  Given a gitorious.org URL, try to determine
the project name and canonical path.  Then configure a feed reader for it if
one doesn't already exist.

The array reference containing network and channel are optional.  If not
specified, magnet/#parrot is assumed.  If the feed already exists but didn't
have the specified target, the existing feed is extended.

Currently supports the following URL format:

    http://gitorious.org/projectname/

...with or without the "/" suffix.

=cut

sub try_link {
    my ($pkg, $url, $target) = @_;
    $target //= ['magnet', '#parrot'];
    my $project;
    if($url =~ m|http://gitorious.org/([^/]+)/?|) {
        $project = $1;
    } else {
        # whatever it is, we can't handle it.  Log and return.
        main::lprint("gitorious try_link(): I can't handle $url");
        return;
    }

    my $array = ($feeds{$project} //= []);
    foreach my $this (@$array) {
        return if($$target[0] eq $$this[0] && $$target[1] eq $$this[1]);
    }
    push @$array, $target;

    main::lprint("$project gitorious ATOM parser autoloaded.");
}

sub init {
    main::create_timer("gitorious_timer", __PACKAGE__, "fetch_feed", 300);
}

=head2 output_item

    $self->output_item($item, $revision);

Takes an XML::Atom::Entry object, extracts the useful bits from it and calls
put() to emit the karma message.

The karma message is typically as follows:

feedname: $revision | username++ | :
feedname: One or more lines of commit log message
feedname: review: http://link/to/diff

=cut

sub format_item {
    my ($self, $project, $rev, $item) = @_;
    my @out;
    my $link;
    my $creator = $item->author;
    if(defined($creator)) {
        $creator = $creator->name;
    } else {
        $creator = 'unknown';
    }

    my $desc = $item->content;
    if(defined($desc)) {
        $desc = $desc->body;
    } else {
        $desc = '(no commit message)';
    }

    $desc =  decode_entities($desc);
    $desc =~ s,(<ul>),$1\n,g;
    $desc =~ s,(</li>),$1\n,g;

    my @lines = split "\n", $desc;
    for my $line (@lines) {
        my ($item) = $line =~ m,\s*<li>(.*)</li>$,;
        next unless $item;

        my ($name, $link)
            = $item =~ m,^([^<]+)<a href="([^"]+)">[[:xdigit:]]{7}</a>:\s*[^<]+$,;
        next unless $link;

        my ($commit) = $link =~ m,/commit/([[:xdigit:]]{40}),;
        next unless $commit && $commit eq $rev;

        $link = "http://gitorious.org$link"
            unless $link =~ m,^https?://,;

        my $patch = ::fetch_url("$link.patch");
        my (@tmp, @log, @files, $this);
        @tmp = split(/\n+/, $patch);
        while(defined($this = shift(@tmp))) {
            last if $this =~ /^Subject:/;
        }
        if(defined($this) && $this =~ /^Subject:\s*(?:\[PATCH\] ?)?(.+)/) {
            push(@log, $1);
            $this = shift(@tmp);
            while(defined($this) && $this ne '---') {
                $this =~ s/^\s+//;
                push(@log, $this) if length $this;
                $this = shift(@tmp);
            }
        }
        $this = shift(@tmp);
        while(defined($this)) {
            if($this =~ /^\s+(\S+)\s+\|\s+\d+/) {
                push(@files, $1);
            } else {
                last;
            }
            $this = shift(@tmp);
        }

        my $prefix =  longest_common_prefix(@files);
        $prefix //= '/';
        $prefix =~ s|^/||;      # cut off the leading slash
        if(scalar @files > 1) {
            $prefix .= " (" . scalar(@files) . " files)";
        }

        $commit = substr($commit, 0, 7);

        main::lprint("$project: output_item: output rev $commit");
        push @out, @{ $self->format_karma_message(
            feed    => $project,
            rev     => $commit,
            user    => $creator,
            log     => \@log,
            link    => $link,
            prefix  => $prefix,
        ) };
    }

    \@out;
}

1;
