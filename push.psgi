# vim: ft=perl
use 5.010;
use JSON;
use YAML;
use Encode;
use strict;
use warnings;

use Plack::Request;

use common;
use modules::local::karmalog;

use constant NOT_FOUND => [
    404,
    [ 'Content-Type' => 'text/plain' ],
    [ 'No handler']
];

use constant OK => [
    200,
    [ 'Content-Type' => 'text/plain' ],
    [ 'OK' ]
];

sub report {
    my ($bits, $tgt) = @_;

    modules::local::karmalog->fetch_metadata;

    my $blob = decode_json $bits;

    my @tgt = map { my ($a,$b) = split ',', $_; [ $a, "#$b" ] }
        split ' ', $tgt;

    return if $blob->{ref} !~ m#^refs/heads/(.*)#;

    my $project = $blob->{repository}{name};

    if ($1 ne 'master') {
        $project = "$project/$1";
    }

    if (@{ $blob->{commits} } > 15) {
        common::put(\@tgt, "Heuristic branch merge: pushed " . @{ $blob->{commits} } . " commits to $project by " . $blob->{pusher}{name});
        return;
    }

    for my $commit (@{ $blob->{commits} }) {
        my @lines = split("\n", $commit->{message} // 'unknown');
        pop(@lines) if $lines[-1] =~ /^git-svn-id: http/;
        pop(@lines) while scalar(@lines) && $lines[-1] eq '';

        my @files = (@{ $commit->{modified} },
                     @{ $commit->{added} // [] },
                     @{ $commit->{removed} // [] });

        my $prefix = common::longest_common_prefix(@files);
        if (defined($prefix) && length($prefix)) {
            # cut off the leading slash.
            $prefix =~ s|^/||;
        } else {
            # add a leading slash, just to be different.
            $prefix = '/' unless(defined($prefix) && length($prefix));
        }
        if (scalar @files > 1) {
            $prefix .= " (" . scalar(@files) . " files)";
        }
        # JSON lives in the world of characters, sadly, karmalog doesn't
        for ($commit->{author}{name}, $project, @lines) {
            $_ = Encode::encode_utf8($_);
        }
        modules::local::karmalog->emit_karma_message(
            targets => \@tgt,
            user    => $commit->{author}{name},
            feed    => $project,
            rev     => substr($commit->{id}, 0, 7),
            prefix  => $prefix,
            log     => \@lines,
            link    => $commit->{url}
        );
    }
}

my $app = sub {
    my $env = shift;
    my $req = Plack::Request->new($env);

    return NOT_FOUND if $req->path_info !~ m#^/dalek# || $req->method ne 'POST';

    my $bits = $req->param('payload');
    my $tgt  = $req->param('t');

    eval {
        open PACKET, ">packet." . time() . "." . $tgt;
        print PACKET $bits;
        close PACKET;
    };

    report($bits, $tgt);

    return OK;
};
