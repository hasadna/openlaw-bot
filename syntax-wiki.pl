#!/usr/bin/perl -w

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

s/[‎‏]//g;           # Throw away LTR/RTL characters
s/[־–—‒―]/-/g;     # All type of dashes
s/[״”“„]/"/g;      # All type of double quotes
s/[`׳’‘‚]/'/g;     # All type of single quotes
s/[ ]{2,}/ /g;     # Pack  long spaces

s/ - / – /g;
s/ -\n/ –\n/g;
s/(\S) ([,.:;])/$1$2/g;

s/(?<=\<ויקי\>)\s*(.*?)\s*(?=\<\/(ויקי)?\>)/&escapeText($1)/egs;

# Parse various elements
s/^<שם>\s*\n?(.*)\n/&parseTitle($1)/em;
s/^<חתימות>\s*\n?(((\*.*\n)+)|(.*\n))/&parseSignatures($1)/egm;
s/^<פרסום>\s*\n?(.*)\n/&parsePubDate($1)/egm;
# s/^<מקור>\s*\n?(.*)\n\n/<מקור>\n$1\n<\\מקור>\n\n/egm;
s/^-{3,}$/<מפריד>\n/gm;
s/^=([^=].*)=/&parseTitle($1)/em;
s/^(==+)([^=]+?)\1/&parseSection($2)/egm;
s/^<סעיף (\S+)>(.*)\n/&parseChapter($1,$2,"סעיף")/egm;
s/^@\s*(\d\S*)\s*\n/&parseChapter($1,"","סעיף")/egm;
s/^@\s*(\d\S*)\s*(.*)\n/&parseChapter($1,$2,"סעיף")/egm;
s/^@\s*(\S+)\s+(\S+)\s+(.*)\n/&parseChapter($2,$3,$1)/egm;
s/^([:]+)\s*(\(\S+\)|)\s*(.*)\n/&parseLine(length($1),$2,$3)/egm;

# Parse links and remarks
s/(?<=[^\[])\[\[\s*([^\]]*?)\s*[|]\s*(.*?)\s*\]\](?=[^\]])/&parseLink($1,$2)/egm;
s/(?<=[^\[])\[\[\s*(.*?)\s*\]\](?=[^\]])/&parseLink('',$1)/egm;

s/(?<=[^\(])\(\(\s*(.*?)\s*(?:\s*[|]\s*(.*?)\s*)?\)\)(?=[^\)])/&parseRemark($1,$2)/egs;

s/(?<=\<ויקי\>)\s*(.*?)\s*(?=\<\/(ויקי)?\>)/&unescapeText($1)/egs;

print $_;
exit;
1;


sub parseTitle {
	my $_ = shift;
	my $fix;
	if (/\(תיקון[:]?\s*([^)]+)\s*\)/) {
		$fix = unquote($1);
		s/\(תיקון[:]?\s*([^)]+)\s*\)//;
	}
	$_ = unquote($_);
	my $str = "<כותרת>\n";
	$str .= "<תיקון $fix>\n" if ($fix);
	$str .= "  $_\n";
	return $str;
}

sub parseSection {
	my $_ = shift;
	my ($type, $num, $fix);
	
	$_ = unquote($_);
	if (/^\((.*?)\)/) {
		$num = $1;
		s/^\((.*?)\)\s*//;
	} else {
		/(\S+)\s*[:]/ || /\S+\s+(\S+)/;
		$num = $1;
	}
	$fix = unquote($1) if (s/\(תיקון[:]?\s*([^)]+)\s*\)//);
	$num =~ s/[.,'"]//;
	($type) = /^(\S+)/;
	my $str = "<$type $num>\n";
	$str .= "<תיקון $fix>\n" if ($fix);
	$str .= "  $_";
	return $str;
}

sub parseChapter {
	my ($num, $desc,$type) = @_;
	my (@fix, $fix, $extra);
	
	@fix = ();
	push @fix, unquote($1) while ($desc =~ s/[\(\[\<\{]תי?קון[:]?(.*?)[\)\]\>\}]//);
	$fix = join(', ',@fix);
	$extra = unquote($1) if ($desc =~ s/\[([^]]+)\s*\]$//);
	
	$desc = unquote($desc);
	$num =~ s/[.,]$//;
	
	my $str = "<$type $num>\n";
	$str .= "<תיאור \"$desc\">\n" if ($desc);
	$str .= "<תיקון $fix>\n" if ($fix);
	$str .= "<אחר $extra>\n" if ($extra);
	return $str;
}

sub parseLine {
	my ($len,$id,$line) = @_;
	if ($id =~ /\(\(/) {
		# ((remark))
		$line = $id.$line;
		$id = '';
	}
	$id = unparent($id);
	$line =~ s/^\s*(.*?)\s*$/$1/;
	my $str;
	$str = "ת"x($len+($id?1:0));
	$str = ($id ? "<$str $id> " : "<$str> ");
	$str .= "<הגדרה> " if ($line =~ s/^[-]\s*//);
	$str .= "$line\n" if (length($line)>0);
	return $str;
}

sub parseLink {
	my ($id,$txt) = @_;
	my $str;
	$id = unquote($id);
	$str = ($id ? "<קישור $id>$txt</>" : "<קישור>$txt</>");
	return $str;
}

# sub parseDefLink {
# 	my ($id,$txt) = @_;
# 	$id = unquote($id);
# 	$txt = unquote($txt);
# 	return "<קישור \"$id\" = \"$txt\"/>";
# }

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
		/^\*?\s*([^,|]*?)(?:\s*[,|]\s*(.*?)\s*)?$/;
		$str .= ($2 ? "* $1 | $2\n" : "* $1\n");
	}
	return $str;
}

sub parsePubDate {
	my $_ = shift;
	return "<פרסום>\n  $_\n"
}

sub unquote {
	my $_ = shift;
	s/^\s*(.*?)\s*$/$1/;
	s/^(["'])(.*?)\1$/$2/;
	s/^\s*(.*?)\s*$/$1/;
	return $_;
}

sub unparent {
	my $_ = unquote(shift);
	s/^\((.*?)\)$/$1/;
	s/^\[(.*?)\]$/$1/;
	s/^\{(.*?)\}$/$1/;
	s/^\s*(.*?)\s*$/$1/;
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

