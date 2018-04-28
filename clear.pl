#!/usr/bin/perl -w

no if $] >= 5.018, warnings => 'experimental';
use strict;
no strict 'refs';
use English;
use utf8;

use Data::Dumper;
use Getopt::Long;

our ($variant, $debug, $raw);
$variant = 1;
$debug = 0;
$raw = 0;

my %lut;
my ($t1, $t2);

GetOptions(
	"type=i" => \$variant, 
	"debug" => \$debug,
	"verbose" => \$debug,
	"raw" => \$raw,
#	"help|?" => \&HelpMessage,
) or die("Error in command line arguments\n");

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
	$_ = join('', <STDIN>);
}

my $LRE = "\x{202A}";
my $RLE = "\x{202B}";
my $PDF = "\x{202C}";

if (/\x{F8FF}/ and /\xD3/) { # Fix f*cked-up macos encoding
	# Convert Unicode to "Mac OS Roman", treat as "Mac OS Hebrew" and convert back to Unicode.
	# See ftp://ftp.unicode.org/Public/MAPPINGS/VENDORS/APPLE/ROMAN.TXT
	# and ftp://ftp.unicode.org/Public/MAPPINGS/VENDORS/APPLE/HEBREW.TXT
	tr/\xC4\xC5\xC7\xC9\xD1\xD6\xDC\xE1\xE0\xE2\xE4\xE3\xE5\xE7\xE9\xE8\xEA\xEB\xED\xEC\xEE\xEF\xF1\xF3\xF2\xF4\xF6\xF5\xFA\xF9\xFB\xFC\x{2020}\xB0\xA2\xA3\xA7\x{2022}\xB6\xDF\xAE\xA9\x{2122}\xB4\xA8\x{2260}\xC6\xD8\x{221E}\xB1\x{2264}\x{2265}\xA5\xB5\x{2202}\x{2211}\x{220F}\x{03C0}\x{222B}\xAA\xBA\x{03A9}\xE6\xF8\xBF\xA1\xAC\x{221A}\x{0192}\x{2248}\x{2206}\xAB\xBB\x{2026}\xA0\xC0\xC3\xD5\x{0152}\x{0153}\x{2013}\x{2014}\x{201C}\x{201D}\x{2018}\x{2019}\xF7\x{25CA}\xFF\x{0178}\x{2044}\x{20AC}\x{2039}\x{203A}\x{FB01}\x{FB02}\x{2021}\xB7\x{201A}\x{201E}\x{2030}\xC2\xCA\xC1\xCB\xC8\xCD\xCE\xCF\xCC\xD3\xD4\x{F8FF}\xD2\xDA\xDB\xD9\x{0131}\x{02C6}\x{02DC}\xAF\x{02D8}\x{02D9}\x{02DA}\xB8\x{02DD}\x{02DB}\x{02C7}/\x80-\xFF/;
	
	# Place RTL tags
	s/([\xA0-\xFF])/$RLE$1$PDF/g;
	tr/\x80-\xFF/\xC4\x{FB1F}\xC7\xC9\xD1\xD6\xDC\xE1\xE0\xE2\xE4\xE3\xE5\xE7\xE9\xE8\xEA\xEB\xED\xEC\xEE\xEF\xF1\xF3\xF2\xF4\xF6\xF5\xFA\xF9\xFB\xFC\x20-\x25\x{20AA}\x27\x29\x28\x2A-\x3F\x{F86A}\x{201E}\x{F89B}-\x{F89E}\x{05BC}\x{FB4B}\x{FB35}\x{2026}\xA0\x{05B8}\x{05B7}\x{05B5}\x{05B6}\x{05B4}\x{2013}\x{2014}\x{201C}\x{201D}\x{2018}\x{2019}\x{FB2A}\x{FB2B}\x{05BF}\x{05B0}\x{05B2}\x{05B1}\x{05BB}\x{05B9}\x{05B8}\x{05B3}\x{05D0}-\x{05EA}\x7D\x5D\x7B\x5B\x7C/;
	
	# Pack numeric and nikkud sequences
	s/ (?=$RLE[\x{05B0}-\x{05BD}]$PDF)//g;
	s/(?<=$RLE[\x{05B0}-\x{05BD}]$PDF) //g;
	s/([א-ת][\x{05B0}-\x{05BD}]*)$PDF$RLE([\x{05B0}-\x{05BD}])/$1$2/g;
	s/($RLE[0-9]$PDF(?:$RLE[0-9.,%]$PDF)+)/$LRE$1$PDF/g;
	s/\x{F86A}/\x{05DC}\x{05B9}/g; # HEBREW LETTER LAMED + HEBREW POINT HOLAM
	tr/\x{F89B}-\x{F89E}//d; # Remove obsolete "canorals"
} elsif (/\x{F8FF}/) {
	tr/\x{F8FF}/נ/;
}

