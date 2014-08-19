#!/usr/bin/perl -w

use v5.14;
use strict;
no strict 'refs';
use English;
use utf8;

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
$_ = unescapeText($_);
s/\r//g;           # Unix style, no CR
s/[\t\xA0]/ /g;    # Tab and hardspace are whitespaces
s/^[ ]+//mg;       # Remove redundant whitespaces
s/[ ]+$//mg;       # Remove redundant whitespaces
s/$/\n/s;          # Add last linefeed
s/\n{3,}/\n\n/sg;  # Convert three+ linefeeds
s/\n\n$/\n/sg;     # Remove last linefeed

s/[\x{200E}\x{200F}\x{202A}-\x{202E}]//g; # Throw away LTR/RTL characters
s/[\x{2000}-\x{200A}\x{205F}]/ /g; # Typographic spaces
s/[\x{200B}-\x{200D}]//g;  # Zero-width spaces
s/[־–—‒―]/-/g;     # Different types of dashes
s/[״”“„‟″‶]/"/g;   # Different types of double quotes
s/[`׳’‘‚‛′‵]/'/g;  # Different types of single quotes
s/[ ]{2,}/ /g;     # Pack  long spaces

s/([ :])-([ \n])/$1–$2/g;
s/([א-ת]) ([,.:;])/$1$2/g;

s/(?<=\<ויקי\>)\s*(.*?)\s*(?=\<\/(ויקי)?\>)/&escapeText($1)/egs;

# Parse various elements
s/^(?|<שם>\s*\n?(.*)|=([^=].*)=)\n/&parseTitle($1)/em; # Once!
s/^<חתימות>\s*\n?(((\*.*\n)+)|(.*\n))/&parseSignatures($1)/egm;
s/^<פרסום>\s*\n?(.*)\n/&parsePubDate($1)/egm;
# s/^<מקור>\s*\n?(.*)\n\n/<מקור>\n$1\n<\\מקור>\n\n/egm;
s/^<(מבוא|הקדמה)>\s*\n?/<הקדמה>\n/gm;
s/^-{3,}$/<מפריד>/gm;

# Parse links and remarks
s/(?<=[^\[])\[\[\s*([^\]]*?)\s*[|]\s*(.*?)\s*\]\](?=[^\]])/&parseLink($1,$2)/egm;
s/(?<=[^\[])\[\[\s*(.*?)\s*\]\](?=[^\]])/&parseLink('',$1)/egm;

s/(?<=[^\(])\(\(\s*(.*?)\s*(?:\s*[|]\s*(.*?)\s*)?\)\)(?=[^\)])/&parseRemark($1,$2)/egs;

# Parse structured elements
s/^(=+)(.*?)\1\n/&parseSection(length($1),$2)/egm;
s/^<סעיף *(.*?)>(.*?)\n/&parseChapter($1,$2,"סעיף")/egm;
s/^(@.*?) +([:]+ .*)$/$1\n$2/gm;
s/^@ *(\d\S*) *\n/&parseChapter($1,"","סעיף")/egm;
s/^@ *(\d\S*) *(.*?)\n/&parseChapter($1,$2,"סעיף")/egm;
s/^@ *(\(תיקון.*?)\n/&parseChapter("",$1,"סעיף*")/egm;
s/^@ *(\(.*?\)) *(.*?)\n/&parseChapter($1,$2,"סעיף*")/egm;
s/^@ *(.*?)\n/&parseChapter("",$1,"סעיף*")/egm;
s/^([:]+) *(\([^( ]+\)) *(\([^( ]+\))/$1 $2\n$1: $3/gm;
s/^([:]+) *(\([^( ]+\)|) *(.*)\n/&parseLine(length($1),$2,$3)/egm;

s/(?<=\<ויקי\>)\s*(.*?)\s*(?=\<\/(ויקי)?\>)/&unescapeText($1)/egs;

print $_;
exit;
1;


sub parseTitle {
	my $_ = shift;
	my ($fix, $str);
	$_ = unquote($_);
	($_, $fix) = get_fixstr($_);
	$str = "<שם>\n";
	$str .= "<תיקון $fix>\n" if ($fix);
	$str .= "$_\n";
	return $str;
}

sub parseSection {
	my ($level, $_) = @_;
	my ($type, $num, $fix);
	
	$level = 2 unless defined $level;
	
	$_ = unquote($_);
	($_, $fix) = get_fixstr($_);
	
	if (s/^\((.*?)\) *//) {
		$num = $1;
	} elsif (/^(.+?)( *:| +[-])/ or /^\S+ +(\S+)/) {
		$num = get_numeral($1);
	} else {
		$num = '';
	}
	
	($type) = (/\bה?(חלק|פרק|סימן|תוספת|טופס)\b/);
	$type = '' if !defined $type;
	
	my $str = "<קטע $level $type $num>\n";
	$str .= "<תיקון $fix>\n" if ($fix);
	$str .= "$_\n";
	return $str;
}

sub parseChapter {
	my ($num, $desc,$type) = @_;
	my ($fix, $extra, $ankor);
	
	$desc = unquote($desc);
	($desc, $fix) = get_fixstr($desc);
	($desc, $extra) = get_extrastr($desc);
	($desc, $ankor) = get_ankor($desc);
	$desc =~ s/"/&quote;/g;
	$num =~ s/[.,]$//;
	
	my $str = "<$type $num>\n";
	$str .= "<תיאור \"$desc\">\n" if ($desc);
	$str .= "<תיקון $fix>\n" if ($fix);
	$str .= "<אחר [$extra]>\n" if ($extra);
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

sub parseLink {
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
		return "<סימון $tip>$text</>";
	} else {
		return "<הערה>$text</>";
	}
}

sub parseSignatures {
	my $_ = shift;
	chomp;
#	print STDERR "Signatures = |$_|\n";
	my $str = "<חתימות>\n";
	s/;/\n/g;
	foreach (split("\n")) {
		s/^\*? *(.*?) *$/$1/;
		s/ *[\|\,] */ | /g;
		$str .= "* $_\n";
# 		/^\*? *([^,|]*?)(?: *[,|] *(.*?) *)?$/;
# 		$str .= ($2 ? "* $1 | $2\n" : "* $1\n");
	}
	return $str;
}

sub parsePubDate {
	my $_ = shift;
	return "<פרסום>\n  $_\n"
}


sub get_fixstr {
	my $_ = shift;
	my @fix = ();
	push @fix, unquote($1) while (s/ *\[ *תי?קון:? *(.*?) *\]//);
	push @fix, unquote($1) while (s/ *\( *תי?קון:? *(.*?) *\)//);
	s/^ *(.*?) *$/$1/;
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
	push @ankor, unquote($1) while (s/ *\[ *עוגן:? *(.*?) *\]//);
	push @ankor, unquote($1) while (s/ *\( *עוגן:? *(.*?) *\)//);
	return ($_, join(', ',@ankor));
}

sub get_numeral {
	my $_ = shift;
	my $num = '';
	my $token = '';
	s/[.,'"]//g;
	$_ = unparent($_);
	given ($_) {
		($num,$token) = ("0",$1) when /\b(ה?מקדמית?)\b/;
		($num,$token) = ("11",$1) when /\b(ה?אחד[- ]עשר|ה?אחת[- ]עשרה)\b/;
		($num,$token) = ("12",$1) when /\b(ה?שניי?ם[- ]עשר|ה?שתיי?ם[- ]עשרה)\b/;
		($num,$token) = ("13",$1) when /\b(ה?שלושה[- ]עשר|ה?שלוש[- ]עשרה)\b/;
		($num,$token) = ("14",$1) when /\b(ה?ארבעה[- ]עשר|ה?ארבע[- ]עשרה)\b/;
		($num,$token) = ("15",$1) when /\b(ה?חמי?שה[- ]עשר|ה?חמש[- ]עשרה)\b/;
		($num,$token) = ("16",$1) when /\b(ה?שי?שה[- ]עשר|ה?שש[- ]עשרה)\b/;
		($num,$token) = ("17",$1) when /\b(ה?שבעה[- ]עשר|ה?שבע[- ]עשרה)\b/;
		($num,$token) = ("18",$1) when /\b(ה?שמונה[- ]עשרה?)\b/;
		($num,$token) = ("19",$1) when /\b(ה?תשעה[- ]עשר|ה?תשע[- ]עשרה)\b/;
		($num,$token) = ("1",$1) when /\b(ה?ראשו(ן|נה)|אח[דת])\b/;
		($num,$token) = ("2",$1) when /\b(ה?שניי?ה?|ש[תנ]יי?ם)\b/;
		($num,$token) = ("3",$1) when /\b(ה?שלישית?|שלושה?)\b/;
		($num,$token) = ("4",$1) when /\b(ה?רביעית?|ארבעה?)\b/;
		($num,$token) = ("5",$1) when /\b(ה?חמי?שית?|חמש|חמי?שה)\b/;
		($num,$token) = ("6",$1) when /\b(ה?שי?שית?|שש|שי?שה)\b/;
		($num,$token) = ("7",$1) when /\b(ה?שביעית?|שבעה?)\b/;
		($num,$token) = ("8",$1) when /\b(ה?שמינית?|שמונה)\b/;
		($num,$token) = ("9",$1) when /\b(ה?תשיעית?|תשעה?)\b/;
		($num,$token) = ("10",$1) when /\b(ה?עשירית?|עשרה?)\b/;
		($num,$token) = ("20",$1) when /\b(ה?עשרים)\b/;
		($num,$token) = ($1,$1) when /\b(\d+(([א-י]|טו|טז|[יכלמנ][א-ט]?|)\d*|))\b/;
		($num,$token) = ($1,$1) when /\b(([א-י]|טו|טז|[יכלמנ][א-ט]?)(\d+[א-י]*|))\b/;
	}
	$num .= "-$1" if (/\b$token\b[- ]([א-י])\b/);
	$num .= $1 if (/\b$token\b[- ](\d+)\b/);
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

sub escapeText {
	my $_ = unquote(shift);
#	print STDERR "|$_|";
	s/&/\&amp;/g;
	s/([(){}"'\[\]<>])/"&#" . ord($1) . ";"/ge;
#	print STDERR "$_|\n";
	return $_;
}

sub unescapeText {
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
