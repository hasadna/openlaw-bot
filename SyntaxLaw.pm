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
use English;
# use Roman;
use utf8;
use Time::HiRes 'time';
use Getopt::Long;
use Data::Dumper;
$Data::Dumper::Useperl = 1;

use constant { true => 1, false => 0 };
my $do_expand = 0;

# \bו?כ?ש?מ?[בהל]?(חוק|פקוד[הת]|תקנות|צו|חלק|פרק|סימן(?: משנה|)|תוספו?ת|טופס|לוח)
our $pre_sig = 'ו?כ?ש?מ?[בהל]?-?';
our $extref_sig = $pre_sig . '(חוק(?:[ -]ה?יסוד:?|)|פקוד[הת]|תקנות(?: שעת[ -]חי?רום)?|צו|החלטה|הכרזה|תקנון|הוראו?ת|הודע[הת]|מנשר|כללים?|נוהל|קביעו?ת|אכרזו?ת|חוק[הת]|אמנ[הת]|דברי?[ -]ה?מלך|החלטו?ת|הנחי[יו]ת|קווים מנחים|אמו?ת מידה|היתר)';
our $type_sig = $pre_sig . '(סעי(?:ף|פים)|תקנ(?:ה|ות)|אמו?ת[ -]מידה|חלק|פרק|סימן(?: משנה|)|לוח(?:ות|) השוואה|נספח|תוספת|טופס|לוח|טבל[הא])';
our $chp_sig = '\d+(?:[^ ,.:;"״\n\[\]()]{0,3}?\.|(?:\.\d+)+\.?)';
our $heb_num2 = '(?:[א-ט]|טו|טז|[יכלמנסעפצ][א-ט]?)';
our $heb_num3 = '(?:[א-ט]|טו|טז|[יכלמנסעפצ][א-ט]?|[קרש](?:טו|טז|[יכלמנסעפצ]?[א-ט]?))';
our $roman = '(?:[IVX]+|[ivx]+)';

