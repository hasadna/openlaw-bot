#!/usr/bin/perl -w
# vim: shiftwidth=4 tabstop=4 noexpandtab

package SyntaxLaw;

use Exporter;
our @ISA = qw(Exporter);
our $VERSION = "1.0";
our @EXPORT = qw(convert);

use v5.14;
no if ($]>=5.018), warnings => 'experimental';
use strict;
no strict 'refs';
# no warnings 'misc::replacement_list_length';
use utf8;
use English;
use Encode;
# use Roman;
use Time::HiRes 'time';
use Getopt::Long;
use Data::Dumper;
$Data::Dumper::Useperl = 1;

eval { require Roman; Roman->import(); };
my $use_roman = defined $Roman::VERSION;

use constant { true => 1, false => 0 };

my $do_expand = 0;
my $div_table = 0;

# \bו?כ?ש?מ?[בהל]?(חוק|פקוד[הת]|תקנות|צו|חלק|פרק|סימן(?: משנה|)|תוספו?ת|טופס|לוח)
our $pre_sig = 'ו?כ?ש?מ?[בהל]?-?';
our $extref_sig = $pre_sig . '(חוק(?:[ -]ה?יסוד:?|)|פקוד[הת]|תקנות(?: שעת[ -]ה?חי?רום)?|צו|דברי?[ -]ה?מלך|(?:החלט|הכרז|אכרז|הודע)(?:ה|ו?ת)|תקנון|הוראו?ת|הסכם|רשימת|מנשר|כללים?|נוהל|רי?שיון|קביעו?ת|נורמו?ת|דריש[הת]|חוק[הת]|אמנ[הת]|הנחי[יו]ת|קווים מנחים|אמות מידה|היתר|(?:כתבי? )?מי?נוי)';
our $date_sig = '(?:\,? ה?תש.?["״].[-–]\d{4}|, *[^ ]*\d{4}|, (חוק |פקודה |צו |)מס([\'׳]|פר) \d+ לשנת \d{4}| [-–] ה?תש.?["״]. מיום \d+.*|\, *\d+ עד \d+|\ \(\d{4}\)|\ [-–] \d{4})';
our $type_sig = $pre_sig . '(סעי(?:ף|פים)|תקנ(?:ה|ות)|אמו?ת[ -]ה?מידה|כלל|חלק|פרק|סימן(?: משנה|)|לוח(?:ות|) השוואה|נספח|תוספת|טופס|לוח|טבל[הא]|מפ(?:ה|ות)|الفصل)';
our $chp_sig = '\d+(?:[^ ,.:;"״\n\[\]()]{0,3}?\.|(?:\.\d+)+[א-י]?\.?)';
our $heb_num2 = '(?:[א-ט]|טו|טז|[יכלמנסעפצ][א-ט]?)';
our $heb_num3 = '(?:[א-ט]|טו|טז|[יכלמנסעפצ][א-ט]?|[קרש](?:טו|טז|[יכלמנסעפצ]?[א-ט]?))';
our $roman = '(?:[IVX]+|[ivx]+)';

our $EN = '[A-Za-z]';
our $HE = '(?:[א-ת][\x{05B0}-\x{05BD}]*+)';
our $nikkud = '[\x{05B0}-\x{05BD}]';
our $nochar = '(?:\'\'\'|\<\/?(?:[bis]|ins|del|qq)\>|\x00|[␚␡␛])*+';
our $nochar2 = '(?:\'\'\'|\<\/?(?:[bis]|ins|del|qq)\>|\x00|[␚␡␛])++';
# our $nochar = '(?:\(\(|\)\)|\'\'\'|\<\/?(?:[bis]|ins|del|qq)\>)*+';

sub main() {
	GetOptions( "expand" => \$do_expand);
	
	if ($#ARGV>=0) {
		my $fin = $ARGV[0];
		my $fout = $fin;
		$fout =~ s/\.[^.]*$/.txt2/;
		open(my $FIN,"<:utf8",$fin) || die "Cannot open file \"$fin\"!\n";
		open(STDOUT, ">$fout") || die "Cannot open file \"$fout\"!\n";
		local $/;
		$_ = <$FIN>;
	} else {
		binmode STDIN, "utf8";
		local $/;
		$_ = <STDIN>;
	}
	binmode STDOUT, "utf8";
	binmode STDERR, "utf8";
	
	print convert($_);
	exit;
}

