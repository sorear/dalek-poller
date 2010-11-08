package modules::local::githubparser;
use strict;
use warnings;

use YAML::Syck;
use HTML::Entities;

use base 'modules::local::karmalog';

=head1 NAME

    modules::local::githubparser

=head1 DESCRIPTION

This module is responsible for parsing ATOM feeds generated by github.com.  It
is also knowledgeable enough about github's URL schemes to be able to recognise
repository URLs, extract the project name/owner/path and generate ATOM feed
URLs.

This is a base class, there is one subclass per tracked project.  For each
subclass, it keeps track of which branches are being tracked, and for each
branch, which channels to emit updates.

=cut


# When new feeds are configured, this number  is incremented and added to the
# base timer interval in an attempt to stagger their occurance in time.
our $feed_number = 1;

# This is a map of $self objects.  Because botnix does not use full class
# instances and instead calls package::name->function() to call methods, the
# actual OO storage for those modules ends up in here.  This hash maps us
# back to the $self objects.
our %objects_by_package;

# Each $self pointer in this hash is a hash tree.  In pseudo-YAML, the layout
# of $self looks like:
# $self:
#   project: rakudo
#   modulename: rakudo # same thing but with invalid characters changed to "_"
#   seen:
#     5c0739f2384ee5a6b7979ce539258a964acd3178: 1
#     ff4ced6fc2880600fe8ada666b317c2a6fce573d: 1
#   branches:
#     master:
#       url: http://github.com/feeds/rakudo/commits/rakudo/master
#       targets:
#         -
#           - magnet
#           - #parrot
#         -
#           - freenode
#           - #perl6
#     ng:
#       url: http://github.com/feeds/rakudo/commits/rakudo/ng
#       targets:
#         -
#           - freenode
#           - #perl6


=head1 METHODS

=head2 process_project

This is a pseudomethod called as a timer callback.  It enumerates the branches,
calling process_branch() for each.

This is the main entry point to this module.  Botnix does not use full class
instances, instead it just calls by package name.  This function maps from the
function name to a real $self object (stored in %objects_by_package).

=cut

sub process_project {
    my $pkg  = shift;
    my $self = $pkg->get_self();
    foreach my $branch (sort keys %{$$self{branches}}) {
        $self->process_branch($branch);
    }
    $$self{not_first_time} = 1;
}


=head2 process_branch

    $self->process_branch($branch);

Fetches the ATOM feed for the 
Enumerates the commits in the feed, emitting any events it hasn't seen before.
This subroutine manages a "seen" cache in $self, and will take care not to
announce any commit more than once.

The first time through, nothing is emitted.  This is because we assume the bot
was just restarted ungracefully and the users have already seen all the old
events.  So it just populates the seen-cache silently.

=cut

