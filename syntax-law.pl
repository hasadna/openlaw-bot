#!/usr/bin/perl -w

use v5.14;
use strict;
no strict 'refs';
use English;
use utf8;

use Data::Dumper;

use constant { true => 1, false => 0 };

our $extref_sig = '\bו?[בהלמש]?(חוק|פקוד[הת]|תקנות|צו|החלטה|תקנון|הוראו?ת|הודעה|כללים?|חוק[הת]|אמנה|דברי?[ -]ה?מלך)\b';
our $type_sig = 'חלק|פרק|סימן|תוספת|טופס|לוח';


if ($#ARGV>=0) {
	my $fin = $ARGV[0];
	my $fout = $fin;
	$fout =~ s/(.*)\.[^.]*/$1.txt2/;
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

# General cleanup
$_ = unescape_text($_);
s/<!--.*?-->//sg;  # Remove comments
s/\r//g;           # Unix style, no CR
s/[\t\xA0]/ /g;    # Tab and hardspace are whitespaces
s/^[ ]+//mg;       # Remove redundant whitespaces
s/[ ]+$//mg;       # Remove redundant whitespaces
s/$/\n/s;          # Add last linefeed
s/\n{3,}/\n\n/sg;  # Convert three+ linefeeds
s/\n\n$/\n/sg;     # Remove last linefeed

tr/\x{200E}\x{200F}\x{202A}-\x{202E}\x{2066}-\x{2069}//d; # Throw away all BIDI characters
tr/\x{2000}-\x{200A}\x{205F}/ /; # Convert typographic spaces
tr/\x{200B}-\x{200D}//d;         # Remove zero-width spaces
tr/־–—‒―\xAD/-/;   # Convert typographic dashes
tr/״”“„‟″‶/"/;     # Convert typographic double quotes
tr/`׳’‘‚‛′‵/'/;    # Convert typographic single quotes
s/[ ]{2,}/ /g;     # Pack  long spaces

s/([ :])-([ \n])/$1–$2/g;
s/([א-ת]) ([,.:;])/$1$2/g;

s/(?<=\<ויקי\>)\s*(.*?)\s*(?=\<\/(ויקי)?\>)/&escape_text($1)/egs;

# Parse various elements
s/^(?|<שם>\s*\n?(.*)|=([^=].*)=)\n/&parse_title($1)/em; # Once!
s/^<חתימות>\s*\n?(((\*.*\n)+)|(.*\n))/&parse_signatures($1)/egm;
s/^<פרסום>\s*\n?(.*)\n/&parse_pubdate($1)/egm;
# s/^<מקור>\s*\n?(.*)\n\n/<מקור>\n$1\n<\\מקור>\n\n/egm;
s/^<(מבוא|הקדמה)>\s*\n?/<הקדמה>\n/gm;
s/^-{3,}$/<מפריד>/gm;

# Parse links and remarks
s/\[\[(?:קובץ:|file:)(.*?)\]\]/<תמונה $1>/gm;

s/(?<=[^\[])\[\[ *([^\]]*?) *\| *(.*?) *\]\](?=[^\]])/&parse_link($1,$2)/egm;
s/(?<=[^\[])\[\[ *(.*?) *\]\](?=[^\]])/&parse_link('',$1)/egm;

s/(?<=[^\(])\(\( *(.*?) *(?:\| *(.*?) *)?\)\)(?=[^\)])/&parseRemark($1,$2)/egs;

# Parse structured elements
s/^(=+)(.*?)\1\n/&parse_section(length($1),$2)/egm;
s/^<סעיף *(.*?)>(.*?)\n/&parse_chapter($1,$2,"סעיף")/egm;
s/^(@.*?) +(:+ .*)$/$1\n$2/gm;
s/^@ *(\(תיקון.*?)\n/&parse_chapter("",$1,"סעיף*")/egm;
s/^@ *(\d\S*) *\n/&parse_chapter($1,"","סעיף")/egm;
s/^@ *(\d[^ .]*\.?) *(.*?)\n/&parse_chapter($1,$2,"סעיף")/egm;
s/^@ *([^ \n.]+\.?) *(.*?)\n/&parse_chapter($1,$2,"סעיף")/egm;
s/^@ *(\(.*?\)) *(.*?)\n/&parse_chapter($1,$2,"סעיף*")/egm;
s/^@ *(.*?)\n/&parse_chapter("",$1,"סעיף*")/egm;
s/^([:]+) *(\([^( ]+\)) *(\([^( ]+\))/$1 $2\n$1: $3/gm;
s/^([:]+) *(\([^( ]+\)|) *(.*)\n/&parseLine(length($1),$2,$3)/egm;

# Parse file linearly, constructing all ankors and links
$_ = linear_parser($_);

s/(?<=\<ויקי\>)\s*(.*?)\s*(?=\<\/(ויקי)?\>)/&unescape_text($1)/egs;
# s/\<תמונה\>\s*(.*?)\s*\<\/(תמונה)?\>/&unescape_text($1)/egs;

print $_;
exit;
1;


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
	my ($type, $num, $fix);
	
	$level = 2 unless defined $level;
	
	$_ = unquote($_);
	($_, $fix) = get_fixstr($_);
	
	if (/^\((.*?)\)$/) {
		$num = '';
	} elsif (s/^\((.*?)\) *//) {
		$num = $1;
	} elsif (/^(.+?)( *:| +[-])/) {
		$num = get_numeral($1);
	} elsif (/^((?:[^ (]+( +|$)){2,3})/) {
		$num = get_numeral($1);
	} else {
		$num = '';
	}
	
	($type) = (/\bה?($type_sig)\b/);
	$type = '' if !defined $type;
	
	my $str = "<קטע";
	$str .= " $level" if ($level);
	$str .= " $type" if ($type);
	$str .= " $num" if ($type && $num ne '');
	$str .= ">";
	$str .= "<תיקון $fix>" if ($fix);
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
	$str .= "<אחר [$extra]>" if ($extra);
	$str .= "\n";
	return $str;
}

sub parseLine {
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
	($id,$txt) = ($txt,$1) if ($txt =~ /^w:(.*)$/ && !$id); 
	$str = ($id ? "<קישור $id>$txt</>" : "<קישור>$txt</>");
	return $str;
}

sub parseRemark {
	my ($text,$tip) = @_;
#	print STDERR "|$text|$tip|" . length($tip) . "\n";
	if ($tip) {
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
	s/[.,'"]//g;
	$_ = unparent($_);
	while ($_) {
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
			($num,$token) = ($1,$1) when /^(\d+(([א-י]|טו|טז|[יכלמנסעפצ][א-ט]?|)\d*|))\b/;
			($num,$token) = ($1,$1) when /^(([א-י]|טו|טז|[יכלמנ][א-ט]?)(\d+[א-י]*|))\b/;
		}
		$token = $1 if ($1);
		if ($num ne '') {
			s/^$token//;
			last;
		} else {
			# Fetch next token
			s/^[^ ()]*[ ()]+// || s/^.*//;
		}
	}
	
	$num .= "-$1" if (/^[- ]([א-י])\b/);
	$num .= "-$1" if ($num =~ /^\d/ and $token !~ /^\d/ and /^[- ](\d)\b/);
	$num =~ s/(\d)[-]([א-ת])/$1$2/;
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
	s/([(){}"'\[\]<>])/"&#" . ord($1) . ";"/ge;
#	print STDERR "$_|\n";
	return $_;
}

sub unescape_text {
	my $_ = shift;
	s/&#(\d+);/chr($1)/ge;
	s/&quote;/"/g;
	s/&lt;/</g;
	s/&gt;/>/g;
	s/&ndash;/–/g;
	s/&nbsp;/ /g;
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


#---------------------------------------------------------------------

our %glob;
our %hrefs;
our %sections;
our (@line, $idx);

sub linear_parser {
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
			my ($level,$name) = split(/ /,$params,2);
			my ($type,$num) = split(/ /,$name || '');
			$num = get_numeral($num) if defined($num);
			given ($type) {
				when (undef) {}
				when (/חלק/) { $glob{part} = $num; $glob{sect} = $glob{subs} = undef; }
				when (/פרק/) { $glob{sect} = $num; $glob{subs} = undef; }
				when (/סימן/) { $glob{subs} = $num; }
				when (/תוספת/) { $glob{supl} = ($num || ""); $glob{part} = $glob{sect} = $glob{subs} = undef; }
				when (/טופס/) { $glob{form} = ($num || ""); $glob{part} = $glob{sect} = $glob{subs} = undef; }
				when (/לוח/) { $glob{tabl} = ($num || ""); $glob{part} = $glob{sect} = $glob{subs} = undef; }
			}
			if (defined $type) {
				$name = "פרק $glob{sect} $name" if ($type eq 'סימן' && defined $glob{sect});
				$name = "חלק $glob{part} $name" if ($type =~ 'סימן|פרק' && $glob{sect_type}==3 && defined $glob{part});
				$name = "תוספת $glob{supl} $name" if ($type ne 'תוספת' && defined $glob{supl});
				$name =~ s/  / /g;
				$sections{$idx} = $name;
				# print STDERR "GOT section |$type|$num| as |$name| (position is " . current_position() . ")\n" if ($type);
			}
		}
		when (/סעיף/) {
			my $num = get_numeral($params);
			$glob{chap} = $num;
			if (defined $glob{supl} && $num) {
				my $ankor = "תוספת $glob{supl} פרט $num";
				$ankor =~ s/  / /g;
				$line[$idx] =~ s/סעיף/סעיף*/;
				$line[$idx] .= "<עוגן $ankor>";
			}
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
			$hrefs{$href_idx} = processHREF();
			# print STDERR "GOT href at $href_idx = |$hrefs{$href_idx}|\n";
			$glob{context} = '';
		}
		default {
			# print STDERR "GOT element $element.\n";
		}
	}
	
}


sub current_position {
	my $str = '';
	$str .= " תוספת $glob{supl}" if (defined $glob{supl});
	$str .= " טופס $glob{form}" if (defined $glob{form});
	$str .= " לוח $glob{tabl}" if (defined $glob{tabl});
	$str .= " חלק $glob{part}" if (defined $glob{part});
	$str .= " פרק $glob{sect}" if (defined $glob{sect});
	$str .= " סימן $glob{subs}" if (defined $glob{subs});
	return substr($str,1);
}


sub check_structure {
	my %types;
	$glob{part_type} = $glob{sect_type} = $glob{subs_type} = 0;
	for (@_) {
		if (/תוספת|טופס|לוח/) { last; }
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

sub processHREF {
	
	my $text = $glob{href}{txt};
	my $helper = $glob{href}{helper};
	my $id = $glob{href}{idx};
	
	my ($int,$ext) = findHREF($text);
	my $marker = '';
	my $found = false;
	my $hash = false;
	
	my $type = ($ext) ? 3 : 1;
	
	$ext = '' if ($type == 1);
	
	# print STDERR "## X |$text| X |$ext|$int| X |$helper|\n";
	
	if ($helper =~ /^קובץ:|file:|תמונה:|image:/) {
		return "";
	} elsif ($helper =~ /^https?:\/\//) {
		$ext = $helper;
		$int = '';
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
	
	if ($helper =~ /^=\s*(.*)/) {
		$type = 3;
		$helper = $1;
		(undef,$ext) = findHREF($text);
		$glob{href}{marks}{$helper} = $ext;
	} elsif ($helper eq '+' || $ext eq '+') {
		$type = 2;
		($int, $ext) = findHREF("+#$text") unless ($found);
		push @{$glob{href}{ahead}}, $id;
	} elsif ($helper eq '-' || $ext eq '-') {
		$type = 2;
		$ext = $glob{href}{last};
		($int, undef) = findHREF("-#$text") unless ($found);
	} elsif ($helper) {
		if ($found) {
			(undef,$ext) = findHREF($helper);
			$ext = $helper unless ($ext);
		} else {
			($int,$ext) = findHREF($helper);
		}
		$type = ($ext) ? 3 : 1;
	} else {
	}
	
	# print STDERR "## X |$text| X |$ext|$int| X |$helper|\n";
	
	if ($ext) {
		$ext = $glob{href}{marks}{$ext} if ($glob{href}{marks}{$ext});
		$text = ($int ? "$ext#$int" : $ext);
		
		if ($type==3) {
			$glob{href}{last} = $ext;
			for (@{$glob{href}{ahead}}) {
				$hrefs{$_} =~ s/\+#/$ext#/;
			}
			$glob{href}{ahead} = [];
		}
	} else {
		$text = $int;
	}
	
	return "$type $text";
}

sub findHREF {
	my $_ = shift;
	if (!$_) { return $_; }
	
	my $ext = '';
	
	if (/^(w:|http:|https:|קובץ:|file:|תמונה:|image:)/) {
		return ('',$_);
	}
	
	if (/^(.*?)#(.*)$/) {
		$_ = $2;
		$ext = findExtRef($1);
	}
	
	if (/דברי?[- ]ה?מלך/ and /(סימן|סימנים) \d/) {
		s/(סימן|סימנים)/סעיף/;
	}
	
	s/(\b[לב]?(אותו|אותה)\b) *($extref_sig[- ]*([א-ת]+\b.*)?)$/$4 $2/;
	
	if (/^(.*?)\s*($extref_sig\b[- ]*([א-ת]+\b.*)?)$/) {
		$_ = $1;
		$ext = findExtRef($2);
	}
	
	s/[\(_]/ ( /g;
	s/[\"\']//g;
	s/\bו-//g;
	s/\bאו\b/ /g;
	s/^ *(.*?) *$/$1/;
	s/טבלת השוואה/טבלת_השוואה/;
	
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
			when (/^ו?ש?[בהל]?(חלק|חלקים)/) { $class = "part"; }
			when (/^ו?ש?[בהל]?(פרק|פרקים)/) { $class = "sect"; }
			when (/^ו?ש?[בהל]?(סימן|סימנים)/) { $class = "subs"; }
			when (/^ו?ש?[בהל]?(תוספת)/) { $class = "supl"; $num = ""; }
			when (/^ו?ש?[בהל]?(טופס|טפסים)/) { $class = "form"; }
			when (/^ו?ש?[בהל]?(לוח|לוחות)/) { $class = "tabl"; }
			when (/טבלת_השוואה/) { $class = "table"; $num = ""; }
			when (/^ו?ש?[בהל]?(סעיף|סעיפים|תקנה|תקנות)/) { $class = "chap"; }
			when (/^ו?ש?[בהל]?(פריט|פרט)/) { $class = "supchap"; }
			when (/^ו?ש?[בהל]?(קט[נן]|פי?סקה|פסקאות|משנה|טור)/) { $class = "small"; }
			when ("(") { $class = "small" unless ($class eq "supchap"); }
			when (/^ה?(זה|זו|זאת)/) {
				given ($class) {
					when ("supl") { $num = $glob{supl} || ''; }
					when ("form") { $num = $glob{form}; }
					when ("tabl") { $num = $glob{tabl}; }
					when ("part") { $num = $glob{part}; }
					when ("sect") { $num = $glob{sect}; }
					when ("subs") {
						$elm{subs} = $glob{subs} unless defined $elm{subs};
						$elm{sect} = $glob{sect} unless defined $elm{sect};
					}
					when ("chap") { $num = $glob{chap}; }
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
	if (defined $elm{table}) {
		$href = "טבלת השוואה";
	} elsif (defined $elm{supl}) {
		$elm{supl} = $elm{supl} || $glob{supl} || '' if ($ext eq '');
	#	if (defined $elm{chap}) {
	#		$href = "תוספת $elm{supl} פרט $elm{chap}";
	#	} elsif (defined $elm{supchap}) {
	#		$href = "תוספת $elm{supl} פרט $elm{supchap}";
	#	} else {
			$elm{supchap} = $elm{supchap} || $elm{chap};
			$href = "תוספת $elm{supl}";
			$href .= " חלק $elm{part}" if (defined $elm{part});
			$href .= " פרק $elm{sect}" if (defined $elm{sect});
			$href .= " סימן $elm{subs}" if (defined $elm{subs});
			$href .= " טופס $elm{form}" if (defined $elm{form});
			$href .= " פרט $elm{supchap}" if (defined $elm{supchap});
	#	}
	} elsif (defined $elm{form}) {
		$href = "טופס $elm{form}";
		$href = "$href חלק $elm{part}" if (defined $elm{part});
		$href = "$href פרק $elm{sect}" if (defined $elm{sect});
		$href = "$href סימן $elm{subs}" if (defined $elm{subs});
	} elsif (defined $elm{tabl}) {
		$href = "לוח $elm{tabl}";
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
	} elsif (defined $elm{supchap} && $glob{supl} ne '' && $ext eq '') {
		$href = "תוספת $glob{supl} פרט $elm{supchap}";
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
	tr/"'`//;
	s/ *\(נוסח (חדש|משולב)\)//g;
	s/ *\[נוסח (חדש|משולב)\]//g;
#	s/(^[^\,\.]*).*/$1/;
	s/#.*$//;
	s/\.[^\.]*$//;
	s/\, *[^ ]*\d+$//;
	s/ מיום \d+.*$//;
	s/\, *\d+ עד \d+$//;
	s/\[.*?\]//g;
	s/^\s*(.*?)\s*$/$1/;
	
	if (/^$extref_sig(.*)$/) {
		$_ = "$1$2";
		return '' if ($2 =~ /^ *ה?(זאת|זו|זה|אלה|אלו)\b/);
		return '' if ($2 eq "" && !defined $glob{href}{marks}{"$1"});
		return '-' if ($2 =~ /^ *[לב]?(האמור|האמורה|האמורות|אותו|אותה)\b/);
	}
	s/\s[-——]+\s/_XX_/g;
	s/_/ /g;
	s/ {2,}/ /g;
	# s/[-]+/ /g;
	s/_XX_/ - /g;
	# s/[ _\:.]+/ /g;
#	print STDERR "$prev -> $_\n";
	return $_;
}