sub convert {
	local $_ = shift;
	
	cleanup();
	
	$div_table = 1 if (s/<מידע נוסף:? טבל(אות|א|ה) שקופ(ות|ה)>\n?//);
	
	# Remove HTML comments
	# s/<!--((?:(?!<!--|-->).)*)-->//sg;
	s/<!--/⟪/g; s/-->/⟫/g;
	s/\n( *⟪[^⟪⟫]*?⟫ *\n)+/\n/sg;
	s/^ *(⟪[^⟪⟫]*?⟫ *)+//mg;
	s/( *)⟪[^⟪⟫]*?⟫( *)/$1$2\x00/sg;
	s/\x00( *\x00)++/\x00/g;
	s/⟪/<!--/g; s/⟫/-->/g;
	
	# Easier parsing using single characeter (⸨⸩⟪⟫⟦⟧⦃⦄ for various elelments
	# s/<!--/⟪/g; s/-->/⟫/g;
	# s/(?<!\()\(\(/⸨/g; s/\)\)(?!\))/⸩/g;
	# s/(?<!\[)\[\[/⟦/g; s/\]\](?!\])/⟧/g;
	# s/(?<!\{)\{\{/⦃/g; s/\}\}(?!\})/⦄/g;
	
	# General cleanup
	s/\r//g;           # Unix style, no CR
	s/[\t\xA0]/ /g;    # tab and hardspace are whitespaces
	s/^[ ]+//mg;       # Remove redundant whitespaces
	s/[ ]+$//mg;       # Remove redundant whitespaces
	s/$/\n/s;          # add last linefeed
	s/\n{3,}/\n\n/sg;  # remove extra linefeeds
	s/\n\n$/\n/sg;     # Remove last linefeed
	if (/[\x{202A}-\x{202E}]/) {
		# Throw away BIDI characters if LRE/RLE/PDF exists
		tr/\x{200E}\x{200F}\x{202A}-\x{202E}\x{2066}-\x{2069}//d;
	}
	
	# Replace vulgar fractions
	s/([½⅓⅔¼¾⅕⅖⅗⅘⅙⅚⅐⅛⅜⅝⅞⅑⅒↉])(\d+)/$2$1/g;
	$_ = s_lut($_, { 
		'½'=>'¹⁄₂', '⅓'=>'¹⁄₃', '⅔'=>'²⁄₃', '¼'=>'¹⁄₄', '¾'=>'³⁄₄', '⅕'=>'¹⁄₅', '⅖'=>'²⁄₅', '⅗'=>'³⁄₅', '⅘'=>'⁴⁄₅', 
		'⅙'=>'¹⁄₆', '⅚' =>'⁵⁄₆', '⅐'=>'¹⁄₇', '⅛'=>'¹⁄₈', '⅜'=>'³⁄₈', '⅝'=>'⁵⁄₈', '⅞'=>'⁷⁄₈', '⅑'=>'¹⁄₉', '⅒'=>'¹⁄₁₀', '↉'=>'⁰⁄₃' 
	});
	
	# Convert Roman numerals
	$_ = s_lut($_, {
		'Ⅰ'=>'I', 'Ⅱ'=>'II', 'Ⅲ'=>'III', 'Ⅳ'=>'IV', 'Ⅴ'=>'V', 'Ⅵ'=>'VI', 'Ⅶ'=>'VII', 'Ⅷ'=>'VIII', 'Ⅸ'=>'IX', 'Ⅹ'=>'X', 'Ⅺ'=>'XI', 'Ⅻ'=>'XII', 
		'ⅰ'=>'i', 'ⅱ'=>'ii', 'ⅲ'=>'iii', 'ⅳ'=>'iv', 'ⅴ'=>'v', 'ⅵ'=>'vi', 'ⅶ'=>'vii', 'ⅷ'=>'viii', 'ⅸ'=>'ix', 'ⅹ'=>'x', 'ⅺ'=>'xi', 'ⅻ'=>'xii', 
	});
	
	s/(?<=[0-9₀-₉])′/&#8242;/g; # Keep prime [feet/minutes], double prime [inch/seconds] and triple prime
	s/(?<=[0-9₀-₉])″/&#8243;/g; # (will be restored later by unescape_text)
	s/(?<=[0-9₀-₉])‴/&#8244;/g; #
	# s/[»«⌸]/"&#".ord($1).";"/ge; # Escape special markers
	
	# Replace subscript/superscript numerals
	s/([₀-₉₊₋₌₍₎]+)/'<sub>' . $1=~tr|₀-₉₊₋₌₍₎|0-9+\-=()|r . '<\/sub>'/ge;
	s/([⁰¹²³⁴-⁹⁺⁻⁼⁽⁾]+)/'<sup>' . $1=~tr|⁰¹²³⁴-⁹⁺⁻⁼⁽⁾|0-9+\-=()|r . '<\/sup>'/ge;
	
	s/(\[\[(?:קובץ|תמונה|[Ff]ile|[Ii]mage):.*?\]\])/ $1 =~ tr| |_|r =~ s|(["'–\-])|"&#".ord($1).";"|gre /ge;
	
	s/($HE['׳]?(?:\(\()?)–(?=(?:\)\))?$HE|\d)/$1--/g; # Keep en-dash between Hebrew words
	s/(\d$HE*)–(?=\d)/$1--/g; # Keep en-dash between numerals
	
	tr/\x{FEFF}//d;     # Unicode marker
	tr/\x{2000}-\x{200A}\x{202F}\x{205F}\x{2060}/ /; # Typographic spaces
	tr/\x{200B}-\x{200D}\xAD//d;       # Remove zero-width spaces and soft-hyphen
	tr/־–—‒―/-/;        # typographic dashes
	tr/\x96\x97/-/;     # more typographic dashes
	tr/‑/–/;            # typographic en-dash
	tr/״”“„‟″‶/"/;      # typographic double quotes
	tr/`׳’‘‚‛′‵/'/;     # typographic single quotes
	s/(?<=[ \n\x00])-{2,4}(?=[ \n\x00])/—/g;   # en-dash
	s/[ ]{2,}/ /g;      # remove extra  spaces
	s/…/.../g;
	
	s/\n+(=[^\n]*=)\n+/\n\n$1\n\n/g;
	
	s/(?<!\n)\n(?=@)/\n\n/gm;
	s/(?<![=\n])\n(\=)/\n\n/gm;
	
	# s/(\d+(?:[.,]\d+)*(?:&#824[23];)?) ([×\\\/—+−±]) (?=\d+(?:[.,]\d+)*)/$1\x{202F}$2\x{202F}/g;
	
	# Unescape HTML characters
	$_ = unescape_text($_);
	
	$_ = process_diffs($_) if /<(ins|del)>/;
	
	s/(?<=\<ויקי\>)\s*(.*?)\s*(?=\<\/(ויקי)?\>)/&escape_text($1)/egs;
	
	s/\[\[קטגוריה:.*?\]\] *\n?//g;  # Ignore categories (for now)
	s/(?<!\[)\[(https?:\/\/[^ |\[\]\n]++) ([^|\[\]\n]++)\](?!\])/[[$1|$2]]/g;
	s/(?<!\[)\[(https?:\/\/[^ |\[\]\n]++)\](?!\])/[[$1]]/g;
	s/\[\[([ws]:)([^\[\]\|]*)\|\]\]/[[$1$2|$2]]/g;
	s/(\[\[[ws]:.*?(?:\||\]\]))/ $1 =~ tr| |_|r /ge;
	s/(\[\[(?:קובץ|תמונה|[Ff]ile|[Ii]mage):.*?\]\])/ $1 =~ tr| |_|r =~ s|(["'–\-])|"&#".ord($1).";"|gre /ge;
	
	s/([ :]\x00?)-(\x00?[ \n])/$1–$2/g;
	
	s/(?<=[ ‎‏|])([A-Za-z0-9+−\-±,.:()\[\]\'′″‴{}<>\/α-ε]{20,})(?=[:;]|\s|$)/&wbr_chemicals($1)/ge;
	
	# Replace with “Smart quotes”
	$_ = convert_quotes($_);
	
	# Parse wikitables
	$_ = parse_wikitable($_) if /\{\|/;
	# s/(\{\|(?:(?R)|.*?)*\n\|\}) *\n?/&parse_wikitable($1)/egs;
	
	# [---] as span float left
	unless ($div_table) {
		s/ \[(?:—|-{2,4})\] *([^\n]*) *$/ <span style="float: left;">$1<\/span><div style="clear: left;"><\/div>/gm;
		s/ \[(?:—|-{2,4})\] *([^\n]*) *$/ <span style="float: left;">$1<\/span><div style="clear: left;"><\/div>/gm;
		s/ \[(?:—|-{2,4})\] */ /gm;
	}
	
	# Parse various elements
	s/^(?|<שם> *\n?(.*)|=([^=].*)=)\n*/&parse_title($1)/em; # Once!
	s/<שם[^>\n]*> .*\n*//g;
	s/<מאגר (\d*) תיקון (.*?)>\n?/<מאגר מזהה="$1" תיקון="$2"\/>\n/;
	s/<מאגר תיקון (.*?)>\n?/<מאגר מזהה="0" תיקון="$1"\/>\n/;
	s/<מאגר (\d*)>\n?/<מאגר מזהה="$1" תיקון="0"\/>\n/;
	s/^<פרסום> *\n?(.*)\n/&parse_pubdate($1)/egm;
	s/^<חתימ(?:ות|ה)> *\n?(((\*.*\n)+)|(.*\n))/&parse_signatures($1)/egm;
	s/^<מקור> *\n?(.*)\n/\n<מקור>\n$1\n<\/מקור>\n/m;
	s/^<(?:מבוא|הקדמה)> *\n?(.*)\n/<הקדמה>\n$1\n<\/הקדמה>\n\n/m;
	s/^<סיום> *\n?(.*)\n/<מפריד\/>\n<הקדמה>\n$1\n<\/הקדמה>\n\n/m;
	s/^(-{3,}|—)$/<מפריד\/>/gm;
	
	s/(<(?:td|th)[^>]*>|\|+)([\x00 ]*)(:)/$1$2␊\n$3/g;
	s/(<\/(?:td|th)[^>]*>)/␊\n$1/g;
	
	# Parse structured elements
	s/^(=+)(.*?)\1\n+/&parse_section(length($1),$2)/egm;
	s/^<סעיף *(.*?)>(.*?)\n/&parse_chapter($1,$2,"סעיף")/egm;
	s/^(@.*?) +($nochar:+?[-–]?$nochar .*)$/$1\n$2/gm;
	s/^(?|($nochar2)(:+[–-]?)($nochar)\ |()(:+[–-]?)($nochar2))/$2 $1$3/gm;
	s/^@ *($nochar\(תיקון: .*?)\n/&parse_chapter("",$1,"סעיף*")/egm;
	s/^@ *($nochar\d\S*) *\n/&parse_chapter($1,"","סעיף")/egm;
	s/^@ *($nochar$chp_sig) +(.*?)\n/&parse_chapter($1,$2,"סעיף")/egm;
	s/^@ *($nochar\d[^ .]*\.$nochar) *(.*?)\n/&parse_chapter($1,$2,"סעיף")/egm;
	s/^@ *($nochar[^ \n.]+\.$nochar) *(.*?)\n/&parse_chapter($1,$2,"סעיף")/egm;
	s/^@ *($nochar\([^()]*?\)$nochar) *(.*?)\n/&parse_chapter($1,$2,"סעיף*")/egm;
	s/^@ *(.*?)\n/&parse_chapter("",$1,"סעיף*")/egm;
	# s/^(:+) *(\([^( ]+\)|[א-י]\. |\d+\. |[^ <>]* \(\(\)\)) *(\([^( ]{1,2}\)|[א-י]\. |[^ <>]* \(\(\)\)) *(\([^( ]{1,2}\)|[א-י]\. |[^ |]* (?:[-–] )?\(\(\)\))/$1 $2\n$1: $3\n$1:: $4/gm;
	# s/^(:+) *(\([^( ]+\)|[א-י]\. |\d+\. |[^ <>]* \(\(\)\)) *(\([^( ]{1,2}\)|[א-י]\. |[^ <>]* (?:[-–] )?\(\(\)\))/$1 $2\n$1: $3/gm;
	s/^(:+) *(\([^( ]+\)|[א-י]\. |\d+\. ) *(\([^( ]{1,2}\)|[א-י]\. ) *(\([^( ]{1,2}\)|[א-י]\. )/$1 $2\n$1: $3\n$1:: $4/gm;
	s/^(:+) *(\([^( ]+\)|[א-י]\. |\d+\. ) *(\([^( ]{1,2}\)|[א-י]\. )/$1 $2\n$1: $3/gm;
	s/^:+-? *(␊?)$/$1/gm;
	# s/^(:+) *("?\([^( ]+\)|\[[^[ ]+\]|\d[^ .]*\.|)(?| +(.*?)|([-–].*?)|())\n/&parse_line($1,$2,$3)/egm;
	s/^(:+[-–]?+) *($nochar["”“]?(?:(?:\([^( \n]+\)|\[[A-Za-z0-9א-ת][^\[\] \n]*\]|[A-Za-z0-9א-ת.]*\)? *\(\(\.?\)\)|\(\(\(\d+.?\)\)\)|\(\(\([א-י]\d?\)\)\)|\d+(?:\.\d+)+\.?|\d[^ .\n]*\.|$heb_num2\d?\.|[A-Za-z]\.|$roman\.?|[•■□-◿*❏☒√✔☑✅☐\-–]|<sup>[0-9א-ת]{1,2}<\/sup>|\( \)|\[ \])\*?|(?:[^ \n]+ |)(?:[-–] |)\(\(\)\)|)$nochar)(?| +(.*?)|(␊?))\n/&parse_line($1,$2,$3)/egm;
	
	# Move container tags if needed
	my $barrier = '<\/?(?:מקור|הקדמה|ת+|קטע|סעיף|חתימות|מידע נוסף|td|tr|table)|__TOC__|$';
	s/(\n?<\/(?:הקדמה|מקור)>)(.*?)(?=\s*($barrier))/$2$1/sg;
	s/(\n?<\/ת+>)(.*?)(?=\s*(<מפריד.*?>\s*)?($barrier))/$2$1/sg;
	# Add <סעיף> marker after <קטע> if not found
	s/(<\/קטע.*?>\s*+)(?!<(קטע|סעיף|חתימות))/$1<סעיף><\/סעיף>\n/g;
	s/␊([^\n]*?)\n/$1/g;
	s/␊//g;
	
	# s/(<(qq|ins|del)>.*?<\/\2>)/&parse_spans($2,$1)/egs;
	
	# Parse links and remarks
	s/(\[\[[ws]:.*?\]\])/ $1 =~ tr|_| |r /ge;
	s/\[\[(?:קובץ:|תמונה:|[Ff]ile:|[Ii]mage:)(.*?)\]\]/"<תמונה>" . (unescape_text($1) =~ tr|_| |r) . "<\/תמונה>"/gem;
	# s/\[\[(?:קובץ:|תמונה:|[Ff]ile:|[Ii]mage:)(.*?)\]\]/"<תמונה>" . $1 =~ tr|_| |r =~ s|&#(\d+);|chr($1)|gre . "<\/תמונה>"/gem;
	
	# s/(?<!\[)(\[\[(?:(?!\]\]|\[\[).)*\]\]\]?(?:(?:,|או|) \[\[(?:(?!\]\]|\[\[).)*\]\]\]?)++)/&mark_linkset($1)/egm;
	s/(?<!\[)\[\[((?:(?!\]\]|\[\[).)*?\]?)\|((?:(?!\]\]|\[\[).)*)\]\](\]?)/&parse_link($1,"$2$3")/egm;
	s/(?<!\[)\[\[((?:(?!\]\]|\[\[).)*)\]\](\]?)/&parse_link('',"$1$2")/egm;
	# s/(?<!\()(\(\(([^\n]*?)\)\)([^(\n]*?\)\))?)(?!\))/&parse_remark($1)/egs;
	s/(?<!\()(\(\(([^()\n]++|(?R)|[()])*?\)\)([^(\n]*?\)\))?)(?!\))/&parse_remark($1)/egs;
	
	# Parse file linearly, constructing all ankors and links
	$_ = linear_parser($_);
	
	s/\n+<סעיף><\/סעיף>\n+(?=(\<מקור|\<מאגר|$))/\n\n/sg;
	s/^(<(?:שם|קטע)[^\n]+)\n\n(?=\<קטע)/$1\n/mg;
	
	s/__TOC__/&insert_TOC()/e;
	s/ *__NOTOC__//g;
	s/ *__NOSUB__//g;
	
	s/(?<=\<ויקי\>)\s*(.*?)\s*(\<\/(ויקי)?\>)/&unescape_text($1) . "<\/ויקי>"/egs;
	# s/\<תמונה\>\s*(.*?)\s*\<\/(תמונה)?\>/&unescape_text($1)/egs;
	s/<לוח_השוואה>\s*(.*?)<\/(לוח_השוואה|)>\n?/&parse_comparetable($1)/egs;
	s/(\<math.*?\>.*?\<\/math\>)/&fix_tags($1)/egs;
	s/(<(?:div|span|table|td|th|tr|מידע נוסף) [^>]+>)/&fix_tags($1)/egs;
	
	s/( ["”“]?(?:[A-Za-zא-ת0-9]{3,}[\\\/]){2,}[A-Za-zא-ת0-9]{3,}[,;."”“]?(?: |\n))/ $1 =~ s|(?<=[\\\/])|<wbr>|gr /eg;
	
	# Use thin spaces in dotted lines
	# s/(\.{21,})/'<span style="word-break: break-all;">' . '. 'x(length($1)-1) . '.<\/span>'/ge;
	s/(\.{21,})/'. ' x 10 . ('<wbr>' . '. ' x 10) x (int((length($1)-20)\/10)) . '<wbr>' . '. ' x (length($1) % 10) . (length($1) % 10 ? '<wbr>' : '') . '. 'x9 . '.'/ge;
	s/(\.{4,20})/'. ' x (length($1)-1) . '.'/ge;
	# Styling for long underscore spacers
	s/(_{3,})/<span style="font-family: Arial; font-size: 80%;">$1<\/span>/g;
	# Use Arial font for fraction slash (U+2044) [bug of ALEF font]
	s/⁄/<span style="font-family: Arial;">⁄<\/span>/g;
	# Compact form for comments mark
	s/(\*{2,})/<span style="letter-spacing: -2pt; padding-inline-end: 2pt;">$1<\/span>/g;
	# LTR wrapper for "300.-" and similar
	s/ (?|[-–]\.([0-9]+)|\x{200E}([0-9]+)\.[-–]\x{200E}) / <span dir="ltr">$1.-<\/span> /g;
	
	# This syntax will be used to link booklets, but not supported yet.
	s/(\d+) \[(\d{4,5})\]/$1/g;
	
	if ($do_expand) {
		# Replace "=" within templates with {{=}}
		s/(\{\{(?:[^{}\n]++|(?R))*\}\})/ &escape_eqsign($1) /eg;
		$_ = expand_templates($_);
	}
	
	s/␚([^␚␡␛]*)␛/<ins>$1<\/ins>/g;
	s/␡([^␚␡␛]*)␛/<del>$1<\/del>/g;
	
	s/\x00//g; # Remove nulls
	s/\n{3,}/\n\n/g;
	s/ {2,}/ /g;
	
	cleanup();
	
	return $_;
}

# Allow usage as a module and as a executable script
__PACKAGE__->main() unless (caller);

######################################################################

sub process_diffs {
	local $_ = shift;
	my $c = '[^␚␡␛]'; my $d = '[0-9A-Za-zא-ת;:\-%,.]';
	s/<ins>/␚/g;
	s/<del>/␡/g;
	s/<\/(ins|del)>/␛/g;
	
#	my @str = split(/([␚␡␛]|<!--|-->)/, $_);
#	my $state = 0;
#	foreach (@str) {
#		if ($state<10) {
#			when (/␛/) { state = 0; }
#			when (/␚/) { state = 1; }
#			when (/␡/) { state = 2; }
#			when (/<!--/) { state += 10; }
#		} else {
#		}
#	}
#	$_ = join(@str);
	
	while (s/([␚␡])($c+)($c*)(␛)\2/$2$1$3$2$4/g) {};
	s/([␚␡])($c+) (␛)/$1$2$3 /g;
	s/␚($c+)␛␡\1␛/$1/g;
	s/␡($c+)␛␚\1␛/$1/g;
	s/␚($c+)␛␡\1($c+)␛/$1␡$2␛/g;
	s/␡($c+)␛␚\1($c+)␛/$1␚$2␛/g;
	s/([␚␡])([.,;:\-])\n($c+)(␛)([.,;:\-])\n/$2\n$1$3$5$4\n/g;
	# ␡57␛␚2003␛8␡858␛␚99␛ => ␡578␛␚20038␛␡858␛␚99␛ => ␡578␛␡858␛␚20038␛␚99␛ => ␡578858␛␚2003899␛
	while (s/([␡␚]$d+␛)($d+)/$1␡$2␛␚$2␛/g || s/($d+)([␡␚]$d+␛)/␡$1␛␚$1␛$2/g || s/[␚␡]␛//g || s/(␚$d+␛)(␡$d+␛)/$2$1/g || s/([␚␡])($c+)␛\1($c+)(␛)/$1$2$3$4/g ) {};
	s/(␡$c+␛)(␚$c+␛)/$1 $2/g;
	s/([\n ]+)(␛)/$2$1/g;
	
	s/^([␚␡])(@|:+[-–]?+) *($nochar["”“]?(?:\([^( ]+\)|\[[A-Za-z0-9א-ת][^\[\] ]*\]|[A-Za-z0-9א-ת.]*\)? *\(\(\.?\)\)|\(\(\(\d+.?\)\)\)|\(\(\([א-י]\d?\)\)\)|\d+(?:\.\d+)+|\d[^ .]*\.|$heb_num2\d?\.|$roman\.?|[•■□-◿*❏☒√✔☑✅☐\-–]|<sup>[0-9א-ת]{1,2}<\/sup>|\( \)|\[ \]|[^ ]+ (?:[-–] )?\(\(\)\)|)$nochar)(?| +(.*?)|(␊?))\n/$2 $1$3␛ $1$4\n/gm;
	while (s/^([␚␡])([\@:]$c*)\n/$1$2␛\n$1/gm) {};
	s/^([␚␡])(@|:+[-–]?+) (\($d+\)|$d\.) ($c*)/$2 $1$3␛ $1$4/gm;
	s/^([␚␡])(@|:+[-–]?+) ($c*)/$2 $1$3/gm;
	s/^([␚␡])(=+ *)($c*?)( *=+)(␛)$/$2$1$3$5$4/gm;
	s/\n{3,}/\n\n/g;
	
	# s/␚($c*)␛/<ins>$1<\/ins>/g;
	# s/␡($c*)␛/<del>$1<\/del>/g;
	return $_;
}

######################################################################

sub parse_title {
	local $_ = shift;
	my ($fix, $str);
	$_ = unquote($_);
	($_, $fix) = get_fixstr($_);
	$str = "<שם>";
	$str .= "<תיקון>$fix</תיקון>\n" if ($fix);
	$str .= "$_</שם>\n\n";
	return $str;
}

sub parse_section {
	my $level = shift;
	local $_ = shift;
	my ($fix, $extra, $str, $ankor);
	
	$level = 2 unless defined $level;
	
	$_ = unquote($_);
	($_, $fix) = get_fixstr($_);
	($_, $extra) = get_extrastr($_);
	($_, $ankor) = get_ankor($_);
	
	$str = $_;
	
	# print STDERR "parse_section with |$_|\n";
	s/\(\([^()]*?\[\[[^()]*?\)\)//g;
	s/(?|\(\(\(([^()]*?)\)\)\)|\(\(([^()]*?)\)\))/$1/g;
	
	if ($ankor) {
		($ankor,undef) = find_href($ankor);
	} elsif (/^\((.*?)\)$/) {
		$ankor = '';
	} elsif (/^(?|(.+?)(?: *:| +[-])|($type_sig *(?:[^ (]+( +|$)){0,2}))/) {
		($ankor,undef) = find_href($1);
		$ankor = '' if ($ankor =~ /סעיף/);
	} else {
		$ankor = '';
	}
	
	my $str2 = $str;
	$str = "<קטע";
	$str .= " דרגה=\"$level\"" if ($level);
	$str .= " עוגן=\"$ankor\"" if ($ankor);
	$str .= ">";
	$str .= "<תיקון>$fix</תיקון>" if ($fix);
	$str .= "<אחר>[$extra]</אחר>" if ($extra);
	$str .= $str2;
	$str .= "</קטע>\n\n";
	return $str;
}

sub parse_chapter {
	my ($num, $desc, $type) = @_;
	my ($id, $fix, $extra, $ankor);
	$desc = unquote($desc);
	($desc, $fix) = get_fixstr($desc);
	($desc, $extra) = get_extrastr($desc);
	($desc, $ankor) = get_ankor($desc);
	if ($num eq '' && $ankor eq '' && $desc =~ /^(סעיף|תקנה|פרט|المادة) (\d+[^ .:\-]*)(?::| [-–]|$)/) {
		$num = $2;
		$type =~ s/\*$//;
	}
	$id = get_numeral($num);
	
	$desc =~ s/(?<=[־–])(?! |$)/<wbr>/g;
	$desc =~ s/(?<=[ |].)<wbr>//g;
	$extra =~ s/(?=\()/<wbr>/g if ($extra);
	# [Don't] Use Roman symbols for numerals
	# $num = roman_ligatures($num);
	
	$type =~ s/\*$//;
	$ankor = ((!$ankor && $num) ? $id : $ankor);
	my $str = "<$type";
	$str .= " עוגן=\"$ankor\"" if ($ankor);
	$str .= ">";
	$str .= "<מספר>$num</מספר>" if ($num);
	$str .= "<תיאור>$desc</תיאור>" if ($desc);
	$str .= "<תיקון>$fix</תיקון>" if ($fix);
	$str .= "<אחר>[$extra]</אחר>" if ($extra);
	$str .= "</$type>\n";
	return $str;
}

sub parse_line {
	my ($type,$num,$line) = @_;
	$type =~ /(:+)([-–]?)/;
	my $len = length($1);
	my $def = length($2)>0;
	my $id;
	
	$num =~ s/"/&quot;/g;
	$num =~ s/ *\(\(\)\)$//;
	$num =~ s/(?|(\[) (\])|(\() (\)))/$1\x{2002}$2/; # ensp
	if (($num =~ /'''/)%2) {
		$num =~ s/$/'''/;
		$num = '' if ($num =~ /^''' *'''$/);
		$line =~ s/^ */'''/;
	}
	$id = unparent($num);
	$id = '' if $num =~ /\(\(.*\)\)/;
	$len++ if ($num);
	$type = "ת" x $len;
	$line =~ s/^ *(.*?) *$/$1/;
	
	if ($div_table) {
		my $local_align = ($line =~ /\[(?:—|-{2,4})\] .*\<u\>/);
		$line =~ s/(?|(.*) |^())\[(?:—|-{2,4})\] ?(.*) ?\[(?:—|-{2,4})\] ?(.*)$/{{טור לשמאל|$1|$2|$3}}/m;
		$line =~ s/(?|(.*) |^())\[(?:—|-{2,4})\] ?(.*)$/{{טור לשמאל|$1|$2}}/m;
		$line =~ s/(\{\{טור לשמאל)(?=\|)/$1|יישור=מרכז/m if $local_align;
	}
	
	my $str;
	$str = "<$type";
	$str .= " מספר=\"$id\"" if ($id);
	$str .= " סוג=\"הגדרה\"" if ($def);
	$str .= ">";
	$str .= "<מספר>$num</מספר> " if ($num);
	$str .= "$line" if (length($line)>0);
	$str .= "</$type>\n";
	return $str;
}

sub parse_link {
	my ($helper,$txt) = @_;
	my $str;
	my $pre = ''; my $post = '';
	
	if ($helper =~ /\{\{/ and $txt =~ /^[^{]*\}\}/) { ($helper, $txt) = ('', "$helper|$txt"); }
	$helper = unquote($helper);
	if ($helper =~ /^\[/ and $txt =~ /\]$/) { $pre = '['; $helper =~ s/^\[//; $txt =~ s/\]$//; $post = ']'; }
	elsif ($txt =~ s/^(\[)(.*)(\])$/$2/) { ($pre, $post) = ($1, $3); }
	elsif ($txt =~ s/(?<=\d{4})(\])$//) { $post = $1; }
	
	($helper,$txt) = ($txt,$1) if ($txt =~ /^[ws]:(?:[a-z]{2}:)?(.*)$/ && !$helper);
	$helper =~ s/<\/?.*?>//g;
	$str = "$pre<קישור" . ($helper ? " $helper" : '') . ">$txt</קישור>$post";
	$str =~ s/([()])\1/$1\x00$1/g unless ($str =~ /\(\(.*\)\)/); # Avoid splitted comments
	
	push_lookahead($2) if ($helper =~ /^([^a-zA-Z]*)\=([^a-zA-Z]+)$/);
	push_lookahead($txt) if ($helper =~ /^([^a-zA-Z]*)\=$/);
	return $str;
}

sub parse_remark {
	local $_ = shift;
	return $1 . parse_remark($2) if /^(?|(\()(\(\(\[[^\[\]]*?\]\)\))|(\()(\(\(\(.*?[^)]\)\)\)))$/;
	s/^\(\((.*?)\)\)$/$1/s;
	my ($text,$tip,$url) = ( /((?:\{\{.*?\}\}|\[\[.*?\]\]|[^|])+)/g );
	return $_ unless defined $text;
	my $str;
	$text =~ s/^ *(.*?) *$/$1/;
	$text =~ s/(?<!\()\(\((.*?)\)\)(?!\))/{{מוקטן|$1}}/g;
	if ($tip) {
		$tip =~ s/^ *(.*?) *$/$1/;
		$tip = escape_quote($tip);
		$str = "<תיבה טקסט=\"$tip\"";
		if ($url) {
			$url = '' if ($url =~ /^\d+[אב]?(_\d+)?$/);
			$url = find_reshumot_href($url);
			$str .= " קישור=\"$url\"";
		}
		$str .= ">$text</תיבה>";
	} else {
		$str = "<הערה>$text</הערה>";
	}
	return $str;
}

my $pubdate = '';

sub parse_signatures {
	local $_ = shift;
	chomp;
	# print STDERR "Signatures = |$_|\n";
	my $str = "<חתימות>\n";
	$str .= "<פרסום>$pubdate</פרסום>\n" if ($pubdate);
	s/;/\n/g;
	foreach (split("\n")) {
		s/^\*? *(.*?) *$/$1/;
		if (/\|/) {}
		elsif (/,/) { tr/,/|/; }
		elsif (s/ +(?=ה?(שר[הת]?|נשיאת?|ראש|יושבת?[\-־ ]ראש|נציבת?)\b)/\|/) {}
		else { s/^([א-ת\-–־"״]{2,} (?:[א-ת]]['.] |\([א-ת\-–־]{2,}\) |)[א-ת\-–־"״]{2,}) ([^ ]+ +.+)$/$1 | $2/; }
		s/ *\| */ | /g;
		$str .= "* $_\n";
		# /^\*? *([^,|]*?)(?: *[,|] *(.*?) *)?$/;
		# $str .= ($2 ? "* $1 | $2\n" : "* $1\n");
	}
	$str .= "</חתימות>\n";
	return $str;
}

sub parse_pubdate {
	$pubdate = shift;
	return "";
}

sub mark_linkset {
	local $_ = shift;
	s/\[\[(?|(.*?)\|(.*?)|()(.*?))\]\]/[[»$1|$2]]/g;
	s/»([^»]+)$/«$1/;
	# print STDERR "$_\n";
	return $_;
}

#---------------------------------------------------------------------

sub parse_wikitable {
	# Based on [mediawiki/core.git]/includes/parser/Parser.php doTableStuff()
	local $_ = shift;
	s/^(\|-.*)\n(.*?)\<עוגן (.*?)\>/$1 id="$3"\n$2/gm;
	s/^(\|-.*?) *\<עוגן (.*?)\>/$1 id="$2"/gm;
	
	my @lines = split(/\n/,$_);
	my $out = '';
	my ($last_tag, $previous, $indent_level, $attributes);
	my (@td_history, @last_tag_history, @tr_history, @tr_attributes, @has_opened_tr);
	
	for (@lines) {
		s/^ *(.*?) *$/$1/;
		if ($_ eq '') {
			$out .= "\n";
			next;
		}
		
		if (/^(.*)\{\|(.*)$/) {
			$previous = $1;
			$attributes = $2;
			$attributes =~ s/wikitable *//; $attributes =~ s/ ?class=([“”]{2}|""|'')//;
			$_ = "$previous<table$attributes>\n";
			push @td_history, false;
			push @last_tag_history, '';
			push @tr_history, false;
			push @tr_attributes, '';
			push @has_opened_tr, false;
		} elsif ( scalar(@td_history) == 0 ) {
			# Don't do any of the following
			$out .= "$_\n";
			next;
		} elsif (/^\|\}(.*)$/ ) {
			# We are ending a table
			$_ = "</table>\n$1";
			$last_tag = pop @last_tag_history;
			$_ = "<tr><td></td></tr>\n$_" if (!(pop @has_opened_tr));
			$_ = "</tr>\n$_" if (pop @tr_history);
			$_ = "</$last_tag>$_" if (pop @td_history);
			pop @tr_attributes;
			# $_ .= "</dd></dl>" x $indent_level;
		} elsif ( /^\|-(.*)/ ) {
			# Now we have a table row
			
			# Whats after the tag is now only attributes
			$attributes = $1;
			pop @tr_attributes;
			push @tr_attributes, $attributes;
			
			$_ = '';
			$last_tag = pop @last_tag_history;
			pop @has_opened_tr;
			push @has_opened_tr, true;
			
			$_ = "</tr>\n" if (pop @tr_history);
			$_ = "</$last_tag>$_" if (pop @td_history);
			
			push @tr_history, false;
			push @td_history, false;
			push @last_tag_history, '';
		} elsif (/^\!\! *(.*)$/) {
			my @cells = split( / *\|\| */, $1 );
			s/(.*)/<col>$1<\/col>/ for (@cells);
			$_ = join('', @cells);
			$_ = "<colgroup>$_</colgroup>";
		} elsif (/^(?|\|(\+)|(\|)|(\!)) *(.*)$/) {
			# This might be cell elements, td, th or captions
			my $type = $1; $_ = $2;
			
			s/!!/||/g if ( $type eq '!' );
			my @cells = split( /[ \x00]*\|\|[ \x00]*/, $_ , -1);
			@cells = ('') if (!@cells);
			$_ = '';
			# print STDERR "Cell is |" . join('|',@cells) . "|\n";
			
			# Loop through each table cell
			foreach my $cell (@cells) {
				
				$previous = '';
				if ($type ne '+') {
					my $tr_after = pop @tr_attributes;
					if ( !(pop @tr_history) ) {
						# $previous = "<tr " . (pop @tr_attributes) . ">\n";
						$previous = "<tr$tr_after>";
					}
					push @tr_history, true;
					push @tr_attributes, '';
					pop @has_opened_tr;
					push @has_opened_tr, true;
				}
				
				$last_tag = pop @last_tag_history;
				$previous = "</$last_tag>$previous" if (pop @td_history);
				
				if ( $type eq '|' ) {
					$last_tag = 'td';
				} elsif ( $type eq '!' ) {
					$last_tag = 'th';
				} elsif ( $type eq '+' ) {
					$last_tag = 'caption';
				} else {
					$last_tag = '';
				}
				
				push @last_tag_history, $last_tag;
				
				# A cell could contain both parameters and data
				my @cell_data = split( / *\| */, $cell, 2 );
				
				if (!defined $cell_data[0]) {
					$cell = "$previous<$last_tag>&nbsp;"; 
				} elsif ( $cell_data[0] =~ /\[\[|\{\{/ ) {
					$cell = "$previous<$last_tag>$cell";
				} elsif ( @cell_data < 2 ) {
					$cell = "$previous<$last_tag>" . $cell_data[0] || "&nbsp;";
				} else {
					$attributes = $cell_data[0];
					$cell = $cell_data[1] || "&nbsp;";
					$cell = "$previous<$last_tag $attributes>$cell";
				}
				
				$_ .= $cell;
				push @td_history, true;
			}
			$_ .= "␊\n";
		} else {
			$_ .= "\n";
			$out =~ s/&nbsp;␊?\n?$//s;
		}
		$out .= $_;
	}

	# Closing open td, tr && table
	while ( @td_history ) {
		$out .= "</td>" if (pop @td_history);
		$out .= "</tr>\n" if (pop @tr_history);
		$out .= "<tr><td></td></tr>\n" if (!(pop @has_opened_tr));
		$out .= "</table>\n";
	}
	
	# # Remove trailing line-ending (b/c)
	# $out =~ s/\n$//s;
	
	# special case: don't return empty table
	if ( $out eq "<table>\n<tr><td></td></tr>\n</table>" ) {
		$out = '';
	}
	# $out =~ s/\n\n/\n/g;
	return $out;
}

#---------------------------------------------------------------------

sub parse_comparetable {
	my @lines = split(/\n/,shift);
	my $col = 0;
	my @table;
	for (@lines) {
		if (/^ *(.*?) *\| *(.*?) *$/) {
			$table[$col][0] = $1;
			$table[$col][1] = $2;
			$col++;
		}
	}
	$col = int(($col+1)/2);
	my $str = '<table border="0" cellpadding="1" cellspacing="0" dir="rtl" align="center">
  <tr><th width="120">הסעיף הקודם</th><th width="120">הסעיף החדש</th><th width="120">הסעיף הקודם</th><th width="120">הסעיף החדש</th></tr>
';
	for (my $i=0; $i<$col; $i++) {
		$str .= "<tr>" . 
			"<td>" . ($table[$i][0] || "&nbsp;") . "</td>" . 
			"<td>" . ($table[$i][1] || "&nbsp;") . "</td>" . 
			"<td>" . ($table[$i+$col][0] || "&nbsp;") . "</td>" . 
			"<td>" . ($table[$i+$col][1] || "&nbsp;") . "</td>" . 
			"</tr>\n";
	}
	$str .= "</table>\n";
	return $str;
}

#---------------------------------------------------------------------

sub expand_templates {
	local $_ = shift;
	# Convert to single character brackets for simpler regexps
	s/\{\{/⦃/g;
	s/\}\}/⦄/g;
	
	s/(⦃(?:[^⦃⦄]++|(?R))*⦄)/ &expand_templates_2($1) /eg;
	
	s/⦃/\{\{/g;
	s/⦄/\}\}/g;
	return $_;
}

sub expand_templates_2 {
	local $_ = shift;
	# s/^⦃ *([^ |])(\|//;
	# s/ *⦄$//;
	# s/((?:[^⦃⦄]++|(?R))*⦄)/ &expand_templates_2($1) /eg;
	return $_;
}

#---------------------------------------------------------------------

sub get_fixstr {
	local $_ = shift;
	my @fix = ();
	my $fix_sig = '(?:תיקון|תקון|תיקונים):';
	push @fix, unquote($1) while (s/(?| *\($fix_sig *(([^()]++|\(.*?\))+) *\)| *\[$fix_sig *(.*?) *\](?!\]))//);
	s/^ *(.*?) *$/$1/;
	my $fix = join(', ',@fix);
	$fix =~ s/\bה(תש[א-ת"]+)\b/$1/g;
	$fix =~ s/(^| )(\*+|-+|\?+),?( |$)/ /g;
	return ($_, $fix);
}

sub get_extrastr {
	local $_ = shift;
	my @extra = ();
	s/\[(נוסח $HE+)\]/⟦$1⟧/g;
	s/(\(\(.*?\)\))/ $1 =~ tr|[]|⟦⟧|r /eg; # Terrible way to avoid [...] match within ((...)).
	push @extra, unquote($1) while (s/(?<=[^\[\(])\[ *([^\[\]]+) *\] *//) || (s/^\[ *([^\[\]]+) *\] *//);
	s/^ *(.*?) *$/$1/;
	tr/⟦⟧/[]/;
	return ($_, join(', ',@extra));
}

sub get_ankor {
	local $_ = shift;
	my @ankor = ();
	push @ankor, unquote($1) while (s/ *<עוגן:? *(.*?)>//);
	s/^ *(.*?) *$/$1/;
	return ($_, join(', ',@ankor));
}

sub get_numeral {
	local $_ = shift;
	return '' if (!defined($_));
	my $num = '';
	my $token = '';
	s/&quot;/"/g;
	s/[,"'״׳]//g;
	s/$nochar//g;
	s/־/-/g;
	s/([א-ת]{3})(\d)/$1-$2/;
	$_ = unparent($_);
	while ($_ ne '') {
		$token = '';
		given ($_) {
			($num,$token) = ("0",$1) when /^(מקדמית?|אפס)\b/;
			($num,$token) = ("11",$1) when /^(אחד[- ]עשר|אחת[- ]עשרה|(ال)?حادي عشر|احد عشر)\b/;
			($num,$token) = ("12",$1) when /^(שניי?ם[- ]עשר|שתיי?ם[- ]עשרה|(ال)?ثاني عشر|اثنا عشر)\b/;
			($num,$token) = ("13",$1) when /^(שלושה[- ]עשר|שלוש[- ]עשרה|(ال)?ثالث عشر|ثلاثة عشر)\b/;
			($num,$token) = ("14",$1) when /^(ארבעה[- ]עשר|ארבע[- ]עשרה|(ال)?رابع عشر|اربعة عشر)\b/;
			($num,$token) = ("15",$1) when /^(חמי?שה[- ]עשר|חמש[- ]עשרה|(ال)?خامس عشر|خمسة عشر)\b/;
			($num,$token) = ("16",$1) when /^(שי?שה[- ]עשר|שש[- ]עשרה|(ال)?سادس عشر|ستة عشر)\b/;
			($num,$token) = ("17",$1) when /^(שבעה[- ]עשר|שבע[- ]עשרה|(ال)?سابع عشر|سبعة عشر)\b/;
			($num,$token) = ("18",$1) when /^(שמונה[- ]עשרה?|(ال)?ثامن عشر|ثمانية عشر)\b/;
			($num,$token) = ("19",$1) when /^(תשעה[- ]עשר|תשע[- ]עשרה|(ال)?تاسع عشر|تسعة عشر)\b/;
			($num,$token) = ("21",$1) when /^(עשרים[- ]ו?אח[דת]|واحد وعشرون)\b/;
			($num,$token) = ("22",$1) when /^(עשרים[- ]ו?ש[נת]יי?ם|اثنان وعشرون)\b/;
			($num,$token) = ("23",$1) when /^(עשרים[- ]ו?שלושה?|ثلاثة وعشرون)\b/;
			($num,$token) = ("24",$1) when /^(עשרים[- ]ו?ארבעה?|أربعة وعشرون)\b/;
			($num,$token) = ("25",$1) when /^(עשרים[- ]ו?חמי?שה?|خمسة وعشرون)\b/;
			($num,$token) = ("26",$1) when /^(עשרים[- ]ו?שי?שה?|ستة وعشرون)\b/;
			($num,$token) = ("27",$1) when /^(עשרים[- ]ו?שבעה|سبعة وعشرون)\b/;
			($num,$token) = ("28",$1) when /^(עשרים[- ]ו?שמונה|ثمانية وعشرون)\b/;
			($num,$token) = ("29",$1) when /^(עשרים[- ]ו?תשעה?|تسعة وعشرون)\b/;
			($num,$token) = ("1",$1) when /^(ראשו(ן|נה)|אחד|אחת|(ال)?أول|واحد)\b/;
			($num,$token) = ("2",$1) when /^(שניי?ה?|ש[תנ]יי?ם|(ال)?(ثاني|ثانيا)|إثنان)\b/;
			($num,$token) = ("3",$1) when /^(שלישית?|שלושה?|(ال)?ثالث|ثلاثة)\b/;
			($num,$token) = ("4",$1) when /^(רביעית?|ארבעה?|(ال)?(رابعة|رابع|أربع))\b/;
			($num,$token) = ("5",$1) when /^(חמי?שית?|חמש|חמי?שה|(ال)?خامس|خمسة)\b/;
			($num,$token) = ("6",$1) when /^(שי?שית?|שש|שי?שה|(ال)?سادس|ستة)\b/;
			($num,$token) = ("7",$1) when /^(שביעית?|שבעה?|(ال)?سابع|سبعة)\b/;
			($num,$token) = ("8",$1) when /^(שמינית?|שמונה|(ال)?ثامن|ثمانية)\b/;
			($num,$token) = ("9",$1) when /^(תשיעית?|תשעה?|(ال)?تاسع|تسعة)\b/;
			($num,$token) = ("10",$1) when /^(עשירית?|עשרה?|(ال)?عاشر|عشرة)\b/;
			($num,$token) = ("20",$1) when /^(עשרים|(ال)?عشرون)\b/;
			($num,$token) = ("30",$1) when /^(שלושים|(ال)?ثلاثون)\b/;
			($num,$token) = ($use_roman ? arabic($1) : uc($1), $1) when /^($roman)\b/;
			($num,$token) = ("$1-2","$1$2") when /^(\d+)([- ]?bis)\b/i;
			($num,$token) = ("$1-3","$1$2") when /^(\d+)([- ]?ter)\b/i;
			($num,$token) = ("$1-4","$1$2") when /^(\d+)([- ]?quater)\b/i;
			($num,$token) = ($2,"$1$2") when /^($pre_sig-|)(\d\d+([._]\d*[א-ט]?)*)\b/; # At least two digits.
			($num,$token) = ($1,$1) when /^(\d+([._]\d+[א-ט]?)+)\b/;
			($num,$token) = ($1,$1) when /^(\d+$heb_num2?\.$heb_num2\d?)\b/;
			($num,$token) = ($1,$1) when /^(\d+($heb_num2?\d*|))\b/;
			($num,$token) = ($1,$1) when /^(\d+$heb_num2\d+$heb_num2)\b/;
			($num,$token) = ($1,$1) when /^($heb_num3(\d+[א-י]*|))\b/;
		}
		# print STDERR "get_numeral: got \$_=\"$_\"; \$num=\"$num\" and \$token=\"$token\".\n";
		if ($num ne '') {
			# Remove token from rest of string
			$_ =~ s/^$token//;
			last;
		} else {
			# Fetch next token
			$_ =~ s/^[הו]// || $_ =~ s/^\<[^>]*\>// || $_ =~ s/^[^ ()|]*[ ()|]+// || last;
		}
	}
	
	$num .= "-$1$2$3" if (s/^[- ]([א-י])[- ]?(\d)[- ]?([א-י])\b//);
	$num .= "-$1$2" if (s/^[- ]([א-י])[- ]?(\d)\b//);
	$num .= "-$1" if (s/^[- ]([א-י])\b//);
	$num .= "-$1" if ($num =~ /^\d/ and $token !~ /^\d/ and /^[- ]?(\d[א-י]?)\b/);
	$num =~ s/(?<=\d)-(?=[א-ת])//;
	return $num;
}

sub unquote {
	my $s = shift;
	# my $Q1 = '["״”“„‟″‶]';
	# my $Q2 = '[\'`׳’‘‚‛′‵]';
	my $Q1 = qr/"/;
	my $Q2 = qr/'/;
	my $sp = qr/[ \x00]*/;
	$s =~ s/'''/‴/g;
	$s =~ s/^$sp(?|$Q1$sp(.*?)$sp$Q1|$Q2$sp(.*?)$sp$Q2|$sp(.*?)$sp)$sp$/$1/;
	$s =~ s/‴/'''/g;
	return $s;
}

sub unparent {
	my $s = unquote(shift);
	$s =~ s/^\(\((.*?)\)\)$/$1/;
	$s =~ s/^<([a-z]+)>(.*)<\/\1>/$2/g;
	$s =~ s/^(?|\((.*?)\)|\[(.*?)\]|\{(.*?)\})$/$1/;
	$s =~ s/^ *(.*?) *$/$1/;
	return $s;
}

sub escape_quote {
	my $s = shift;
	$s =~ s/^ *(.*?) *$/$1/;
	$s =~ s/&/\&amp;/g;
	$s =~ s/"/&quot;/g;
	return $s;
}

sub escape_text {
	my $s = unquote(shift);
	$s =~ s/&/\&amp;/g;
	$s =~ s/</&lt;/g;
	$s =~ s/>/&gt;/g;
	$s =~ s/([(){}"'\[\]<>\|])/"&#" . ord($1) . ";"/ge;
	return $s;
}

sub unescape_text {
	local $_ = shift;
	my %table = ( 'quot' => '"', 'lt' => '<', 'gt' => '>', 'ndash' => '–', 'nbsp' => ' ', 'apos' => "'", # &amp; subs later
		'lrm' => "\x{200E}", 'rlm' => "\x{200F}", 'thinsp' => "\x{2009}", 'shy' => '&null;',
		'deg' => '°', 'minus' => '−', 'pm' => '±', 'plusmn' => '±', 'mnplus' => '∓', 'mp' => '∓', 'times' => '×', 'sup1' => '¹', 'sup2' => '²', 'sup3' => '³', 
		'frac14' => '¼', 'frac12' => '½', 'frac34' => '¾', 'alpha' => 'α', 'beta' => 'β', 'gamma' => 'γ', 'delta' => 'δ', 'epsilon' => 'ε', 'micro' => 'µ',
		'percnt' => '%', 'permil' => '‰', 'pertenk' => '‱', 
	);
	s/&#(\d+);/chr($1)/ge;
	s/(&([a-z]+);)/($table{$2} || $1)/ge;
	s/&null;//g;
	s/&amp;/&/g;
	return $_;
}

sub s_lut {
	my ($str, $regexp, $table);
	if (scalar(@_)==2) {
		($str,$table) = @_;
		$regexp = '([' . join('', keys(%{$table})) . '])';
	} else {
		($str, $regexp, $table) = @_;
	}
	$str =~ s|$regexp| $table->{$1} // $1 |ge;
	return $str;
}

sub roman_ligatures {
	my $str = shift;
	$str = s_lut($str, '([ivx]+|[IVX]+)', {
		'I'=>'Ⅰ', 'II'=>'Ⅱ', 'III'=>'Ⅲ', 'IV'=>'Ⅳ', 'V'=>'Ⅴ', 'VI'=>'Ⅵ', 'VII'=>'Ⅶ', 'VIII'=>'Ⅷ', 'IX'=>'Ⅸ', 'X'=>'Ⅹ', 
		'XI'=>'Ⅺ', 'XII'=>'Ⅻ', 'XIII'=>'ⅩⅢ', 'XIV'=>'ⅩⅣ', 'XV'=>'ⅩⅤ', 'XVI'=>'ⅩⅥ', 'XVII'=>'ⅩⅦ', 'XVIII'=>'ⅩⅧ', 'XIX'=>'ⅩⅨ', 'XX'=>'ⅩⅩ', 
		'i'=>'ⅰ', 'ii'=>'ⅱ', 'iii'=>'ⅲ', 'iv'=>'ⅳ', 'v'=>'ⅴ', 'vi'=>'ⅵ', 'vii'=>'ⅶ', 'viii'=>'ⅷ', 'ix'=>'ⅸ', 'x'=>'ⅹ', 
		'xi'=>'ⅺ', 'xii'=>'ⅻ', 'xiii'=>'ⅹⅲ', 'xiv'=>'ⅹⅳ', 'xv'=>'ⅹⅴ', 'xvi'=>'ⅹⅵ', 'xvii'=>'ⅹⅶ', 'xviii'=>'ⅹⅷ', 'xix'=>'ⅹⅸ', 'xx'=>'ⅹⅹ', 
	});
	return $str;
}

sub canonic_name {
	local $_ = shift;
	tr/–־/-/;
	tr/״”“„/"/;
	tr/׳‘’/'/;
	tr/\x{05B0}-\x{05BD}//d;
	tr/אּ-תּ/א-ת/;
	s/ - / – /g;
	s/^ *(.*?) *$/$1/;
	s/ {2,}/ /g;
	# s/\(\((?|\[(.*?)\]|(.*?))\)\)/$1/g;
	# s/<הערה>(?|\[(.*?)\]|(.*?))<\/הערה>\)\)/$1/g;
	return $_;
}

sub fix_tags {
	local $_ = shift;
	tr/–/-/;
	tr/“”״/"/;
	s/\{\{==?\}\}/=/g;
	return $_;
}

sub escape_eqsign {
	local $_ = shift;
	s/\{\{==?\}\}/⌸/g;
	s/(\<[^>]+\>)/ $1 =~ s|=|⌸|gr /eg;
	s/⌸/\{\{=\}\}/g;
	tr/⌸/=/;
	return $_;
}

sub dump_hash {
	my $h = shift;
	return join('; ', map("$_ => '" . ($h->{$_} // "[undef]") . "'", keys(%{$h})));
}


#---------------------------------------------------------------------

our %glob;
our %hrefs;
our %sections;
our @lookahead;
our (@line, $idx);

sub cleanup {
	$do_expand = 0;
	$div_table = 0;
	undef %glob; undef %hrefs; undef %sections; undef @line;
	undef $pubdate;
	$glob{context} = '';
	$glob{href}{last_class} = '';
	$glob{level} = ['','','',''];
	$glob{part_type} = $glob{sect_type} = $glob{subs_type} = 0;
}

sub linear_parser {
	cleanup();
	local $_ = shift;
	
	foreach my $l (@lookahead) { process_href($l, '++'); }
	undef @lookahead;
	
	my @sec_list = (m/<קטע [^>]*?עוגן="(.*?)">/g);
	check_structure(@sec_list);
	# print STDERR "part_type = $glob{part_type}; sect_type = $glob{sect_type}; subs_type = $glob{subs_type};\n";
	
	@line = split(/(<(?: "[^"]*"|[^>])*>|__[A-Z]+__)/, $_);
	$idx = 0;
	for (@line) {
		if (/__TOC__/) {
			# Clear all section references above TOC.
			undef %sections;
		} elsif (/<(.*)>/) {
			parse_element($1);
		} elsif ($glob{context} eq 'href') {
			$glob{href}{txt} .= $_;
		}
		$idx++;
		$glob{href}{last_class} = '' if /\n$/;
	}
	
	for (keys %hrefs) {
		$hrefs{$_} =~ /(\d*);(.*)/;
		my $type = $1;
		my $href = escape_quote($2);
		$line[$_] = "<קישור סוג=\"$type\" עוגן=\"$href\">";
	}
	for (keys %sections) {
		$line[$_] =~ s/<(קטע דרגה="\d").*?>/<$1 עוגן="$sections{$_}">/;
	}
	
	return join('',@line);
}

sub parse_element {
	my $all = shift;
	my ($element, $params) = split(/ |$/,$all,2);
	
	given ($element) {
		when (/^קטע/) {
			process_section($params);
		}
		when (/^סעיף/) {
			process_chapter($params);
			$glob{href}{last_class} = 'chap';
		}
		when (/^תיאור/) {
			# Split, ignore outmost parenthesis.
			my @inside = split(/(<[^>]*>)/, $all);
			continue if ($#inside<=1);
			$inside[0] =~ s/^/</; $inside[-1] =~ s/$/>/;
			# print STDERR "Spliting: |" . join('|',@inside) . "| (";
			# print STDERR "length $#line -> ";
			splice(@line, $idx, 1, @inside);
			# print STDERR "$#line)\n";
		}
		when (/^קישור/) {
			$glob{context} = 'href';
			# ($params) = ($params =~ /(?|.*עוגן="(.*?)"|()/);
			# print STDERR "GOT href at $idx with |$params|\n";
			$glob{href}{helper} = $params || '';
			$glob{href}{txt} = '';
			$glob{href}{idx} = $idx;
			$hrefs{$idx} = '';
			$params = "#" . $idx;
		}
		when (/^\/קישור/) {
			my $href_idx = $glob{href}{idx};
			$hrefs{$href_idx} = process_href();
			# print STDERR "GOT href at $href_idx = |$hrefs{$href_idx}|\n";
			$glob{context} = '';
		}
		when (/^(\/?)הערה/) {
			# Insert comment mark "((...))" into href text
			$glob{href}{txt} .= ($1 ? '))' : '((') if ($glob{context} eq 'href');
		}
		when (/^\/?(s|strike)$/) {
			# Insert <s>...</s> into href text, so href can ignore the strikethrough text
			$glob{href}{txt} .= "<$element>" if ($glob{context} eq 'href');
		}
		when (/^(tr|td|th|table|div)$/) {
			process_div_id($params);
		}
		default {
			# print STDERR "GOT element $element.\n";
		}
	}
	
}

sub process_section {
	my $params = shift;
	my ($level,$name);
	($level) = ($params =~ /(?|.*דרגה="(.*?)"|())/);
	($name) = ($params =~ /(?|.*עוגן="(.*?)"|())/);
	my ($type,$num) = split(/ /, $name || ' ');
	# print STDERR "process_section with \$level=|$level|, \$type=|$type|, \$num=|$num|, \$name=|$name|\n";
	$type =~ s/\(\(.*?\)\)//g if (defined $type);
	given ($type) {
		when (undef) {}
		when (/חלק/) { $glob{href}{prev}{part} = $glob{part}; $glob{part} = $num; $glob{sect} = $glob{subs} = $glob{subsub} = undef; }
		when (/פרק/) { $glob{href}{prev}{sect} = $glob{sect}; $glob{sect} = $num; $glob{subs} = $glob{subsub} = undef; }
		when (/סימן/) { $glob{href}{prev}{subs} = $glob{subs}; $glob{subs} = $num; $glob{subsub} = undef; }
		when (/משנה/) { $glob{href}{prev}{subsub} = $glob{subsub}; $glob{subsub} = $num; }
		when (/לוחהשוואה/) { delete @glob{"part", "sect", "subs", "subsub", "supl", "appn", "form", "tabl", "tabl2"}; }
		when (/תוספת/) { $glob{href}{prev}{supl} = $glob{supl}; $glob{supl} = ($num || ""); delete @glob{"part", "sect", "subs", "subsub", "appn", "form", "tabl", "tabl2"}; $glob{level}[0] = ''; }
		when (/נספח/) { $glob{href}{prev}{appn} = $glob{appn}; $glob{appn} = ($num || ""); delete @glob{"part", "sect", "subs", "subsub"}; $glob{level}[0] = ''; }
		when (/טופס/) { $glob{href}{prev}{form} = $glob{form}; $glob{form} = ($num || ""); delete @glob{"part", "sect", "subs", "subsub"}; $glob{level}[0] = ''; }
		when (/לוח/) { $glob{href}{prev}{tabl} = $glob{tabl}; $glob{tabl} = ($num || ""); delete @glob{"part", "sect", "subs", "subsub"}; $glob{level}[0] = ''; }
		when (/טבלה/) { $glob{href}{prev}{tabl2} = $glob{tabl2}; $glob{tabl2} = ($num || ""); delete @glob{"part", "sect", "subs", "subsub"}; $glob{level}[0] = ''; }
	}
	splice @{$glob{level}}, $level-1, 4-$level, ($name, '', '', '');
	# print STDERR "process_section: |$glob{level}[0]|$glob{level}[1]|$glob{level}[2]|$glob{level}[3]|\n";
	if ($type) {
		return if ($type =~ 'טופס' && !$num);
		$name = "סימן $glob{subs} $name" if ($type =~ 'משנה' && defined $glob{subs});
		$name = "פרק $glob{sect} $name" if ($type =~ 'סימן|משנה' && defined $glob{sect});
		$name = "חלק $glob{part} $name" if ($type =~ 'סימן|פרק|משנה' && ($glob{sect_type}==3 || defined $glob{supl}) && defined $glob{part});
		$name = "תוספת $glob{supl} $name" if ($type ne 'תוספת' && defined $glob{supl});
		$name = "לוחהשוואה" if ($type eq 'לוחהשוואה');
		$name =~ s/  / /g;
		$sections{$idx} = $name;
	}
}

sub process_chapter {
	my $params = shift;
	return unless $params =~ /עוגן="(?:סעיף |)([^"]+)"/;
	my $num = $1;
	if (defined($num) && !$num) { $num = '0'; } else { $num //= ''; }
	my $exact = ($num =~ s/^ *[=*] *//) || 0;
	my $ankor = '';
	if (!$num || $num eq '-') {
		$ankor = '-';
	} elsif ($exact) {
		my $last_class = $glob{href}{last_class};
		($ankor, undef) = find_href($num);
		$glob{href}{last_class} = $last_class;
	} elsif ((defined $glob{supl} || defined $glob{appn} || defined $glob{tabl}) && $num) {
		$ankor = $num;
		$ankor = "פרט $ankor" if ($ankor =~ /^\d|^$heb_num3(\d+[א-י]*)?$/);
		$ankor = "סימן $glob{subs} $ankor" if (defined $glob{part} && defined $glob{subs});
		$ankor = "חלק $glob{part} $ankor" if (defined $glob{part});
		$ankor = "לוח $glob{tabl} $ankor" if (defined $glob{tabl});
		$ankor = "טבלה $glob{tabl2} $ankor" if (defined $glob{tabl2});
		$ankor = "נספח $glob{appn} $ankor" if (defined $glob{appn});
		$ankor = "תוספת $glob{supl} $ankor" if (defined $glob{supl});
		$ankor =~ s/  / /g;
	} elsif ($num) {
		$glob{href}{prev}{chap} = $glob{chap};
		$glob{chap} = $num;
		$ankor = "סעיף $num";
	}
	# print STDERR "process_chapter with \$num=\"$num\" and \$exact=\"$exact\" => \$ankor=\"$ankor\"\n";
	$line[$idx] =~ s/ עוגן=".*?"/ עוגן="$ankor"/;
}

sub process_div_id {
	my $params = shift;
	return unless $params =~ /id="(.*?)"/;
	my $id = $1 // '';
	if ($id) {
		my $last_class = $glob{href}{last_class};
		($id, undef) = find_href($id);
		$glob{href}{last_class} = $last_class;
		$line[$idx] =~ s/id=".*?"/id="$id"/;
	}
}

sub current_position {
	my @type = ( 'supl', 'תוספת', 'appn', 'נספח', 'form', 'טופס', 'tabl', 'לוח', 'tabl2', 'טבלה', 'part', 'חלק', 'sect', 'פרק', 'subs', 'סימן', 'subsub', 'משנה' );
	my $str = '';
	for (my $i=0; $i < @type; $i +=2) {
		$str .= " $type[$i+1] $glob{$type[$i]}" if (defined $glob{$type[$i]});
	}
	$str =~ s/^ +//;
	return $str;
}

#---------------------------------------------------------------------

sub insert_TOC {
	local $_;
	# my $str = "<קטע דרגה=\"2\">תוכן עניינים</קטע>\n\n<סעיף></סעיף>\n";
	my $str = "<קטע דרגה=\"2\">תוכן עניינים</קטע>\n\n";
	$str .= "<div class=\"law-toc\">\n";
	my ($name, $indent, $text, $next, $style, $skip);
	for (sort {$a <=> $b} keys %sections) {
		$text = $next = '';
		$name = $sections{$_};
		$indent = $line[$_++];
		$indent = ($indent =~ /<קטע דרגה="(\d)"/ ? $1 : 2);
		$text .= $line[$_++] while ($text !~ /\n/ and defined $line[$_]);
		$next .= $line[$_++] while ($next !~ /\n/ and defined $line[$_]);
		if ($next =~ /(<הערה>|\(\()[^)]*<קישור/) {
			$next = '';
			$next .= $line[$_++] while ($next !~ /\n/ and defined $line[$_]);
		}
		next if ($skip and $indent>$skip);
		next if ($indent>3);
		if ($text =~ /__NOTOC__/) { $skip = $indent; next; }
		$skip = 0;
		$skip = $indent if ($text =~ s/ *__NOSUB__//);
		$text =~ s/<\/קטע>//;
		$text =~ s/<(תיקון|אחר).*?>.*?<\/\1>//g;
		# $text =~ s/<(תיקון|אחר).*?> *//g;
		$text =~ s/<הערה>([^)]*<קישור.*?>.*?<\/.*?>.*?)+<\/.*?> *//g;
		$text =~ s/\(\(.?<קישור.*?>.*?<\/.*?>.?\)\) *//g;
		$text =~ s/<קישור.*?>(.*?)<\/.*?>/$1/g;
		$text =~ s/<b>(.*?)<\/b?>/$1/g;
		$text =~ s/ *\{\{ש\}\} */: /;
		$text =~ s/ +$//;
		($text) = ($text =~ /^ *(.*?) *$/m);
		if ($next =~ /^<קטע דרגה="(\d)"> *(.*?) *$/m && $1>=$indent && !$skip) {
			$next = $2;
			$next =~ s/<\/קטע>//;
			$next =~ s/<(תיקון|אחר).*?>.*?<\/\1>//g;
			# $next =~ s/<(תיקון|אחר).*?> *//g;
			$next =~ s/<קישור.*?>(.*?)<\/.*?>/$1/g;
			$next =~ s/<b>(.*?)<\/b?>/$1/g;
			$next =~ s/^<הערה.*?>.*?<\/.*?>$//g;
			unless ($next) {
			} elsif ($text =~ /^(.*?) *(<הערה>.*<\/>$)/) {
				$text = "$1: {{מוקטן|$next}} $2";
			} else {
				$text .= ": {{מוקטן|$next}}";
			}
		}
		given ($indent) {
			when ($_==1) { $style = "law-toc-1"; }
			when ($_==2) { $style = "law-toc-2"; }
			when ($_==3) { $style = "law-toc-3"; }
		}
		# print STDERR "Visiting section |$_|$indent|$name|$text|\n";
		$str .= "<div class=\"$style\"><קישור סוג=\"1\" עוגן=\"$name\">$text</קישור></div>\n";
	}
	$str .= "</div>\n";
	return $str;
}

sub check_structure {
	my %types;
	$glob{part_type} = $glob{sect_type} = $glob{subs_type} = 0;
	for (@_) {
		if (/תוספת|נספח|טופס|לוח|טבלה/) { last; }
		/^(.*?) (.*?)$/;
		next unless defined($1) && defined($2);
		# print STDERR "Got |$1|$2|\n";
		if (++$types{$1}{$2} > 1) {
			if ($1 eq 'פרק') { $glob{sect_type} = 3; }
			if ($1 eq 'סימן') { $glob{subs_type} = 3; }
		} else {
			if ($1 eq 'חלק' and !$glob{part_type}) { $glob{part_type} = 1; }
			if ($1 eq 'פרק' and !$glob{sect_type}) { $glob{sect_type} = 1; }
			if ($1 eq 'סימן' and !$glob{subs_type}) { $glob{subs_type} = 1; }
		}
	}
}

#---------------------------------------------------------------------

sub push_lookahead {
	my $s = shift;
	# print STDERR "Adding lookahead '$s'\n";
	push @lookahead, $s;
}

sub process_href {
	my ($text, $helper, $id);
	if (@_>=1) {
		$text = shift;
		$helper = shift // '';
		$id = 0;
	} else {
		$text = $glob{href}{txt};
		$helper = $glob{href}{helper};
		$id = $glob{href}{idx};
	}
	
	# Canonic name
	$text = canonic_name($text);
	$helper = canonic_name($helper);
	
	my $linkset = ($helper =~ s/^[»«]>//);
	$helper =~ s/\$/ $text /;
	
	my ($int,$ext) = find_href($text);
	# my ($helper_int,$helper_ext) = find_href($helper);
	my $marker = '';
	my $found = false;
	my $hash = false;
	my $update_lookahead = false;
	my $update_mark = false;
	
	my $type = ($ext) ? 3 : 1;
	
	$ext = '' if ($type == 1);
	
	# print STDERR "## X |$text| X |$ext|$int| X |$helper|\n";
	
	if ($helper =~ /^(קובץ|[Ff]ile|תמונה|[Ii]mage):/) {
		return '';
	} elsif ($helper =~ /^https?:\/\/|[ws]:/i) {
		$type = 4;
		(undef, $ext) = find_href($helper);
		$int = $helper = '';
		$found = true;
	} elsif ($helper =~ /^(.*?)#(.*)/) {
		my ($helper_int,$helper_ext) = find_href($helper);
		$type = 3;
		$helper = $1 || $ext;
		# $ext = '' if ($1 ne '');
		$int = $helper_int; $ext = $helper_ext;
		# (undef,$ext) = find_href($1); $int = $2;
		($int, undef) = find_href("+#$2") if ($2);
		$found = true;
		$hash = ($2 eq '');
	}
	
	# print STDERR "## X |$text| X |$ext|$int| X |$helper|\n";
	
	if ($helper =~ /^(.*?) *= *(.*)/) {
		$type = 3;
		$ext = $1; $helper = $2;
		(undef, $ext) = find_href($text, $helper) if ($ext eq '');
		(undef, $helper) = find_href($text, $text) if ($helper eq '');
		$helper =~ s/^ה//; $helper =~ s/[-: ]+/ /g;
		(undef, $ext) = find_href($ext, $helper);
		$ext = find_href_mark($ext);
		$update_mark = true;
	} elsif ($helper) {
		my ($helper_int,$helper_ext) = find_href($helper);
		# print STDERR "## X |$text| X |$helper_ext|$helper_int| X |$helper|\n";
		if ($found) {
			$ext = ($helper_ext ne '' ? $helper_ext : $helper);
		} elsif (defined $glob{href}{marks}{$helper =~ s/[-: ]+/ /gr}) {
			$ext = find_href_mark($helper);
		} else {
			$int = $helper_int and $found = true if ($helper_int);
			$ext = $helper_ext;
		}
		$type = ($ext) ? 3 : 1;
	}
	
	# print STDERR "process_href \$text=|$text| \$ext=|$ext| \$int=|$int| X \$helper=|$helper|\n";
	
	if ($ext eq '+') {
		$type = 2;
		($int, $ext) = find_href("+#$text") unless ($found);
		push @{$glob{href}{ahead}}, $id if ($id);
	} elsif ($ext eq '++') {
		$type = 3;
		(undef, $helper) = find_href($text, $helper);
		$ext = $helper ? "++$helper" : "++$text";
		# $helper =~ s/^ה//;
		# $glob{href}{all_marks} .= "|ה?$text";
		# $glob{href}{all_marks} .= "|ה?$helper" if ($helper && $helper ne $text);
		# $glob{href}{all_marks} =~ s/^\|//;
		# $glob{href}{marks}{$helper} = $ext;
		# $helper = '';
	} elsif ($ext eq '-') {
		$type = 2;
		$ext = $glob{href}{last} // '';
		($int, undef) = find_href("-#$text") unless ($found);
		$update_lookahead = true;
		if ($ext =~ /\+\+(.*)/) {
			$helper = $1;
			push @{$glob{href}{marks_ahead}{$helper}}, $id if ($id);
		}
	}
	
	# print STDERR "## X |$text| X |$ext|$int| X |$helper|\n";
	
	if ($update_mark) {
		$helper =~ s/[-: ]+/ /g;
		$glob{href}{marks}{$helper} = $glob{href}{marks}{"ה$helper"} = $ext;
		# print STDERR "adding mark '$helper' to '$ext'\n";
		unless ($helper =~ /$extref_sig/) {
			$glob{href}{all_marks} .= "|ה?$helper";
			$glob{href}{all_marks} =~ s/^\|//;
			# print STDERR "adding mark 'ה$helper' to '$ext'\n";
		}
		for (@{$glob{href}{marks_ahead}{$helper}}, @{$glob{href}{marks_ahead}{"ה$helper"}}) {
			$hrefs{$_} =~ s/\+[^#]*(.*)/$ext$1/;
		}
		$glob{href}{marks_ahead}{$helper} = [];
	}
	
	if ($ext) {
		$helper = $ext =~ s/[-: ]+/ /gr;
		$ext = $glob{href}{marks}{$helper} if ($glob{href}{marks}{$helper});
		$text = ($int && ($ext !~ /^https?:\/\//) ? "$ext#$int" : $ext);
		if ($type==3 || $update_lookahead) {
			$glob{href}{last} = $ext;
			if ($ext =~ /\+\+(.*)/) {
				$helper = $1;
				$glob{href}{marks}{$helper} = $ext;
				push @{$glob{href}{marks_ahead}{$helper}}, $id if ($id>0);
				push @{$glob{href}{marks_ahead}{$helper}}, @{$glob{href}{ahead}} if ($glob{href}{ahead});
			} else {
				if ($ext !~ /^https?:\/\//) {
					for (@{$glob{href}{ahead}}) { $hrefs{$_} =~ s/\+[^#]*(.*)/$ext$1/; }
				} else {
					for (@{$glob{href}{ahead}}) { $hrefs{$_} = $ext; }
				}
			}
			$glob{href}{ahead} = [];
		}
	} else {
		$text = $int;
	}
	# $glob{href}{ditto} = $text;
	
	return "$type;$text";
}

sub find_href {
	local $_ = shift;
	my $helper = shift // '';
	if (!$_) { return $_; }
	
	# print STDERR "find_href |$_|; \$helper=|$helper|;\n\t\$ditto before " . dump_hash($glob{href}{ditto}) . "\n";
	
	my $ext = '';
	$_ = find_reshumot_href($_);
	
	if (/^HTTPS?:/) { $_ = lc($_); }
	if (/^(https?:|mailto:)/) {
		s/%([Dd][0-9A-Fa-f])%([0-9A-Fa-f]{2})/decode_utf8(chr(hex($1)).chr(hex($2)))/ge;
		return ('', $_);
	}
	if (/^([wsWS]:|קובץ:|[Ff]ile:|תמונה:|[Ii]mage:)/) {
		s/&#(\d+);/chr($1)/ge;
		return ('', $_); 
	}
	
	my $exact = (/\*/);
	
	# s/\(\(\((.*?)\)\)\)/(([$1]))/g;                 # Better to keep parenthesis inside a comment,
	s/\(\(\(((?:במקור|צ["״]ל:).*?)\)\)\)/(([$1]))/g;  # unless it's a special case
	s/\(\(\[במקור: .*?\]\)\)//g;
	s/\(\(<s>.*?<\/s>\)\)//g;
	s/$date_sig *\(\(\[צ["״]ל:$date_sig\]\)\)$//;
	s/\(\(\[(?:צ["״]ל: *)(.*?)\]\)\)/$1/g;
	s/\(\((?|\[(.*?)\]|(.*?))\)\)/$1/g;
	
	if (/^(.*?)#(.*)$/) {
		$_ = $2;
		$ext = find_ext_ref($1);
	}
	if (/^[-+]+$/) { return ('', $_); }
	
	s/$pre_sig(הגדר(ה|ו?ת)|מונח(ים)?) ["”“][^"”“]+["”“] ((ו[-־]?|או )["”“][^"”“]+["”“])*//g;
	
	# Avoid special cases of internal hrefs
	s/(סימן|סימנים)/סעיף/ if (/דברי?[- ]ה?מלך/ and /(סימן|סימנים) \d/);
	s/$pre_sig(תקנו?ת[ -]משנה)//g;
	
	s/المادة|المادتان|المادتين/סעיף/g; s/الفصل|الفصلين|الفصول/פרק/g;
	
	s/(\b[בלמ]?(אות[הוםן])\b) *($extref_sig[- ]*([א-ת]+\b.*)?)$/$4 $2/;
	if (/^(.*?) *\b($extref_sig\b[- ]*(?:[א-ת]+\b.*|[א-ת].*תש.?["״]?.[-–]\d{4}|))$/) {
		# Ignore in special case
		unless (substr($1,-1) eq '(' and substr($2,-1) eq ')') {
			$_ = $1;
			$ext = find_ext_ref($2) unless ($ext);
		}
	} elsif (/^(.*?) *\b$extref_sig(.*?)$/ and $glob{href}{marks}{"$2$3"}) {
		$ext = "$2$3";
		$_ = $1;
	} elsif ($glob{href}{all_marks} and /^(.*?) *\b$pre_sig($glob{href}{all_marks})\b(.*?)$/) {
		$ext = "$2$3";
		$_ = $1;
	}
	
	if ($ext =~ /^$extref_sig( *)(.*)$/) {
		my ($e1,$e3) = ("$1$2", $3);
		my $e2 = $ext =~ s/[-– ]+/ /gr;
		if ($e3 eq '' and !defined $glob{href}{marks}{$e2} and !$helper) {
			$ext = '0';
		} elsif ($e3 =~ /^ה?(?:זאת|זו|זה|אלה|אלו)\b(.*)$/) {
			$ext = '0';
			$_ .= $1;
		} elsif ($e3 =~ /^[בלמ]?(?:[הכ]אמור(?:|ה|ות|ים)|אות[הוםן]|שב[הו]|הה[וי]א)\b(.*)$/) {
			$ext = '-' ;
			$_ .= $1;
		}
	}
	
	s/((?:סעי[פף]|תקנ[הת]|פסק[האת]|פרט)\S*) (קטן|קטנים|משנה) (\d[^( ]*?)(\(.*?\))/$1 $3 $2 $4/;
	s/\(/ ( /g;
	s/(פרי?ט|פרטים) \(/$1/g;
	s/["'״׳]//g;
	s/\bו-//g;
	s/\b$pre_sig(או|מן|סיפ[הא]|ריש[הא])\b( של\b|)/ /g;
	s/^ *(.*?) *$/$1/;
	s/לוח השוואה/לוחהשוואה/;
	s/סימ(ן|ני) משנה/סימןמשנה/;
	s/$pre_sig(אות[והםן]) $type_sig/$2 $1/g;
	s/\b($pre_sig)($type_sig)$/$2 this/ unless ($ext);
	
	my $href = $_;
	my $class = '';
	my ($num, $numstr);
	my %elm = ();
	
	my @pos = ();
	push @pos, $-[0] while ($_ =~ /([^ ,.\-\)*]+)/g);
	
	for my $p (@pos) {
		$_ = substr($href,$p);
		# s/ .*//;
		$num = undef;
		given ($_) {
			when (/לוחהשוואה/) { $class = 'comptable'; $num = ""; }
			when (/^$pre_sig(חלק|חלקים|שער|שערים)/) { $class = 'part'; }
			when (/^$pre_sig(פרק|פרקים)/) { $class = 'sect'; }
			when (/^$pre_sig(סימןמשנה)/) { $class = 'subsub'; }
			when (/^$pre_sig(סימן|סימנים)/) { $class = 'subs'; }
			when (/^$pre_sig(תוספת|תוספות)/) { $class = 'supl'; $num = ""; }
			when (/^$pre_sig(נספח|נספחים)/) { $class = 'appn'; $num = ""; }
			when (/^$pre_sig(טופס|טפסים)/) { $class = 'form'; }
			when (/^$pre_sig(לוח|לוחות)/) { $class = 'tabl'; }
			when (/^$pre_sig(טבל[הא]|טבלאות)/) { $class = 'tabl2'; }
			when (/^$pre_sig(מפה|מפות)/) { $class = 'map'; }
			when (/^$pre_sig(סעיף|סעיפים|תקנה|תקנות|אמו?ת[ -]ה?מידה|כלל|כללים)/) { $class = 'chap'; }
			when (/^$pre_sig(פריט|פרט)/) { $class = 'supchap'; }
			when (/^$pre_sig(קט[נן]|פי?סק[האת]|פסקאות|משנה|טור)/) { $class = 'small'; }
			when (/^\(/) { 
				if (($class ? $class : $glob{href}{last_class}) eq 'supchap') {
					$class = 'supchap';
				} elsif ($class eq 'chap') {
					$class = 'chap_';
				} elsif ($class ne '' and !defined $elm{$class}) {
					# Keep class
				} else {
					$class = 'small';
				}
			}
			when (/^ה?(זה|זו|זאת|this)\b/) {
				given ($class) {
					when (/^(supl|appn|form|tabl|table2|map)$/) { $num = $glob{$class} || ''; }
					when (/^(part|sect|form|chap)$/) { $num = $glob{$class}; }
					when (/^subs$/) {
						$elm{subs} = $glob{subs} unless defined $elm{subs};
						$elm{sect} = $glob{sect} unless defined $elm{sect};
					}
					when (/^subsub$/) {
						$elm{subsub} = $glob{subsub} unless defined $elm{subsub};
						$elm{subs} = $glob{subs} unless defined $elm{subs};
						$elm{sect} = $glob{sect} unless defined $elm{sect};
					}
				}
				$elm{supl} = $glob{supl} if ($glob{supl} && !defined($elm{supl}));
			}
			when (/^$pre_sig(קוד(ם|מת)|אחרו(ן|נה))\b/) {
				$elm{$class} = $glob{href}{prev}{$class} if defined $glob{href}{prev}{$class};
			}
			when (/^([מל]?אות[והםן]|הה[וי]א|הה[םן]|האמור(ה|ים|ות|)|ש?ב[הו]|דלעיל)\b/) {
				$elm{$class} ||= $glob{href}{ditto}{$class} if $glob{href}{ditto}{$class};
				$ext = $glob{href}{ditto}{ext};
				given ($class) {
					when (/^subs$/) {
						$elm{sect} = $glob{href}{ditto}{sect} unless defined $elm{sect};
						$elm{part} = $glob{href}{ditto}{part} unless defined $elm{part};
					}
					when (/^subsub$/) {
						$elm{subs} = $glob{href}{ditto}{subs} unless defined $elm{subs};
						$elm{sect} = $glob{href}{ditto}{sect} unless defined $elm{sect};
						$elm{part} = $glob{href}{ditto}{part} unless defined $elm{part};
					}
				}
				# $elm{supl} = $glob{href}{ditto}{supl} unless defined $elm{supl};
				# print STDERR "DITTO \"$class\"\n";
				# print STDERR "\t\$href:  $href\n";
				# print STDERR "\t\$helper: $helper\n" if ($helper);
				# print STDERR "\t\$ditto: " . dump_hash($glob{href}{ditto}) . "\n";
				# print STDERR "\t\$elm:   " . dump_hash(\%elm) . "\n";
			}
			when (/\*/) {
				$exact = true;
			}
			default {
				s/^[לב]-(\d.*)/$1/;
				$num = get_numeral($_);
				$num = '' if ($num =~ /^[א-ת]{2,}$/ && $class eq '' && $p>10);
				if ($num ne '' && $class eq '') {
					$class = (/^\d+/) ? 'chap_' : ($glob{href}{last_class} || 'chap_');
					# $class = ($glob{href}{last_class} || 'chap_');
					$class = 'supchap' if ($glob{href}{last_class} eq 'supchap');
				}
			}
		}
		# print STDERR " --> |$_|$class|" . ($num || '') . "|\n";
		
		if (defined($num) && !$elm{$class}) {
			$elm{$class} = $num;
		}
	}
	
	$elm{chap} = $elm{chap_} if (defined $elm{chap_} and !defined $elm{chap});
	$elm{ext} = $ext // '';
	
	$glob{href}{last_class} = $elm{supchap} ? 'supchap' : $elm{chap} ? 'chap' : $elm{form} ? 'form' : $elm{subsub} ? 'subsub' : $elm{subs} ? 'subs' : $elm{sect} ? 'sect' : $elm{part} ? 'part' : $class eq 'small' ? '' : $class;
	
	$glob{href}{ditto}{ext} = $ext if (defined $glob{href}{ditto}{ext} and ($ext) and $glob{href}{ditto}{ext} eq '+');
	
	if ($helper && defined $glob{href}{ditto}{ext}) {
		$glob{href}{ditto}{ext} = $helper;
		# print STDERR "\t\$ditto set to '$ext'.\n";
	} elsif (defined $glob{href}{ditto}{ext} and defined $elm{ext} and $glob{href}{ditto}{ext} eq $elm{ext}) {
		foreach my $key (keys(%elm)) {
			$glob{href}{ditto}{$key} = $elm{$key};
		}
		# print STDERR "\t\$ditto of '$ext' set to: " . dump_hash($glob{href}{ditto}) . "\n";
	} else {
		$glob{href}{ditto} = \%elm;
		# print STDERR "\t\$ditto set to: " . dump_hash($glob{href}{ditto}) . "\n";
	}
	
	# print STDERR "\t\$ditto after " . dump_hash($glob{href}{ditto}) . "\n";
	
	$exact = true if ($ext ne '');
	
	$href = '';
	if (defined $elm{comptable}) {
		$href = "לוחהשוואה";
	} elsif (defined $elm{supl}) {
		$elm{supl} = $elm{supl} || $glob{supl} || '' unless ($ext ne '');
		$elm{supchap} = $elm{supchap} || $elm{chap};
		$href = "תוספת $elm{supl}";
		$href .= " חלק $elm{part}" if (defined $elm{part});
		$href .= " פרק $elm{sect}" if (defined $elm{sect});
		$href .= " סימן $elm{subs}" if (defined $elm{subs});
		$href .= " טופס $elm{form}" if (defined $elm{form});
		$href .= " לוח $elm{tabl}" if (defined $elm{tabl});
		$href .= " טבלה $elm{tabl2}" if (defined $elm{tabl2});
		$href .= " נספח $elm{appn}" if (defined $elm{appn});
		$href .= " מפה $elm{map}" if (defined $elm{map});
		$href .= " פרט $elm{supchap}" if (defined $elm{supchap});
	} elsif (defined $elm{form} || defined $elm{tabl} || defined $elm{tabl2} || defined $elm{appn} || defined $elm{map}) {
		$elm{supchap} = $elm{supchap} || $elm{chap};
		$href = "טופס $elm{form}" if (defined $elm{form});
		$href = "לוח $elm{tabl}" if (defined $elm{tabl});
		$href = "טבלה $elm{tabl2}" if (defined $elm{tabl2});
		$href = "נספח $elm{appn}"  if (defined $elm{appn});
		$href = "מפה $elm{map}"  if (defined $elm{map});
		$href .= " חלק $elm{part}" if (defined $elm{part});
		$href .= " פרק $elm{sect}" if (defined $elm{sect});
		$href .= " סימן $elm{subs}" if (defined $elm{subs});
		$href .= " פרט $elm{supchap}" if (defined $elm{supchap});
	} elsif (defined $elm{part}) {
		$href = "חלק $elm{part}";
		$href .= " פרק $elm{sect}" if (defined $elm{sect});
		$href .= " סימן $elm{subs}" if (defined $elm{subs});
		$href .= " משנה $elm{subsub}" if (defined $elm{subsub});
	} elsif (defined $elm{sect}) {
		$href = "פרק $elm{sect}";
		$href .= " סימן $elm{subs}" if (defined $elm{subs});
		$href .= " משנה $elm{subsub}" if (defined $elm{subsub});
		$href = "חלק $glob{part} $href" if ($glob{sect_type}==3 && defined $glob{part} && !$exact);
		# $href = "תוספת $glob{supl} $href" if ($glob{supl} && !$exact);
	} elsif (defined $elm{subs}) {
		$href = "סימן $elm{subs}";
		$href .= " משנה $elm{subsub}" if (defined $elm{subsub});
		$href = "פרק $glob{sect} $href" if (defined $glob{sect} && !$exact);
		$href = "חלק $glob{part} $href" if ($glob{sect_type}==3 && defined $glob{part} && !$exact);
		# $href = "תוספת $glob{supl} $href" if (defined $elm{supl} && $glob{supl} && $ext eq '');
	} elsif (defined $elm{subsub}) {
		$href = "משנה $elm{subsub}";
		$href = "סימן $glob{subs} $href" if (defined $glob{subs} && !$exact);
		$href = "פרק $glob{sect} $href" if (defined $glob{sect} && !$exact);
		$href = "חלק $glob{part} $href" if ($glob{sect_type}==3 && defined $glob{part} && !$exact);
		# $href = "תוספת $glob{supl} $href" if (defined $elm{supl} && $glob{supl}  && !$exact);
	} elsif (defined $elm{chap}) {
		$href = "סעיף $elm{chap}";
	} elsif (defined $elm{supchap}  && !$exact) {
		$href = "פרט $elm{supchap}";
		$href = "חלק $glob{part} $href" if (defined $glob{part});
		$href = "לוח $glob{tabl} $href" if (defined $glob{tabl});
		$href = "טבלה $glob{tabl2} $href" if (defined $glob{tabl2});
		$href = "תוספת $glob{supl} $href" if (defined $glob{supl});
	} else {
		$href = "";
	}
	
	$href =~ s/  / /g;
	$href =~ s/^ *(.*?) *$/$1/;
	
	if (false) {
		print STDERR "\$elm: " . dump_hash(\%elm) . "\n";
		print STDERR "GOT |$href|$ext|\n";
	}
	return ($href,$ext);
}	

sub find_reshumot_href {
	my $url = shift;
	$url =~ s/^ *(.*?) *$/$1/;
	$url = "https://fs.knesset.gov.il/$1/law/$1_lsr_$2.pdf" if ($url =~ /^(\d+):(\d+)$/);
	$url = "https://fs.knesset.gov.il/$2/law/$2_lsr_$1_$3.pdf" if ($url =~ /^(ec|vn):(\d+):(\d+)$/);
	$url = "https://fs.knesset.gov.il/$2/law/$2_ls_$1_$3.pdf" if ($url =~ /^(fr|nv):(\d+):(\d+)$/);
	$url = "https://fs.knesset.gov.il/$2/SecondaryLaw/$2_$1_$3.pdf" if ($url =~ /^(scl_[a-z]+):(\d+):(\d+)$/);
	$url = "https://fs.knesset.gov.il/$2/law/$2_ls$1_$3.pdf" if ($url =~ /^(?:ls|)([a-z]+):(\d+):(\d+)$/);
	$url = "https://fs.knesset.gov.il/$2/law/$2_$1_$3.pdf" if ($url =~ /^([a-z]+_[a-z]+):(\d+):(\d+)$/);
	$url = "https://supremedecisions.court.gov.il/Home/Download?path=HebrewVerdicts/$1/$3/$2/$4&fileName=$1$2$3_$4.pdf&type=4" if ($url =~ /^(\d\d)(\d\d\d)(\d\d\d)[_.]([a-zA-Z]\d\d)$/);
	$url = "https://www.gov.il/he/pages/$1" if ($url =~ /^(?|(\d{4}[\-_]?de[sc]\d+|dec\d+[\-_]\d{4}))$/);
	$url = "https://www.gov.il/he/pages/$1" if ($url =~ /^(?:page:|des__)(.*)$/);
	$url = "https://www.gov.il/he/service/$1" if ($url =~ /^service:(.*)$/);
	# $url = "http://knesset.gov.il/laws/data/law/$1/$1_$2.pdf" if ($url =~ /^(\d+)_(\d+)$/);
	# $url = "http://knesset.gov.il/laws/data/law/$1/$1.pdf" if ($url =~ /^(\d{4})$/);
	return $url;
}

sub find_href_mark {
	my $ext = shift;
	my $helper = $ext;
	$helper =~ s/[-: ]+/ /g;
	$helper = $glob{href}{marks}{$helper};
	$ext = $helper if ($helper && $helper !~ /^\+\+/);
	return $ext;
}

sub find_ext_ref {
	local $_ = shift;
	return $_ if (/^https?:\/\//);
	return lc($_) if (/^HTTPS?:\/\//);
	return $_ if (/^[+-]+$/);
	
	s/^(.*?)#(.*)$/$1/;
	$_ = "$1$2" if /$extref_sig(.*)/;
	
	tr/״”“„/"/;
	tr/׳‘’/'/;
	tr/־–/-/;
	tr/\x{05B0}-\x{05BD}//d;
	tr/אּ-תּ/א-ת/;
	s/#.*$//;
	s/_/ /g;
	s/ [-——]+ / – /g;
	s/ {2,}/ /g;
	
	s/ *\(\(.*?\)\)//g;
	s/ *\(נוסח (חדש|משולב)\)//g;
	s/,? *\[.*?\]//g;
	s/\.[^\.]*$// unless /[0-9]\.[0-9]+$/;
	# s/\, *[^ ]*\d+$//;
	s/$date_sig$//;
	s/\(פרק .*?\)$//g;
	
	s/ \((צו )?מס' \d\d+\)$//; # Keep single digit "מס' 0"
	s/^ *(.*?) *$/$1/;
	
	return $_;
}

######################################################################

sub convert_quotes {
	local $_ = shift;
	# my $start = time(); my $end;
	s/(תש[א-ת])"([א-ת])/$1״$2/g;
	s/(תש)"([א-ת])/$1״$2/g;
	# $end = time(); printf STDERR "\ttook %.2f sec.\n", $end-$start; $start = $end;
	# s/(\s+[בהו]?-?)"([^\"\n]+)"/$1”$2“/g;
	s/($nochar[\s\|(]+[בהו]?-?$nochar(?:"$nochar)?)"($nochar[^\"\n\s]++(?:[״"](?:$HE+|$EN+)[^\"\n\s]*| [^\"\n\s]+)*)"/$1”$2“/g;
	s/([\s\|]+ו?כ?ש?מ?[בהל]?-?)'($HE+[^"'\n\s]*)'(?!['א-ת])/$1’$2‘/g;
	s/([\s\|]+[בהו]?-?)'($HE+[^"'\n\s]*)'(?!['א-ת])/$1’$2‘/g;
	s/($HE+$nochar)"($nochar$HE(ות|וֹת|ים|)$nochar)(?![א-ת])/$1״$2/g;
	s/($pre_sig$nochar)"($nochar[^\"\n\s]++(?: [^\"\n\s]+)*)"(?=$nochar[\s,.;]|\]\])/$1”$2“/g;
	# s/([\s\|(]$pre_sig$nochar)'($nochar[^\'\"\n\s]++(?: [^\'\n\s]+)*)'(?=$nochar[\s,.;]|\]\])/$1’$2‘/g;
	# s/($nochar[\s\|(]+$pre_sig$nochar)'($nochar[^\'\n\s]++)'/$1’$2‘/g;
	# s/”([A-Za-z][^א-ת“]*)“/“$1”/g;
	s/(?<=[א-ת])'(?!['])/׳/g;
	s/(?<=[א-ת]\(\()'(?=\)\))/׳/g;
	s/(?<=[א-ת])-(?![\s.\-])/־/g;
	s/(?<=[א-ת]\(\()-(?=\)\))/־/g;
	s/(?<![\s.\-])-([א-ת])/־$1/g;
	s/(\([א-ת0-9]{1,2})[־\-]([א-ת0-9]{1,2}\))/$1–$2/g;
	s/(\(..?\))-(\(..?\))/$1–$2/g;
	s/(תש[א-ת]?["״][א-ת])(?:--|—)(\d)/$1־$2/g;
	s/(תש[א-ת]?["״][א-ת])[-־](\d{4})/$1–$2/g;
	s/(?<=[^ \s\-])(?:--|—)(?=[^ \s\-])/–/g;
	return $_;
}

######################################################################

sub wbr_chemicals {
	# our $chem_pre = '(?:(|mono|di|tri|tetra|pente|hexa|poly|cis|trans|bis|ortho|cyclo|meta|lyso|homo|iso)';
	# our $chem_grp = '(?:acid|acryl[ao]|aldehy|alk[aey]n[eo]|alcohol|ami[dn][eio]|ammon|anthra|azin|benzo?|bor(?:ate|ic)|brom[io]|but(?:[ae]n|yl)|carb[ao](?:n|xyl)|chlor[oi]|cinnam|citro|coumarin|cyan[io]|ester|ether|eth(?:an|[yi]l)|ferr(?:ate|ic)|fluor[oi]|halide|hexa(?:dine|noate)|hydr[ao]|iodo|ketone|meth(?:[ae]n|[yi]l)|naphth?[ao]|nitr[iao]|octan[eo]|pent(?:[ae]n|yl)|piperid|phen[iyo]|phosph|pyr(?:an|azo|imid)|prop(?:[ae]n|yl)|quino[ln]|s[ai]lic|sul(?:ph|f)|toluene|morpho|cyclo)(?:ane|ate|ene|ic|ide|ol|one|onic|oxy|yl|yne|amine|)';
	
	our $chem_pre = qr/(mono|di|tri|tetra|penta|hexa|hepta|octa|nona|deca|un?deca|dodeca|eicosa|hetero|homo|iso|neo|cyclo|spiro|bicyclo|fused|cis|trans|syn|anti|endo|exo|meso|race?m|ortho|meta|para)/i;
	our $chem_post = qr/(ate|ide|ite|ium|yl|ylidene|oyl|one|ose|ol|al|an|ene|yne|oic|ine|ilide)+/i;
	our $chem_grp = qr/(acet|acid|acridin|acryl|actini|adipic|alcohol|aldehyde?|alk(yl|[aey]n)|amide?|amin[eo]?|ammon|anhydrid|anthra|azepin|azide?|(ox|pyrid|hydr|phthal)?azin|arsin|((ox|thi)(adi)?)azol|azonin|benzo?|but([ae]n|yl)|bromo?|boron|caprolactam|carbazol|carbo?(n|xyl?)?|chalcon|chloro?|chrom([oa]n)?|couma(?:an|rin)|cinnolin|cobalt|cyanid|eth(an|[yi]l)|ether|ester|ferr[oi]|fluoro?|form|furan|furazan|glyc|hafni|hexan|hydr(o|ox|oxy)?|hydraz|imid|indol|indolin|iodo?|iodid|lactam|lanthan|keton|mangan|meth|mercur|mercapt|molybd|morpholin|naphth(al|yl|yridin)|nepthalen|nitr(ile|o|oso)|nickel|oxepin|ox([iy]|ol)|pallad|paraquat|pent([ae][nl]|yl)|peroxi|phen([yo]l)?|phenan(thren|thridin)|phos(ph|f)(ate?|in|ite|o|onate)?|piperid|platin|pterdin|prop(ion)?|purin|pyr(an|azin|azo|id|imid|imidin|rol)|quinol|quater|rhen|rhodium|rutheni|silyl|stannane?|stibin|styr|sulfo(nat)?|thio|thi[eo]pin|titan|tolu|tungst|vanadi|xanthen|zircon)(ic|ous)?$chem_post?/i;
	
	local $_ = shift;
	return $_ unless /-/ || /$chem_grp/;
	
	s/<wbr>//g;  # Remove existing <wbr> tags
	
	# Insert break opportunities
	s/($chem_grp[a-z]*?)(?=$chem_pre?$chem_grp)/$1␟/ig;
	s/([a-z]{5}$chem_post)(?=$chem_pre?$chem_grp)/$1␟/ig;
	s/($chem_grp)(?=[a-z]{7})/$1␟/ig;
	s/([a-z]{5}[a-z]*?)(?=$chem_pre?$chem_grp)/$1␟/ig;
	# s/([a-z]{6}$chem_pre)(?=[a-z]{5})/$1␟/ig;
	s/␟([a-z])(?=$chem_pre?$chem_grp)/$1␟/ig;
	
	# Special cases
	s/(trim)␟(eth(?:y|an))/$1$2/ig;
	s/(m)␟(eth(?:y|an))/␟$1$2/ig;
	s/␟(oxy)/$1/ig;
	s/([a-z])␟($chem_post)/$1$2␟/ig;
	
	# Handle parentheses, brackets, and hyphens
	s/([^␟]{5}[)\]\}])([0-9\-,'′″‴]*[a-z]{2})/$1␟$2/ig;
	s/([^␟]{2})([(\[\{][0-9\-,'′″‴]*[a-z]{5})/$1␟$2/ig;
	s/([^␟]{5}\-[0-9\-,'′″‴]+\-)([a-z]{5,})/$1␟$2/ig;
	s/␟?(-(?:[0-9n]+[abchsr]?['′″‴]?,?)+-)([a-z]{5})/$1␟$2/ig;
	
	# Adjust break positions around punctuation
	s/␟([\-)\]\}]+)/$1␟/g;
	s/([\(\[\{]+)␟/␟$1/g;
	s/␟$//g;
	
	# Replace ␟ with <wbr>
	s/␟+/<wbr>/g;
	return $_;
}

1;
