#!/usr/bin/perl -w

package SyntaxWiki;

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
binmode STDOUT, "utf8";
binmode STDERR, "utf8";

use constant { true => 1, false => 0 };


sub main() {
	if ($#ARGV>=0) {
		my $fin = $ARGV[0];
		my $fout = $fin;
		$fout =~ s/\.[^.]*$/.wiki/;
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
	
	s/^ *(.*?) *$/$1/g;
	
	s/(<שם>.*<\/שם>)\n?/&parse_title($1)/se;
	s/(<מקור>.*<\/מקור>)\n?/&parse_bib($1)/se;
	s/(<הקדמה>.*<\/הקדמה>)\n?/&parse_preface($1)/se;
	s/(<חתימות>.*<\/חתימות>)\n?/&parse_signatures($1)/se;
	s/(<קטע.*?>.*?<\/קטע>)\n?/&parse_section($1)/gse;
	s/(<סעיף.*?>.*?<\/סעיף>)\n?/&parse_chapter($1)/gse;
	s/(<ת+( .*?)?>.*?<\/ת+>)\n?/&parse_line($1)/gse;
	
	s/(<קישור.*?>.*?<\/קישור>)/&parse_link($1)/ge;
	s/<הגדרה *.*?>(.*?)<\/הגדרה>/&parse_template('ח:הגדרה', $1)/gse;
	s/<הערה *.*?>(.*?)<\/הערה>/&parse_template('ח:הערה', $1)/gse;
	s/<תמונה.*?>(.*?)<\/תמונה>/[[Image:$1|link=]]/gs;
	
	s/<מפריד.*?>\n?/{{ח:מפריד}}\n/g;
	
	s/^\n*/{{ח:התחלה}}\n/s;
	s/\n*$/\n{{ח:סוף}}/s;
	
	$_ .= "\n$1\n" while (s/<ויקי.*?>(.*?)\n?<\/ויקי>\n?//s);
	
	return $_;
}

# Allow usage as a module and as a executable script
__PACKAGE__->main() unless (caller);

###################################################################################################

sub parse_title {
	my ($str, %attr) = parse_attr(shift);
	$str =~ s/\s*<תיקון>.*?<\/תיקון>\s*//gs;
	$str = escape_template($str);
	$str = "{{ח:כותרת|$str}}\n";
	return $str;
}

sub printBox {
	my ($str, %attr) = parse_attr(shift);
	my $tip = $attr{'טקסט'} // '';
	my $url = $attr{'קישור'} // '';
	# print STDERR "printBox got |$str|$tip|$url|\n";
	$str = escape_template($str);
	$tip =~ s|&|&amp;|g;
	$tip =~ s|"|&quot;|g;
	$tip = escape_template($tip);
	$url = escape_template($url);
	return "{{ח:תיבה|$str|$tip" . ($url ? "|$url" : "") . "}}";
}

sub parse_bib {
	# print STDERR "parse_bib got |$_[0]|\n";
	my ($_, %attr) = parse_attr(shift);
	# print STDERR "parse_bib got |$_| with \n\t\t" . dump_hash(%attr) . "\n";
	s/(<תיבה.*?>.*?<\/תיבה>)/&printBox($1)/ge;
	s/\.\n+/\.\n\n/g;
	s/\n*$//s;
	my $str = "{{ח:פתיח-התחלה}}\n$_\n";
	$str .= "{{ח:סוגר}}\n";
	$str .= "{{ח:מפריד}}\n";
	return $str;
}

sub parse_preface {
	my ($_, %attr) = parse_attr(shift);
	my $str = "{{ח:מבוא}}\n";
	$_ = trim($_);
	$str .= "$_\n";
	$str .= "{{ח:סוגר}}\n";
	$str .= "{{ח:מפריד}}\n";
	return $str;
}

sub parse_template {
	my $str = shift;
	my $cnt = 0;
	while (my $_ = shift) {
		$cnt++;
		# $str .= (/=/) ? "|$cnt=$_" : "|$_";
		# s/({{==}}|=)(?!"[^"]+")/{{==}}/g;
		s/({{==}}|=)/{{==}}/g;
		$str .= "|$_";
	}
	return "{{$str}}";
}

sub parse_signatures {
	my ($_, %attr) = parse_attr(shift);
	($_, my %tags) = parse_tag_list($_, 'פרסום');
	my $pubdate = $tags{'פרסום'};
	my $str = "{{ח:חתימות";
	$str .= "|$pubdate" if ($pubdate);
	$str .= "}}\n";
	foreach my $line (split(/\n/, $_)) {
		last unless ($line =~ /^ *\*/);
		$line =~ s/^ *\* *(.*?) *$/$1/;
		$line =~ s/ *\| */<br>/g;
		$line =~ s/^(.*?)(?=\<br\>|$)/\'\'\'$1\'\'\'/;
		$str .= "* $line\n";
	}
	$str .= "{{ח:סוגר}}\n";
	return $str;
}

sub parse_section {
	my ($str, %attr, %tags);
	my ($level, $ankor, $fix, $other, $text);
	($str, %attr) = parse_attr(shift);
	($str, %tags) = parse_tag_list($str, 'תיקון', 'אחר');
	$level = $attr{'דרגה'} // '2';
	$ankor = $attr{'עוגן'} // '';
	# print STDERR "At parse_section got |$level|$ankor|\n";
	$fix = $tags{'תיקון'};
	$other = $tags{'אחר'};
	$text = escape_template($str);
	
	$str = "{{ח:קטע$level|$ankor|$text";
	$str .= "|תיקון: $fix" if ($fix);
	$str .= "|אחר=$other" if ($other);
	$str .= "}}\n";
	return $str;
}

sub parse_chapter {
	my ($str, %attr, %tags);
	my ($number, $ankor, $desc, $fix, $other, $text);
	($str, %attr) = parse_attr(shift);
	($str, %tags) = parse_tag_list($str, 'מספר', 'תיאור', 'תיקון', 'אחר');
	$ankor = $attr{'עוגן'} // '';
	# print STDERR "parse_chapter got |$str| and |" . dump_hash(\%tags) . "|\n";
	$number = $tags{'מספר'} // '';
	$number =~ s/\.$//;
	$desc = $tags{'תיאור'} // '';
	$fix = $tags{'תיקון'};
	$other = $tags{'אחר'};
	$text = trim($str);
	my $ankor2 = $ankor unless ($ankor =~ s/^סעיף *//);
	
	$str = "{{ח:סעיף";
	$str .= "*" if ($ankor2 || !$ankor);
	$str .= "|$number|$desc" if ($number || $desc || $fix);
	$str .= "|תיקון: $fix" if ($fix);
	$str .= "|אחר=$other" if ($other);
	$str .= "|עוגן=$ankor2" if ($ankor2);
	$str .= "}}\n";
	
	if ($text) {
		# Warning: missing keyword
		$str .= "<ת>$text</ת>\n";
	}
	return $str;
}

sub parse_line {
	my ($str, %attr) = parse_attr(shift);
	my $type = $attr{tag};
	my $num = $attr{'מספר'};
	$num //= $1 if ($str =~ s/<מספר>(.*?)<\/מספר>//);
	return "{{ח:$type" . ($num ? "|$num" : "") . "}}" . ($str ? " $str\n" : " ");
}

sub parse_link {
	my ($str, %attr) = parse_attr(shift);
	my $type = $attr{'סוג'} // 1;
	$type = ($type==1 ? "פנימי" : "חיצוני" );
	my $href = $attr{'עוגן'};
	return $str unless ($href);
	$str = escape_template($str,2);
	$href = escape_template($href,1);
	$href =~ s/"/&quot;/;
	return "{{ח:$type|$href|$str}}";
}

###################################################################################################

sub trim {
	my $_ = shift // '';
	s/^\s*(.*?)\s*$/$1/s;
	return $_;
}

sub escape_template {
	my $_ = shift // '';
	my $id = shift;
	if (/=/) {
		# ($id) ? ($_ = "$id=$_") : (s/({{==}}|=)(?!"[^"]+")/{{==}}/g);
		s/({{==}}|=)(?!"[^"]+")/{{==}}/g;
	}
	s/\|/{{!}}/g;
	s/(?={{[^}\s]+){{!}}/|/g;
	return $_;
}

sub unquote {
	my $_ = shift // '';
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

sub parse_attr {
	my $_ = trim(shift);
	s/(<(?:[^>]+|"[^"]*"|'[^']*')+>)\s*(.*)/$1/s;
	my $str = $2;
	my %attr;
	my ($tag) = /<([^ >\/]+).*?>/;
	$attr{tag} = $tag;
	$str =~ s/[ \n]*<\/$tag>\n*//;
	$attr{$1} = unescape_text($2) while (/(\S+) *= *" *(.*?) *"/g);
	return ($str, %attr);
}

sub parse_tags {
	return parse_tag_list(shift, '\S+');
}

sub parse_tag_list {
	my $_ = trim(shift);
	my %tags;
	while (my $t = shift) {
		$tags{$1} = $2 while (s/<($t).*?>(.*?)<\/\1.*?>\s*//);
	}
	return ($_, %tags);
}

sub dump_hash {
	# print STDERR Dumper(@_);
	if (ref $_[0]) {
		my $h = shift;
		return join('; ', map("$_ => '" . ($h->{$_} // "[undef]") . "'", keys($h)));
	} else {
		my %h = @_;
		return join('; ', map("$_ => '" . ($h{$_} // "[undef]") . "'", keys(%h)));
	}
}
