#!/usr/bin/perl -w

use strict;
no strict 'refs';
use English;
use utf8;

if ($#ARGV>=0) {
	my $fin = $ARGV[0];
	my $fout = $fin;
	$fout =~ s/(.*)\.[^.]*/$1-2.txt/;
	$fout = $ARGV[1] if ($#ARGV>=1);
	open(my $FIN,"<:utf8",$fin) || die "Cannot open file \"$fin\"!\n";
	open(STDOUT, ">$fout") || die "Cannot open file \"$fout\"!\n";
	binmode STDOUT, "utf8";
	binmode STDERR, "utf8";
	local $/;
	$_ = <$FIN>;
} else {
	binmode STDIN, "utf8";
	binmode STDOUT, "utf8";
	binmode STDERR, "utf8";
	local $/;
	$_ = <STDIN>;
}

my $LRE = "\x{202A}";
my $RLE = "\x{202B}";
my $PDF = "\x{202C}";

# Try to fix RLE/PDF (usually dumb bidi in PDF files)
# s/ ?([\x{202A}\x{202B}](.|(?1))\x{202C}) (?=[\x{202A}\x{202B}])/$1/g;
   # Place lines with [RLE][PDF] inside [LRE][PDF] context
   # and recursively pop embedded bidi formating
s/^(.*?\x{202B}.*?\x{202C}.*)$/\x{202A}$1\x{202C}/gm;
s/([\x{202A}\x{202B}](?:[^\x{202A}-\x{202C}]*|(?0))*\x{202C})/&pop_embedded($1)/ge;


# General cleanup
tr/\x{200E}\x{200F}\x{202A}-\x{202E}\x{2066}-\x{2069}//d; # Throw away BIDI characters
tr/\x{2000}-\x{200A}\x{205F}/ /; # Typographic spaces
tr/\x{200B}-\x{200D}//d;  # Zero-width spaces
tr/־–—‒―\xAD/-/;
tr/״”“„‟″‶/"/;
tr/`׳’‘‚‛′‵/'/;

# Clean HTML markups
s/<br\/?>/\n/gi;
s/<\/p>/\n/gi;
s/<\/?(?:".*?"|'.*?'|[^'">]*+)*>/ /g;
s/&#(\d+);/chr($1)/ge;
s/&quote;/"/gi;
s/&lt;/</gi;
s/&gt;/>/gi;
s/&ndash;/-/gi;
s/&nbsp;/ /gi;
s/&amp;/&/gi;

# Clean WIKI markups
s/'''//g;
s/^ *=+ *(.*?) *=+ *$/$1/gm;
# s/^[:;]+-? *//gm;

s/\r//g;           # Unix style, no CR
s/[\t\xA0]/ /g;    # Tab and hardspace are whitespaces
s/^[ ]+//mg;       # Remove redundant whitespaces
s/[ ]+$//mg;       # Remove redundant whitespaces
s/[ ]{2,}/ /g;     # Pack  long spaces
s/$/\n/s;          # Add last linefeed
s/\n{2,}/\n/sg;    # Convert three+ linefeeds
s/^\n+//sg;        # Remove first linefeed
s/\n{2,}$/\n/sg;   # Remove last linefeed
# s/\n\n/\n/sg;

# Special corrections
s/(\S) ([,.:;])/$1$2/g;  # Remove redundant whitespaces
s/("[א-ת])(\d{4})[-]/$1-$2/g;
s/^[.](\d.*?) +/$1. /gm;
s/(\S[([\-]) /$1/gm;
s/(?<=[א-ת]\b) - (?=[0-9])/-/g;
s/([\(\[]) /$1/g;
s/ ([\)\]])/$1/g;
s/ " -/" -/g;
s/(^| )" /"/gm;
s/ ("[.,:;])/$1/g;
s/ ('[ .,:;])/$1/g;
s/^([:]+)(?=\S)/$1 /gm;

print $_;
exit;
1;


sub pop_embedded {
	my $_ = shift; my $type = shift || '';
	
	if (/^([\x{202A}\x{202B}])(.*)\x{202C}$/) {
		$type .= $1; $_ = $2;
		my @arr = (m/([^\x{202A}-\x{202C}]+|[\x{202A}\x{202B}](?0)*\x{202C})/g);
		# dump_stderr("pop_embedded: |" . join('|',@arr) . "|\n") if ($#arr>0);
		@arr = map { pop_embedded($_,$type) } @arr;
		# dump_stderr("pop_embedded: |" . join('|',@arr) . "|\n") if ($#arr>0);
		@arr = reverse(@arr) if ($type eq "\x{202A}");  # [LRE]$_[PDF]
		return join('',@arr);
	} 
	if ($type =~ /\x{202B}/) {        # within RLE block
	# if (substr($type,-1) eq "\x{202B}") {
		tr/([{<>}])/)]}><{[(/;
	} 
	if (substr($type,-1) eq "\x{202A}") { # LRE block
		my $punc = '[ \t.,:;?!#$%^&*"\'\-\(\)\[\]{|}<>א-ת]';
		s/^($punc*)(.*?)($punc*)$/reverse($3).$2.reverse($1)/e;
	}
	return $_;
}

sub dump_stderr {
	my $_ = shift;
	
	tr/\x00-\x1F\x7F/␀-␟␡/;
	s/([␍␊]+)/\n/g;
	s/␉/␉\t/g;

	s/\x{200E}/[LRM]/g;
	s/\x{200F}/[RLM]/g;
	s/\x{202A}/[LRE]/g;
	s/\x{202B}/[RLE]/g;
	s/\x{202C}/[PDF]/g;
	s/\x{202D}/[LRO]/g;
	s/\x{202E}/[RLO]/g;
	s/\x{2066}/[LRI]/g;
	s/\x{2067}/[RLI]/g;
	s/\x{2068}/[FSI]/g;
	s/\x{2069}/[PDI]/g;
	s/\x{061C}/[ALM]/g;

	s/\x{200B}/[ZWSP]/g;
	s/\x{200C}/[ZWNJ]/g;
	s/\x{200D}/[ZWJ]/g;
	s/\x{2060}/[WJ]/g;
	print STDERR $_;
}