#!/usr/bin/perl -w

no if $] >= 5.018, warnings => 'experimental';
use strict;
no strict 'refs';
use English;
use utf8;
no warnings 'misc';

use Data::Dumper;
use Getopt::Long;
use constant { true => 1, false => 0 };
sub max($$) { $_[$_[0] < $_[1]] }
sub min($$) { $_[$_[0] > $_[1]] }

our ($variant, $debug, $raw);
$variant = 1;
$debug = 0;
$raw = 0;

our $LRE = "\x{202A}"; our $LRM = "\x{200E}";
our $RLE = "\x{202B}"; our $RLM = "\x{200F}";
our $PDF = "\x{202C}";

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
	binmode STDOUT, ":utf8";
	binmode STDERR, ":utf8";
	local $/;
	$_ = <$FIN>;
} else {
	binmode STDIN, ":utf8";
	binmode STDOUT, ":utf8";
	binmode STDERR, ":utf8";
	$_ = join('', <STDIN>);
}

##### Various Encodings #####

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

if (/[\xE0-\xFA]{5,}/) { # Convert Windows-1255 codepage
	# Convert Windows-1255 to Unicode
	tr/\xE0-\xFA/א-ת/;
	tr/\xC0-\xCF/\x{05B0}-\x{05BF}/;
}

