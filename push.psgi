# vim: ft=perl
use 5.010;
use JSON;
use YAML;
use strict;
use warnings;

use Plack::Request;

use common;
use modules::local::karmalog;

my $app = sub {
    my $env = shift;
    my $req = Plack::Request->new($env);

    if ($req->path_info ne '/dalek' || $req->method ne 'POST') {
        return [ 404, [ 'Content-Type' => 'text/plain' ], [ 'No handler'] ];
    }

    modules::local::karmalog->fetch_metadata;

    my $blob = decode_json $req->raw_body;
    my @tgt = map { my ($a,$b) = split ',', $_; [ $a, "#$b" ] }
        $req->param('t');

    if ($blob->{ref} !~ m#^refs/heads/(.*)#) {
        goto ignore;
    }

    my $project = $blob->{repository}{name};

    if ($1 ne 'master') {
        $project = "$project/$1";
    }

    for my $commit (reverse @{ $blob->{commits} }) {
        my @lines = split("\n", $commit->{message} // 'unknown');
        pop(@lines) if $lines[-1] =~ /^git-svn-id: http/;
        pop(@lines) while scalar(@lines) && $lines[-1] eq '';

        my @files;
        @files = @{$$commit{modified}};
        @files = (@files, @{$$commit{added}})   if exists $$commit{added};
        @files = (@files, @{$$commit{removed}}) if exists $$commit{removed};
        my $prefix = common::longest_common_prefix(@files);
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
        modules::local::karmalog->emit_karma_message(
            targets => \@tgt,
            user => $commit->{author}{name},
            feed => $project,
            rev => substr($commit->{id}, 0, 7),
            prefix => $prefix,
            log => \@lines,
            link => "https://github.com" . $commit->{url}
        );
    }

ignore:
    return [
        200,
        [ 'Content-Type' => 'text/plain' ],
        [ 'OK' ]
    ];
};