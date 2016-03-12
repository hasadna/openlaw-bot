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

# General cleanup
tr/\x{2000}-\x{200A}\x{205F}/ /; # Typographic spaces
tr/\x{200B}-\x{200D}//d;  # Zero-width spaces
tr/־–—‒―/-/;        # Convert typographic dashes
tr/\xAD\x96\x97/-/; # Convert more typographic dashes
tr/״”“„‟″‶/"/;      # Convert typographic double quotes
tr/`׳’‘‚‛′‵/'/;     # Convert typographic single quotes
tr/;/;/;            # Convert wrong OCRed semicolon

# Hebrew ligatures and alternative forms
tr/ﬠﬡﬢﬣﬤﬥﬦﬧﬨ/עאדהכלםרת/;
# tr/﬩/+/;
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



s/\n{2,}/\n/g;

# Try to fix RLE/PDF (usually dumb bidi in PDF files)
# s/ ?([\x{202A}\x{202B}](.|(?1))\x{202C}) (?=[\x{202A}\x{202B}])/$1/g;
   # Place lines with [RLE][PDF] inside [LRE][PDF] context
   # and recursively pop embedded bidi formating
if (/[\x{202A}-\x{202C}]/) {
	s/\x{200F}\x{202C}\n/\x{200F}\x{202C} /g;
	s/^(.+)$/\x{202A}$1\x{202C}/gm;
	# s/^(.*?\x{202B}.*?\x{202C}.*)$/\x{202A}$1\x{202C}/gm;
	s/([\x{202A}\x{202B}](?:[^\x{202A}-\x{202C}]*|(?0))*\x{202C})/&pop_embedded($1)/ge;
}

tr/\x{200E}\x{200F}\x{202A}-\x{202E}\x{2066}-\x{2069}//d; # Throw away BIDI characters

my $t1 = () = (/\).\(/g);
my $t2 = () = (/\(.\)/g);
# print STDERR "got $t1 and $t2.\n";
if ($t1 > $t2) {
	tr/([{<>}])/)]}><{[(/;
}

$t1 = () = (/^[45T]+$/mg);
$t2 = () = (/\n/mg);
if ($t1>$t2/100) {
	s/^\d? ?([TPF]\d?)+ ?\d?$//mg;
}

s/^\.(\d[\d\-]*)$/$1./gm;
s/^(\d)\n+\.\n/$1\.\n/gm;

# Clean HTML markups
s/<style.*?<\/style>//gs;
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
s/'''//g;
s/^ *=+ *(.*?) *=+ *$/$1/gm;
# s/^[:;]+-? *//gm;

tr/\r\f//d;        # Romove CR, FF
tr/\t\xA0/ /;      # Tab and hardspace are whitespaces
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
s/([^'])''([^'])/$1"$2/g;
s/("[א-ת])(\d{4})[-]/$1-$2/g;
s/^[.](\d.*?) +/$1. /gm;
s/(\S[([\-]) /$1/gm;
s/(?<=[א-ת]\b)( -| -)(?=[0-9])/-/g;
s/([\(\[]) /$1/g;
s/ ([\)\]])/$1/g;
s/ " -/" -/g;
s/(^| )" /"/gm;
s/ ("[.,:;])/$1/g;
s/ ('[ .,:;])/$1/g;
s/^([:]++-?)(?=\S)/$1 /gm;

s/%([\d.]*\d)/$1%/g;

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
	my $_ = shift; my $type = shift || '';
	
	if (/^([\x{202A}\x{202B}])(.*)\x{202C}$/) {
		$type .= $1; $_ = $2;
		my @arr = (m/([^\x{202A}-\x{202C}]+|[\x{202A}\x{202B}](?0)*\x{202C})/g);
		if ($type eq "\x{202A}" && scalar(@arr)>1) {
			# dump_stderr("pop_embedded: |" . join('|',@arr) . "|\n") if ($#arr>0);
			# s/^([^\x{202A}-\x{202C}]+)$/\x{202A}$1\x{202C}/ for @arr;
		}
		dump_stderr("pop_embedded: |" . join('|',@arr) . "|\n") if ($#arr>0);
		@arr = map { pop_embedded($_,$type) } @arr;
		dump_stderr("pop_embedded: |" . join('|',@arr) . "|\n") if ($#arr>0);
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