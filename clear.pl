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

if (/\x{F8FF}/) { # Fix f*cked-up macos charmap
	# Convert Unicode to Mac OS Roman
	tr/\x{00C4}\x{00C5}\x{00C7}\x{00C9}\x{00D1}\x{00D6}\x{00DC}\x{00E1}\x{00E0}\x{00E2}\x{00E4}\x{00E3}\x{00E5}\x{00E7}\x{00E9}\x{00E8}\x{00EA}\x{00EB}\x{00ED}\x{00EC}\x{00EE}\x{00EF}\x{00F1}\x{00F3}\x{00F2}\x{00F4}\x{00F6}\x{00F5}\x{00FA}\x{00F9}\x{00FB}\x{00FC}\x{2020}\x{00B0}\x{00A2}\x{00A3}\x{00A7}\x{2022}\x{00B6}\x{00DF}\x{00AE}\x{00A9}\x{2122}\x{00B4}\x{00A8}\x{2260}\x{00C6}\x{00D8}\x{221E}\x{00B1}\x{2264}\x{2265}\x{00A5}\x{00B5}\x{2202}\x{2211}\x{220F}\x{03C0}\x{222B}\x{00AA}\x{00BA}\x{03A9}\x{00E6}\x{00F8}\x{00BF}\x{00A1}\x{00AC}\x{221A}\x{0192}\x{2248}\x{2206}\x{00AB}\x{00BB}\x{2026}\x{00A0}\x{00C0}\x{00C3}\x{00D5}\x{0152}\x{0153}\x{2013}\x{2014}\x{201C}\x{201D}\x{2018}\x{2019}\x{00F7}\x{25CA}\x{00FF}\x{0178}\x{2044}\x{20AC}\x{2039}\x{203A}\x{FB01}\x{FB02}\x{2021}\x{00B7}\x{201A}\x{201E}\x{2030}\x{00C2}\x{00CA}\x{00C1}\x{00CB}\x{00C8}\x{00CD}\x{00CE}\x{00CF}\x{00CC}\x{00D3}\x{00D4}\x{F8FF}\x{00D2}\x{00DA}\x{00DB}\x{00D9}\x{0131}\x{02C6}\x{02DC}\x{00AF}\x{02D8}\x{02D9}\x{02DA}\x{00B8}\x{02DD}\x{02DB}\x{02C7}/\x80-\xFF/;
	
	# Convert Mac OS Hebrew to Unicode, place RTL tags
	s/([\xA0-\xFF])/$RLE$1$PDF/g;
	tr/\x80-\xFF/\x{00C4}\x{FB1F}\x{00C7}\x{00C9}\x{00D1}\x{00D6}\x{00DC}\x{00E1}\x{00E0}\x{00E2}\x{00E4}\x{00E3}\x{00E5}\x{00E7}\x{00E9}\x{00E8}\x{00EA}\x{00EB}\x{00ED}\x{00EC}\x{00EE}\x{00EF}\x{00F1}\x{00F3}\x{00F2}\x{00F4}\x{00F6}\x{00F5}\x{00FA}\x{00F9}\x{00FB}\x{00FC}\x{0020}\x{0021}\x{0022}\x{0023}\x{0024}\x{0025}\x{20AA}\x{0027}\x{0029}\x{0028}\x{002A}\x{002B}\x{002C}\x{002D}\x{002E}\x{002F}\x{0030}\x{0031}\x{0032}\x{0033}\x{0034}\x{0035}\x{0036}\x{0037}\x{0038}\x{0039}\x{003A}\x{003B}\x{003C}\x{003D}\x{003E}\x{003F}\x{F86A}\x{201E}\x{F89B}\x{F89C}\x{F89D}\x{F89E}\x{05BC}\x{FB4B}\x{FB35}\x{2026}\x{00A0}\x{05B8}\x{05B7}\x{05B5}\x{05B6}\x{05B4}\x{2013}\x{2014}\x{201C}\x{201D}\x{2018}\x{2019}\x{FB2A}\x{FB2B}\x{05BF}\x{05B0}\x{05B2}\x{05B1}\x{05BB}\x{05B9}\x{05B8}\x{05B3}\x{05D0}\x{05D1}\x{05D2}\x{05D3}\x{05D4}\x{05D5}\x{05D6}\x{05D7}\x{05D8}\x{05D9}\x{05DA}\x{05DB}\x{05DC}\x{05DD}\x{05DE}\x{05DF}\x{05E0}\x{05E1}\x{05E2}\x{05E3}\x{05E4}\x{05E5}\x{05E6}\x{05E7}\x{05E8}\x{05E9}\x{05EA}\x{007D}\x{005D}\x{007B}\x{005B}\x{007C}/;
	s/(?<=[0-9])\x{202C}\x{202B}(?=[0-9])//g;
}

# General cleanup
tr/\x{2000}-\x{200A}\x{205F}/ /; # Typographic spaces
tr/\x{200B}-\x{200D}//d;  # Zero-width spaces
tr/־–—‒―/-/;        # Convert typographic dashes
tr/\xAD\x96\x97/-/; # Convert more typographic dashes
tr/״”“„‟″‶/"/;      # Convert typographic double quotes
tr/`׳’‘‚‛′‵/'/;     # Convert typographic single quotes
tr/;/;/;            # Convert wrong OCRed semicolon

tr/\x{FEFF}\x{FFFC}-\x{FFFF}//d;    # Unicode placeholders and junk

# Hebrew ligatures and alternative forms
tr/ﬠﬡﬢﬣﬤﬥﬦﬧﬨ/עאדהכלםרת/;
# Keep hebrew plus sign - tr/﬩/+/;
$_ = s_lut($_, {
	'שׁ' => 'שׁ', 'שׂ' => 'שׂ', 'שּׁ' => 'שּׁ', 'שּׂ' => 'שּׂ', 'אַ' => 'אַ', 'אָ' => 'אָ', 'יִ' => 'יִ', 'ײַ' => 'ײַ', 'ﭏ' => 'אל', 
	'אּ' => 'אּ', 'בּ' => 'בּ', 'גּ' => 'גּ', 'דּ' => 'דּ', 'הּ' => 'הּ', 'וּ' => 'וּ', 'זּ' => 'זּ', "﬷" => 'חּ', 'טּ' => 'טּ', 
	'יּ' => 'יּ', 'ךּ' => 'ךּ', 'כּ' => 'כּ', 'לּ' => 'לּ', '﬽' => 'םּ', 'מּ' => 'מּ', '﬿' => 'ןּ', 'נּ' => 'נּ', 'סּ' => 'סּ', 
	'﭂' => 'עּ', 'ףּ' => 'ףּ', 'פּ' => 'פּ', '﭅' => 'ץּ', 'צּ' => 'צּ', 'קּ' => 'קּ', 'רּ' => 'רּ', 'שּ' => 'שּ', 'תּ' => 'תּ', 
	'וֹ' => 'וֹ', 'בֿ' => 'בֿ', 'כֿ' => 'כֿ', 'פֿ' => 'פֿ', 
});

# Latin ligatures
$_ = s_lut($_, {
	'ﬀ' => 'ff', 'ﬁ' => 'fi', 'ﬂ' => 'fl', 'ﬃ' => 'ffi', 'ﬄ' => 'ffl', 'ﬅ' => 'ft', 'ﬆ' => 'st', # '🙰' => 'et', '🙱' => 'et',
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
$t1 = () = (/\).\(/g);
$t2 = () = (/\(.\)/g);
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
s/(?<=[- ])(\d{1,2})((19|20)\d\d)(?!\d)/$2 $1/gm;

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