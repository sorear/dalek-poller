package modules::local::googlecodeparser;
use strict;
use warnings;

use XML::Atom::Client;
use HTML::Entities;

use base 'modules::local::karmalog';

=head1 NAME

    modules::local::googlecodeparser

=head1 DESCRIPTION

This module is responsible for parsing ATOM feeds generated by code.google.com.
It is also knowledgeable enough about google code's URL schemes to be able to
recognise repository URLs, extract the project name and generate ATOM feed URLs.

This is very similar to, and heavily based on, modules::local::githubparser.

=head1 METHODS

=head2 process_feed

    $self->process_feed($feed, $targets);

Enumerates the commits in the feed, emitting any events.

=cut

sub process_feed {
    my ($self, $project, $targets) = @_;
    my $link = "http://code.google.com/feeds/p/$project/svnchanges/basic";
    my $atom = XML::Atom::Client->new();
    my $feed = $atom->getFeed($link);
    my @items = $feed->entries;
    @items = sort { $a->updated cmp $b->updated } @items; # ascending order
    my $newest = $items[-1];
    my $latest = $newest->updated;

    foreach my $item (@items) {
        my ($rev)   = $item->link->href =~ m|\?r=([0-9]+)|;
        common::try_item($self, $project, $targets, $rev, $item);
    }
    common::mark_feed_started(__PACKAGE__, $project);
}

=head2 try_link

    modules::local::googlecode->parse_url($url, $branch_ignored);

This is called by autofeed.pm.  Given a google code URL, try to determine the
project name and canonical path.  Then configure a feed reader for it if one
doesn't already exist.

Currently supports 2 URL formats:

    http://code.google.com/p/pynie/
    http://partcl.googlecode.com/

This covers all of the links on the Languages page at time of writing.

=cut

sub parse_url {
    my ($pkg, $url, $branch) = @_;
    my $projectname;
    if($url =~ m|http://code.google.com/p/([^/]+)/?$|) {
        $projectname = $1;
    } elsif($url =~ m|http://([^.]+).googlecode.com/$|) {
        $projectname = $1;
    } else {
        # whatever it is, we can't handle it.  Log and return.
        common::lprint("googlecode try_link(): I can't handle $url");
        return;
    }

    return $projectname;
}

=head2 output_item

    $self->output_item($item);

Takes an XML::Atom::Entry object, extracts the useful bits from it and calls
put() to emit the karma message.

The karma message is typically as follows:

feedname: $revision | username++ | $commonprefix:
feedname: One or more lines of commit log message
feedname: review: http://link/to/googlecode/diff/page

=cut

sub format_item {
    my ($self, $feedid, $rev, $item) = @_;
    my $prefix  = 'unknown';
    my $creator = $item->author->name;
    my $link    = $item->link->href;
    my $desc    = $item->content->body;

    $creator = "($creator)" if($creator =~ /\s/);

    my $log;
    decode_entities($desc);
    $desc =~ s/^\s+//s;   # leading whitespace
    $desc =~ s/\s+$//s;   # trailing whitespace
    $desc =~ s/<br\/>//g; # encapsulated newlines
    my @lines = split("\n", $desc);
    shift(@lines) if $lines[0] eq 'Changed Paths:';
    my @files;
    while(defined($lines[0]) && $lines[0] =~ /[^ ]/) {
        my $line = shift @lines;
        if($line =~ m[\xa0\xa0\xa0\xa0(?:Modify|Add|Delete)\xa0\xa0\xa0\xa0/(.+)]) {
            push(@files, $1);
        } elsif($line =~ m[^ \(from /]) {
            # skip this line and the one after it.
            shift(@lines);
        } else {
            unshift(@lines, $line);
            last;
        }
        while(defined($lines[0]) && $lines[0] eq ' ') {
            $line = shift @lines;
        }
    }
    pop(@lines) while scalar(@lines) && $lines[-1] eq '';
    $log = join("\n", @lines);
    $log =~ s/^\s+//;

    $prefix =  common::longest_common_prefix(@files);
    $prefix =~ s|^/||;      # cut off the leading slash
    if(scalar @files > 1) {
        $prefix .= " (" . scalar(@files) . " files)";
    }

    $log =~ s|<br */>||g;
    decode_entities($log);
    my @log_lines = split(/[\r\n]+/, $log);

    common::lprint("$feedid: output_item: output rev $rev");
    $self->format_karma_message(
        feed    => $feedid,
        rev     => "r$rev",
        user    => $creator,
        log     => \@log_lines,
        link    => $link,
        prefix  => $prefix,
    );
}

1;