our $EN = '[A-Za-z]';
our $HE = '(?:[א-ת][\x{05B0}-\x{05BD}]*+)';
our $nikkud = '[\x{05B0}-\x{05BD}]';
our $nochar = '(?:\(\(|\)\)|\'\'\'|\<\/?[bis]\>)*+';

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
	
	# General cleanup
	s/\n *<!--.*?--> *\n/\n/sg;  # Remove comments
	s/<!--.*?-->//sg;  # Remove comments
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
	
	s/(?<=[0-9₀-₉])′/&#8242;/g; # Keep prime [feet/minutes] and double prime [inch/seconds]
	s/(?<=[0-9₀-₉])″/&#8243;/g; # (restored later by unescape_text)
	
	# s/[»«⌸]/"&#".ord($1).";"/ge; # Escape special markers
	
	s/($HE)–($HE)/$1--$2/g; # Keep en-dash between Hebrew words
	s/(\d$HE*)–(\d)/$1--$2/g; # Keep en-dash between numerals
	
	tr/\x{FEFF}//d;    # Unicode marker
	tr/\x{2000}-\x{200A}\x{202F}\x{205F}\x{2060}/ /; # Typographic spaces
	tr/\x{200B}-\x{200D}//d;         # Remove zero-width spaces
	tr/־–—‒―/-/;        # typographic dashes
	tr/\xAD\x96\x97/-/; # more typographic dashes
	tr/״”“„‟″‶/"/;      # typographic double quotes
	tr/`׳’‘‚‛′‵/'/;     # typographic single quotes
	tr/;/;/;            # wrong OCRed semicolon
	s/(?<=[ \n])-{2,4}(?=[ \n])/—/g;   # em-dash
	s/[ ]{2,}/ /g;     # remove extra  spaces
	
	s/\n+(=[^\n]*=)\n+/\n\n$1\n\n/g;
	
	s/(?<!\n)\n(?=@)/\n\n/gm;
	s/(?<![=\n])\n(\=)/\n\n/gm;
	
	s/\[\[קטגוריה:.*?\]\] *\n?//g;  # Ignore categories (for now)
	
	
	# Unescape HTML characters
	$_ = unescape_text($_);
	
	s/([ :])-([ \n])/$1–$2/g;
	
	# Replace with “Smart quotes”
	$_ = convert_quotes($_);
	
	s/(?<=\<ויקי\>)\s*(.*?)\s*(?=\<[\\\/](ויקי)?\>)/&escape_text($1)/egs;
	
	s/(\{\|.*?\n\|\}) *\n?/&parse_wikitable($1)/egs;
	
	# Parse various elements
	s/^(?|<שם> *\n?(.*)|=([^=].*)=)\n*/&parse_title($1)/em; # Once!
	s/<שם (קודם|אחר)> .*\n*//g;
	s/<מאגר (\d*) תיקון (\d*)>\n?/<מאגר מזהה="$1" תיקון="$2"\/>\n/;
	s/^<פרסום> *\n?(.*)\n/&parse_pubdate($1)/egm;
	s/^<חתימ(?:ות|ה)> *\n?(((\*.*\n)+)|(.*\n))/&parse_signatures($1)/egm;
	s/^<מקור> *\n?(.*)\n/\n<מקור>\n$1\n<\/מקור>\n/m;
	s/^<(?:מבוא|הקדמה)> *\n?(.*)\n/<הקדמה>\n$1\n<\/הקדמה>\n\n/m;
	s/^<סיום> *\n?(.*)\n/<מפריד\/>\n<הקדמה>\n$1\n<\/הקדמה>\n\n/m;
	s/^(-{3,}|—)$/<מפריד\/>/gm;
	
	# Parse structured elements
	s/^(=+)(.*?)\1\n+/&parse_section(length($1),$2)/egm;
	s/^<סעיף *(.*?)>(.*?)\n/&parse_chapter($1,$2,"סעיף")/egm;
	s/^(@.*?) +(:+ .*)$/$1\n$2/gm;
	s/^@ *(\(תיקון: .*?)\n/&parse_chapter("",$1,"סעיף*")/egm;
	s/^@ *(\d\S*) *\n/&parse_chapter($1,"","סעיף")/egm;
	s/^@ *($chp_sig) +(.*?)\n/&parse_chapter($1,$2,"סעיף")/egm;
	s/^@ *(\d[^ .]*\.) *(.*?)\n/&parse_chapter($1,$2,"סעיף")/egm;
	s/^@ *([^ \n.]+\.) *(.*?)\n/&parse_chapter($1,$2,"סעיף")/egm;
	s/^@ *(\([^()]*?\)) *(.*?)\n/&parse_chapter($1,$2,"סעיף*")/egm;
	s/^@ *(.*?)\n/&parse_chapter("",$1,"סעיף*")/egm;
	s/(<(?:td|th)[^>]*>)(:)/$1␊\n$2/g;
	s/(<\/(?:td|th)[^>]*>)/␊\n$1/g;
	s/^(:+) *(\([^( ]+\)) *(\([^( ]{1,2}\)) *(\([^( ]{1,2}\))/$1 $2\n$1: $3\n$1:: $4/gm;
	s/^(:+) *(\([^( ]+\)) *(\([^( ]{1,2}\))/$1 $2\n$1: $3/gm;
	s/^:+-? *$//gm;
	# s/^(:+) *("?\([^( ]+\)|\[[^[ ]+\]|\d[^ .]*\.|)(?| +(.*?)|([-–].*?)|())\n/&parse_line($1,$2,$3)/egm;
	s/^(:+[-–]?) *((?:'''|)["”“]?(?:\([^( ]+\)|\[[^[ ]+\]|\(\(\(\d.?\)\)\)|\(\(\([א-י]\d?\)\)\)|\d+(?:\.\d+)+|\d[^ .]*\.|$heb_num2\d?\.|$roman\.?|[•■□-◿*]|[A-Za-z0-9א-ת]+\)? *\(\(\)\)|<sup>[0-9א-ת]{1,2}<\/sup>|)(?:'''|))(?| +(.*?)|())\n/&parse_line($1,$2,$3)/egm;
	
	# Move container tags if needed
	my $barrier = '<\/?(?:מקור|הקדמה|ת+|קטע|סעיף|חתימות|td|tr)|__TOC__|$';
	s/(\n?<\/(?:הקדמה|מקור)>)(.*?)(?=\s*($barrier))/$2$1/sg;
	s/(\n?<\/ת+>)(.*?)(?=\s*(<מפריד.*?>\s*)?($barrier))/$2$1/sg;
	# Add <סעיף> marker after <קטע> if not found
	s/(<\/קטע.*?>\s*+)(?!<(קטע|סעיף|חתימות))/$1<סעיף><\/סעיף>\n/g;
	s/␊(.*?)\n/$1/g;
	
	# s/(<(qq|ins|del)>.*?<\/\2>)/&parse_spans($2,$1)/egs;
	
	# Parse links and remarks
	s/\[\[(?:קובץ:|תמונה:|[Ff]ile:|[Ii]mage:)(.*?)\]\]/<תמונה>$1<\/תמונה>/gm;
	
	# s/(?<!\[)(\[\[(?:(?!\]\]|\[\[).)*\]\]\]?(?:(?:,|או|) \[\[(?:(?!\]\]|\[\[).)*\]\]\]?)++)/&mark_linkset($1)/egm;
	s/(?<!\[)\[\[((?:(?!\]\]|\[\[).)*?\]?)\|((?:(?!\]\]|\[\[).)*)\]\](\]?)/&parse_link($1,"$2$3")/egm;
	s/(?<!\[)\[\[((?:(?!\]\]|\[\[).)*)\]\](\]?)/&parse_link('',"$1$2")/egm;
	s/(?<!\()(\(\((.*?)\)\)([^(]*?\)\))?)(?!\))/&parse_remark($1)/egs;
	
	# Parse file linearly, constructing all ankors and links
	$_ = linear_parser($_);
	
	s/__TOC__/&insert_TOC()/e;
	s/ *__NOTOC__//g;
	s/ *__NOSUB__//g;
	
	s/(?<=\<ויקי\>)\s*(.*?)\s*(\<[\\\/](ויקי)?\>)/&unescape_text($1) . "<\/ויקי>"/egs;
	# s/\<תמונה\>\s*(.*?)\s*\<\/(תמונה)?\>/&unescape_text($1)/egs;
	s/<לוח_השוואה>\s*(.*?)<\/(לוח_השוואה|)>\n?/&parse_comparetable($1)/egs;
	s/(\<math.*?\>.*?\<[\\\/]math\>)/&fix_tags($1)/egs;
	s/(<(?:div|span|table|td|th|tr) [^>]+>)/&fix_tags($1)/egs;
	
	# Use thin spaces in dotted lines
	s/(\.{21,})/'<span style⌸"word-break: break-all;">' . '. 'x(length($1)-1) . '.<\/span>'/ge;
	s/(\.{4,20})/'. 'x(length($1)-1) . '.'/ge;
	
	# Replace vulgar fractions
	s/([½⅓⅔¼¾⅕⅖⅗⅘⅙⅚⅐⅛⅜⅝⅞⅑⅒↉])(\d+)/$2$1/g;
	$_ = s_lut($_, { 
		'½' => '¹⁄₂', '⅓' => '¹⁄₃', '⅔' => '²⁄₃', '¼' => '¹⁄₄', '¾' => '³⁄₄', 
		'⅕' => '¹⁄₅', '⅖' => '²⁄₅', '⅗' => '³⁄₅', '⅘' => '⁴⁄₅', '⅙' => '¹⁄₆', '⅚' => '⁵⁄₆',  
		'⅐' => '¹⁄₇', '⅛' => '¹⁄₈', '⅜' => '³⁄₈', '⅝' => '⁵⁄₈', '⅞' => '⁷⁄₈', 
		'⅑' => '¹⁄₉', '⅒' => '¹⁄₁₀', '↉' => '⁰⁄₃'
	});
	# use arial font for fraction slash (U+2044)
	s/⁄/<font face⌸"arial">⁄<\/font>/g;
	
	# Replace "=" (⌸) within templates with {{=}}
	s/(\{\{(?:[^{}\n]++|(?R))*\}\})/ $1 =~ s|⌸|\{\{=\}\}|gr /eg;
	tr/⌸/=/;
	
	s/\x00//g; # Remove nulls
	s/\n{3,}/\n\n/g;
	
	$_ = expand_templates($_) if ($do_expand);
	
	cleanup();
	
	return $_;
}

# Allow usage as a module and as a executable script
__PACKAGE__->main() unless (caller);

######################################################################

sub parse_title {
	local $_ = shift;
	my ($fix, $str);
	$_ = unquote($_);
	($_, $fix) = get_fixstr($_);
	$str = "<שם>";
	$str .= "<תיקון>$fix</תיקון>\n" if ($fix);
	$str .= "$_</שם>\n";
	return $str;
}

sub parse_section {
	my $level = shift;
	local $_ = shift;
	my ($type, $num, $fix, $extra, $str);
	
	$level = 2 unless defined $level;
	
	$_ = unquote($_);
	($_, $fix) = get_fixstr($_);
	($_, $extra) = get_extrastr($_);
	
	$str = $_;
	
	# print STDERR "parse_section with |$_|\n";
	s/\(\([^()]*?\[\[[^()]*?\)\)//g;
	s/(?|\(\(\(([^()]*?)\)\)\)|\(\(([^()]*?)\)\))/$1/g;
	
	if (/^\((.*?)\)$/) {
		$num = '';
	# } elsif (/^\((.*?)\) */) {
	#	$num = $1;
	#	$str =~ s/^\((.*?)\) *//;
	} elsif (/^(.+?)( *:| +[-])/) {
		$num = get_numeral($1);
	} elsif (/^((?:[^ (]+( +|$)){2,3})/) {
		$num = get_numeral($1);
	} else {
		$num = '';
	}
	
	$type = $_;
	$type =~ s/\(\(.*?\)\)//g;
	$type = ($type =~ /^(?:|[א-ת]+ )$type_sig\b/ ? $1 : '');
	$type = 'משנה' if ($type =~ /סימ(ן|ני) משנה/);
	$type = 'לוחהשוואה' if ($type =~ /השוואה/);
	my $ankor = $type;
	$ankor .= " $num" if ($type && $num ne '');
	# $ankor = find_href($s);
	
	my $str2 = $str;
	$str = "<קטע";
	$str .= " דרגה=\"$level\"" if ($level);
	$str .= " עוגן=\"$ankor\"" if ($type && $ankor);
	$str .= ">";
	$str .= "<תיקון>$fix</תיקון>" if ($fix);
	$str .= "<אחר>[$extra]</אחר>" if ($extra);
	$str .= $str2;
	$str .= "</קטע>\n\n";
	return $str;
}

sub parse_chapter {
	my ($num, $desc,$type) = @_;
	my ($id, $fix, $extra, $ankor);
	
	$desc = unquote($desc);
	($desc, $fix) = get_fixstr($desc);
	($desc, $extra) = get_extrastr($desc);
	($desc, $ankor) = get_ankor($desc);
	$id = get_numeral($num);
	
	$desc =~ s/(?<=–)(?! |$)/<wbr>/g;
	$extra =~ s/(?=\()/\<wbr\>/g if defined $extra;
	
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
	# print STDERR "|$num|$line|\n";
	$num =~ s/"/&quot;/g;
	$num =~ s/ *\(\(\)\)$//;
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
	$helper = unquote($helper);
	# $txt =~ s/\(\((.*?)\)\)/$1/g;
	
	if ($helper =~ /^\[/ and $txt =~ /\]$/) { $pre = '['; $helper =~ s/^\[//; $txt =~ s/\]$//; $post = ']'; }
	elsif ($txt =~ s/^(\[)(.*)(\])$/$2/) { ($pre, $post) = ($1, $3); }
	elsif ($txt =~ s/(?<=\d{4})(\])$//) { $post = $1; }
	
	($helper,$txt) = ($txt,$1) if ($txt =~ /^[ws]:(?:[a-z]{2}:)?(.*)$/ && !$helper);
	$str = "$pre<קישור" . ($helper ? " $helper" : '') . ">$txt</קישור>$post";
	$str =~ s/([()])\1/$1\x00$1/g unless ($str =~ /\(\(.*\)\)/); # Avoid splitted comments
	
	push_lookahead($2) if ($helper =~ /^([^a-zA-Z]*)\=([^a-zA-Z]+)$/);
	push_lookahead($txt) if ($helper =~ /^([^a-zA-Z]*)\=$/);
	return $str;
}

sub parse_remark {
	local $_ = shift;
	s/^\(\((.*?)\)\)$/$1/s;
	my ($text,$tip,$url) = ( /((?:\{\{.*?\}\}|\[\[.*?\]\]|[^\|])+)/g );
	return $_ unless defined $text;
	my $str;
	$text =~ s/^ *(.*?) *$/$1/;
	if ($tip) {
		$tip =~ s/^ *(.*?) *$/$1/;
		$tip = escape_quote($tip);
		$str = "<תיבה טקסט=\"$tip\"";
		if ($url) {
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
		else { s/ +(?=ה?(שר[הת]?|נשיאת?|ראש|יושבת?[\-־ ]ראש)\b)/|/; }
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
	shift;
	s/\[\[(?|(.*?)\|(.*?)|()(.*?))\]\]/[[»$1|$2]]/g;
	s/»([^»]+)$/«$1/;
	# print STDERR "$_\n";
	return $_;
}

#---------------------------------------------------------------------

sub parse_wikitable {
	# Based on [mediawiki/core.git]/includes/parser/Parser.php doTableStuff()
	my @lines = split(/\n/,shift);
	my $out = '';
	my ($last_tag, $previous);
	my (@td_history, @last_tag_history, @tr_history, @tr_attributes, @has_opened_tr);
	my ($indent_level, $attributes);
	for (@lines) {
		s/^ *(.*?) *$/$1/;
		if ($_ eq '') {
			$out .= "\n";
			next;
		}
		
		if (/^\{\|(.*)$/) {
			$attributes = $1;
			$_ = "<table$1>\n";
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
			my @cells = split( / *\|\| */, $_ , -1);
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
					# print STDERR "Empty cell data at |" . join('|',@cells) . "|\n";
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
		} else {
			$_ .= "\n";
			$out =~ s/&nbsp;\n?$//s;
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
		$str .= "  <tr>" . 
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
	# Convert to single character brackets for simplier regexps
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
	s/\bה(תש[א-ת"]+)\b/$1/g for (@fix);
	return ($_, join(', ',@fix));
}

sub get_extrastr {
	local $_ = shift;
	my @extra = ();
	return ($_, undef) if /\[נוסח $HE+\]/;
	push @extra, unquote($1) while (s/(?<=[^\[\(])\[ *([^\[\]]+) *\] *//) || (s/^\[ *([^\[\]]+) *\] *//);
	s/^ *(.*?) *$/$1/;
	return ($_, join(', ',@extra));
}

sub get_ankor {
	local $_ = shift;
	my @ankor = ();
	push @ankor, unquote($1) while (s/ *<עוגן:? *(.*?)>//);
	return ($_, join(', ',@ankor));
}

sub get_numeral {
	local $_ = shift;
	return '' if (!defined($_));
	my $num = '';
	my $token = '';
	s/&quot;/"/g;
	s/[,"'״׳]//g; # s/[.,"']//g;
	s/־/-/g;
	s/([א-ת]{3})(\d)/$1-$2/;
	$_ = unparent($_);
	while ($_) {
		$token = '';
		given ($_) {
			($num,$token) = ("0",$1) when /^(מקדמית?)\b/;
			($num,$token) = ("11",$1) when /^(אחד[- ]עשר|אחת[- ]עשרה)\b/;
			($num,$token) = ("12",$1) when /^(שניי?ם[- ]עשר|שתיי?ם[- ]עשרה)\b/;
			($num,$token) = ("13",$1) when /^(שלושה[- ]עשר|שלוש[- ]עשרה)\b/;
			($num,$token) = ("14",$1) when /^(ארבעה[- ]עשר|ארבע[- ]עשרה)\b/;
			($num,$token) = ("15",$1) when /^(חמי?שה[- ]עשר|חמש[- ]עשרה)\b/;
			($num,$token) = ("16",$1) when /^(שי?שה[- ]עשר|שש[- ]עשרה)\b/;
			($num,$token) = ("17",$1) when /^(שבעה[- ]עשר|שבע[- ]עשרה)\b/;
			($num,$token) = ("18",$1) when /^(שמונה[- ]עשרה?)\b/;
			($num,$token) = ("19",$1) when /^(תשעה[- ]עשר|תשע[- ]עשרה)\b/;
			($num,$token) = ("1",$1) when /^(ראשו(ן|נה)|אחד|אחת])\b/;
			($num,$token) = ("2",$1) when /^(שניי?ה?|ש[תנ]יי?ם)\b/;
			($num,$token) = ("3",$1) when /^(שלישית?|שלושה?)\b/;
			($num,$token) = ("4",$1) when /^(רביעית?|ארבעה?)\b/;
			($num,$token) = ("5",$1) when /^(חמי?שית?|חמש|חמי?שה)\b/;
			($num,$token) = ("6",$1) when /^(שי?שית?|שש|שי?שה)\b/;
			($num,$token) = ("7",$1) when /^(שביעית?|שבעה?)\b/;
			($num,$token) = ("8",$1) when /^(שמינית?|שמונה)\b/;
			($num,$token) = ("9",$1) when /^(תשיעית?|תשעה?)\b/;
			($num,$token) = ("10",$1) when /^(עשירית?|עשרה?)\b/;
			($num,$token) = ("20",$1) when /^(עשרים)\b/;
			# ($num,$token) = (arabic($1), $1) when /^($roman)\b/;
			($num,$token) = ("$1-2","$1$2") when /^(\d+)([- ]?bis)\b/i;
			($num,$token) = ("$1-3","$1$2") when /^(\d+)([- ]?ter)\b/i;
			($num,$token) = ("$1-4","$1$2") when /^(\d+)([- ]?quater)\b/i;
			($num,$token) = ($1,$1) when /^(\d+([._]\d+[א-ט]?)+)\b/;
			($num,$token) = ($1,$1) when /^(\d+$heb_num2?\.$heb_num2\d?)\b/;
			($num,$token) = ($1,$1) when /^(\d+($heb_num2?\d*|))\b/;
			($num,$token) = ($1,$1) when /^($heb_num3(\d+[א-י]*|))\b/;
		}
		if ($num ne '') {
			# Remove token from rest of string
			$_ =~ s/^$token//;
			last;
		} else {
			# Fetch next token
			$_ =~ s/^[הו]// || $_ =~ s/^\<[^>]*\>// || $_ =~ s/^[^ ()|]*[ ()|]+// || last;
		}
	}
	
	$num .= "-$1" if (s/^[- ]([א-י])\b//);
	$num .= "-$1$2" if (s/^[- ]([א-י])[- ]?(\d)\b//);
	$num .= "-$1" if ($num =~ /^\d/ and $token !~ /^\d/ and /^[- ]?(\d[א-י]?)\b/);
	$num =~ s/(?<=\d)-(?=[א-ת])//;
	return $num;
}

sub unquote {
	my $s = shift;
	# my $Q1 = '["״”“„‟″‶]';
	# my $Q2 = '[\'`׳’‘‚‛′‵]';
	my $Q1 = '"';
	my $Q2 = '\'';
	$s =~ s/'''/‴/g;
	$s =~ s/^ *(?|$Q1 *(.*?) *$Q1|$Q2 *(.*?) *$Q2) *$/$1/;
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
#	print STDERR "|$s|";
	$s =~ s/&/\&amp;/g;
	$s =~ s/</&lt;/g;
	$s =~ s/>/&gt;/g;
	$s =~ s/([(){}"'\[\]<>\|])/"&#" . ord($1) . ";"/ge;
#	print STDERR "$s|\n";
	return $s;
}

sub unescape_text {
	local $_ = shift;
	my %table = ( 'quot' => '"', 'lt' => '<', 'gt' => '>', 'ndash' => '–', 'nbsp' => ' ', 'apos' => "'", # &amp; subs later
		'lrm' => "\x{200E}", 'rlm' => "\x{200F}", 'shy' => '&null;',
		'deg' => '°', 'plusmn' => '±', 'times' => '×', 'sup1' => '¹', 'sup2' => '²', 'sup3' => '³', 
		'frac14' => '¼', 'frac12' => '½', 'frac34' => '¾', 'alpha' => 'α', 'beta' => 'β', 'gamma' => 'γ', 'delta' => 'δ', 'epsilon' => 'ε'
	);
	s/&#(\d+);/chr($1)/ge;
	s/(&([a-z]+);)/($table{$2} || $1)/ge;
	s/&null;//g;
	s/&amp;/&/g;
	return $_;
}

sub s_lut {
	my $str = shift;
	my $table = shift;
	my $keys = join('', keys(%{$table}));
	$str =~ s/([$keys])/$table->{$1}/ge;
	return $str;
}

sub canonic_name {
	local $_ = shift;
	tr/–־/-/;
	tr/״”“/"/;
	tr/׳‘’/'/;
	tr/\x{05B0}-\x{05BD}//;
	s/ - / – /g;
	return $_;
}

sub fix_tags {
	local $_ = shift;
	tr/–/-/;
	tr/“”״/"/;
	s/\{\{==?\}\}/=/g;
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
	undef %glob; undef %hrefs; undef %sections; undef @line;
	undef $pubdate;
}

sub linear_parser {
	cleanup();
	local $_ = shift;
	
	$glob{context} = '';
	$glob{href}{last_class} = '';
	
	foreach my $l (@lookahead) { process_href($l, '++'); }
	undef @lookahead;
	
	my @sec_list = (m/<קטע [^>]*?עוגן="(.*?)">/g);
	check_structure(@sec_list);
	# print STDERR "part_type = $glob{part_type}; sect_type = $glob{sect_type}; subs_type = $glob{subs_type};\n";
	
	@line = split(/(<(?: "[^"]*"|[^>])*>)/, $_);
	$idx = 0;
	for (@line) {
		if (/<(.*)>/) {
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
	my ($type,$num) = split(/ /, $name || '');
	# $num = get_numeral($num) if defined($num);
	$type =~ s/\(\(.*?\)\)//g if (defined $type);
	given ($type) {
		when (undef) {}
		when (/חלק/) { $glob{part} = $num; $glob{sect} = $glob{subs} = $glob{subsub} = undef; }
		when (/פרק/) { $glob{sect} = $num; $glob{subs} = $glob{subsub} = undef; }
		when (/סימן/) { $glob{subs} = $num; $glob{subsub} = undef; }
		when (/משנה/) { $glob{subsub} = $num; }
		when (/לוחהשוואה/) { delete @glob{"part", "sect", "subs", "subsub", "supl", "appn", "form", "tabl", "tabl2"}; }
		when (/תוספת/) { $glob{supl} = ($num || ""); delete @glob{"part", "sect", "subs", "subsub", "appn", "form", "tabl", "tabl2"}; }
		when (/נספח/) { $glob{appn} = ($num || ""); delete @glob{"part", "sect", "subs", "subsub"}; }
		when (/טופס/) { $glob{form} = ($num || ""); delete @glob{"part", "sect", "subs", "subsub"}; }
		when (/לוח/) { $glob{tabl} = ($num || ""); delete @glob{"part", "sect", "subs", "subsub"}; }
		when (/טבלה/) { $glob{tabl2} = ($num || ""); delete @glob{"part", "sect", "subs", "subsub"}; }
	}
	if (defined $type) {
		return if ($type =~ 'טופס' && !$num);
		$name = "סימן $glob{subs} $name" if ($type =~ 'משנה' && defined $glob{subs});
		$name = "פרק $glob{sect} $name" if ($type =~ 'סימן|משנה' && defined $glob{sect});
		$name = "חלק $glob{part} $name" if ($type =~ 'סימן|פרק|משנה' && ($glob{sect_type}==3 || defined $glob{supl}) && defined $glob{part});
		$name = "תוספת $glob{supl} $name" if ($type ne 'תוספת' && defined $glob{supl});
		$name = "לוח השוואה" if ($type eq 'לוחהשוואה');
		$name =~ s/  / /g;
		$sections{$idx} = $name;
	}
}

sub process_chapter {
	my $params = shift;
	$params =~ /עוגן="(?:סעיף |)([^"]+)"/;
	my $num = $1 // '';
	$glob{chap} = $num;
	if ((defined $glob{supl} || defined $glob{tabl}) && $num) {
		my $ankor = $num;
		$ankor = "פרט $ankor" if ($ankor =~ /^\d|^$heb_num3(\d+[א-י]*)?$/);
		$ankor = "סימן $glob{subs} $ankor" if (defined $glob{part} && defined $glob{subs});
		$ankor = "חלק $glob{part} $ankor" if (defined $glob{part});
		$ankor = "לוח $glob{tabl} $ankor" if (defined $glob{tabl});
		$ankor = "טבלה $glob{tabl2} $ankor" if (defined $glob{tabl2});
		$ankor = "נספח $glob{appn} $ankor" if (defined $glob{appn});
		$ankor = "תוספת $glob{supl} $ankor" if (defined $glob{supl});
		$ankor =~ s/  / /g;
		$line[$idx] =~ s/ עוגן=".*?"/ עוגן="$ankor"/;
	} elsif ($num) {
		$line[$idx] =~ s/ עוגן=".*?"/ עוגן="סעיף $num"/;
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
	# str = "== תוכן ==\n";
	my $str = "<קטע דרגה=\"2\">תוכן עניינים</קטע>\n\n<סעיף></סעיף>\n";
	$str .= "<div style=\"columns: 2 auto; -moz-columns: 2 auto; -webkit-columns: 2 auto; text-align: right; padding-bottom: 1em;\">\n";
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
		$type = 3;
		$helper = $1 || $ext;
		# $ext = '' if ($1 ne '');
		$ext = $1; $int = $2;
		($int, undef) = find_href("+#$2") if ($2);
		$found = true;
		$hash = ($2 eq '');
	}
	
	# print STDERR "## X |$text| X |$ext|$int| X |$helper|\n";
	
	if ($helper =~ /^= *(.*)/) {
		$type = 3;
		$helper = $1;
		$helper =~ s/^ה//; $helper =~ s/[-: ]+/ /g;
		(undef, $ext) = find_href($text, $helper);
		$ext = $glob{href}{marks}{$ext} if (defined $glob{href}{marks}{$ext} && $glob{href}{marks}{$ext} ne "++$ext");
		$update_mark = true;
	} elsif ($helper =~ /^(.*?) *= *(.*)/) {
		$type = 3;
		$ext = $1; $helper = $2;
		(undef, $helper) = find_href($text,$text) if ($2 eq '');
		$helper =~ s/^ה//; $helper =~ s/[-: ]+/ /g;
		(undef, $ext) = find_href($ext, $helper);
		$ext = $glob{href}{marks}{$ext} if (defined $glob{href}{marks}{$ext} && $glob{href}{marks}{$ext} ne "++$ext");
		$update_mark = true;
	} elsif ($helper) {
		if ($found) {
			(undef, $ext) = find_href($helper);
			$ext = $helper if ($ext eq '');
		} elsif (defined $glob{href}{marks}{$helper}) {
			$ext = $glob{href}{marks}{$helper};
		} else {
			my ($int2, $ext2) = find_href($helper);
			$int = $int2 and $found = true if ($int2);
			$ext = $ext2;
		}
		$type = ($ext) ? 3 : 1;
	}
	
	# print STDERR "## X |$text| X |$ext|$int| X |$helper|\n";
	
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
		$ext = $glob{href}{last};
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
			# print STDERR "adding '$helper' to all_marks = '$glob{href}{all_marks}'\n";
		}
		for (@{$glob{href}{marks_ahead}{$helper}}) {
			$hrefs{$_} =~ s/\+[^#]*(.*)/$ext$1/;
		}
		$glob{href}{marks_ahead}{$helper} = [];
	}
	
	if ($ext) {
		$helper = $ext =~ s/[-: ]+/ /gr;
		$ext = $glob{href}{marks}{$helper} if ($glob{href}{marks}{$helper});
		$text = ($int ? "$ext#$int" : $ext);
		if ($type==3 || $update_lookahead) {
			$glob{href}{last} = $ext;
			if ($ext =~ /\+\+(.*)/) {
				$helper = $1;
				$glob{href}{marks}{$helper} = $ext;
				push @{$glob{href}{marks_ahead}{$helper}}, $id if ($id>0);
				push @{$glob{href}{marks_ahead}{$helper}}, @{$glob{href}{ahead}} if ($glob{href}{ahead});
			} else {
				for (@{$glob{href}{ahead}}) {
					$hrefs{$_} =~ s/\+[^#]*(.*)/$ext$1/;
					# print STDERR "## X |$hrefs{$_}|\n";
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
	my $helper = shift;
	if (!$_) { return $_; }
	
	my $ext = '';
	
	if (/^([wsWS]:|https?:|קובץ:|[Ff]ile:|תמונה:|[Ii]mage:)/) { return ('', $_); }
	if (/^HTTPS?:/) { return ('', lc($_)); }
	if (/^([a-z_]+:|)(\d+):(\d+)$/) { return ('', find_reshumot_href($_)); }
	
	if (/^(.*?)#(.*)$/) {
		$_ = $2;
		$ext = find_ext_ref($1);
	}
	if (/^[-+]+$/) { return ('', $_); }
	
	s/\(\((?|\[(.*?)\]|(.*?))\)\)/$1/g;
	s/<הערה>(?|\[(.*?)\]|(.*?))<\/הערה>/$1/g;
	
	if (/דברי?[- ]ה?מלך/ and /(סימן|סימנים) \d/) {
		s/(סימן|סימנים)/סעיף/;
	}
	
	s/(\b[לב]?(אותו|אותה)\b) *($extref_sig[- ]*([א-ת]+\b.*)?)$/$4 $2/;
	if (/^(.*?)\s*\b($extref_sig[- ]*([א-ת]+\b.*|[א-ת].*תש.?["״]?.[-–]\d{4}|))$/) {
		# Ignore in special case
		unless (substr($1,-1) eq '(' and substr($2,-1) eq ')') {
			$_ = $1;
			$ext = find_ext_ref($2) unless ($ext);
		}
	} elsif (/^(.*?) *\b$pre_sig$extref_sig(.*?)$/ and $glob{href}{marks}{"$2$3"}) {
		$ext = "$2$3";
		$_ = $1;
	} elsif ($glob{href}{all_marks} and /^(.*?) *\b$pre_sig($glob{href}{all_marks})(.*?)$/) {
		$ext = "$2$3";
		$_ = $1;
	}
	
	if ($ext =~ /^$extref_sig( *)(.*)$/) {
		my ($e1,$e3) = ("$1$2", $3);
		my $e2 = $ext =~ s/[-– ]+/ /gr;
		$ext = '0' if ($e3 =~ /^ה?(זאת|זו|זה|אלה|אלו)\b/) || ($e3 eq '' and !defined $glob{href}{marks}{$e2} and !$helper);
		$ext = '-' if (defined $e3 && $e3 =~ /^[בלמ]?([הכ]אמור(|ה|ות|ים)|אות[הו]|שב[הו]|הה[וי]א)\b/);
		s/^ *(.*?) *$/$1/;
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
	push @pos, $-[0] while ($_ =~ /([^ ,.\-\)]+)/g);
	
	for my $p (@pos) {
		$_ = substr($href,$p);
		$num = undef;
		given ($_) {
			when (/לוחהשוואה/) { $class = 'comptable'; $num = ""; }
			when (/^$pre_sig(חלק|חלקים)/) { $class = 'part'; }
			when (/^$pre_sig(פרק|פרקים)/) { $class = 'sect'; }
			when (/^$pre_sig(סימןמשנה)/) { $class = 'subsub'; }
			when (/^$pre_sig(סימן|סימנים)/) { $class = 'subs'; }
			when (/^$pre_sig(תוספת|תוספות)/) { $class = 'supl'; $num = ""; }
			when (/^$pre_sig(נספח|נספחים)/) { $class = 'appn'; $num = ""; }
			when (/^$pre_sig(טופס|טפסים)/) { $class = 'form'; }
			when (/^$pre_sig(לוח|לוחות)/) { $class = 'tabl'; }
			when (/^$pre_sig(טבל[הא]|טבלאות)/) { $class = 'tabl2'; }
			when (/^$pre_sig(סעיף|סעיפים|תקנה|תקנות|אמו?ת[ -]ה?מידה)/) { $class = 'chap'; }
			when (/^$pre_sig(פריט|פרט)/) { $class = 'supchap'; }
			when (/^$pre_sig(קט[נן]|פי?סקה|פסקאות|משנה|טור)/) { $class = 'small'; }
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
			when (/^ה?(זה|זו|זאת|this)/) {
				given ($class) {
					when (/^(supl|appn|form|tabl|table2)$/) { $num = $glob{$class} || ''; }
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
			when (/^([מל]?אות[והםן]|הה[וי]א|הה[םן]|האמורה?|שב[הו])/) {
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
			default {
				s/^[לב]-(\d.*)/$1/;
				$num = get_numeral($_);
				if ($num ne '' && $class eq '') {
					$class = (/^$pre_sig\d+/) ? 'chap_' : ($glob{href}{last_class} || 'chap_');
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
	
	$glob{href}{last_class} = $elm{supchap} ? 'supchap' : $elm{chap} ? 'chap' : $elm{subsub} ? 'subsub' : $elm{subs} ? 'subs' : $elm{sect} ? 'sect' : $elm{part} ? 'part' : $class eq 'small' ? '' : $class;
	
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
	
	$href = '';
	if (defined $elm{comptable}) {
		$href = "לוח השוואה";
	} elsif (defined $elm{supl}) {
		$elm{supl} = $elm{supl} || $glob{supl} || '' if ($ext eq '');
		$elm{supchap} = $elm{supchap} || $elm{chap};
		$href = "תוספת $elm{supl}";
		$href .= " חלק $elm{part}" if (defined $elm{part});
		$href .= " פרק $elm{sect}" if (defined $elm{sect});
		$href .= " סימן $elm{subs}" if (defined $elm{subs});
		$href .= " טופס $elm{form}" if (defined $elm{form});
		$href .= " לוח $elm{tabl}" if (defined $elm{tabl});
		$href .= " טבלה $elm{tabl2}" if (defined $elm{tabl2});
		$href .= " נספח $elm{appn}" if (defined $elm{appn});;
		$href .= " פרט $elm{supchap}" if (defined $elm{supchap});
	} elsif (defined $elm{form} || defined $elm{tabl} || defined $elm{tabl2} || defined $elm{appn}) {
		$href = "טופס $elm{form}" if (defined $elm{form});
		$href = "לוח $elm{tabl}" if (defined $elm{tabl});
		$href = "טבלה $elm{tabl2}" if (defined $elm{tabl2});
		$href = "נספח $elm{appn}"  if (defined $elm{appn});
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
		$href = "חלק $glob{part} $href" if ($glob{sect_type}==3 && defined $glob{part} && $ext eq '');
		# $href = "תוספת $glob{supl} $href" if ($glob{supl} && $ext eq '');
	} elsif (defined $elm{subs}) {
		$href = "סימן $elm{subs}";
		$href .= " משנה $elm{subsub}" if (defined $elm{subsub});
		$href = "פרק $glob{sect} $href" if (defined $glob{sect} && $ext eq '');
		$href = "חלק $glob{part} $href" if ($glob{sect_type}==3 && defined $glob{part} && $ext eq '');
		# $href = "תוספת $glob{supl} $href" if (defined $elm{supl} && $glob{supl} && $ext eq '');
	} elsif (defined $elm{subsub}) {
		$href = "משנה $elm{subsub}";
		$href = "סימן $glob{subs} $href" if (defined $glob{subs});
		$href = "פרק $glob{sect} $href" if (defined $glob{sect} && $ext eq '');
		$href = "חלק $glob{part} $href" if ($glob{sect_type}==3 && defined $glob{part} && $ext eq '');
		# $href = "תוספת $glob{supl} $href" if (defined $elm{supl} && $glob{supl} && $ext eq '');
	} elsif (defined $elm{chap}) {
		$href = "סעיף $elm{chap}";
	} elsif (defined $elm{supchap} && $ext eq '') {
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
	$url = "https://fs.knesset.gov.il/$2/law/$2_ls$1_$3.pdf" if ($url =~ /^(?|ls([a-z_0-9]+)|([a-z_]+)):(\d+):(\d+)$/);
	$url = "https://supremedecisions.court.gov.il/Home/Download?path=HebrewVerdicts/$1/$3/$2/$4&fileName=$1$2$3_$4.pdf&type=4" if ($url =~ /^(\d\d)(\d\d\d)(\d\d\d)[_.]([a-zA-Z]\d\d)$/);
	$url = '' if ($url =~ /^(\d+)(?|_(\d+)|())$/);
	# $url = "http://knesset.gov.il/laws/data/law/$1/$1_$2.pdf" if ($url =~ /^(\d+)_(\d+)$/);
	# $url = "http://knesset.gov.il/laws/data/law/$1/$1.pdf" if ($url =~ /^(\d{4})$/);
	return $url;
}

sub find_ext_ref {
	local $_ = shift;
	return $_ if (/^https?:\/\//);
	return lc($_) if (/^HTTPS?:\/\//);
	return $_ if (/^[+-]+$/);
	
	s/^(.*?)#(.*)$/$1/;
	$_ = "$1$2" if /$extref_sig(.*)/;
	
	tr/"'`”׳//;
	tr/\x{05B0}-\x{05BD}//;
	s/#.*$//;
	s/_/ /g;
	s/ [-——]+ / – /g;
	s/ {2,}/ /g;
	
	s/ *\(נוסח (חדש|משולב)\)//g;
	s/,? *\[.*?\]//g;
	s/\.[^\.]*$//;
	# s/\, *[^ ]*\d+$//;
	s/(\,? ה?תש.?["״].[-–]\d{4}|, *[^ ]*\d{4}|, מס['׳] \d+ לשנת \d{4}| [-–] ה?תש.?["״]. מיום \d+.*|\, *\d+ עד \d+)$//;
	s/ \(מס' \d\d+\)$//;
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
	s/([\s\|]+[בהו]?-?)'($HE+[^"'\n\s]*)'(?!['א-ת])/$1’$2‘/g;
	s/($HE+$nochar)"($nochar$HE(ות|וֹת|ים|)$nochar)(?![א-ת])/$1״$2/g;
	s/($pre_sig$nochar)"($nochar[^\"\n\s]++(?: [^\"\n\s]+)*)"(?=$nochar[\s,.;]|\]\])/$1”$2“/g;
	s/(?<=[א-ת])'(?!['])/׳/g;
	s/(?<=[א-ת]\(\()'(?=\)\))/׳/g;
	s/(?<=[א-ת])-(?![\s.\-])/־/g;
	s/(?<=[א-ת]\(\()-(?=\)\))/־/g;
	s/(?<![\s.\-])-([א-ת])/־$1/g;
	s/(\([א-ת0-9]{1,2})[־\-]([א-ת0-9]{1,2}\))/$1–$2/g;
	s/(\(..?\))-(\(..?\))/$1–$2/g;
	s/(תש[א-ת]?["״][א-ת])[-־](\d{4})/$1–$2/g;
	s/([^ \s\-])(?:--|—)([^ \s\-])/$1–$2/g;
	return $_;
}

######################################################################

1;
