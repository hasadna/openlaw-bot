#!/usr/bin/perl

use warnings;
no if ($]>=5.018), warnings => 'experimental';
use strict;
no strict 'refs';
use utf8;
use English;
use Encode;
use Getopt::Long;
use IPC::Run 'run';

binmode STDIN, "utf8";
binmode STDOUT, "utf8";
binmode STDERR, "utf8";

my $raw = 1;
my $brackets = 1;
my $debug = 0;
my $verbose = 0;

my ($t1, $t2);

GetOptions(
	"raw" => \$raw,
	"brackets" => sub { $brackets = 0; },
	"debug" => \$debug,
) or die("Error in command line arguments\n");

local $/;
$_ = <>;
$_ = cleanup($_);

$verbose ||= $debug;
print STDERR "Input size is " . length($_) . "\n" if $verbose;
$debug &&= (length($_)<2000);

my $fix_sig = 'תי?קו(?:ן|ים)';
my $num_sig = '\d+(?:[^ ,.:;"\n\[\]()]+|(?:\.\d+)+|\([^ ,.:;"\n\[\]()]+\))*+';
my $chp_sig = '\d+(?:[^ ,.:;"\n\[\]()]{0,5}?\d*\.|(?:\.\d+)+)';
my $ext_sig = 'ה?(?:(ראשו[נן]ה?|שניי?ה?|שלישית?|רביעית?|חמישית?|שי?שית?|שביעית?|שמינית?|תשיעית?|עשירית?|[א-יכל][\' ]|[טיכל]"[א-ט]|\d+[א-ת])(\d*))';
my $law_sig = 'ו?ש?[בהלמ]?(?:חוק|פקוד[הת]|תקנות|צו)\b';


print "################\n$_\n################\n" if ($debug);