sub process_branch {
    my ($self, $branch, $feed) = @_;

    # allow the testsuite to call us in a slightly different way.
    $self = $self->get_self() unless ref $self;
    if(!defined($feed)) {
        $feed = get_yaml($$self{branches}{$branch}{url});
    }
    if(!defined($feed)) {
        warn "could not fetch branch $branch feed " . $$self{branches}{$branch}{url};
        return;
    }
    warn "fetching branch $branch feed " . $$self{branches}{$branch}{url};

    my @items = @{$$feed{commits}};
    @items = sort { $$a{committed_date} cmp $$b{committed_date} } @items; # ascending order
    my $newest = $items[-1];
    my $latest = $$newest{committed_date};

    # skip the first run, to prevent new installs from flooding the channel
    foreach my $item (@items) {
        my $link    = $$item{url};
        my ($rev)   = $$item{id};
        my ($proj)  = $link =~ m|^/[^/]+/([^/]+)/|;
        if(exists($$self{not_first_time})) {
            return unless $proj eq $$self{project};
            # output new entries to channel
            next if exists($$self{seen}{$rev});
	    print "outputting $rev for $proj\n";
            $$self{seen}{$rev} = 1;
            $self->output_item($item, $branch, "https://github.com" . $link, $rev);
        } else {
            die "got bad data from github feed" unless $proj = $$self{project};
	    #print "preseeding $rev for $proj\n";
            # just populate the seen cache
            $$self{seen}{$rev} = 1;
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

    modules::local::githubparser->try_link(
        $url,
        ['network', '#channel'],
        [qw(master ng)]
    );

This is called by autofeed.pm.  Given a github.com URL, try to determine the
project name and canonical path.  Then configure a feed reader for it if one
doesn't already exist.

The array reference containing network and channel are optional.  If not
specified, magnet/#parrot is assumed.  If the feed already exists but didn't
have the specified target, the existing feed is extended.  Similarly, if the
feed already existed but didn't have the specified branch, the existing feed
is extended.

The array reference containing branch names are also optional.  However,
to prevent ambiguity, you must also specify the network/channel in this case.
Branches is an optional array reference containing the branches to be
monitored, and defaults to C<[qw(master)]>.

Currently supports 3 URL formats:

    https://github.com/tene/gil/
    https://wiki.github.com/TiMBuS/fun
    https://bschmalhofer.github.com/hq9plus/

...with or without a suffix of "/" or "/tree/master".  This covers all of the
links on the Languages page at time of writing.

=cut

sub try_link {
    my ($pkg, $url, $target, $branches) = @_;
    $target = ['magnet', '#parrot'] unless defined $target;
    $branches = ['master'] unless defined $branches;
    my($author, $project);
    if($url =~ m|https://(?:wiki.)?github.com/([^/]+)/([^/]+)/?|) {
        $author  = $1;
        $project = $2;
    } elsif($url =~ m|https://([^.]+).github.com/([^/]+)/?|) {
        $author  = $1;
        $project = $2;
    } else {
        # whatever it is, we can't handle it.  Log and return.
        main::lprint("github try_link(): I can't handle $url");
        return;
    }

    my $parsername = $project . "log";
    my $modulename = "modules::local::" . $parsername;
    $modulename =~ s/[-\.]/_/g;

    # create project, if necessary
    my $self = $objects_by_package{$modulename};
    my $register_timer = 0;
    if(!defined($self)) {
        $objects_by_package{$modulename} = $self = {
            project    => $project,
            author     => $author,
            modulename => $modulename,
            branches   => {},
            commit     => "https://github.com/api/v2/yaml/commits/show/$author/$project/",
        };

        # create a dynamic subclass to get the timer callback back to us
        eval "package $modulename; use base 'modules::local::githubparser';";
        $objects_by_package{$modulename} = bless($self, $modulename);
        $register_timer = 1;
        main::lprint("github: created project $project ($modulename)");
    }

    # create branches, if necessary
    foreach my $branchname (@$branches) {
        my $branch = $$self{branches}{$branchname};
        if(!defined($branch)) {
            # https://github.com/api/v2/yaml/commits/list/rakudo/rakudo/master
            my $url = "https://github.com/api/v2/yaml/commits/list/$author/$project/$branchname";
            $$self{branches}{$branchname} = $branch = {
                url     => $url,
                targets => [],
            };
            main::lprint("github: $project has branch $branchname with feed url $url");
        }

        # update target list, if necessary
        my $already_have_target = 0;
        foreach my $this (@{$$branch{targets}}) {
            $already_have_target++
                if($$target[0] eq $$this[0] && $$target[1] eq $$this[1]);
        }
        unless($already_have_target) {
            push(@{$$branch{targets}}, $target);
            main::lprint("github: $project/$branchname will output to ".join("/",@$target));
        }
    }

    if($register_timer) {
        main::create_timer($parsername."_process_project_timer", $modulename,
            "process_project", 300 + $feed_number++);
    }
}


=head2 output_item

    $self->output_item($item, $branch, $link, $revision);

Takes an XML::Atom::Entry object, extracts the useful bits from it and calls
put() to emit the karma message.

The karma message is typically as follows:

feedname/branch: $revision | username++ | $commonprefix:
feedname/branch: One or more lines of commit log message
feedname/branch: review: https://link/to/github/diff/page

The "/branch" suffix is only emitted if we track more than one branch for this
repository.

=cut

sub output_item {
    my ($self, $item, $branch, $link, $rev) = @_;
    my $prefix  = 'unknown';
    my $creator = $$item{author}{login};
    $creator = $$item{author}{name} unless(defined $creator && length $creator);
    $creator = 'unknown'            unless(defined $creator && length $creator);
    my $desc    = $$item{message};
    $desc = '(no commit message)' unless defined $desc;

    my @lines = split("\n", $desc);
    pop(@lines) if $lines[-1] =~ /^git-svn-id: http/;
    pop(@lines) while scalar(@lines) && $lines[-1] eq '';

    my @files;
    my $commit = $$self{commit} . $rev;
    $commit = get_yaml($commit);
    if(defined($commit)) {
        $commit = $$commit{commit};
        @files = map { $$_{filename} } (@{$$commit{modified}});
        @files = (@files, @{$$commit{added}})   if exists $$commit{added};
        @files = (@files, @{$$commit{removed}}) if exists $$commit{removed};
        $prefix = longest_common_prefix(@files);
        if(defined($prefix) && length($prefix)) {
            # cut off the leading slash.
            $prefix =~ s|^/||;
        } else {
            # add a leading slash, just to be different.
            $prefix = '/' unless(defined($prefix) && length($prefix));
        }
        if(scalar @files > 1) {
            $prefix .= " (" . scalar(@files) . " files)";
        }
    }

    $rev = substr($rev, 0, 7);

    my $project = $$self{project};
    if(scalar keys %{$$self{branches}} > 1) {
        $project .= "/$branch";
    }

    $self->emit_karma_message(
        feed    => $project,
        rev     => $rev,
        user    => $creator,
        log     => \@lines,
        link    => $link,
        prefix  => $prefix,
        targets => $$self{branches}{$branch}{targets},
    );

    main::lprint($$self{project}.": output_item: output $project rev $rev");
}


=head2 implements

This is a pseudo-method called by botnix to determine which event callbacks
this module supports.  It is only called when explicitly subclassed (rakudo
does this).  Returns an empty array.

=cut

sub implements {
    return qw();
}


=head2 get_self

This is a helper method used by the test suite to fetch a feed's local state.
It isn't used in production.

=cut

sub get_self {
    my $pkg = shift;
    return $objects_by_package{$pkg};
}

=head2 get_yaml

Given a URL, fetches content and tries to parse as a YAML document.  Returns
undef on error.

=cut

sub get_yaml {
    my $url = shift;
    my $response = ::fetch_url($url);
    if (defined $response) {
        my $rv = Load($response);
        return $rv;
    }
    return undef;
}

1;
