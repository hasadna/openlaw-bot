#!/usr/bin/perl -w

use strict;
no strict 'refs';
use English;
# use utf8;

if ($#ARGV>=0) {
	my $fin = $ARGV[0];
	my $fout = $fin;
	$fout =~ s/(.*)\.[^.]*/$1.txt2/;
	open(my $FIN,$fin) || die "Cannot open file \"$fin\"!\n";
	open(STDOUT, ">$fout") || die "Cannot open file \"$fout\"!\n";
	local $/;
	$_ = <$FIN>;
} else {
	local $/;
	$_ = <STDIN>;
}

# binmode STDIN, "utf8";
# binmode STDOUT, "utf8";
# binmode STDERR, "utf8";

# General cleanup
s/\r//g;           # Unix style, no CR
s/^[ \t]+//mg;     # Remove redundant whitespaces
s/[ \t]+$//mg;     # Remove redundant whitespaces
s/$/\n/s;          # Add last linefeed
s/\n{3,}/\n\n/sg;  # Convert three+ linefeeds
s/\n\n$/\n/sg;     # Remove last linefeed

s/ - / -- /g;
s/ -\n/ --\n/g;
s/&quote;/"/g;
s/&lt;/</g;
s/&gt;/>/g;
s/&ndash;/–/g;
s/&amp;/&/g;
s/(\S) ([,.:;])/$1$2/g;

# Parse various elements
s/^<שם>\s*\n?(.*)\n/&parseTitle($1)/em;
s/^=([^=].*)=/&parseTitle($1)/em;
s/^(==+)([^=]+?)\1/&parseSection($2)/egm;
s/^<סעיף (\S+)>(.*)\n/&parseChapter($1,$2,"סעיף")/egm;
s/^@\s*(\d\S*)[ ]*(.*)\n/&parseChapter($1,$2,"סעיף")/egm;
s/^@\s*(\S+)[ ]*(\S+)[ ]*(.*)\n/&parseChapter($2,$3,$1)/egm;
s/^([:]+)[ ]*(\(\S+\)|)[ ]*(.*)\n/&parseLine(length($1),$2,$3)/egm;
s/^<חתימות>\s*\n?((\*.*\n)*)/&parseSignatures($1)/egm;
s/^-{3,}$/<מפריד>\n/gm;

# Parse links and remarks
## s/\[\[\s*([^]]*?)\s*\=\s*(.*?)\s*\]\]/&parseDefLink($1,$2)/egm;
s/\[\[\[/\[\[ \[/g;
s/\]\]\]/\] \]\]/g;
s/\[\[\s*([^]]*?)\s*[|]\s*(.*?)\s*\]\]/&parseLink($1,$2)/egm;
s/\[\[\s*(.*?)\s*\]\]/&parseLink('',$1)/egm;

s/\(\(\s*(.*?)[|](.*?)\s*\)\)/&parseTip($1,$2)/egm;
s/\(\(\s*(\(.*?\).*?)\s*\)\)/&parseRemark($1)/egm;
s/\(\(\s*(.*?)\s*\)\)/&parseRemark($1)/egm;

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
	$str .= "  $_";
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
	my ($fix, $extra);
	
	$fix = unquote($1) if ($desc =~ s/[\(\[\<\{]תיקון[:]?\s*([^)]+)\s*[\)\]\>\}]//);
	$extra = unquote($1) if ($desc =~ s/\[([^]]+)\s*\]$//);
	
	$desc = unquote($desc);
	$num =~ s/[.,]$//;
	
	my $str = "<$type $num>\n";
	$str .= "<תיאור $desc>\n" if ($desc);
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
	my $str;
	$str = "ת"x($len+($id?1:0));
	$str = ($id ? "<$str $id>\n" : "<$str>\n");
	$str .= "  $line\n" if (length($line)>0);
	return $str;
}

sub parseLink {
	my ($id,$txt) = @_;
	my $str;
	$id = unquote($id);
	$str = ($id ? "<קישור $id>$txt</>" : "<קישור>$txt</>");
	return $str;
}

sub parseDefLink {
	my ($id,$txt) = @_;
	$id = unquote($id);
	$txt = unquote($txt);
	return "<קישור \"$id\" = \"$txt\"/>";
}

sub parseRemark {
	my $_ = shift;
	return "<הערה>$_</>";
}

sub parseTip {
	my ($text,$tip) = @_;
	return "<סימון $tip>$text</>";
}

sub parseSignatures {
	my $_ = shift;
	my $str = "<חתימות>\n";
	foreach (split("\n")) {
		/\*\s*([^,]*)[,]\s*(.*)/;
		$str .= "  $1 | $2\n";
	}
	return $str;
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