if ((/[A-Z]/) and (/\[/) and !(/[א-ת]/)) {
	tr/B-V/א-ת/;
	tr/WXY\[Z\\/ץצקשרת/;
	tr/=/–/;
	tr/e/וּ/;
	s/([א-ת])\n?\]/ִ$1/;
	s/([א-תוּ\x{05B0}-\x{05BD}])/$RLE$1$PDF/g;
}

##### Bidi corrections #####

s/([\x{05B0}-\x{05BD}]+)([א-ת])/$2$1/g if (/$RLE\x{05BC}[א-ת]/);

# Try to fix RLE/PDF (dumb BIDI encoding in PDFs)
if (/[$LRE$RLE$PDF]/) {
	# Place lines with [RLE][PDF] inside [LRE][PDF] context
	# and recursively pop embedded bidi formating
	s/(?<=$RLM$PDF)\n/ /g;
	# Try to analyze context:
	my $t1 = () = (/^(?P<rec>[$LRE$RLE](?&rec)*[$PDF]|[^$LRE$RLE$PDF\n]++)$/gm);
	my $t2 = () = (/^(?P<rec>[$LRE$RLE](?&rec)*[$PDF]|[^$LRE$RLE$PDF\n]++){2,}$/gm);
	print STDERR "Got $t1/$t2 single/multiple embedded blocks.\n" if ($debug);
	if ($t1<=$t2*10) {
		s/^(.+)$/$LRE$1$PDF/gm;
	} else {
		s/(?P<rec>[$LRE$RLE](?:[^$LRE$RLE$PDF\n]*|(?&rec))*[$PDF])\n*/$1\n/gm;
	}
	# s/^(.*?$RLE.*?$PDF.*)$/$LRE$1$PDF/gm;
	s/([$LRE$RLE](?:[^$LRE$RLE$PDF]*|(?0))*$PDF)/&pop_embedded($1)/ge;
	# Use internal seperators for very long words
	# s/([א-ת\-.,;:'"␀]{10,})/ $1 =~ tr|␀| |r /ge;
	s/([^ ␀\n]{2,}␀[^ \n]{5,}[א-ת]{2,})/ $1 =~ s\␀|(?<=[א-ת])(?=[^␀ א-ת])|(?<=[^␀ א-ת])(?=[א-ת])\ \gr /ge;
	tr/␀//d;
}

# Throw away remaining BIDI characters
tr/\x{200E}\x{200F}\x{202A}-\x{202E}\x{2066}-\x{2069}//d;
# Join seperated lines with ␡ marker
while (s/^(.*)\n␡\n(\(\S+\)|\d\S*\.|\d+)$/$2 $1/gm) {}
s/\n␡\n/ /g;

##### Characters-level corrections #####

# Keep ndash between hebrew words if not all words are seperated with ndash
# s/(?<=[א-ת])–(?=[א-ת])/&ndash;/g if /[א-ת][\־\-][א-ת]/;

# General cleanup
s/ ?\t\n/\n␡\n/g;             # This LF will be later removed
s/(\n\r|\r\n|\r)/\n/g;        # Remove CR
tr/\x07\x08\x7F//d;           # Remove BELL, BS and DEL
tr/\x11/\t/;                  # VT is Tab
tr/\xA0\x{2000}-\x{200A}\x{202F}\x{205F}\x{2060}/ /; # Typographic spaces
tr/\x{200B}-\x{200D}//d;      # Zero-width spaces and ZWJ
tr/־–—‒―/-/;                  # Convert typographic dashes
tr/‑/–/;
# s/(?<![א-ת\x{05B0}-\x{05BD}])\x{05BF}/-/g; # Rafe (U+05BF) misused as dash
s/\x{05BF} ?/-/g;             # Rafe (U+05BF) misused as dash
tr/\xAD\x96\x97/-/;           # Convert more typographic dashes
tr/״”“„‟″‶/"/;                # Convert typographic double quotes
tr/`׳’‘‚‛′‵/'/;               # Convert typographic single quotes
tr/;/;/;                      # Convert wrong OCRed semicolon
s/(\x{FFFD}{2,})/' ' . ',' x length($1) . ' '/ge; # dots
s/,( ¸){2,}|,{3,}/ /g;        # dots seperator
tr/¸/,/;                      # Convert Cedilla used for comma
tr/\x{F0A8}\x{F063}/□/;       # White square (special font)
tr/º/°/;                      # ordinal indicatior meant to be degree sign
s/…/.../g;
s/()(?:(\n)|)[\x{FEFF}\x{FFFC}-\x{FFFF}](?:(\n)|)/$+/g;    # Unicode placeholders and junk
tr/\x{F000}-\x{F031}\x{F07F}/□/;      # Replacement font codes, cannot recover without OCR.

# Hebrew ligatures and alternative forms
tr/ﬠﬡﬢﬣﬤﬥﬦﬧﬨ/עאדהכלםרת/;
# Keep hebrew plus sign - tr/﬩/+/;
# Keep math symbols     - tr/ℵℶℷℸ/אבגד/;
$_ = s_lut($_, {
	'אּ' => 'אּ', 'בּ' => 'בּ', 'גּ' => 'גּ', 'דּ' => 'דּ', 'הּ' => 'הּ', 'וּ' => 'וּ', 'זּ' => 'זּ', '﬷' => 'חּ', 'טּ' => 'טּ', 
	'יּ' => 'יּ', 'ךּ' => 'ךּ', 'כּ' => 'כּ', 'לּ' => 'לּ', '﬽' => 'םּ', 'מּ' => 'מּ', '﬿' => 'ןּ', 'נּ' => 'נּ', 'סּ' => 'סּ', 
	'﭂' => 'עּ', 'ףּ' => 'ףּ', 'פּ' => 'פּ', '﭅' => 'ץּ', 'צּ' => 'צּ', 'קּ' => 'קּ', 'רּ' => 'רּ', 'שּ' => 'שּ', 'תּ' => 'תּ', 
	'שׁ' => 'שׁ', 'שׂ' => 'שׂ', 'שּׁ' => 'שּׁ', 'שּׂ' => 'שּׂ', 'אַ' => 'אַ', 'אָ' => 'אָ', 'יִ' => 'יִ', 'ײַ' => 'ײַ', 'ﭏ' => 'אל', '' => 'לֹ',
	'וֹ' => 'וֹ', 'בֿ' => 'בֿ', 'כֿ' => 'כֿ', 'פֿ' => 'פֿ',
});

# Latin ligatures
$_ = s_lut($_, {
	'ﬀ' => 'ff', 'ﬁ' => 'fi', 'ﬂ' => 'fl', 'ﬃ' => 'ffi', 'ﬄ' => 'ffl', 'ﬅ' => 'ſt', 'ﬆ' => 'st', # '🙰' => 'et', '🙱' => 'et',
	'Ǳ' => 'DZ', 'ǲ' => 'Dz', 'ǳ' => 'dz', 'Ǆ' => 'DŽ', 'ǅ' => 'Dž', 'ǆ' => 'dž', 
	'Ĳ' => 'IJ', 'ĳ' => 'ij', 'Ǉ' => 'LJ', 'ǈ' => 'Lj', 'ǉ' => 'lj', 'Ǌ' => 'NJ', 'ǋ' => 'Nj', 'ǌ' => 'nj', 
	'ȸ' => 'db', 'ȹ' => 'qp', 'Ꝡ' => 'VY', 'ꝡ' => 'vy',
	# 'Œ' => 'OE', 'œ' => 'oe', 'Æ' => 'AE', 'æ' => 'ae', # Also ǢǣǼǽÆ̀æ̀Æ̂æ̂Æ̃æ̃... Also ꜲꜳꜴꜵꜶꜷꜸꜹꜼꜽꝎꝏ and ...
	# 'ʩ' => 'fŋ', 'ʪ' => 'ls', 'ʫ' => 'lz', 'ɮ' => 'lʒ', 'ʨ' => 'tɕ', 'ʦ' => 'ts', 'ꭧ' => 'tʂ', 'ꭦ'=> 'dʐ', 'ʧ' => 'tʃ', 
	# 'ƒ' => '<i>f</i>', 'Ƒ' => '<i>F</i>',
});

# Strange typos in reshumot (PDF)
s/(?<=[0-9])(שׂ| שׂ )(?=[0-9])/×/g;
s/(?<!ש)[\x{05C1}\x{05C2}]+//g;

# Special encoding in rare cases
$t1 = () = (/^[45T]+$/mg);
$t2 = () = (/\n/mg);
if ($t1>$t2/100) {
	s/^\d? ?([TPF]\d?)+ ?\d?$//mg;
}

# Check if we got all parentheses wrong
$t1 = () = (/[^()\n]*\n?\)\n?[^()\n]+\n?\(/gm);
$t2 = () = (/[^()\n]\n?\(\n?[^()\n]+\n?\)/gm);
# print STDERR "got $t1 and $t2.\n";
if ($t1 > $t2) {
	tr/([{<>}])/)]}><{[(/;
}


# Clean HTML markups
s/\n/ /g if (/<html>/ and /<body/);
s/<style.*?<\/style>//gsi;
s/\s*\n\s*/ /g if /<\/p>/i;
s/<br\/?>/\n/gi;
s/<\/(div|td|p|tr|th).*?>/\n/gi; # Block elements
# s/<\/(p|tr|th).*?>/\n\n/gi; # Block elements
s/<\/?(?:".*?"|'.*?'|[^'">]*+)*>//g;
$_ = unescape_text($_);

if ($raw) { 
	s/[␀␡]//g;
	print $_; exit 0; 
}

##### Complex corrections rules #####

$_ = fix_footnotes($_);

s/\f/␌\f\n␊\n/gm;
s/^ *\t+ *(.+)\n(\([^()]+\))$/$2 $1/gm;
s/^\.(\d[\d\-]*)$/$1./gm;
s/^(\d[0-9א-ת]*)\n+\.\n/$1\.\n/gm;
# s/\n([0-9]+|-)\n/ $1 /g;


# Join lines, but not all
# - Don't join lines ending with dot, colon etc.
# - Don't join short lines with colon which may be section title.
s/^ +/␊/gm;
s/^(\.\.\.|[,.:;])(?!\.{3,})/␡$1/gm;
s/([\(\[])$/$1␡/gm;
s/^(\(.+ .+\))$/␊$1␊/gm;
s/([.:;0-9])$/$1␊/gm;
s/^(_+)/␊$1/gm;
s/^(.*[:].*[א-ת].*?)␊?$/␊$1␊/gm;
s/^(")\n([^"\n]+)\n(")$/␊$1$2$3/gm;
s/^("[^"\n]+)\n(")$/$1$2/gm;
s/^([0-9][0-9א-ת]*\.)␊?/␡␡ $1␊/gm;
s/^(-|[()0-9.,]+[;,]?|[א-ת "]+)(?=␊?$)/␡ $1 ␡/gm;
s/([א-ת][0-9,\- ']*\n)((- )?[א-ת]|[0-9][א-ת0-9, \-\[\]'"()]*␊?$)/$1␡ $2/gm;

s/ ␡\n␊?␡(?! )|(?<![ ␡])\n␡//g;
s/( ␡\n␡ | ␡\n|\n␡ )/ /g;
s/ *(␊ *\n?)+/␊\n/gm;
s/^([^\n␊]+[^.:;\n␊])(?:␊\n|)␡ *([^\n␊]*)(␊?)$/$2 $1$3/gm;   # ␡␡ is a special mark when concatenating article numerals
s/␡//g;

# # Don't join short lines without puncuation marks
# s/^([א-ת]+ [א-ת0-9 ]{1,20})$/␊$1␊/gm;

# s/(?<=[א-ת'])\n((- )?['"]?[א-ת]|[0-9][א-ת0-9, \-\[\]'"()]*␊?$)/ $1/gm;
# s/(?<=[א-ת'"])\n((- )?[א-ת'"][א-ת0-9, \-\[\]'"()]*[:;.]?␊?|[0-9][א-ת0-9, \-\[\]'"()]*␊?)$/ $1/gm;
# s/(?<=[א-ת0-9'"])\n([א-ת'"][א-ת0-9, \-\[\]'"()]*[;.]?|[0-9][א-ת0-9, \-\[\]'"()]*)$/ $1/gm;
s/[␊␌]//g;  # But keep \f.


# Replace vulgar fractions
s/([½⅓⅔¼¾⅕⅖⅗⅘⅙⅚⅐⅛⅜⅝⅞⅑⅒↉])(\d+)/$2$1/g;
$_ = s_lut($_, { 
	'½' => '¹⁄₂', '⅓' => '¹⁄₃', '⅔' => '²⁄₃', '¼' => '¹⁄₄', '¾' => '³⁄₄', 
	'⅕' => '¹⁄₅', '⅖' => '²⁄₅', '⅗' => '³⁄₅', '⅘' => '⁴⁄₅', '⅙' => '¹⁄₆', '⅚' => '⁵⁄₆',  
	'⅐' => '¹⁄₇', '⅛' => '¹⁄₈', '⅜' => '³⁄₈', '⅝' => '⁵⁄₈', '⅞' => '⁷⁄₈', 
	'⅑' => '¹⁄₉', '⅒' => '¹⁄₁₀', '↉' => '⁰⁄₃'
});

# Replcace Mathematical Alphanumeric Symbols (and create <b/i/tt> tags if nessesary)
$_ = fix_symbols($_) if (/[\x{1D400}-\x{1D7FF}]/);

# Escape control characters if found in the PDF stream...
tr/\x00-\x08\x0b\x0d-\x1F\x7F/␀-␉␋␍-␟␡/;

# [Don't] Clean WIKI markups
# s/'''//g;
# s/^ *=+ *(.*?) *=+ *$/$1/gm;
# s/^[:;]+-? *//gm;

tr/\t\xA0/ /;      # Tab and hardspace are whitespaces
s/^ +//mg;         # Remove redundant whitespaces
s/ +$//mg;         # Remove redundant whitespaces
s/ {2,}/ /g;       # Pack  long spaces
s/\n{2,}/\n/g;     # Chop two+ linefeeds
s/\f\n*/\f\n\n/g;  # Keep FF as two linefeeds
s/\n{3,}/\n\n/g;   # 
s/^\n+//s;         # Remove first and last linefeeds
s/\n*$/\n/s;

# Special corrections
s/(?<=\S) (\.\.\.|[,.:;])(?!\.{3,})/$1/g;  # Remove redundant whitespaces
s/(?<!')''(?!')/"/g;
s/("[א-ת])(\d{4})[-]/$1-$2/g;
s/^[.](\d.*?) +/$1. /gm;
s/^(\d.*?)\n\.\n/$1. /gm;
s/([א-ת0-9A-z:][([\-]) /$1/gm;
s/(?<=[א-ת]\b)( -| -)(?=[0-9])/-/g;
s/(?<=[\(\[]) //g;
s/ (?=[\)\]])//g;
s/"- |" -(?=[א-ת])|"-(?=[א-ת])/" - /g;
s/ (?=" -)//g;
s/(^| )" /"/gm;
s/ (?="[.,:;])//g;
s/ (?='[ .,:;])//g;
s/^([:]++-?)(?=\S)/$1 /gm;
s/(?<=[א-ת]-)(\d{1,2})((19|20)\d\d)(?!\d)/$2 $1/gm;

s/([⁰¹²³⁴-⁹]+\⁄[₀-₉]+)(\d+)/$2$1/g;
s/%(\d*[⁰¹²³⁴-⁹]+\⁄[₀-₉]+|\d+\/\d+|\d+(\.\d+)?)/$1%/g;
s/([א-ת])(\d+(?:\.\d+)?)-([א-ת])/$1-$2 $3/g;
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
	local $_ = shift;
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
	local $_ = shift; my $type = shift // '';
	
	# 0x202A is [LRE]; 0x202B is [RLE]; 0x202C is [PDF].
	if (/^([$LRE$RLE])(.*)[$PDF]$/) {
		$type .= $1; $_ = $2;
		s/(?<=[$PDF])(?=[$LRE$RLE])/␀/g;
		# dump_stderr("pop_embedded: got |$_|\n");
		my @arr = (m/([^$LRE$RLE$PDF]+|[$LRE$RLE](?0)*[$PDF])/g);
		if ($type eq "$LRE" && scalar(@arr)>1) {
			# dump_stderr("pop_embedded: |" . join('|',@arr) . "|\n") if ($#arr>0);
			# s/^([^$LRE$RLE$PDF]+)$/$LRE$1$PDF/ for @arr;
		}
		# dump_stderr("pop_embedded: ($type) |" . join('|',@arr) . "|\n") if ($#arr>0);
		@arr = map { pop_embedded($_,$type) } @arr;
		@arr = reverse(@arr) if ($type eq "$LRE");  # [LRE]$_[PDF]
		# dump_stderr("pop_embedded: ret |" . join('|',@arr) . "|\n") if ($#arr>0);
		return join('',@arr);
	} 
	if ($type =~ /$RLE/) {        # within RLE block
	# if (substr($type,-1) eq "$RLE") {
		tr/([{<>}])/)]}><{[(/ if ($variant==0 || $variant==2);
	}
	if (substr($type,-1) eq "$LRE") { # LRE block
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


# fix_symbols: Replcace Mathematical Alphanumeric Symbols (and create <b/i/tt> tags if nessesary)
sub fix_symbols {
	local $_ = shift;
	# Make symbols linear in unicode space
	tr/ℬℰℱℋℐℒℳℛℯℊℴ/𝒝𝒠𝒡𝒣𝒤𝒧𝒨𝒭𝒺𝒼𝓄/;
	tr/ℭℌℑℜℨ/𝔆𝔋𝔋𝔕𝔝/;
	tr/ℂℍℕℙℚℝℤ/𝔺𝔿𝕅𝕇𝕈𝕉𝕑/;
	tr/ℎ/𝑕/;
	
	# Normal letters			# tr/𝖠-𝖹𝖺-𝗓𝟢-𝟫𝔄-𝔝𝔞-𝔷/A-Za-z0-9A-Za-z/;
	tr/𝖠-𝗓𝟢-𝟫/A-Za-z0-9/;
	tr/𝔄-𝔷/A-Za-z/;
	# Bold letters				# tr/𝐀-𝐙𝐚-𝐳𝟎-𝟗𝗔-𝗭𝗮-𝘇𝟬-𝟵𝕬-𝖅𝖆-𝖟/A-Za-z0-9A-Za-z0-9A-Za-z/;
	s|([𝐀-𝐳𝟎-𝟗]+)|sprintf("<b>%s</b>", $1 =~ tr/𝐀-𝐳𝟎-𝟗/A-Za-z0-9/r)|ge;
	s|([𝗔-𝘇𝟬-𝟵]+)|sprintf("<b>%s</b>", $1 =~ tr/𝗔-𝘇𝟬-𝟵/A-Za-z0-9/r)|ge;
	s|([𝕬-𝖟]+)|sprintf("<b>%s</b>", $1 =~ tr/𝕬-𝖟/A-Za-z/r)|ge;
	s|([𝚨-𝛀𝛂-𝛚𝛁𝟊𝛛𝛜𝛝𝛞𝛟𝛠𝛡𝟋]+)|sprintf("<b>%s</b>", $1 =~ tr/𝚨-𝛀𝛂-𝛚𝛁𝟊𝛛𝛜𝛝𝛞𝛟𝛠𝛡𝟋/Α-Ωα-ω∇Ϝ∂ϵϑϰϕϱϖϝ/r)|ge;
	s|([𝝖-𝝮𝝰-𝞈𝝯𝞉𝞊𝞋𝞌𝞍𝞎𝞏]+)|sprintf("<b>%s</b>", $1 =~ tr/𝝖-𝝮𝝰-𝞈𝝯𝞉𝞊𝞋𝞌𝞍𝞎𝞏/Α-Ωα-ω∇∂ϵϑϰϕϱϖ/r)|ge;
	# Italic letters			# tr/𝐴-𝑍𝑎-𝑧𝘈-𝘡𝘢-𝘻𝒜-𝒵𝒶-𝓏/A-Za-zA-Za-zA-Za-z/;
	s|([𝐴-𝑧𝚤𝚥]+)|sprintf("<i>%s</i>", $1 =~ tr/𝐴-𝑧𝚤𝚥/A-Za-zıȷ/r)|ge;
	s|([𝘈-𝘻]+)|sprintf("<i>%s</i>", $1 =~ tr/𝘈-𝘻/A-Za-z/r)|ge;
	s|([𝒜-𝓏]+)|sprintf("<i>%s</i>", $1 =~ tr/𝒜-𝓏/A-Za-z/r)|ge;
	s|([𝛢-𝛺𝛼-𝜔𝛻𝜕𝜖𝜗𝜘𝜙𝜚𝜛]+)|sprintf("<b>%s</b>", $1 =~ tr/𝛢-𝛺𝛼-𝜔𝛻𝜕𝜖𝜗𝜘𝜙𝜚𝜛/Α-Ωα-ω∇∂ϵϑϰϕϱϖ/r)|ge;
	# Bold Italic				# tr/𝑨-𝒁𝒂-𝒛𝘼-𝙕𝙖-𝙯𝓐-𝓩𝓪-𝔃/A-Za-zA-Za-zA-Za-z/;
	s|([𝑨-𝒛]+)|sprintf("<b><i>%s</i></b>", $1 =~ tr/𝑨-𝒛/A-Za-z/r)|ge;
	s|([𝘼-𝙯]+)|sprintf("<b><i>%s</i></b>", $1 =~ tr/𝘼-𝙯/A-Za-z/r)|ge;
	s|([𝓐-𝔃]+)|sprintf("<b><i>%s</i></b>", $1 =~ tr/𝓐-𝔃/A-Za-z/r)|ge;
	s|([𝜜-𝜴𝜶-𝝎𝜵𝝏𝝐𝝑𝝒𝝓𝝔𝝕]+)|sprintf("<b><i>%s</i></b>", $1 =~ tr/𝜜-𝜴𝜶-𝝎𝜵𝝏𝝐𝝑𝝒𝝓𝝔𝝕/Α-Ωα-ω∇∂ϵϑϰϕϱϖ/r)|ge;
	s|([𝞐-𝞨𝞪-𝟂𝞩𝟃𝟄𝟅𝟆𝟇𝟈𝟉]+)|sprintf("<b><i>%s</i></b>", $1 =~ tr/𝞐-𝞨𝞪-𝟂𝞩𝟃𝟄𝟅𝟆𝟇𝟈𝟉/Α-Ωα-ω∇∂ϵϑϰϕϱϖ/r)|ge;
	# Monospace					# tr/𝙰-𝚉𝚊-𝚣𝟶-𝟿/A-Za-z0-9/;
	s|([𝙰-𝚣𝟶-𝟿]+)|sprintf("<tt>%s</tt>", $1 =~ tr/𝙰-𝚣𝟶-𝟿/A-Za-z0-9/r)|ge;
	# Monospace Bold			# tr/𝔸-𝕑𝕒-𝕫𝟘-𝟡/A-Za-z0-9/;
	s|([𝔸-𝕫𝟘-𝟡]+)|sprintf("<tt><b>%s</b></tt>", $1 =~ tr/𝔸-𝕫𝟘-𝟡/A-Za-z0-9/r)|ge;
	
	tr/΢/ϴ/;
	s/<\/(i|b|tt)><\/(i|b|tt)>([ \n]*)<\2><\1>/$3/gs;
	s/<\/(i|b|tt)>([ \n]*)<\1>/$2/g;
	return $_;
}


# fix_footnotes: Change order of lines in case of incorrect break due to numeric comment reference.
sub fix_footnotes {
	my $text = shift;
	# Check if comments fix is required.
	my ($t1, $t2);
	$t1 = () = ($text =~ /\d{4}[ ␊\n]+\d{1,2}\)?[;,.]/gm);
	$t2 = () = ($text =~ /^\d{1,2}\)?[;,.].*[␊\n]+.*\d{4}/gm);
	print STDERR "fix_footnotes, before: $t1 correct, $t2 incorrect\n" if ($debug);
	if ($t1>$t2) { return $text; }
	my ($cnt, $p_cnt1, $p_cnt2, $restart, $flex);
	$cnt = $p_cnt1 = $p_cnt2 = 1; $restart = true; $flex = 1;
	my @lines = split(/\n/, $text);
	for (my $i = 0; $i < scalar(@lines)-1; $i++) {
		local $_ = $lines[$i];
		if (/בתוקף/ || $lines[$i+1] =~ /בתוקף/) { $restart = true; }
		if (/\f/) {
			($p_cnt2, $p_cnt1) = ($p_cnt1, $cnt);
			$cnt = max($p_cnt1, $cnt);
			next;
		}
		/^([0-9]+)(?|(\)?[;,. ])(.*)|()())$/ || next;
		my ($n, $s, $t) = (scalar($1), $2, $3);
		next if (/^\d+\.? (ס"ח|ק"ת|י"פ)|^\d+[,.]\d+/);
		if ($n>9999 && $lines[$i+1] =~ /, ה?תש.?".-$/) {
			$n =~ /^(\d{4})(\d+)$/;
			$n = scalar($2);
			$flex = min($flex+1, 2);
		}
		elsif ($s =~ /^[. ]?$/ && $lines[$i+1] !~ /\d{4} *$/) {
			$flex = min($flex+1, 2);
			next;
		}
		next unless (($n>=$cnt && $n<=$cnt+$flex) || ($restart && $n < 2) || $n==$p_cnt2);
		print STDERR "fix_footnotes: replacing |${lines[$i]}| and |${lines[$i+1]}|\n" if ($debug);
		$cnt = $n; $restart = false; $flex = 1;
		($lines[$i], $lines[$i+1]) = ("$lines[$i+1]␊", "<!-- (footnote) --> $lines[$i]␊");
		$i++; $cnt++;
	}
	$text = join("\n", @lines);
	$t1 = () = ($text =~ /\d{4}[ ␊\n]+(<!--.*?--> *|)\d{1,2}\)?[;,.]/gm);
	$t2 = () = ($text =~ /^\d{1,2}\)?[;,.].*[␊\n]+.*\d{4}/gm);
	print STDERR "fix_footnotes, after: $t1 correct, $t2 incorrect\n" if ($debug);
	return $text;
}


sub dump_stderr {
	return if (!$debug);
	local $_ = shift;
	
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