# Section elements
s/^("?חלק ($num_sig|$ext_sig) *([:,-].*|))$/\n= $1 =\n/gm;
s/^("?(פרק|תוספת) ($num_sig|$ext_sig) *([:,-].*|))$/\n== $1 ==\n/gm;
s/^("?סימן ($num_sig|$ext_sig) *([:,-].*|))$/\n=== $1 ===\n/gm;
s/\n+(?=\=)/\n\n/g;

print "##AA############\n$_\n##AA############\n" if ($debug);

# Join seperated lines
s/^([\d=\@:\-].*)$/$1 /gm; # Disallow concatination on certain prefixes
s/([א-ת\,A-Za-z])\n([א-תA-Za-z])/$1 $2/gm;
s/ +$//gm;

s/\n([\(\[]מס' \d)/ $1/gm;
s/([\(\[](תיקון|תיקונים):?) *\n/$1 /gm;
s/\n(?=[\[\(](תיקון|תיקונים):?\b)/ /gm;

print "##BB############\n$_\n##BB############\n" if ($debug);

s/^($chp_sig) */$1 /gm;

# Check if chapter number is misplaced
$t1 = () = (/^.*[.;:\-] *\n{1,2}\d+\S{0,3}?\./gm);
$t2 = () = (/^.*[^.;:\-] *\n{1,2}\d+\S{0,3}?\./gm);
print STDERR "Got $t1 vs $t2.\n" if $verbose;
if ($t1<$t2 || /^[^.]+ (\((תיקון|תיקונים).*\)|\[(תיקון|תיקונים).*\])\n{1,2}\d+\./m || $debug) {
	s/^([^=.\n_]+)\n{1,2}($chp_sig) +/@ $2 $1\n/gm;
}

# print $_; exit;

# $t1 = () = (/^\d[^\.\n ]*\. .*?[:;.]\n.*?[^.;:\-\n]\n/gm);
# $t2 = () = (/^\d[^\.\n ]*\. .*?[^:;.\n]\n/gm);
# print STDERR "Got $t1 vs $t2.\n" if $verbose;
# 
# if ($t1>$t2) {
# 	s/^(\d[^\.\n ]*\.) (.*)\n/$2\n$1 /gm;
# }

# Should swap chapter title and numeral?
s/^("?\(\S{1,4}?\))\n("?\(\S{1,4}?\))/$1 $2/gm;
# s/^(.+)\n((\d\S*?\. *)?"?\(\S{1,4}?\)) *\n(?!\()/$2 $1\n/gm;
s/^(.+)\n{1,2}((\d\S*?\. *)?"?\(\S{1,4}?\)) *\n/$2 $1\n/gm;
s/^(.+[^".;:\n])\n("?\d\S*?\.)\n/$2 $1\n/gm;

if ($raw) {
	s/^(.+)\n(\d+|\*)\n/$2 $1\n/gm;
	# s/^(\d+[,;.]?)\n($law_sig.*)/$2 $1/gm;
	s/^(\d+[,;.]?.*?)\n(.*?\d{4}( \[.*?\])?)$/$2 $1/gm;
}

print "##CC############\n$_\n##CC############\n" if ($debug);

# s/^(?:\n?@ *|)(\d\S*?\.)(?| (.*)|())$/"@ $1 " . fix_description($2)/gme;
# s/^(?:\n?@ *|)($chp_sig)( +(.*)|())$/@ $1 $2/gm;
s/^(?:\n?@ *|)($chp_sig) (.+)$/@ $1 $2/gm;
s/^([^.;:=\n_|]+?) *\n(@ $chp_sig)[ \n]+/\n$2 $1\n/gm;
s/^("?\([^)]{1,4}\))/: $1/gm;
s/^(@.*?)\n(?=[^:=@])/$1\n: /gm;
s/\n++(?=@)/\n\n/gs;
s/^@ ($chp_sig) (.*)$/"@ $1 " . fix_description($2)/gme;

print "##DD############\n$_\n##DD############\n" if ($debug);

if ($raw) {
	while (s/^([א-ת].{5,20}?[^"=.;\n)_ ]) *\n\n(@ \d.*?\.) /\n\n$2 $1 /gm) {}
}

$t1 = () = (/^.*[.;:\-] *\n[^\(:\n].*\n: \([א-ת]\) \(\d\)/gm);
$t2 = () = (/^.*[^.;:\-] *\n[^\(:\n].*\n: \([א-ת]\) \(\d\)/gm);
print STDERR "Got $t1 vs $t2.\n" if $verbose;
if ($t1>$t2) {
	s/^([^\(:\n].*)\n(: \([א-ת]\S{0,2}?\)) (\(\d\S{0,2}?\))/$2 $1\n: $3/gm;
	# s/([^\d=\@:\-\n].*?[א-ת\-\,])\n([א-ת])/$1 $2/gm;
	s/^([\d=\@:\-].*)$/$1 /gm;
	s/([א-ת\,A-Za-z])\n([א-תA-Za-z])/$1 $2/gm;
	s/ +$//gm;
	
	# s/([א-ת\-\,])\n([א-ת])/$1 $2/gm;
	s/^([א-ת].*?[^.;:\-\n])\n(:( \(\S{1,3}?\))+)\n?/$2 $1\n/gm;
	# s/^([^\(:].*)\n(: \(.{1,3}?\)) (\(.{1,3}?\))/$2 $1\n: $3/gm;
}


print "##EE############\n$_\n##EE############\n" if ($debug);

# print $_; exit;

s/ \((נמחקה?|בו?טלה?|פקעה?)(?|\)([.;])|([.;])\))\n/ ((($1)$2))\n/gm;
# s/^(:+) *(\([^)\n]*\)[.;])$/$1 (($2))/gm;
# s/^(:+ \(\S+?\)) (\([^)\n]+\)[.;])$/$1 (($2))/gm;
s/ {2,}/ /g;


if ($brackets) {
	s/(?<!\[)(ו?ש?[בהלמ]?(סעיף|סעיפים|תקנה|תקנות|פרט|פרטים) $num_sig)(?!\])/[[$1]]/g;
	pos = 0;
	my $repeat = 0;
	while ($repeat || m/\[\[(.*?)\]\]/gc) {
		$repeat = 0;
		next if /\G[,; ]*\[\[/;
		my $pos = $+[1];
		pos = $pos;
		# m/(.{0,20})\G(.{0,20})/; print STDERR "POS is $pos\t ... $1<-|->$2 ...\n";
		
		0 	|| s/\G\]\], ($num_sig)/]], [[$1]]/
			|| s/\G\]\](,?(( ו-| או | עד |)\([א-ת\d]+\))+)/$1]]/
			|| s/\G\]\]( עד $num_sig| (?:ו-|או) \(\d\S*?\))/$1]]/
			|| s/\G\]\] ((?:ו-|או )$num_sig)(?!\])/]] [[$1]]/
			|| next;
		
		pos = $pos;
		# m/(.{0,20})\G(.{0,20})/; print STDERR "\t\t ... $1<-|->$2 ...\n";
		
		$repeat = 1;
		m/(.*?)\]\]/gc;
	}
	
	s/(?<!\[)(ו?ש?[בהלמ]?(פרק|פרקים|סימן|סימנים|תוספת) ה?(ז[הו]|$num_sig|$ext_sig)[^ ,.:;\n\[\]]{0,8}+)(?![\]:])/[[$1]]/g;
	s/(?<!\[)(ו?ש?[בהלמ]?אות[והם] (סעיף(?! קטן)|סעיפים(?! קטנים)|פרק|פרקים|סימן|סימנים|תוספת))(?![\]:])/[[$1]]/g;
	s/(?<!\[)(ו?ש?[בהלמ]?(סעיף|פרק|פרקים|סימן|סימנים|תוספת) האמור[א-ת]*)(?![\]:])/[[$1]]/g;
	# s/(?<!\[)(ו?ש?[בהלמ]?(תוספת))\b(?!\])/[[$1]]/g;
	s/(?<!\[)($law_sig [^;.\n]{1,100}?(, |-)\d{4})(?!\])/[[$1]]/g;
	s/\]\]( \[(נוסח חדש|נוסח משולב)\])/$1]]/g;
	s/\]\] \[\[(?=$law_sig)/ /g;
	s/\[\[($law_sig [^\[\]].*?) ($law_sig[^\[\]].*)\]\]/$1 [[$2]]/g;
	
	s/\[\[([^\[\]]*+)\[\[(.*?)\]\](.*?)\]\]/[[$1$2$3]]/g;
	s/^(=.*)$/remove_brakets($1)/gme;
}

if (/^\[*(חוק|פקודת|תקנות)\b/s) {
	s/^(?:\<שם\>|) *(.*)\n/"<שם> ". remove_brakets($1) . "\n"/se;
	s/^(.*?\n)/$1\n<מקור> ...\n/s if (!/<מקור>/);
}

s/\n*(.*?)\n*$/$1\n/s;
s/\n{3,}/\n\n/g;
s/ +$//mg;

print STDERR "Output size is " . length($_) . "\n" if $verbose;

print $_;

exit;
1;


sub fix_description {
	my $_ = shift;
	
	s/(?|(\[(תי?קון|תיקונים)\b([^\[\]]+|\[.*?\])+\])|(\((תי?קון|תיקונים)\b([^\(\)]+|\(.*?\))+\))|(\[(תי?קון|תיקונים)\b.*)$)/(FIXSTR)/;
#	s/(\[(?:תי?קון|תיקונים)\b:? *(?:[^\[\]]+|\[.*?\])+\])/(FIXSTR)/ ||
#		s/(\((?:תי?קון|תיקונים)\b:? *(?:[^\(\)]+|\(.*?\))+\))/(FIXSTR)/ ||
#		s/([\[\(](?:תי?קון|תיקונים)\b.*)$/(FIXSTR)/;
	my $fix = $1 // '';
	
	$fix =~ s/^[\(\[](?:תי?קון|תיקונים)\b:? *(.*?)[\)\]]$/$1/;
	$fix =~ s/ה(תש.?".?)/$1/g;
	$fix =~ s/(תש.?".) \(מס' (\d.*?)\)/$1-$2/g;
	while ($fix =~ s/(תש.?".)-(\d[^\,]*|),\s*\(מס' (\d.*?)\)/$1-$2, $1-$3/g) {};
	s/\(FIXSTR\)/(תיקון: $fix)/;
	s/^ *(.*?) *$/$1/;
	return $_;
}

sub remove_brakets {
	my $_ = shift;
	s/\[\[//;
	s/\]\]//;
	return $_;
}


sub cleanup {
	my $pwd = $0; $pwd =~ s/[^\/]*$//;
	my @cmd = ("$pwd/clear.pl");
	my $in = shift;
	my $out;
	run \@cmd, \$in, \$out, *STDERR;
	return decode_utf8($out);
}
