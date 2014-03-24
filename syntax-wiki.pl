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
s/[־–—‒―]/-/g;     # All type of dashes
s/[״”“„]/"/g;      # All type of double quotes
s/[`׳’‘‚]/'/g;     # All type of single quotes
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
s/^@ *(\(.*?\)) *(.+?)\n/&parseChapter($1,$2,"סעיף*")/egm;
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
	
	if (/^\((.*?)\)/) {
		$num = $1;
		s/^\((.*?)\)\s*//;
	} else {
		/^(\S+)( *:| +[-])/ or /^\S+\s+(\S+)/;
		$num = $1;
	}
	# $num = get_numeral($num);
	($type) = /^(\S+)/;
	
	my $str;
# 	if ($name =~ /\b(חלק|פרק|סימן|תוספת|טופס)\b/) {
# 		$str = "<$type $num>\n" 
# 	} else {
# 		$str = "<$type>\n";
# 	}
	$str = "<קטע $level $type $num>\n";
	$str .= "<תיקון $fix>\n" if ($fix);
	$str .= "$_\n";
	return $str;
}

sub parseChapter {
	my ($num, $desc,$type) = @_;
	my ($fix, $extra);
	
	$desc = unquote($desc);
	($desc, $fix) = get_fixstr($desc);
	($desc, $extra) = get_extrastr($desc);
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
		/^\*? *([^,|]*?)(?: *[,|] *(.*?) *)?$/;
		$str .= ($2 ? "* $1 | $2\n" : "* $1\n");
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
	return ($_, join(', ',@fix));
}

sub get_extrastr {
	my $_ = shift;
	my $extra = undef;
	$extra = unquote($1) if (s/(?<=[^\[])\[ *([^\[\]]+) *\]$//);
	return ($_, $extra);
}

sub get_numeral {
	my $_ = shift;
	my $num = "";
	s/[.,'"]//g;
	$_ = unparent($_);
	given ($_) {
		$num = $1 when /\b(\d+(([א-י]|טו|טז|[כלמנ][א-ט]?|)\d*|))\b/;
		$num = $1 when /\b(([א-י]|טו|טז|[כלמנ][א-ט]?)(\d+[א-י]*|))\b/;
		$num = "1" when /\b(ה?ראשו(ן|נה)|אח[דת])\b/;
		$num = "2" when /\b(ה?שניי?ה?|ש[תנ]יי?ם)\b/;
		$num = "3" when /\b(ה?שלישית?|שלושה?)\b/;
		$num = "4" when /\b(ה?רביעית?|ארבעה?)\b/;
		$num = "5" when /\b(ה?חמי?שית?|חמש|חמישה)\b/;
		$num = "6" when /\b(ה?שי?שית?|שש|שי?שה)\b/;
		$num = "7" when /\b(ה?שביעית?|שבעה?)\b/;
		$num = "8" when /\b(ה?שמינית?|שמונה)\b/;
		$num = "9" when /\b(ה?תשיעית?|תשעה?)\b/;
		$num = "10" when /\b(ה?עשירית?|עשרה?)\b/;
	}
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
