#!/usr/bin/perl -w
# vim: shiftwidth=4 tabstop=4 noexpandtab

package SyntaxLaw;

use Exporter;
our @ISA = qw(Exporter);
our $VERSION = "0.0";
our @EXPORT = qw(convert);

use v5.14;
no if ($]>=5.018), warnings => 'experimental';
use strict;
no strict 'refs';
use English;
use utf8;

use Data::Dumper;

use constant { true => 1, false => 0 };

our $pre_sig = "ו?כ?ש?[בהלמ]?";
our $extref_sig = "\\b$pre_sig(חוק|פקוד[הת]|תקנות|צו|החלטה|תקנון|הוראו?ת|הודעה|מנשר|כללים?|חוק[הת]|אמנ[הת]|דברי?[ -]ה?מלך)\\b";
our $type_sig = "חלק|פרק|סימן|לוח(ות)? השוואה|נספח|תוספת|טופס|לוח|טבל[הא]";

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
	tr/\x{2000}-\x{200A}\x{205F}/ /; # Convert typographic spaces
	tr/\x{200B}-\x{200D}//d;         # Remove zero-width spaces
	tr/־–—‒―/-/;        # Convert typographic dashes
	tr/\xAD\x96\x97/-/; # Convert more typographic dashes
	tr/״”“„‟″‶/"/;      # Convert typographic double quotes
	tr/`׳’‘‚‛′‵/'/;     # Convert typographic single quotes
	tr/;/;/;            # Convert wrong OCRed semicolon
	s/[ ]{2,}/ /g;      # Pack  long spaces
	s/ -- / — /g;
	
	s/\[\[קטגוריה:.*?\]\] *\n?//g;  # Ignore categories (for now)
	
	# Unescape HTML characters
	$_ = unescape_text($_);
	
	s/([ :])-([ \n])/$1–$2/g;
	
	s/(?<=\<ויקי\>)\s*(.*?)\s*(?=\<\/(ויקי)?\>)/&escape_text($1)/egs;
	
	# Parse various elements
	s/^(?|<שם> *\n?(.*)|=([^=].*)=)\n/&parse_title($1)/em; # Once!
	s/<שם קודם> .*\n//g;
	s/<מאגר .*?>\n?//;
	s/^<חתימות> *\n?(((\*.*\n)+)|(.*\n))/&parse_signatures($1)/egm;
	s/^<פרסום> *\n?(.*)\n/&parse_pubdate($1)/egm;
	# s/^<מקור> *\n?(.*)\n\n/<מקור>\n$1\n<\\מקור>\n\n/egm;
	s/^<(מבוא|הקדמה)> *\n?/<הקדמה>\n/gm;
	s/^-{3,}$/<מפריד>/gm;
	
	# Parse links and remarks
	s/\[\[(?:קובץ:|תמונה:|[Ff]ile:|[Ii]mage:)(.*?)\]\]/<תמונה $1>/gm;
	
	s/(?<=[^\[])\[\[ *([^\]]*?) *\| *(.*?) *\]\](?=[^\]])/&parse_link($1,$2)/egm;
	s/(?<=[^\[])\[\[ *(.*?) *\]\](?=[^\]])/&parse_link('',$1)/egm;
	s/(?<!\()(\(\((.*?)\)\)([^(]*?\)\))?)(?!\))/&parse_remark($1)/egs;
	
	# Parse structured elements
	s/^(=+)(.*?)\1\n/&parse_section(length($1),$2)/egm;
	s/^<סעיף *(.*?)>(.*?)\n/&parse_chapter($1,$2,"סעיף")/egm;
	s/^(@.*?) +(:+ .*)$/$1\n$2/gm;
	s/^@ *(\(תיקון.*?)\n/&parse_chapter("",$1,"סעיף*")/egm;
	s/^@ *(\d\S*) *\n/&parse_chapter($1,"","סעיף")/egm;
	s/^@ *(\d[^ .]*\.) *(.*?)\n/&parse_chapter($1,$2,"סעיף")/egm;
	s/^@ *([^ \n.]+\.) *(.*?)\n/&parse_chapter($1,$2,"סעיף")/egm;
	s/^@ *(\([^()]*?\)) *(.*?)\n/&parse_chapter($1,$2,"סעיף*")/egm;
	s/^@ *(.*?)\n/&parse_chapter("",$1,"סעיף*")/egm;
	s/^(:+) *(\([^( ]+\)) *(\([^( ]{1,2}\)) *(\([^( ]{1,2}\))/$1 $2\n$1: $3\n$1:: $4/gm;
	s/^(:+) *(\([^( ]+\)) *(\([^( ]{1,2}\))/$1 $2\n$1: $3/gm;
#	s/^(:+) *("?\([^( ]+\)|\[[^[ ]+\]|\d[^ .]*\.|)(?| +(.*?)|([-–].*?)|())\n/&parse_line(length($1),$2,$3)/egm;
	s/^(:+)([-–]?) *("?\([^( ]+\)|\[[^[ ]+\]|\d[^ .]*\.|[א-י]\d?\.|)(.*?)\n/&parse_line(length($1),$3,"$2$4")/egm;

	
	# Parse file linearly, constructing all ankors and links
	$_ = linear_parser($_);
	s/__TOC__/&insert_TOC()/e;
	s/ *__NOTOC__//g;
	s/ *__NOSUB__//g;
	
	s/(?<=\<ויקי\>)\s*(.*?)\s*(\<\/(ויקי)?\>)/&unescape_text($1) . "<\/>"/egs;
	# s/\<תמונה\>\s*(.*?)\s*\<\/(תמונה)?\>/&unescape_text($1)/egs;
	s/^(\:* *|<ת+> *)(\{\|(.*\n)+^\|\} *)$/"$1" . &parse_wikitable($2)/egm;
	s/\x00//g; # Remove nulls
	
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
	$str = "<שם>\n";
	$str .= "<תיקון $fix>\n" if ($fix);
	$str .= "$_\n";
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
	} elsif (/^\((.*?)\) */) {
		$num = $1;
		$str =~ s/^\((.*?)\) *//;
	} elsif (/^(.+?)( *:| +[-])/) {
		$num = get_numeral($1);
	} elsif (/^((?:[^ (]+( +|$)){2,3})/) {
		$num = get_numeral($1);
	} else {
		$num = '';
	}
	
	$type = $_;
	$type =~ s/\(\(.*?\)\)//g;
	$type = ($type =~ /\bה?($type_sig)\b/ ? $1 : '');
	$type = 'לוחהשוואה' if ($type =~ /השוואה/);
	
	$_ = $str;
	$str = "<קטע";
	$str .= " $level" if ($level);
	$str .= " $type" if ($type);
	$str .= " $num" if ($type && $num ne '');
	$str .= ">";
	$str .= "<תיקון $fix>" if ($fix);
	$str .= "<אחר [$extra]>" if ($extra);
	$str .= " $_\n";
	return $str;
}

sub parse_chapter {
	my ($num, $desc,$type) = @_;
	my ($fix, $extra, $ankor);
	
	$desc = unquote($desc);
	($desc, $fix) = get_fixstr($desc);
	($desc, $extra) = get_extrastr($desc);
	($desc, $ankor) = get_ankor($desc);
	$desc =~ s/"/&quote;/g;
	$num =~ s/[.,]$//;
	
	my $str = "<$type" . ($num ? " $num" : "") . ">";
	$str .= "<תיאור \"$desc\">" if ($desc);
	$str .= "<תיקון $fix>" if ($fix);
	$str .= "<אחר \"[$extra]\">" if ($extra);
	$str .= "\n";
	return $str;
}

sub parse_line {
	my ($len,$id,$line) = @_;
	# print STDERR "|$id|$line|\n";
	if ($id =~ /\(\(/) {
		# ((remark))
		$line = $id.$line;
		$id = '';
	}
	$id = unparent($id);
	$line =~ s/^ *(.*?) *$/$1/;
	my $str;
	$str = "ת"x($len+($id?1:0));
	$str = ($id ? "<$str $id> " : "<$str> ");
	$str .= "<הגדרה> " if ($line =~ s/^[-–] *//);
	$str .= "$line" if (length($line)>0);
	$str .= "\n";
	return $str;
}

sub parse_link {
	my ($id,$txt) = @_;
	my $str;
	$id = unquote($id);
	($id,$txt) = ($txt,$1) if ($txt =~ /^[ws]:(?:[a-z]{2}:)?(.*)$/ && !$id); 
	$str = ($id ? "<קישור $id>$txt</>" : "<קישור>$txt</>");
	$str =~ s/([()])\1/$1\x00$1/g unless ($str =~ /\(\(.*\)\)/); # Avoid splitted comments
	return $str;
}

sub parse_remark {
	my $_ = shift;
	s/^\(\((.*?)\)\)$/$1/s;
	my ($text,$tip,$url) = ( /((?:\{\{.*?\}\}|\[\[.*?\]\]|[^\|])+)/g );
	$text =~ s/^ *(.*?) *$/$1/;
	if ($tip) {
		$tip =~ s/^ *(.*?) *$/$1/;
		if ($url) {
			$url =~ s/^ *(.*?) *$/$1/;
			$url = "http://fs.knesset.gov.il/$1/law/$1_lsr_$2.pdf" if ($url =~ /^(\d+):(\d+)$/);
			$url = "http://knesset.gov.il/laws/data/law/$1/$1_$2.pdf" if ($url =~ /^(\d+)_(\d+)$/);
			$url = "http://knesset.gov.il/laws/data/law/$1/$1.pdf" if ($url =~ /^(\d{4})$/);
			$tip .= "|$url";
		}
		return "<תיבה $tip>$text</>";
	} else {
		return "<הערה>$text</>";
	}
}

sub parse_signatures {
	my $_ = shift;
	chomp;
#	print STDERR "Signatures = |$_|\n";
	my $str = "<חתימות>\n";
	s/;/\n/g;
	foreach (split("\n")) {
		s/^\*? *(.*?) *$/$1/;
		s/ *[\|\,] */ | /g;
		$str .= "* $_\n";
		# /^\*? *([^,|]*?)(?: *[,|] *(.*?) *)?$/;
		# $str .= ($2 ? "* $1 | $2\n" : "* $1\n");
	}
	return $str;
}

sub parse_pubdate {
	my $_ = shift;
	return "<פרסום>\n  $_\n"
}

#---------------------------------------------------------------------

sub parse_wikitable {
	# Based on [mediawiki/core.git]/includes/parser/Parser.php doTableStuff() function
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

	# Remove trailing line-ending (b/c)
	$out =~ s/\n$//s;
	
	# special case: don't return empty table
	if ( $out eq "<table>\n<tr><td></td></tr>\n</table>" ) {
		$out = '';
	}
	
	return $out;
}

#---------------------------------------------------------------------

sub get_fixstr {
	my $_ = shift;
	my @fix = ();
	my $fix_sig = '(?:תיקון|תקון|תיקונים):?';
	push @fix, unquote($1) while (s/(?| *\($fix_sig *(.*?) *\)| *\[$fix_sig *(.*?) *\])//);
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
	s/&quote;/"/g;
	s/[.,"']//g;
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
	s/^ *(.*?) *$/$1/;
	s/^(["'])(.*?)\1$/$2/;
	s/^ *(.*?) *$/$1/;
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

sub escape_text {
	my $_ = unquote(shift);
#	print STDERR "|$_|";
	s/&/\&amp;/g;
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

sub bracket_match {
	my $_ = shift;
	print STDERR "Bracket = $_ -> ";
	tr/([{<>}])/)]}><{[(/;
	print STDERR "$_\n";
	return $_;
}

sub canonic_name {
	my $_ = shift;
	tr/–־/-/;
	tr/״”“/"/;
	tr/׳‘’/'/;
	return $_;
}


#---------------------------------------------------------------------

our %glob;
our %hrefs;
our %sections;
our (@line, $idx);

sub linear_parser {
	undef %glob; undef %hrefs; undef %sections; undef @line;
	
	my $_ = shift;
	
	my @sec_list = (m/<קטע \d (.*?)>/g);
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
	
	$line[$_] = "<קישור $hrefs{$_}>" for (keys %hrefs);
	$line[$_] =~ s/<(קטע \d).*?>/<$1 $sections{$_}>/ for (keys %sections);
	
	return join('',@line);
}

sub parse_element {
	my $all = shift;
	my ($element, $params) = split(/ |$/,$all,2);
	
	given ($element) {
		when (/קטע/) {
			process_section($params);
		}
		when (/סעיף/) {
			process_chapter($params);
		}
		when (/תיאור/) {
			# Split, ignore outmost parenthesis.
			my @inside = split(/(<[^>]*>)/, $all);
			continue if ($#inside<=1);
			$inside[0] =~ s/^/</; $inside[-1] =~ s/$/>/;
			# print STDERR "Spliting: |" . join('|',@inside) . "| (";
			# print STDERR "length $#line -> ";
			splice(@line, $idx, 1, @inside);
			# print STDERR "$#line)\n";
		}
		when (/קישור/) {
			$glob{context} = 'href';
			$glob{href}{helper} = $params || '';
			$glob{href}{txt} = '';
			$glob{href}{idx} = $idx;
			$hrefs{$idx} = '';
			$params = "#" . $idx;
		}
		when ('/' and $glob{context} eq 'href') {
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
	my ($level,$name) = split(/ /,$params,2);
	my ($type,$num) = split(/ /,$name || '');
	# $num = get_numeral($num) if defined($num);
	$type =~ s/\(\(.*?\)\)//g if (defined $type);
	given ($type) {
		when (undef) {}
		when (/חלק/) { $glob{part} = $num; $glob{sect} = $glob{subs} = undef; }
		when (/פרק/) { $glob{sect} = $num; $glob{subs} = undef; }
		when (/סימן/) { $glob{subs} = $num; }
		when (/לוחהשוואה/) { delete @glob{"part", "sect", "subs", "supl", "appn", "form", "tabl", "tabl2"}; }
		when (/תוספת/) { $glob{supl} = ($num || ""); delete @glob{"part", "sect", "subs", "appn", "form", "tabl", "tabl2"}; }
		when (/נספח/) { $glob{appn} = ($num || ""); delete @glob{"part", "sect", "subs"}; }
		when (/טופס/) { $glob{form} = ($num || ""); delete @glob{"part", "sect", "subs"}; }
		when (/לוח/) { $glob{tabl} = ($num || ""); delete @glob{"part", "sect", "subs"}; }
		when (/טבלה/) { $glob{tabl2} = ($num || ""); delete @glob{"part", "sect", "subs"}; }
	}
	if (defined $type) {
		$name = "פרק $glob{sect} $name" if ($type eq 'סימן' && defined $glob{sect});
		$name = "חלק $glob{part} $name" if ($type =~ 'סימן|פרק' && ($glob{sect_type}==3 || defined $glob{supl}) && defined $glob{part});
		$name = "תוספת $glob{supl} $name" if ($type ne 'תוספת' && defined $glob{supl});
		$name = "לוח השוואה" if ($type eq 'לוחהשוואה');
		$name =~ s/  / /g;
		$sections{$idx} = $name;
		# print STDERR "GOT section |$type|$num| as |$name| (position is " . current_position() . ")\n" if ($type);
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
		$line[$idx] =~ s/סעיף\*?/סעיף*/;
		$line[$idx] .= "\n<עוגן $ankor>";
	}
}

sub current_position {
	my @type = ( 'supl', 'תוספת', 'appn', 'נספח', 'form', 'טופס', 'tabl', 'לוח', 'tabl2', 'טבלה', 'part', 'חלק', 'sect', 'פרק', 'subs', 'סימן' );
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
	my $str = "<קטע 2> תוכן עניינים\n<סעיף*>\n";
	$str .= "<div style=\"columns: 2 auto; -moz-columns: 2 auto; -webkit-columns: 2 auto; text-align: right; padding-bottom: 1em;\">\n";
	my ($name, $indent, $text, $next, $style, $skip);
	for (sort {$a <=> $b} keys %sections) {
		$text = $next = '';
		$name = $sections{$_};
		$indent = $line[$_++];
		$indent = ($indent =~ /<קטע (\d)/ ? $1 : 2);
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
		$text =~ s/<(תיקון|אחר).*?> *//g;
		$text =~ s/<הערה>([^)]*<קישור.*?>.*?<\/>.*?)+<\/> *//g;
		$text =~ s/\(\(.?<קישור.*?>.*?<\/>.?\)\) *//g;
		$text =~ s/<קישור.*?>(.*?)<\/>/$1/g;
		$text =~ s/<b>(.*?)<\/b?>/$1/g;
		$text =~ s/ +$//;
		($text) = ($text =~ /^ *(.*?) *$/m);
		if ($next =~ /^<קטע (\d)> *(.*?) *$/m && $1>=$indent && !$skip) {
			$next = $2;
			$next =~ s/<(תיקון|אחר).*?> *//g;
			$next =~ s/<קישור.*?>(.*?)<\/>/$1/g;
			$next =~ s/<b>(.*?)<\/b?>/$1/g;
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
		$str .= "<div class=\"$style\"><קישור 1 $name>$text</></div>\n";
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

	my ($int,$ext) = findHREF($text);
	my $marker = '';
	my $found = false;
	my $hash = false;
	my $update_lookahead = false;
	
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
		$ext = $1;
		($int, undef) = findHREF("+#$2") if ($2);
		$found = true;
		$hash = ($2 eq '');
	}
	
	# print STDERR "## X |$text| X |$ext|$int| X |$helper|\n";
	
	if ($helper =~ /^= *(.*)/) {
		$type = 3;
		$helper = $1;
		$helper =~ s/^ה//; $helper =~ s/[-: ]+/ /g;
		(undef,$ext) = findHREF($text);
		$glob{href}{marks}{$helper} = $ext;
	} elsif ($helper =~ /^(.*?) *= *(.*)/) {
		$type = 3;
		$ext = $1; $helper = $2;
		$helper =~ s/^ה//; $helper =~ s/[-: ]+/ /g;
		(undef,$ext) = findHREF($ext);
		$glob{href}{marks}{$helper} = $ext;
	} elsif ($helper eq '+' || $ext eq '+') {
		$type = 2;
		($int, $ext) = findHREF("+#$text") unless ($found);
		push @{$glob{href}{ahead}}, $id;
	} elsif ($helper eq '-' || $ext eq '-') {
		$type = 2;
		$ext = $glob{href}{last};
		($int, undef) = findHREF("-#$text") unless ($found);
		$update_lookahead = true;
	} elsif ($helper) {
		if ($found) {
			(undef,$ext) = findHREF($helper);
			$ext = $helper if ($ext eq '');
		} else {
			($int,$ext) = findHREF($helper);
		}
		$ext = $glob{href}{last} if ($ext eq '-');
		$type = ($ext) ? 3 : 1;
	} else {
	}
	
	## print STDERR "## X |$text| X |$ext|$int| X |$helper|\n";
	
	if ($ext) {
		$helper = $ext =~ s/[-: ]+/ /gr;
		$ext = $glob{href}{marks}{$helper} if ($glob{href}{marks}{$helper});
		$text = ($int ? "$ext#$int" : $ext);
		
		if ($type==3 || $update_lookahead) {
			$glob{href}{last} = $ext;
			for (@{$glob{href}{ahead}}) {
				$hrefs{$_} =~ s/\+(#|$)/$ext$1/;
			}
			$glob{href}{ahead} = [];
		}
	} else {
		$text = $int;
	}
	$glob{href}{ditto} = $text;
	
	return "$type $text";
}

sub findHREF {
	my $_ = shift;
	if (!$_) { return $_; }
	
	my $ext = '';
	
	if (/^([ws]:|https?:|קובץ:|[Ff]ile:|תמונה:|[Ii]mage:)/) {
		return ('',$_);
	}
	
	if (/^(.*?)#(.*)$/) {
		$_ = $2;
		$ext = findExtRef($1);
	}
	
	$_ = $glob{href}{ditto} if (/^(אות[וה] ה?(סעיף|תקנה)|$pre_sig(סעיף|תקנה) האמורה?)$/);
	
	s/\(\((.*?)\)\)/$1/g;
	
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
	}
	
	s/[\(_]/ ( /g;
	s/(פרי?ט|פרטים) \(/$1/g;
	s/[\"\']//g;
	s/\bו-//g;
	s/\b(או|מן|סיפא|רישא)\b/ /g;
	s/^ *(.*?) *$/$1/;
	s/לוח השוואה/לוחהשוואה/;
	
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
				}
				$elm{supl} = $glob{supl} if ($glob{supl} && !defined($elm{supl}));
			}
			default {
				$num = get_numeral($_);
				$class = "chap_" if ($num ne '' && $class eq '');
			}
		}
		# print STDERR "  --> |$_|$class|" . ($num || '') . "|\n";
		
		if (defined($num) && !$elm{$class}) {
			$elm{$class} = $num;
		}
	}
	
	$elm{chap} = $elm{chap_} if (defined $elm{chap_} and !defined $elm{chap});
	
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
		$href = "$href חלק $elm{part}" if (defined $elm{part});
		$href = "$href פרק $elm{sect}" if (defined $elm{sect});
		$href = "$href סימן $elm{subs}" if (defined $elm{subs});
	} elsif (defined $elm{part}) {
		$href = "חלק $elm{part}";
		$href .= " פרק $elm{sect}" if (defined $elm{sect});
		$href .= " סימן $elm{subs}" if (defined $elm{subs});
	} elsif (defined $elm{sect}) {
		$href = "פרק $elm{sect}";
		$href = "$href סימן $elm{subs}" if (defined $elm{subs});
		$href = "חלק $glob{part} $href" if ($glob{sect_type}==3 && defined $glob{part} && $ext eq '');
		# $href = "תוספת $glob{supl} $href" if ($glob{supl} && $ext eq '');
	} elsif (defined $elm{subs}) {
		$href = "סימן $elm{subs}";
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
	
	# print STDERR "$_ => $elm{$_}; " for (keys %elm);
	# print STDERR "\n";
	# print STDERR "GOT |$href|$ext|\n";
	return ($href,$ext);
}	

sub findExtRef {
	my $_ = shift;
	return $_ if (/^https?:\/\//);
	return $_ if (/^[+-]$/);
	tr/"'`//;
	s/#.*$//;
	s/_/ /g;
	
	s/ *\(נוסח (חדש|משולב)\)//g;
	s/ *\[.*?\]//g;
	s/\.[^\.]*$//;
	s/\, *[^ ]*\d+$//;
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

1;
