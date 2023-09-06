#!/usr/bin/env perl

use JSON::PP;

my $json;

sub get_from_json_env {
    my ($key) = @_;
    return () unless defined $ENV{$key} && $ENV{$key};

    our $json;
    $json = JSON::PP->new->utf8->pretty->sort_by(sub { $JSON::PP::a cmp $JSON::PP::b }) unless defined $json;
    my $result = $json->decode($ENV{$key});
    return $result;
}

my %inputs = %{ get_from_json_env 'INPUTS' };

my @required;

open INPUT, '<', "$ENV{GITHUB_ACTION_PATH}/action.yml";
while (<INPUT>) {
    if ($state == 0) {
        $state = 1 if /^inputs:/;
        next;
    }
    if ($state == 1) {
        last if /^\S/;
        if (/^  (\S+):/) {
            $key = $1;
        } elsif (/^    required: true/) {
            push @required, $key unless %inputs && defined $inputs{$key};
        }
    }
}

if (@required) {
    print "::error ::Some required inputs are missing\n";
    print '::notice ::Required inputs: ['.join(', ', @required)."]\n";
}
exit 1;