s/([\x{05B0}-\x{05BD}]+)([א-ת])/$2$1/g if (/$RLE\x{05BC}[א-ת]/);

# General cleanup
tr/\x{2000}-\x{200A}\x{205F}/ /; # Typographic spaces
tr/\x{200B}-\x{200D}//d;  # Zero-width spaces
tr/־–—‒―/-/;        # Convert typographic dashes
s/(?<![א-ת\x{05B0}-\x{05BD}])\x{05BF}/-/g; # Rafe (U+05BF) misused as dash
tr/\xAD\x96\x97/-/; # Convert more typographic dashes
tr/״”“„‟″‶/"/;      # Convert typographic double quotes
tr/`׳’‘‚‛′‵/'/;     # Convert typographic single quotes
tr/;/;/;            # Convert wrong OCRed semicolon

tr/\x{FEFF}\x{FFFC}-\x{FFFF}//d;    # Unicode placeholders and junk

# Hebrew ligatures and alternative forms
tr/ﬠﬡﬢﬣﬤﬥﬦﬧﬨ/עאדהכלםרת/;
# Keep hebrew plus sign - tr/﬩/+/;
# Keep math symbols     - tr/ℵℶℷℸ/אבגד/;
$_ = s_lut($_, {
	'שׁ' => 'שׁ', 'שׂ' => 'שׂ', 'שּׁ' => 'שּׁ', 'שּׂ' => 'שּׂ', 'אַ' => 'אַ', 'אָ' => 'אָ', 'יִ' => 'יִ', 'ײַ' => 'ײַ', 'ﭏ' => 'אל', '' => 'לֹ',
	'אּ' => 'אּ', 'בּ' => 'בּ', 'גּ' => 'גּ', 'דּ' => 'דּ', 'הּ' => 'הּ', 'וּ' => 'וּ', 'זּ' => 'זּ', '﬷' => 'חּ', 'טּ' => 'טּ', 
	'יּ' => 'יּ', 'ךּ' => 'ךּ', 'כּ' => 'כּ', 'לּ' => 'לּ', '﬽' => 'םּ', 'מּ' => 'מּ', '﬿' => 'ןּ', 'נּ' => 'נּ', 'סּ' => 'סּ', 
	'﭂' => 'עּ', 'ףּ' => 'ףּ', 'פּ' => 'פּ', '﭅' => 'ץּ', 'צּ' => 'צּ', 'קּ' => 'קּ', 'רּ' => 'רּ', 'שּ' => 'שּ', 'תּ' => 'תּ', 
	'וֹ' => 'וֹ', 'בֿ' => 'בֿ', 'כֿ' => 'כֿ', 'פֿ' => 'פֿ',
});

# Latin ligatures
$_ = s_lut($_, {
	'ﬀ' => 'ff', 'ﬁ' => 'fi', 'ﬂ' => 'fl', 'ﬃ' => 'ffi', 'ﬄ' => 'ffl', 'ﬅ' => 'ſt', 'ﬆ' => 'st', # '🙰' => 'et', '🙱' => 'et',
	'Ǳ' => 'DZ', 'ǲ' => 'Dz', 'ǳ' => 'dz', 'Ǆ' => 'DŽ', 'ǅ' => 'Dž', 'ǆ' => 'dž', 
	'Ĳ' => 'IJ', 'ĳ' => 'ij', 'Ǉ' => 'LJ', 'ǈ' => 'Lj', 'ǉ' => 'lj', 'Ǌ' => 'NJ', 'ǋ' => 'Nj', 'ǌ' => 'nj', 
});


# Try to fix RLE/PDF (dumb BIDI encoding in PDFs)
if (/[\x{202A}-\x{202C}]/) {
	# Place lines with [RLE][PDF] inside [LRE][PDF] context
	# and recursively pop embedded bidi formating
	s/\x{200F}\x{202C}\n/\x{200F}\x{202C} /g;
	# Try to analyze context:
	my $t1 = () = (/^(?P<rec>[\x{202A}\x{202B}](?&rec)*[\x{202C}]|[^\x{202A}-\x{202C}\n]++)$/gm);
	my $t2 = () = (/^(?P<rec>[\x{202A}\x{202B}](?&rec)*[\x{202C}]|[^\x{202A}-\x{202C}\n]++){2,}$/gm);
	print STDERR "Got $t1/$t2 single/multiple embedded blocks.\n" if ($debug);
	if ($t1<=$t2*10) {
		s/^(.+)$/\x{202A}$1\x{202C}/gm 
	} else {
		s/(?P<rec>[\x{202A}\x{202B}](?:[^\x{202A}-\x{202C}\n]*|(?&rec))*[\x{202C}])\n*/$1\n/gm;
	}
	# s/^(.*?\x{202B}.*?\x{202C}.*)$/\x{202A}$1\x{202C}/gm;
	s/([\x{202A}\x{202B}](?:[^\x{202A}-\x{202C}]*|(?0))*\x{202C})/&pop_embedded($1)/ge;
}

# Throw away remaining BIDI characters
tr/\x{200E}\x{200F}\x{202A}-\x{202E}\x{2066}-\x{2069}//d;

# Strange typos in reshumot (PDF)
s/(?<!ש)[\x{05C1}\x{05C2}]+//gm;

$t1 = () = (/^[45T]+$/mg);
$t2 = () = (/\n/mg);
if ($t1>$t2/100) {
	s/^\d? ?([TPF]\d?)+ ?\d?$//mg;
}

# Check if we've got all parentheses wrong.
$t1 = () = (/[^()\n]*\)[^()\n]+\(/gm);
$t2 = () = (/[^()\n]\([^()\n]+\)/gm);
# print STDERR "got $t1 and $t2.\n";
if ($t1 > $t2) {
	tr/([{<>}])/)]}><{[(/;
}

s/^\.(\d[\d\-]*)$/$1./gm;
s/^(\d)\n+\.\n/$1\.\n/gm;

s/\n("?\(\D.{0,2}\))\n([^\(].*)\n(\(\d.{0,2}\))\n/\n$1 $3 $2\n/g;
while (s/\n(.*)\n("?\(.{1,2}\)|\*|[0-9]|[1-9].?\.)\n/\n$2 $1\n/g) {}


# Clean HTML markups
s/<style.*?<\/style>//gsi;
s/\s*\n\s*/ /g if /<\/p>/i;
s/<br\/?>/\n/gi;
s/<\/p>/\n\n/gi;
s/<\/?(?:".*?"|'.*?'|[^'">]*+)*>//g;
$_ = unescape_text($_);

$_ = s_lut($_, { 
	'½' => '¹⁄₂', '⅓' => '¹⁄₃', '⅔' => '²⁄₃', '¼' => '¹⁄₄', '¾' => '³⁄₄', 
	'⅕' => '¹⁄₅', '⅙' => '¹⁄₆', '⅐' => '¹⁄₇', '⅛' => '¹⁄₈', '⅑' => '¹⁄₉', '⅒' => '¹⁄₁₀'
});

# Clean WIKI markups
# s/'''//g;
# s/^ *=+ *(.*?) *=+ *$/$1/gm;
# s/^[:;]+-? *//gm;

tr/\r//d;          # Remove CR
tr/\t\xA0/ /;      # Tab and hardspace are whitespaces
s/^ +//mg;         # Remove redundant whitespaces
s/ +$//mg;         # Remove redundant whitespaces
s/ {2,}/ /g;       # Pack  long spaces
s/\n{2,}/\n/g;     # Chop two+ linefeeds
s/\f\n?/\n \n/g;   # Keep FF as two linefeeds
s/^\n+//s;         # Remove first and last linefeeds
s/\n*$/\n/s;

# Special corrections
s/(?<=\S) (?=[,.:;])//g;  # Remove redundant whitespaces
s/(?<!')''(?!')/"/g;
s/("[א-ת])(\d{4})[-]/$1-$2/g;
s/^[.](\d.*?) +/$1. /gm;
s/(\S[([\-]) /$1/gm;
s/(?<=[א-ת]\b)( -| -)(?=[0-9])/-/g;
s/(?<=[\(\[]) //g;
s/ (?=[\)\]])//g;
s/ " -/" -/g;
s/(^| )" /"/gm;
s/ (?="[.,:;])//g;
s/ (?='[ .,:;])//g;
s/^([:]++-?)(?=\S)/$1 /gm;
s/(?<=[א-ת]-)(\d{1,2})((19|20)\d\d)(?!\d)/$2 $1/gm;

s/([⁰¹²³⁴-⁹]+\⁄[₀-₉]+)(\d+)/$2$1/g;
s/%(\d*[⁰¹²³⁴-⁹]+\⁄[₀-₉]+|\d+\/\d+|\d+(\.\d+)?)/$1%/g;
s/(\S)(\d+(?:\.\d+)?)-(\S)/$1-$2 $3/g;
s/\b(\d+(?:\.\d+)?)[Xx](\d+(?:\.\d+)?)\b/$2×$1/g;

s/^לתחילת העמוד$//gm;

print $_; 
exit;
1;

sub s_lut {
	my $str = shift;
	my $table = shift;
	my $keys = join('', keys(%{$table}));
#	print STDERR "Keys are |$keys|\n";
	$str =~ s/([$keys])/$table->{$1}/ge;
	return $str;
}


sub unescape_text {
	my $_ = shift;
	my %table = ( 'quot' => '"', 'lt' => '<', 'gt' => '>', 'ndash' => '–', 'nbsp' => ' ', 'apos' => "'", 
		'lrm' => "\x{200E}", 'rlm' => "\x{200F}", 'shy' => '&null;',
		'deg' => '°', 'plusmn' => '±', 'times' => '×', 'sup1' => '¹', 'sup2' => '²', 'sup3' => '³', 'frac14' => '¼', 'frac12' => '½', 'frac34' => '¾', 'alpha' => 'α', 'beta' => 'β', 'gamma' => 'γ', 'delta' => 'δ', 'epsilon' => 'ε',
	);
	s/&#(\d+);/chr($1)/ge;
	s/(&([a-z]+);)/($table{$2} || $1)/ge;
	s/&null;//g;
	s/&amp;/&/g;
	return $_;
}


sub pop_embedded {
	my $_ = shift; my $type = shift // '';
	
	# dump_stderr("pop_embedded :|$_|\n");
	# 0x202A is [LRE]; 0x202B is [RLE]; 0x202C is [PDF].
	if (/^([\x{202A}\x{202B}])(.*)[\x{202C}]$/) {
		$type .= $1; $_ = $2;
		my @arr = (m/([^\x{202A}-\x{202C}]+|[\x{202A}\x{202B}](?0)*[\x{202C}])/g);
		if ($type eq "\x{202A}" && scalar(@arr)>1) {
			# dump_stderr("pop_embedded: |" . join('|',@arr) . "|\n") if ($#arr>0);
			# s/^([^\x{202A}-\x{202C}]+)$/\x{202A}$1\x{202C}/ for @arr;
		}
		dump_stderr("pop_embedded($type): |" . join('|',@arr) . "|\n") if ($#arr>0);
		@arr = map { pop_embedded($_,$type) } @arr;
		dump_stderr("pop_embedded($type): |" . join('|',@arr) . "|\n") if ($#arr>0);
		@arr = reverse(@arr) if ($type eq "\x{202A}");  # [LRE]$_[PDF]
		return join('',@arr);
	} 
	if ($type =~ /\x{202B}/) {        # within RLE block
	# if (substr($type,-1) eq "\x{202B}") {
		tr/([{<>}])/)]}><{[(/ if ($variant==0 || $variant==2);
	}
	if (substr($type,-1) eq "\x{202A}") { # LRE block
		my $soft = '(?:[ \t.\,:;?!#$%^&*"\'\\-–\(\)\[\]{|}<>א-ת]|\d[\d.,\\/\\-:]*\d[%$]?|\d)';
		my ($pre,$mid,$post) = (m/^($soft*+)(.*?)($soft*)$/);
		$pre = join('',reverse(split /($soft)/, $pre));
		$post = join('',reverse(split /($soft)/, $post));
		$_ = $pre . $mid . $post;
		$_ = $post . $mid . $pre;
		tr/([{<>}])/)]}><{[(/ if ($variant==3 || $variant==2);
		# s/^($soft*)(.*?)($soft*)$/reverse($3).$2.reverse($1)/e;
	}
	return $_;
}

sub dump_stderr {
	return if (!$debug);
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