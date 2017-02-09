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

sub max ($$) { $_[$_[0] < $_[1]] }
sub min ($$) { $_[$_[0] > $_[1]] }


my $title;

sub main() {
	if ($#ARGV>=0) {
		my $fin = $ARGV[0];
		my $fout = $fin;
		$fout =~ s/\.[^.]*$/.html/;
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
	s/(<ת+.*?>.*?<\/ת+>)\n?/&parse_line($1)/gse;
	s/<הגדרה *.*?>(.*?)<\/הגדרה>/&parse_definition($1)/gse;
	s/<הערה *.*?>(.*?)<\/הערה>/&parse_note($1)/gse;
	s/(<קישור.*?>.*?<\/קישור>)/&parse_link($1)/ge;
	s/<תמונה.*?>(.*?)<\/תמונה>/[[Image:$1|link=]]/gs;
	
#	s/<מפריד.*?>\n?/{{ח:מפריד}}\n/g;
	
	s/(?<!')'''(.*?)'''(?!')/<b>$1<\/b>/g;
	
	$_ = print_header() . $_ . print_footer();
	
	s/\n*<div><div>\s*<\/div><\/div>\n*/\n/gs;
	s/ *<div class=\"law-content\d?\">\s*<\/div>\n*//gs;
	s/\n(<\/div>)\n?/$1\n/gs;
	
	# my $template = "[^{}]*(?>(?>(?'open'{)[^{}]*)+(?>(?'-open'})[^{}]*)+)+(?(open)(?!))";
	my $template = '(?:{(?1)}|[^{}])*?';
	
	s/{{עמודות\|($template)\|($template)}}\n*/<div style="columns: $1; -moz-columns: $1; -webkit-columns: $1;">\n$2\n<\/div>\n/g;
	s/{{דוכיווני\|($template)\|($template)\|($template)}}\n*/<div style="width: 100%; overflow: hidden; display: table;"><div style="direction: rtl; text-align: right; display: table-cell; *float: right; *width: 49%; padding-left: 5px;">$1<\/div><div style="direction: ltr; text-align: left; display: table-cell; *float: left; *width: 49%; padding-right: 5px;">$2<\/div><\/div>\n<div style="direction: ltr; text-align: center;">$3<\/div>\n/g;
	s/{{דוכיווני\|($template)\|($template)}}\n*/<div style="width: 100%; overflow: hidden; display: table;"><div style="direction: rtl; text-align: right; display: table-cell; *float: right; *width: 49%; padding-left: 5px;">$1<\/div><div style="direction: ltr; text-align: left; display: table-cell; *float: left; *width: 49%; padding-right: 5px;">$2<\/div><\/div>\n/g;
	s/{{מוקטן\|($template)}}/<span style="font-size: 90%;">$1<\/span>/g;
	s/ *{{ש}} */<br>/g;
	
	s/<ויקי.*?>(.*?)\n?<\/ויקי>\n?//s;
	# $_ .= "\n$1\n" while (s/<ויקי.*?>(.*?)\n?<\/ויקי>\n?//s);
	
	return $_;
}

# Allow usage as a module and as a executable script
__PACKAGE__->main() unless (caller);

###################################################################################################

sub print_header {
	return <<EOT;
<!DOCTYPE html>
<html lang="he" dir="rtl">
<head>
  <meta http-equiv="Content-Type" content="text/html; charset=utf8">
  <title>$title</title>
  <link rel="stylesheet" type="text/css" href="src/law.css">
</head>

<body>
<div class="openlaw-indicator"><span style="position: relative; top: -15px; background: white; padding: 5px;"><a href="http://he.wikisource.org/wiki/ספר_החוקים_הפתוח" title="חלק מפרויקט ספר החוקים הפתוח"><img alt="חלק מפרויקט ספר החוקים הפתוח" src="src/openlaw-logo.png" height="30" width="65"></a></span></div>

<div class="law">
EOT
}

sub print_footer {
	return <<EOT;
</div>
<div class="graytext" style="border-top: 2px solid #ddd; border-bottom: 2px solid #ddd; margin: 13px 40px 0 40px; font-size: 90%;" align="center"><img alt="ויקיטקסט" src="src/wikisource-logo.png" title="ויקיטקסט" height="17" width="16"> &nbsp; <b><u>אזהרה</u>:</b> המידע נועד להעשרה בלבד ואין לראות בו ייעוץ משפטי.&nbsp; במידת הצורך, היוועצו בעורך-דין.</div>
</body>
</html>
EOT
}

sub parse_title {
	my ($str, %attr) = parse_attr(shift);
	$str =~ s/\s*<תיקון>.*?<\/תיקון>\s*//gs;
	$title = $str;
	$str = "<div class=\"law-title\">$str</div>\n";
	$str .= "<div><div>\n";
	return $str;
}

sub printBox {
	my ($txt, %attr) = parse_attr(shift);
	my $tip = $attr{'טקסט'} // '';
	my $url = $attr{'קישור'} // '';
	# print STDERR "printBox got |$str|$tip|$url|\n";
	$txt = escape_template($txt);
	if ($tip) {
		$tip =~ s|&|&amp;|g;
		$tip =~ s|"|&quot;|g;
		$tip = " title=\"$tip\"";
	}
	if ($url) {
		return "<span class=\"law-external\"$tip><a href=\"$url\">$txt</a></span>";
	} elsif ($tip) {
		return "<span$tip>$txt</span>";
	} else {
		return $txt;
	}
}

sub parse_bib {
	# print STDERR "parse_bib got |$_[0]|\n";
	my ($_, %attr) = parse_attr(shift);
	# print STDERR "parse_bib got |$_| with \n\t\t" . dump_hash(%attr) . "\n";
	s/(<תיבה.*?>.*?<\/תיבה>)/&printBox($1)/ge;
	s/\.\n+/\.\n\n/g;
	s/\n*$//s;
	my $str = <<EOT;
</div></div>
<hr class="law-separator">
<div><div class="law-note">
$_
<div class="law-cleaner"></div>
<hr class="law-separator">
EOT
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


sub parse_signatures {
	my ($_, %attr) = parse_attr(shift);
	($_, my %tags) = parse_tag_list($_, 'פרסום');
	my $pubdate = $tags{'פרסום'};
	my $str = "</div></div>\n";
	$str .= "<span class=\"law-cleaner\"></span>\n";
	$str .= "<hr class=\"law-separator\">\n";
	$str .= "<div style=\"text-align: left; margin-left:75px; margin-bottom: 5px; font-size: smaller;\">$pubdate</div>\n" if ($pubdate);
	$str .= "<div><div class=\"law-signatures\" id=\"חתימות\">\n";
	$str .= "  <ul>\n";
	foreach my $line (split(/\n/, $_)) {
		last unless ($line =~ /^ *\*/);
		$line =~ s/^ *\* *(.*?) *$/$1/;
		$line =~ s/ *\| */<br>/g;
		$line =~ s/^(.*?)(?=\<br\>|$)/<b>$1<\/b>/;
		$str .= "    <li>$line</li>\n";
	}
	$str .= "  </ul>\n";
	$str .= "<div class=\"law-cleaner\"></div>\n";
	$str .= "</div></div>\n";
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
	
	my %table = ( '1' => 'law-part', '2' => 'law-section', '3' => 'law-subsection', '4' => 'law-subsubsection' );
	my $type = $table{$level} // 'law-section';
	
	$str = "</div></div>\n";
	$str .= "<div class=\"law-cleaner\"></div>\n";
	if ($fix || $other) {
		$str .= "<div class=\"law-sec-desc\">" ;
		$str .= "<span class=\"graytext\"><b>$other</b></span>" if ($other);
		$str .= " " if ($fix && $other);
		$str .= "<span class=\"law-note\">[$fix]</span>" if ($fix);
		$str .= "</div>";
	}
	if ($ankor) {
		$str .= "<div class=\"$type\" id=\"$ankor\">";
		$text =~ /^([^:\-]*?)( *[:\-].*|)$/;
		$str .= "<span class=\"selflink\"><a href=\"#$ankor\">$1</a></span>$2";
		$str .= "</div>\n";
	} else {
		$str .= "<div class=\"$type\">$text</div>\n";
	}
	$str .= "<div><div>\n";
	
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
	$desc = $tags{'תיאור'} // '';
	$fix = $tags{'תיקון'};
	$other = $tags{'אחר'};
	$text = trim($str);
	$ankor = "סעיף $number" if (!$ankor && $number);
	$ankor =~ s/\.$//;
	
	$str = "</div></div>\n";
	$str .= "<div class=\"law-cleaner\"></div>\n";
	$str .= "<div class=\"law-main\">\n";
	if ($number) {
		$str .= "  <div class=\"law-number";
		if (length($number)>3) { $str .= " text-condensed-" . max(length($number)-3,3); }
		$str .= "\"";
		if ($ankor) {
			$str .= " id=\"$ankor\"><span class=\"selflink\"><a href=\"#$ankor\">$number</a></span></div>\n"
		} else {
			$str .= ">$number</div>\n";
		}
	}
	if ($desc || $other || $fix) {
		$str .= "  <div class=\"law-desc\">$desc ";
		$str .= "<span class=\"graytext\">$other</span> " if ($other);
		$str .= "<span class=\"law-note\">[תיקון: $fix]</span> " if ($fix);
		$str =~ s/ $//;
		$str .= "</div>\n";
	}
	$str .= "  <div class=\"law-content\">\n";
	
	if ($text) {
		# Warning: missing keyword
		$str .= "<ת>$text</ת>\n";
	}
	return $str;
}

sub parse_line {
	my ($text, %attr) = parse_attr(shift);
	my $type = $attr{tag};
	my $num = $attr{'מספר'};
	$num //= $1 if ($text =~ s/<מספר>(.*?)<\/מספר>//);
	$num = "($num)" if ($num && $num !~ /[."]/);
	$type = length($type);
	
	my $str = "</div>\n";
	$str .= "  " x $type;
	$str .= "<div class=\"law-number$type\">$num</div> " if ($num);
	$str .= "<div class=\"law-content$type\">";
	$str .= "$text\n" if ($text);
	return $str;
}

sub parse_link {
	my ($text, %attr) = parse_attr(shift);
	my $type = $attr{'סוג'} // 1;
	my $href = $attr{'עוגן'} // '';
	$href = escape_quote($href);
	$text ||= unescape_text($href);
	$type = 0 unless ($href);
	$type = 3 if ($href =~ /^https?:\\\\/);
	my $str;
	given ($type) {
		when (0) { $str = $text; }
		when (1) { $str = "<span class=\"law-local\" title=\"$href\"><a href=\"#$href\">$text</a></span>"; }
		when (2) {
			my $href2 = $href;
			$href2 =~ s/^([^#]+)/$1.html/;
			$str = "<span class=\"law-external\" title=\"$href\"><a href=\"$href2\">$text</a></span>";
		}
		when (3) { $str = "<span class=\"law-external\" title=\"$href\"><a href=\"$href\">$text</a></span>"; }
	}
	return $str;
}

sub parse_definition {
	my $text = trim(shift);
	my $str = "<div class=\"law-indent\">$text</div>";
	return $str;
}

sub parse_note {
	my $text = trim(shift);
	my $str = "<span class=\"law-note\">$text</span>";
	return $str;
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
		if ($id) {
			$_ = "$id=$_";
		} else {
			s/({{==}}|=)(?!"[^"]+")/{{==}}/g;
		}
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

sub escape_quote {
	my $_ = unquote(shift);
	s/&/&amp;/g;
	s/"/&quot;/g;
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
	$str =~ s/ *<\/$tag>\n*//;
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
