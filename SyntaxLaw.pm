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
use utf8;

use Data::Dumper;
$Data::Dumper::Useperl = 1;

use constant { true => 1, false => 0 };

our $pre_sig = '\bו?כ?ש?מ?[בהל]?';
our $extref_sig = $pre_sig . '(חוק|פקוד[הת]|תקנות|צו|החלטה|הכרזה|תקנון|הוראו?ת|הודעה|מנשר|כללים?|נוהל|חוק[הת]|אמנ[הת]|דברי?[ -]ה?מלך)\b';
our $type_sig = $pre_sig . '(סעי(?:ף|פים)|תקנ(?:ה|ות)|חלק|פרק|סימן(?: משנה|)|לוח(?:ות|) השוואה|נספח|תוספת|טופס|לוח|טבל[הא])';
our $chp_sig = '\d+(?:[^ ,.:;"״\n\[\]()]{0,3}?\.|(?:\.\d+)+\.?)';

sub main() {
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
	my $_ = shift;
	
	# General cleanup
	s/<!--.*?-->//sg;  # Remove comments
	s/\r//g;           # Unix style, no CR
	s/[\t\xA0]/ /g;    # Tab and hardspace are whitespaces
	s/^[ ]+//mg;       # Remove redundant whitespaces
	s/[ ]+$//mg;       # Remove redundant whitespaces
	s/$/\n/s;          # Add last linefeed
	s/\n{3,}/\n\n/sg;  # Convert three+ linefeeds
	s/\n\n$/\n/sg;     # Remove last linefeed
	
	if (/[\x{202A}-\x{202E}]/) {
		# Throw away BIDI characters if LRE/RLE/PDF exists
		tr/\x{200E}\x{200F}\x{202A}-\x{202E}\x{2066}-\x{2069}//d;
	}
	tr/\x{FEFF}//d;    # Unicode marker
	tr/\x{2000}-\x{200A}\x{205F}/ /; # Convert typographic spaces
	tr/\x{200B}-\x{200D}//d;         # Remove zero-width spaces
	tr/־–—‒―/-/;        # typographic dashes
	tr/\xAD\x96\x97/-/; # more typographic dashes
	tr/״”“„‟″‶/"/;      # typographic double quotes
	tr/`׳’‘‚‛′‵/'/;     # typographic single quotes
	tr/;/;/;            # wrong OCRed semicolon
	s/[ ]{2,}/ /g;      # Pack  long spaces
	s/ -{2,4} / — /g;   # em-dash
	
	s/\[\[קטגוריה:.*?\]\] *\n?//g;  # Ignore categories (for now)
	
	# Unescape HTML characters
	$_ = unescape_text($_);
	
	s/([ :])-([ \n])/$1–$2/g;
	
	# Replace with “Smart quotes”
	$_ = convert_quotes($_);
	# Use thin spaces in dotted lines
	s/(\.{4,})/'. ' x (length($1)-1) . '.'/ge;
	
	s/(?<=\<ויקי\>)\s*(.*?)\s*(?=\<[\\\/](ויקי)?\>)/&escape_text($1)/egs;
	
	# Parse various elements
	s/^(?|<שם> *\n?(.*)|=([^=].*)=)\n*/&parse_title($1)/em; # Once!
	s/<שם קודם> .*\n//g;
	s/<מאגר .*?>\n?//;
	s/^<פרסום> *\n?(.*)\n/&parse_pubdate($1)/egm;
	s/^<חתימות> *\n?(((\*.*\n)+)|(.*\n))/&parse_signatures($1)/egm;
	s/^<מקור> *\n?(.*)\n/\n<מקור>\n$1\n<\/מקור>\n/m;
	s/^<(?:מבוא|הקדמה)> *\n?(.*)\n/<הקדמה>\n$1\n<\/הקדמה>\n\n/m;
	s/^<סיום> *\n?(.*)\n/<מפריד\/>\n<הקדמה>\n$1\n<\/הקדמה>\n\n/m;
	s/^-{3,}$/<מפריד\/>/gm;
	
	# Parse structured elements
	s/^(=+)(.*?)\1\n/&parse_section(length($1),$2)/egm;
	s/^<סעיף *(.*?)>(.*?)\n/&parse_chapter($1,$2,"סעיף")/egm;
	s/^(@.*?) +(:+ .*)$/$1\n$2/gm;
	s/^@ *(\(תיקון.*?)\n/&parse_chapter("",$1,"סעיף*")/egm;
	s/^@ *(\d\S*) *\n/&parse_chapter($1,"","סעיף")/egm;
	s/^@ *($chp_sig) +(.*?)\n/&parse_chapter($1,$2,"סעיף")/egm;
	s/^@ *(\d[^ .]*\.) *(.*?)\n/&parse_chapter($1,$2,"סעיף")/egm;
	s/^@ *([^ \n.]+\.) *(.*?)\n/&parse_chapter($1,$2,"סעיף")/egm;
	s/^@ *(\([^()]*?\)) *(.*?)\n/&parse_chapter($1,$2,"סעיף*")/egm;
	s/^@ *(.*?)\n/&parse_chapter("",$1,"סעיף*")/egm;
	s/^(:+) *(\([^( ]+\)) *(\([^( ]{1,2}\)) *(\([^( ]{1,2}\))/$1 $2\n$1: $3\n$1:: $4/gm;
	s/^(:+) *(\([^( ]+\)) *(\([^( ]{1,2}\))/$1 $2\n$1: $3/gm;
	s/^:+-? *$//gm;
	# s/^(:+) *("?\([^( ]+\)|\[[^[ ]+\]|\d[^ .]*\.|)(?| +(.*?)|([-–].*?)|())\n/&parse_line(length($1),$2,$3)/egm;
	s/^\n?(:+)([-–]?) *("?\([^( ]+\)|\[[^[ ]+\]|\d+(?:\.\d+)+|\d[^ .]*\.|[א-י]\d?\.|)( +.*?|)\n/&parse_line(length($1),$3,"$2$4")/egm;
	
	# Move container tags if needed
	my $structure_tags = '<(מקור|הקדמה|ת+|קטע|סעיף|חתימות)|__TOC__|$';
	s/(\n?<\/(?:הקדמה|מקור)>)(.*?)(?=\s*($structure_tags))/$2$1/sg;
	s/(\n?<\/ת+>)(.*?)(?=\s*(<מפריד.*?>\s*)?($structure_tags))/$2$1/sg;
	# Add <סעיף> marker after <קטע> if not found
	s/(<\/קטע.*?>\s*+)(?!<(קטע|סעיף|חתימות))/$1<סעיף><\/סעיף>\n/g;
	
	# s/(<(qq|ins|del)>.*?<\/\2>)/&parse_spans($2,$1)/egs;
	
	# Parse links and remarks
	s/\[\[(?:קובץ:|תמונה:|[Ff]ile:|[Ii]mage:)(.*?)\]\]/<תמונה>$1<\/תמונה>/gm;
	
	s/(?<=[^\[])\[\[ *([^\]]*?) *\| *(.*?) *\]\](?=[^\]])/&parse_link($1,$2)/egm;
	s/(?<=[^\[])\[\[ *(.*?) *\]\](?=[^\]])/&parse_link('',$1)/egm;
	s/(?<!\()(\(\((.*?)\)\)([^(]*?\)\))?)(?!\))/&parse_remark($1)/egs;
	
	# s/\x00//g; return $_;
	
	# Parse file linearly, constructing all ankors and links
	$_ = linear_parser($_);
	s/__TOC__/&insert_TOC()/e;
	s/ *__NOTOC__//g;
	s/ *__NOSUB__//g;
	
	s/(\{\|.*?\n\|\}) *\n?/&parse_wikitable($1)/egs;
	
	s/(?<=\<ויקי\>)\s*(.*?)\s*(\<[\\\/](ויקי)?\>)/&unescape_text($1) . "<\/ויקי>"/egs;
	# s/\<תמונה\>\s*(.*?)\s*\<\/(תמונה)?\>/&unescape_text($1)/egs;
	s/<לוח_השוואה>\s*(.*?)<\/(לוח_השוואה|)>\n?/&parse_comparetable($1)/egs;
	s/(?<=\<math\>)(.*?)(?=\<[\\\/]math\>)/&fix_math($1)/egs;
	
	s/\x00//g; # Remove nulls
	s/\n{3,}/\n\n/g;
	
	cleanup();
	
	return $_;
}

# Allow usage as a module and as a executable script
__PACKAGE__->main() unless (caller);

######################################################################

sub parse_title {
	my $_ = shift;
	my ($fix, $str);
	$_ = unquote($_);
	($_, $fix) = get_fixstr($_);
	$str = "<שם>";
	$str .= "<תיקון>$fix</תיקון>\n" if ($fix);
	$str .= "$_</שם>\n";
	return $str;
}

sub parse_section {
	my ($level, $_) = @_;
	my ($type, $num, $fix, $extra, $str);
	
	$level = 2 unless defined $level;
	
	$_ = unquote($_);
	($_, $fix) = get_fixstr($_);
	($_, $extra) = get_extrastr($_);
	
	$str = $_;
	
	# print STDERR "parse_section with |$_|\n";
	s/^\(\(([^()]*?)\)\)/$1/g;
	
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
	$type = ($type =~ /$type_sig\b/ ? $1 : '');
	$type = 'משנה' if ($type =~ /סימ(ן|ני) משנה/);
	$type = 'לוחהשוואה' if ($type =~ /השוואה/);
	my $ankor = $type;
	$ankor .= " $num" if ($type && $num ne '');
	
	$_ = $str;
	$str = "<קטע";
	$str .= " דרגה=\"$level\"" if ($level);
	$str .= " עוגן=\"$ankor\"" if ($type);
	$str .= ">";
	$str .= "<תיקון>$fix</תיקון>" if ($fix);
	$str .= "<אחר>[$extra]</אחר>" if ($extra);
	$str .= $_;
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
	$id = $num;
	$id =~ s/[.,]$//;
	
	$type =~ s/\*$//;
	$ankor = "$type $id" if (!$ankor && $num);
	my $str = "<$type עוגן=\"$ankor\">";
	$str .= "<מספר>$num</מספר>" if ($num);
	$str .= "<תיאור>$desc</תיאור>" if ($desc);
	$str .= "<תיקון>$fix</תיקון>" if ($fix);
	$str .= "<אחר>[$extra]</אחר>" if ($extra);
	$str .= "</$type>\n";
	return $str;
}

sub parse_line {
	my ($len,$num,$line) = @_;
	my $def = false;
	my $type = '';
	my $id;
	# print STDERR "|$num|$line|\n";
	if ($num =~ /\(\(/) {
		# ((remark))
		$line = $num.$line;
		$num = '';
	}
	$num =~ s/"/&quot;/g;
	$id = unparent($num);
	$len++ if ($num);
	$type = "ת" x $len;
	$line =~ s/^ *(.*?) *$/$1/;
	$def = true if ($line =~ s/^[-–] *//);
	my $str;
	$str = "<$type" . ($id ? " מספר=\"$id\"" : "") . ">";
	$str .= "<מספר>$num</מספר>" if ($num);
	$str .= "<הגדרה>" if ($def);
	$str .= "$line" if (length($line)>0);
	$str .= "</הגדרה>" if ($def);
	$str .= "</$type>\n";
	return $str;
}

sub parse_link {
	my ($id,$txt) = @_;
	my $str;
	$id = unquote($id);
	# $txt =~ s/\(\((.*?)\)\)/$1/g;
	($id,$txt) = ($txt,$1) if ($txt =~ /^[ws]:(?:[a-z]{2}:)?(.*)$/ && !$id); 
	$str = "<קישור";
	$str .= " $id" if ($id);
	$str .= ">$txt</קישור>";
	$str =~ s/([()])\1/$1\x00$1/g unless ($str =~ /\(\(.*\)\)/); # Avoid splitted comments
	return $str;
}

sub parse_remark {
	my $_ = shift;
	s/^\(\((.*?)\)\)$/$1/s;
	my ($text,$tip,$url) = ( /((?:\{\{.*?\}\}|\[\[.*?\]\]|[^\|])+)/g );
	my $str;
	$text =~ s/^ *(.*?) *$/$1/;
	if ($tip) {
		$tip =~ s/^ *(.*?) *$/$1/;
		$tip = escape_quote($tip);
		$str = "<תיבה טקסט=\"$tip\"";
		if ($url) {
			$url =~ s/^ *(.*?) *$/$1/;
			$url = "http://fs.knesset.gov.il/$1/law/$1_lsr_$2.pdf" if ($url =~ /^(\d+):(\d+)$/);
			$url = "http://fs.knesset.gov.il/$2/law/$2_lsr_$1_$3.pdf" if ($url =~ /^(ec):(\d+):(\d+)$/);
			$url = "http://fs.knesset.gov.il/$2/law/$2_ls$1_$3.pdf" if ($url =~ /^([a-z]+):(\d+):(\d+)$/);
			$url = "http://knesset.gov.il/laws/data/law/$1/$1_$2.pdf" if ($url =~ /^(\d+)_(\d+)$/);
			$url = "http://knesset.gov.il/laws/data/law/$1/$1.pdf" if ($url =~ /^(\d{4})$/);
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
	my $_ = shift;
	chomp;
#	print STDERR "Signatures = |$_|\n";
	my $str = "<חתימות>\n";
	$str .= "<פרסום>$pubdate</פרסום>\n" if ($pubdate);
	s/;/\n/g;
	foreach (split("\n")) {
		s/^\*? *(.*?) *$/$1/;
		s/ *[\|\,] */ | /g;
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
	# my $_ = shift;
	# return "<פרסום>$_</פרסום>\n"
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
			$attributes = ($1);
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
					$cell = "$previous<$last_tag>"; 
					# print STDERR "Empty cell data at |" . join('|',@cells) . "|\n";
				} elsif ( $cell_data[0] =~ /\[\[|\{\{/ ) {
					$cell = "$previous<$last_tag>$cell";
				} elsif ( @cell_data < 2 ) {
					$cell = "$previous<$last_tag>$cell_data[0]";
				} else {
					$attributes = $cell_data[0];
					$cell = $cell_data[1];
					$cell = "$previous<$last_tag $attributes>$cell";
				}
				
				$_ .= $cell;
				push @td_history, true;
			}
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
	for my $_ (@lines) {
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

sub get_fixstr {
	my $_ = shift;
	my @fix = ();
	my $fix_sig = '(?:תיקון|תקון|תיקונים):?';
	push @fix, unquote($1) while (s/(?| *\($fix_sig *(([^()]++|\(.*?\))+) *\)| *\[$fix_sig *(.*?) *\](?!\]))//);
	s/^ *(.*?) *$/$1/;
	s/\bה(תש[א-ת"]+)\b/$1/g for (@fix);
	return ($_, join(', ',@fix));
}

sub get_extrastr {
	my $_ = shift;
	my $extra = undef;
	$extra = unquote($1) if (s/(?<=[^\[])\[ *([^\[\]]+) *\] *//) || (s/^\[ *([^\[\]]+) *\] *//);
	s/^ *(.*?) *$/$1/;
	$extra =~ s/(?=\()/\<wbr\>/g if defined $extra;
	return ($_, $extra);
}

sub get_ankor {
	my $_ = shift;
	my @ankor = ();
	push @ankor, unquote($1) while (s/(?| *\(עוגן:? *(.*?) *\)| *\[עוגן:? *(.*?) *\])//);
	return ($_, join(', ',@ankor));
}

sub get_numeral {
	my $_ = shift;
	return '' if (!defined($_));
	my $num = '';
	my $token = '';
	s/&quot;/"/g;
	s/[,"'״׳]//g; # s/[.,"']//g;
	s/([א-ת]{3})(\d)/$1-$2/;
	$_ = unparent($_);
	while ($_) {
		$token = '';
		given ($_) {
			($num,$token) = ("0",$1) when /^(ה?מקדמית?)\b/;
			($num,$token) = ("11",$1) when /^(ה?אחד[- ]עשר|ה?אחת[- ]עשרה)\b/;
			($num,$token) = ("12",$1) when /^(ה?שניי?ם[- ]עשר|ה?שתיי?ם[- ]עשרה)\b/;
			($num,$token) = ("13",$1) when /^(ה?שלושה[- ]עשר|ה?שלוש[- ]עשרה)\b/;
			($num,$token) = ("14",$1) when /^(ה?ארבעה[- ]עשר|ה?ארבע[- ]עשרה)\b/;
			($num,$token) = ("15",$1) when /^(ה?חמי?שה[- ]עשר|ה?חמש[- ]עשרה)\b/;
			($num,$token) = ("16",$1) when /^(ה?שי?שה[- ]עשר|ה?שש[- ]עשרה)\b/;
			($num,$token) = ("17",$1) when /^(ה?שבעה[- ]עשר|ה?שבע[- ]עשרה)\b/;
			($num,$token) = ("18",$1) when /^(ה?שמונה[- ]עשרה?)\b/;
			($num,$token) = ("19",$1) when /^(ה?תשעה[- ]עשר|ה?תשע[- ]עשרה)\b/;
			($num,$token) = ("1",$1) when /^(ה?ראשו(ן|נה)|אחד|אחת])\b/;
			($num,$token) = ("2",$1) when /^(ה?שניי?ה?|ש[תנ]יי?ם)\b/;
			($num,$token) = ("3",$1) when /^(ה?שלישית?|שלושה?)\b/;
			($num,$token) = ("4",$1) when /^(ה?רביעית?|ארבעה?)\b/;
			($num,$token) = ("5",$1) when /^(ה?חמי?שית?|חמש|חמי?שה)\b/;
			($num,$token) = ("6",$1) when /^(ה?שי?שית?|שש|שי?שה)\b/;
			($num,$token) = ("7",$1) when /^(ה?שביעית?|שבעה?)\b/;
			($num,$token) = ("8",$1) when /^(ה?שמינית?|שמונה)\b/;
			($num,$token) = ("9",$1) when /^(ה?תשיעית?|תשעה?)\b/;
			($num,$token) = ("10",$1) when /^(ה?עשירית?|עשרה?)\b/;
			($num,$token) = ("20",$1) when /^(ה?עשרים)\b/;
			($num,$token) = ("$1-2","$1$2") when /^(\d+)([- ]?bis)\b/i;
			($num,$token) = ("$1-3","$1$2") when /^(\d+)([- ]?ter)\b/i;
			($num,$token) = ("$1-4","$1$2") when /^(\d+)([- ]?quater)\b/i;
			($num,$token) = ($1,$1) when /^(\d+(\.\d+[א-ט]?)+)\b/;
			($num,$token) = ($1,$1) when /^(\d+(([א-י]|טו|טז|[יכלמנסעפצ][א-ט]?|)\d*|))\b/;
			($num,$token) = ($1,$1) when /^(([א-י]|טו|טז|[יכלמנסעפצ][א-ט]?|[ק](טו|טז|[יכלמנסעפצ]?[א-ט]?))(\d+[א-י]*|))\b/;
		}
		if ($num ne '') {
			# Remove token from rest of string
			s/^$token//;
			last;
		} else {
			# Fetch next token
			s/^[^ ()|]*[ ()|]+// || s/^.*//;
		}
	}
	
	$num .= "-$1" if (s/^[- ]([א-י])\b//);
	$num .= "-$1$2" if (s/^[- ]([א-י])[- ]?(\d)\b//);
	$num .= "-$1" if ($num =~ /^\d/ and $token !~ /^\d/ and /^[- ]?(\d[א-י]?)\b/);
	$num =~ s/(?<=\d)-(?=[א-ת])//;
	return $num;
}

sub unquote {
	my $_ = shift;
	s/^ *(["']) *(.*?) *\1 *$/$2/;
	return $_;
}

sub unparent {
	my $_ = unquote(shift);
	s/^\((.*?)\)$/$1/;
	s/^\[(.*?)\]$/$1/;
	s/^\{(.*?)\}$/$1/;
	s/^ *(.*?) *$/$1/;
	return $_;
}

sub escape_quote {
	my $_ = shift;
	s/^ *(.*?) *$/$1/;
	s/&/\&amp;/g;
	s/"/&quot;/g;
	return $_;
}

sub escape_text {
	my $_ = unquote(shift);
#	print STDERR "|$_|";
	s/&/\&amp;/g;
	s/</&lt;/g;
	s/>/&gt;/g;
	s/([(){}"'\[\]<>\|])/"&#" . ord($1) . ";"/ge;
#	print STDERR "$_|\n";
	return $_;
}

sub unescape_text {
	my $_ = shift;
	my %table = ( 'quot' => '"', 'lt' => '<', 'gt' => '>', 'ndash' => '–', 'nbsp' => ' ', 'apos' => "'", # No &amp; conversion here!
		'lrm' => "\x{200E}", 'rlm' => "\x{200F}", 'shy' => '&null;',
		'deg' => '°', 'plusmn' => '±', 'times' => '×', 'sup1' => '¹', 'sup2' => '²', 'sup3' => '³', 
		'frac14' => '¼', 'frac12' => '½', 'frac34' => '¾', 'alpha' => 'α', 'beta' => 'β', 'gamma' => 'γ', 'delta' => 'δ', 'epsilon' => 'ε',
	);
	s/&#(\d+);/chr($1)/ge;
	s/(&([a-z]+);)/($table{$2} || $1)/ge;
	s/&null;//g;
	s/&amp;/&/g;
#	print STDERR "|$_|\n";
	return $_;
}

sub canonic_name {
	my $_ = shift;
	tr/–־/-/;
	tr/״”“/"/;
	tr/׳‘’/'/;
	return $_;
}

sub fix_math {
	my $_ = shift;
	tr/–/-/;
	return $_;
}

sub dump_hash {
	my $h = shift;
	return join('; ', map("$_ => '" . ($h->{$_} // "[undef]") . "'", keys($h)));
}


#---------------------------------------------------------------------

our %glob;
our %hrefs;
our %sections;
our (@line, $idx);

sub cleanup {
	undef %glob; undef %hrefs; undef %sections; undef @line;
	undef $pubdate;
}

sub linear_parser {
	cleanup();
	my $_ = shift;
	
	my @sec_list = (m/<קטע [^>]*?עוגן="(.*?)">/g);
	check_structure(@sec_list);
	# print STDERR "part_type = $glob{part_type}; sect_type = $glob{sect_type}; subs_type = $glob{subs_type};\n";
	
	$glob{context} = '';
	
	@line = split(/(<(?: "[^"]*"|[^>])*>)/, $_);
	$idx = 0;
	for (@line) {
		if (/<(.*)>/) {
			parse_element($1);
		} elsif ($glob{context} eq 'href') {
			$glob{href}{txt} .= $_;
		}
		$idx++;
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
			$hrefs{$href_idx} = process_HREF();
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
	my ($type,$num) = split(/ /,$name || '');
	# $num = get_numeral($num) if defined($num);
	$type =~ s/\(\(.*?\)\)//g if (defined $type);
	given ($type) {
		when (undef) {}
		when (/חלק/) { $glob{part} = $num; $glob{sect} = $glob{subs} = undef; }
		when (/פרק/) { $glob{sect} = $num; $glob{subs} = undef; }
		when (/משנה/) { $glob{subsub} = $num; }
		when (/סימן/) { $glob{subs} = $num; }
		when (/לוחהשוואה/) { delete @glob{"part", "sect", "subs", "subsub", "supl", "appn", "form", "tabl", "tabl2"}; }
		when (/תוספת/) { $glob{supl} = ($num || ""); delete @glob{"part", "sect", "subs", "subsub", "appn", "form", "tabl", "tabl2"}; }
		when (/נספח/) { $glob{appn} = ($num || ""); delete @glob{"part", "sect", "subs", "subsub"}; }
		when (/טופס/) { $glob{form} = ($num || ""); delete @glob{"part", "sect", "subs", "subsub"}; }
		when (/לוח/) { $glob{tabl} = ($num || ""); delete @glob{"part", "sect", "subs", "subsub"}; }
		when (/טבלה/) { $glob{tabl2} = ($num || ""); delete @glob{"part", "sect", "subs", "subsub"}; }
	}
	if (defined $type) {
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
	my $num = get_numeral($params);
	$glob{chap} = $num;
	if ((defined $glob{supl} || defined $glob{tabl}) && $num) {
		my $ankor = "פרט $num";
		$ankor = "סימן $glob{subs} $ankor" if (defined $glob{part} && defined $glob{subs});
		$ankor = "חלק $glob{part} $ankor" if (defined $glob{part});
		$ankor = "לוח $glob{tabl} $ankor" if (defined $glob{tabl});
		$ankor = "טבלה $glob{tabl2} $ankor" if (defined $glob{tabl2});
		$ankor = "נספח $glob{appn} $ankor" if (defined $glob{appn});
		$ankor = "תוספת $glob{supl} $ankor" if (defined $glob{supl});
		$ankor =~ s/  / /g;
		# $line[$idx] =~ s/סעיף\*?/סעיף*/;
		$line[$idx] =~ s/ עוגן=".*?"/ עוגן="$ankor"/;
		# $line[$idx] .= "\n<עוגן $ankor>";
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
		if ($text =~ /__NOTOC__/) {
			$skip = $indent;
			next;
		}
		next if ($skip and $indent>$skip);
		next if ($indent>3);
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

sub process_HREF {
	
	my $text = $glob{href}{txt};
	my $helper = $glob{href}{helper};
	my $id = $glob{href}{idx};
	
	# Canonic name
	$text = canonic_name($text);
	$helper = canonic_name($helper);
	
	$helper =~ s/\$/ $text /;
	
	my ($int,$ext) = findHREF($text);
	my $marker = '';
	my $found = false;
	my $hash = false;
	my $update_lookahead = false;
	my $update_mark = false;
	
	my $type = ($ext) ? 3 : 1;
	
	$ext = '' if ($type == 1);
	
	# print STDERR "## X |$text| X |$ext|$int| X |$helper|\n";
	
	if ($helper =~ /^(קובץ|[Ff]ile|תמונה|[Ii]mage):/) {
		return "";
	} elsif ($helper =~ /^https?:\/\/|w:|s:/) {
		$type = 4;
		$ext = $helper;
		$int = $helper = '';
		$found = true;
	} elsif ($helper =~ /^(.*?)#(.*)/) {
		$type = 3;
		$helper = $1 || $ext;
		# $ext = '' if ($1 ne '');
		$ext = $1; $int = $2;
		($int, undef) = findHREF("+#$2") if ($2);
		$found = true;
		$hash = ($2 eq '');
	}
	
	# print STDERR "## X |$text| X |$ext|$int| X |$helper|\n";
	
	if ($helper =~ /^= *(.*)/) {
		$type = 3;
		$helper = $1;
		$helper =~ s/^ה//; $helper =~ s/[-: ]+/ /g;
		(undef,$ext) = findHREF($text,$helper);
		$update_mark = true;
	} elsif ($helper =~ /^(.*?) *= *(.*)/) {
		$type = 3;
		$ext = $1; $helper = $2;
		(undef,$helper) = findHREF($text) if ($2 eq '');
		$helper =~ s/^ה//; $helper =~ s/[-: ]+/ /g;
		(undef,$ext) = findHREF($ext,$helper);
		$update_mark = true;
	} elsif ($helper eq '+' || $ext eq '+') {
		$type = 2;
		($int, $ext) = findHREF("+#$text") unless ($found);
		push @{$glob{href}{ahead}}, $id;
	} elsif ($helper eq '++' || $ext eq '++') {
		$type = 3;
		(undef, $helper) = findHREF("$text");
		$ext = "++$helper";
		# push @{$glob{href}{marks_ahead}{$helper}}, $id;
	} elsif ($helper eq '-' || $ext eq '-') {
		$type = 2;
		$ext = $glob{href}{last};
		($int, undef) = findHREF("-#$text") unless ($found);
		$update_lookahead = true;
		if ($ext =~ /\+\+(.*)/) {
			$helper = $1;
			push @{$glob{href}{marks_ahead}{$helper}}, $id;
		}
	} elsif ($helper) {
		if ($found) {
			(undef,$ext) = findHREF($helper);
			$ext = $helper if ($ext eq '');
		} elsif (defined $glob{href}{marks}{$helper}) {
			$ext = $glob{href}{marks}{$helper};
		} else {
			($int,$ext) = findHREF($helper);
		}
		$ext = $glob{href}{last} if ($ext eq '-');
		$type = ($ext) ? 3 : 1;
	} else {
	}
	
	## print STDERR "## X |$text| X |$ext|$int| X |$helper|\n";
	
	if ($update_mark) {
		$glob{href}{marks}{$helper} = $ext;
		unless ($helper =~ /$extref_sig/) {
			$glob{href}{all_marks} .= "|$helper";
			$glob{href}{all_marks} =~ s/^\|//;
			# print STDERR "adding '$helper' to all_marks = '$glob{href}{all_marks}'\n";
		}
		## print STDERR "$helper is $ext\n";
		for (@{$glob{href}{marks_ahead}{$helper}}) {
			## print STDERR "## X replacing |$hrefs{$_}|";
			$hrefs{$_} =~ s/\+[^#]*(.*)/$ext$1/;
			## print STDERR " with |$hrefs{$_}|\n";
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
				push @{$glob{href}{marks_ahead}{$helper}}, $id;
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

sub findHREF {
	my $_ = shift;
	my $helper = shift;
	if (!$_) { return $_; }
	
	my $ext = '';
	
	if (/^([ws]:|https?:|קובץ:|[Ff]ile:|תמונה:|[Ii]mage:)/) {
		return ('', $_);
	}
	
	if (/^(.*?)#(.*)$/) {
		$_ = $2;
		$ext = findExtRef($1);
	}
	
	s/\(\((.*?)\)\)/$1/g;
	s/<הערה>(.*?)<\/הערה>/$1/g;
	
	if (/דברי?[- ]ה?מלך/ and /(סימן|סימנים) \d/) {
		s/(סימן|סימנים)/סעיף/;
	}
	
	s/(\b[לב]?(אותו|אותה)\b) *($extref_sig[- ]*([א-ת]+\b.*)?)$/$4 $2/;
	
	if (/^(.*?)\s*($extref_sig[- ]*([א-ת]+\b.*)?)$/) {
		$_ = $1;
		$ext = findExtRef($2) unless ($ext);
	} elsif (/^(.*?) *$extref_sig(.*?)$/ and $glob{href}{marks}{"$2$3"}) {
		$ext = "$2$3";
		$_ = $1;
	} elsif ($glob{href}{all_marks} and /^(.*?) *\b$pre_sig($glob{href}{all_marks})(.*?)$/) {
		$ext = "$2$3";
		$_ = $1;
	}
	
	s/((?:סעי[פף]|תקנ[הת])\S*) (קטן|קטנים|משנה) (\d[^( ]*?)(\(.*?\))/$1 $3 $2 $4/;
	s/[\(_]/ ( /g;
	s/(פרי?ט|פרטים) \(/$1/g;
	s/["'״׳]//g;
	s/\bו-//g;
	s/\b(או|מן|סיפא|רישא)\b/ /g;
	s/^ *(.*?) *$/$1/;
	s/לוח השוואה/לוחהשוואה/;
	s/סימ(ן|ני) משנה/משנה/;
	s/$pre_sig(אות[והםן]) $type_sig/$2 $1/g;
	my $href = $_;
	my @parts = split /[ ,.\-\)]+/;
	my $class = '';
	my ($num, $numstr);
	my %elm = ();
	
	my @matches = ();
	my @pos = ();
	push @pos, $-[0] while (/([^ ,.\-\)]+)/g);
	
	for my $p (@pos) {
		$_ = substr($href,$p);
		$num = undef;
		given ($_) {
			when (/לוחהשוואה/) { $class = "comptable"; $num = ""; }
			when (/^$pre_sig(חלק|חלקים)/) { $class = "part"; }
			when (/^$pre_sig(פרק|פרקים)/) { $class = "sect"; }
			when (/^$pre_sig(משנה)/) { $class = "subsub"; }
			when (/^$pre_sig(סימן|סימנים)/) { $class = "subs"; }
			when (/^$pre_sig(תוספת|תוספות|נספח|נספחים)/) { $class = "supl"; $num = ""; }
			when (/^$pre_sig(טופס|טפסים)/) { $class = "form"; }
			when (/^$pre_sig(לוח|לוחות)/) { $class = "tabl"; }
			when (/^$pre_sig(טבל[הא]|טבלאות)/) { $class = "tabl2"; }
			when (/^$pre_sig(סעיף|סעיפים|תקנה|תקנות)/) { $class = "chap"; }
			when (/^$pre_sig(פריט|פרט)/) { $class = "supchap"; }
			when (/^$pre_sig(קט[נן]|פי?סקה|פסקאות|משנה|טור)/) { $class = "small"; }
			when ("(") { $class = "small" unless ($class eq "supchap"); }
			when (/^ה?(זה|זו|זאת)/) {
				given ($class) {
					when (/supl|form|tabl|table2/) { $num = $glob{$class} || ''; }
					when (/part|sect|form|chap/) { $num = $glob{$class}; }
					when (/subs/) {
						$elm{subs} = $glob{subs} unless defined $elm{subs};
						$elm{sect} = $glob{sect} unless defined $elm{sect};
					}
					when (/subsub/) {
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
					when (/subs/) {
						$elm{sect} = $glob{href}{ditto}{sect} unless defined $elm{sect};
						$elm{part} = $glob{href}{ditto}{part} unless defined $elm{part};
					}
					when (/subsub/) {
						$elm{subs} = $glob{href}{ditto}{subs} unless defined $elm{subs};
						$elm{sect} = $glob{href}{ditto}{sect} unless defined $elm{sect};
						$elm{part} = $glob{href}{ditto}{part} unless defined $elm{part};
					}
				}
				# $elm{supl} = $glob{href}{ditto}{supl} unless defined $elm{supl};
				# print STDERR "DITTO \"$class\"\n";
				# print STDERR "\t\$ditto: " . dump_hash($glob{href}{ditto}) . "\n";
				# print STDERR "\t\$elm:   " . dump_hash(\%elm) . "\n";
			}
			default {
				s/^[לב]-(\d.*)/$1/;
				$num = get_numeral($_);
				$class = "chap_" if ($num ne '' && $class eq '');
			}
		}
		# print STDERR " --> |$_|$class|" . ($num || '') . "|\n";
		
		if (defined($num) && !$elm{$class}) {
			$elm{$class} = $num;
		}
	}
	
	$elm{chap} = $elm{chap_} if (defined $elm{chap_} and !defined $elm{chap});
	$elm{ext} = $ext // '';
	
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
		$href .= " לוח $elm{tabl}" if defined $elm{tabl};
		$href .= " טבלה $elm{tabl2}" if defined $elm{tabl2};
		$href .= " פרט $elm{supchap}" if (defined $elm{supchap});
	} elsif (defined $elm{form} || defined $elm{tabl} || defined $elm{tabl2}) {
		$href = "טופס $elm{form}" if defined $elm{form};
		$href = "לוח $elm{tabl}" if defined $elm{tabl};
		$href = "טבלה $elm{tabl2}" if defined $elm{tabl2};
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

sub findExtRef {
	my $_ = shift;
	return $_ if (/^https?:\/\//);
	return $_ if (/^[+-]$/);
	tr/"'`”׳//;
	s/#.*$//;
	s/_/ /g;
	
	s/ *\(נוסח (חדש|משולב)\)//g;
	s/ *\[.*?\]//g;
	s/\.[^\.]*$//;
	s/\, *[^ ]*\d+$//;
	s/\ ה?תש.?["״]?.[-–]\d{4}$//;
	s/ מיום \d+.*$//;
	s/\, *\d+ עד \d+$//;
	s/^ *(.*?) *$/$1/;
	
	if (/^$extref_sig( *)(.*)$/) {
		$_ = "$1$2$3";
		return '0' if ($3 =~ /^ה?(זאת|זו|זה|אלה|אלו)\b/);
		return '0' if ($3 eq "" && !defined $glob{href}{marks}{"$1"});
		return '-' if ($3 =~ /^[בלמ]?(האמורה?|האמורות|אות[הו]|שב[הו]|הה[וי]א)\b/);
		s/^ *(.*?) *$/$1/;
	}
	
	s/ [-——]+ / - /g;
	s/ {2,}/ /g;
	return $_;
}

######################################################################

sub convert_quotes {
	my $_ = shift;
	s/(תש[א-ת]?)"([א-ת])/$1״$2/g;
	# s/(\s+[בהו]?-?)"([^\"\n]+)"/$1”$2“/g;
	s/(\s+[בהו]?-?|")"([^\"\n]+(?:[״"][א-ת]+)*)"/$1”$2“/g;
	s/(\s+[בהו]?-?)"([^\"\n]+(?:[״"][א-ת]+)*)"/$1”$2“/g;
	s/([א-ת]+)"([א-ת])(?![א-ת])/$1״$2/g;
	s/([א-ת])'(?!['])/$1׳/g;
	s/([א-ת])-([\dא-ת(])/$1־$2/g;
	s/(תש[א-ת]?["״][א-ת])[-־](\d{4})/$1–$2/g;
	return $_;
}

######################################################################

1;
