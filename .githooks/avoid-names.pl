# Prints each use of a word in .githooks/avoid-names, beside this script, as
# <file>:<line>: <the words as found>, in the files named, or in standard
# input given as -, skipping a file that is missing or binary. Prints
# nothing when there is none.
#
#   perl .githooks/avoid-names.pl <file>...
use strict;
use warnings;
use File::Basename qw(dirname);

my $list = dirname(__FILE__) . "/avoid-names";
open(my $fh, "<", $list) or die "avoid-names.pl: cannot read $list\n";
my $between = '\s+(?:(?:#|\/\/|--|\*)\s*)?';
my @words;
while (<$fh>) {
    s/\r?\n$//;
    next if /^\s*(#|$)/;
    push @words, join($between, map { quotemeta } split ' ');
}
close $fh;
exit 0 unless @words;
my $re = '(?<![.A-Za-z0-9])(?:' . join('|', @words) . ')(?![A-Za-z0-9])';

for my $file (@ARGV) {
    my $in;
    if ($file eq "-") { $in = \*STDIN }
    else { next if !-f $file || -B _; open($in, "<", $file) or next }
    local $/;
    my $text = <$in>;
    next unless defined $text;
    while ($text =~ /$re/gi) {
        my ($found, $at) = ($&, $-[0]);
        $found =~ s/$between/ /g;
        my $line = 1 + (substr($text, 0, $at) =~ tr/\n//);
        print "$file:$line: $found\n";
    }
}
