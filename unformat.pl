#!/usr/bin/perl -w

use strict;
no strict 'refs';
use English;
use utf8;
use Encode;
use Encode::Guess qw/windows-1255 utf8/;

if ($#ARGV>=0) {
        my $fin = $ARGV[0];
        my $fout = ($#ARGV>=1 ? $ARGV[1] : $fin);
        $fout =~ s/(.*)\.[^.]*/$1.src/;
        open(my $FIN,$fin) || die "Cannot open file \"$fin\"!\n";
        open(STDOUT, ">$fout") || die "Cannot open file \"$fout\"!\n";
        local $/;
        $_ = <$FIN>;
} else {
        local $/;
        $_ = <STDIN>;
}

binmode STDIN, "utf8";
binmode STDOUT, "utf8";
binmode STDERR, "utf8";

$_ = decode("Guess", $_);

# General cleanup
s/\r//g;           # Unix style, no CR
s/[\t\xA0]/ /g;    # Tab and hardspace are whitespaces
s/^[ ]+//mg;       # Remove redundant whitespaces
s/[ ]+$//mg;       # Remove redundant whitespaces
s/$/\n/s;          # Add last linefeed
s/\n{3,}/\n\n/sg;  # Convert three+ linefeeds
s/\n\n$/\n/sg;     # Remove last linefeed

s/[\x{200E}\x{200F}\x{202A}-\x{202E}]//g; # Throw away LTR/RTL characters
s/[\x{2000}-\x{200A}\x{205F}]/ /g; # Typographic spaces
s/[\x{200B}-\x{200D}]//g;  # Zero-width spaces
s/[־–—‒―]/-/g;     # Different types of dashes
s/[״”“„‟″‶]/"/g;   # Different types of double quotes
s/[`׳’‘‚‛′‵]/'/g;  # Different types of single quotes
s/[ ]{2,}/ /g;     # Pack  long spaces

# s/ - / -- /g;
# s/ -\n/ --\n/g;
s/&quote;/"/g;
s/&lt;/</g;
s/&gt;/>/g;
s/&ndash;/–/g;
s/&amp;/&/g;
s/(\S) ([,.:;])/$1$2/g;
s/--/-/g;

# Parse various elements
s/^<כותרת>\s*\n?(.*?)\n/<שם> $1\n/m;
s/<ביבליוגרפיה>/<מקור>/g;

s/<סימון\s*"?(.*?)"?>(.*?)<\/>/(($2|$1))/g;

s/<חלק.*?>\n?(.*)\n/= $1 =/g;
s/<פרק.*?>\n?(.*)\n/== $1 ==/g;
s/<תתפרק.*?>\n?(.*)\n/=== $1 ===/g;
s/<סימן.*?>\n?(.*)\n/=== $1 ===/g;

s/<מפריד>/----/g;
s/<סעיף\s*(.*?)[.]?>\n?<אחר\s*"?(.*?)"?>\n?<תי?אור\s*"?(.*?)"?>\n?/@ $1. $2 $3\n/g;
s/<סעיף\s*(.*?)[.]?>\n?<תי?אור\s*"?(.*?)"?>\n?/@ $1. $2\n/g;
s/<סעיף\s*(.*?)>/@ $1/g;
s/\n*<אחר\s*"?(.*?)"?>/ $1/g;
s/<תיקון\s*"?(.*?)"?>\n?<תיקון\s*"?(.*?)"?>/<תיקון $1, $2>/g;
s/<תיקון\s*"?(.*?)"?>\n?<תיקון\s*"?(.*?)"?>/<תיקון $1, $2>/g;
s/<תיקון\s*"?(.*?)"?>\n?<תיקון\s*"?(.*?)"?>/<תיקון $1, $2>/g;
s/\n*<תיקון\s*"?(.*?)"?>/ (תיקון: $1)/g;
s/<תת>\s*/:: /g;
s/<תת\s+(.*?)>\s+/: ($1) /g;
s/<תתת>\s*/::: /g;
s/<תתת\s+(.*?)>\s+/:: ($1) /g;
s/<תתתת>\s*/:::: /g;
s/<תתתת\s+(.*?)>\s+/::: ($1) /g;

s/<(פנימי|חיצוני)\s+"?(.*?)"?>(.*?)<\/>/[[$2|$3]]/g;
s/<(פנימי|חיצוני|קישור).*?>\s*(.*?)\s*<\/>/[[$2]]/g;
s/<מודגש>(.*?)<\/>/<b>$1<\/b>/g;
s/<עוגן.*?>\s*\n*//g;

s/<הערה\s*>(.*?)<\/>/(($1))/g;
s/<פסקהערה>\n?\s*(.*?)\n/: (($1))\n/g;
s/<הגדרה>[\s\n]*/:- /g;
s/<פסקה>//g;
s/<יציאה>//g;


print $_;
exit;
1;


s/^=([^=].*)=/&parseTitle($1)/em;
s/^(==+)([^=]+?)\1/&parseSection($2)/egm;

s/^<סעיף (\S+)>(.*)\n/&parseChapter($1,$2,"סעיף")/egm;
s/^@\s*(\d\S*)[ ]*(.*)\n/&parseChapter($1,$2,"סעיף")/egm;
s/^@\s*(\S+)[ ]*(\S+)[ ]*(.*)\n/&parseChapter($2,$3,$1)/egm;
s/^([:]+)[ ]*(\(\S+\)|)[ ]*(.*)\n/&parseLine(length($1),$2,$3)/egm;
s/^<חתימות>\s*\n?((\*.*\n)*)/&parseSignatures($1)/egm;
s/^-{3,}$/<מפריד>\n/gm;

# Parse links and remarks
## s/\[\[\s*([^]]*?)\s*\=\s*(.*?)\s*\]\]/&parseDefLink($1,$2)/egm;
s/\[\[\[/\[\[ \[/g;
s/\]\]\]/\] \]\]/g;
s/\[\[\s*([^]]*?)\s*[|]\s*(.*?)\s*\]\]/&parseLink($1,$2)/egm;
s/\[\[\s*(.*?)\s*\]\]/&parseLink('',$1)/egm;

s/\(\(\s*(.*?)[|](.*?)\s*\)\)/&parseTip($1,$2)/egm;
s/\(\(\s*(\(.*?\).*?)\s*\)\)/&parseRemark($1)/egm;
s/\(\(\s*(.*?)\s*\)\)/&parseRemark($1)/egm;


sub unquote {
        my $_ = shift;
        s/^\s*(.*?)\s*$/$1/;
        s/^(["'])(.*?)\1$/$2/;
        s/^\s*(.*?)\s*$/$1/;
        return $_;
}

sub unparent {
        my $_ = unquote(shift);
        s/^\((.*?)\)$/$1/;
        s/^\[(.*?)\]$/$1/;
        s/^\{(.*?)\}$/$1/;
        s/^\s*(.*?)\s*$/$1/;
        return $_;
}
