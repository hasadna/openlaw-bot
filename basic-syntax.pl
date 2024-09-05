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
use constant { true => 1, false => 0 };

binmode STDIN, "utf8";
binmode STDOUT, "utf8";
binmode STDERR, "utf8";

my $raw = true;
my $brackets = true;
my $debug = false;
my $verbose = false;
my $clean = undef;

my ($t1, $t2);

GetOptions(
	"raw" => \$raw,
	"clean" => \$clean,
	"brackets" => sub { $brackets = true; },
	"debug" => \$debug,
	"skip" => sub { $clean = false; }
) or die("Error in command line arguments\n");

local $/;
$_ = decode_utf8(<>);
$clean = (/[\x{200E}\x{200F}\x{202A}-\x{202E}\x{2066}-\x{2069}]/) unless (defined $clean);
$_ = cleanup($_) if ($clean);

$verbose ||= $debug;
print STDERR "Input size is " . length($_) . "\n" if $verbose;
$debug &&= (length($_)<2000);

our $pre_sig = 'ו?כ?ש?מ?[בהל]?';
our $fix_sig = 'תי?קו(?:ן|ים)';
our $num_sig = '\d+(?:[^ ,.:;"\n\[\]()]+|(?:\.\d+)+|\([^ ,.:;"\n\[\]()]+\))*+';
our $num2_sig = '\d+(?:[^ ,.:;"\n\[\]()]+|\([^ ,.:;"\n\[\]()]+\))*+(?!\.\d)';
our $sub_sig = '\(\d[^ ,.:;"\n\[\]()]*\)(?:\([^ ,.:;"\n\[\]()]+\))*+';
# our $chp_sig = '\d+(?:[^ ,.:;"\n\[\]()]{0,5}?\d*\.|(?:\.\d+)+)';
our $chp_sig = '\d+[^ ,.:;"\n\[\]()]{0,5}?\d*\.(?!\d)';
our $ext_sig = 'ה?(?:(ראשו[נן]ה?|שניי?ה?|שלישית?|רביעית?|חמישית?|שי?שית?|שביעית?|שמינית?|תשיעית?|עשירית?|אח[דת][ \-]עשרה?|ש[נת]יי?ם[ \-]עשרה?|שלושה?[ \-]עשרה?|ארבע[ \-]עשרה?|חמי?שה?[ \-]עשרה?|שי?שה?[ \-]עשרה?|שבעה?[ \-]עשרה?|[שמונה[ \-]עשרה?|תשעה?[ \-]עשרה?|עשרים|[א-יכל][\' ]|[טיכל]"[א-ט]|\d+[א-ת])(\d*))';
our $law_sig = 'ו?ש?[בהלמ]?(?:חוק|פקוד[הת]|תקנות|צו)\b';


# Check if we got all parentheses wrong
$t1 = () = (/[^()\n]*\n?\)\n?[^()\n]+\n?\(/gm);
$t2 = () = (/[^()\n]\n?\(\n?[^()\n]+\n?\)/gm);
# print STDERR "got $t1 and $t2.\n";
if ($t1 > $t2) {
	tr/([{<>}])/)]}><{[(/;
}

s/(\((?:תיקון|תיקונים):?[^\(\)\n]+\n[^\(\)]+\))/ $1 =~ tr|\n| |r /ge;
s/(\[(?:תיקון|תיקונים):?[^\[\]\n]+\n[^\[\]]+\])/ $1 =~ tr|\n| |r /ge;

s/\n([\(\[]מס' \d)/ $1/gm;
s/([\(\[](תיקון|תיקונים):?) *\n/$1 /gm;
s/\n(?=[\[\(](תיקון|תיקונים):?\b)/ /gm;

s/ *\(תיקון:? מס' \d+\) (תש.?".)-\d\d\d\d/\n(תיקון: $1)/g;
while (s/(\(תיקון: [^()\n]+)\)[\n ]\(תיקון: ([^()\n]+\))/$1, $2/g) {};

print "##AA############\n$_\n##AA############\n" if ($debug);

s/\n([^\n]+)\n(\d+\S{0,3}\. \([^\n\)]+\)) *\n/\n$2 $1\n/g;

# Join seperated lines
s/<!--.*--> */␀/g;

s/\n-\n/ - /g;
# s/^((?:[\d=\@:\-]פרק|סימן|חלק).*)$/␊$1␊/gm; # Disallow concatination on certain prefixes
# s/^([^:]+[:].*)$/␊$1␊/gm;
# s/([א-ת\,A-Za-z])\n([א-תA-Za-z])/$1 $2/gm;
s/("[א-ת]-)\n(\d{4})/$1$2/gm;

# s/^([א-ת ]+) (\d[\dא-ת]*\.)(\n| )/$2 $1/g;
# s/(\n\d[\dא-ת]*) (.*)\n([^\.]+)\n(\d*\.) /$1$4 $2 $3\n: /g;
# s/(\n\d[\dא-ת]*) (.*)\n(\d*\.) /$1$3 $2\n: /g;
s/^: *$//gm;

print "##BB############\n$_\n##BB############\n" if ($debug);

s/^($chp_sig) */$1 /gm;

# Check if chapter number is misplaced
$t1 = () = (/^.*[.;:\-] *\n{1,2}$chp_sig *$/gm);
$t1 += () = (/^$chp_sig [א-ת]/gm);
$t2 = () = (/^.*[^.;:\-] *\n{1,2}$chp_sig *$/gm);
print STDERR "Got $t1 vs $t2.\n" if $verbose;
# if ($t1<$t2 || /^[^.]+ (\((תיקון|תיקונים).*\)|\[(תיקון|תיקונים).*\])\n{1,2}\d+\./m || $debug) {
if ($t1<$t2) {
	s/^([א-ת0-9",() ]+)\n{1,2}($chp_sig)[ \n]+/@ $2 $1\n/gm;
}

# $t1 = () = (/^\d[^\.\n ]*\. .*?[:;.]\n.*?[^.;:\-\n]\n/gm);
# $t2 = () = (/^\d[^\.\n ]*\. .*?[^:;.\n]\n/gm);
# print STDERR "Got $t1 vs $t2.\n" if $verbose;
# 
# if ($t1>$t2) {
# 	s/^(\d[^\.\n ]*\.) (.*)\n/$2\n$1 /gm;
# }

s/^\.([0-9]+)/$1./g;
# Should swap chapter title and numeral?
s/^("?\(\S{1,4}?\))\n("?\(\S{1,4}?\))/$1 $2/gm;
# s/^(.+)\n((\d\S*?\. *)?"?\(\S{1,4}?\)) *\n(?!\()/$2 $1\n/gm;
# s/^(.+)\n{1,2}((\d\S*?\. *)?"?\(\S{1,4}?\)) *\n/$2 $1\n/gm;
s/^(.+[^".;:\n])\n("?\d\S*?\.)\n/$2 $1\n/gm;

if ($raw) {
	# s/^(.+)\n(\d+|\*)\n/$2 $1\n/gm;
	# s/^(\d+[,;.]?)\n($law_sig.*)/$2 $1/gm;
	# s/^(\d+[,;.]?.*?)\n(.*?\d{4}( \[.*?\])?)$/$2 $1/gm;
}

print "##CC############\n$_\n##CC############\n" if ($debug);

# Section elements
s/^("?חלק ($num_sig|$ext_sig) *([:,-].*|))$/\n= $1 =\n/gm;
s/^("?(פרק|תוספת) ($num2_sig|$ext_sig) *([:,-].*|))$/\n== $1 ==\n/gm;
s/^("?סימן ($num_sig|$ext_sig) *([:,-].*|))$/\n=== $1 ===\n/gm;
s/\n+(?=\=)/\n\n/g;
s/\n *(\((?:תיקון|תיקונים):? .*?\)) *(\n+=+ .*) (=+)\n/$2 $1 $3\n/g;
s/ *(=+)\n+ *(\((תיקון|תיקונים):? .*?\)) *\n/ $2 $1\n/g;

# Article elements
# s/^(?:\n?@ *|)(\d\S*?\.)(?| (.*)|())$/"@ $1 " . fix_description($2)/gme;
# s/^(?:\n?@ *|)($chp_sig)( +(.*)|())$/@ $1 $2/gm;
s/^(?:\n?@ *|)($chp_sig) (.+)$/@ $1 $2/gm;
s/^($chp_sig) *$/@ $1/gm;

s/^([^.;:=\n_|]+?) *\n(@ $chp_sig)[ \n]+/\n$2 $1\n/gm;
s/^␊?("?\([^ )]{1,4}\))/: $1/gm;
s/^(@.*?)\n(?=[^:=@])/$1\n: /gm;
s/\n++(?=@)/\n\n/gs;
s/^@ ($chp_sig) (.*)$/"@ $1 " . fix_description($2)/gme;
s/^(=+ .* =+)$/fix_description($1)/gme;

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
	# s/^([א-ת].*?[^.;:\-\n])\n(:( \(\S{1,3}?\))+)\n?/$2 $1\n/gm;
	# s/^([^\(:].*)\n(: \(.{1,3}?\)) (\(.{1,3}?\))/$2 $1\n: $3/gm;
}

s/^(:(?: ?\([^ )]+\))+)\n([א-ת"])/$1 $2/gm;
s/([א-ת\,A-Za-z])\n([א-תA-Za-z])/$1 $2/gm;

# We use FF (\f) to mark EOP
s/((ץבוק|((ת?ו)?נ)?קתה) ?)+'?[א-ת]?\n?(,\d{4,}|\d{4,},) ((ץבוק|((ת?ו)?נ)?קתה) ?)+/\f\n\n/gs;
s/((רפס|((ם?י)?ק)?וחה) ?)+'?[א-ת]?\n?(,\d{4,}|\d{4,},) ((רפס|רפס|((ם?י)?ק)?וחה) ?)+/\f\n\n/gs;
s/(קובץ התקנות|ילקוט הפרסומים|ספר החוקים) \d+, [א-ת'"]+ ב[א-ת ']+ התש[א-ת]?"[א-ת], \d+\.\d+\.20\d\d/\f\n\n/g;
s/Ministry of Justice [^\n:]DoCenter Id: ?\d{3}-\d{2}-\d{4}-\d{6}, received on/\n\n/g;
s/([0-9]+\/[0-9]+\/[0-9]+\n[0-9][0-9]:[0-9][0-9]\n)?\f//gs;

print "##EE############\n$_\n##EE############\n" if ($debug);

tr/␀␊//d;

s/ \((נמחקה?|בו?טלה?|פקעה?)(?|\)([.;])|([.;])\))\n/ ((($1)$2))\n/gm;
# s/^(:+) *(\([^)\n]*\)[.;])$/$1 (($2))/gm;
# s/^(:+ \(\S+?\)) (\([^)\n]+\)[.;])$/$1 (($2))/gm;
s/ {2,}/ /g;

s/ (ה?תש[א-ת]?"[א-ת])(?: - |- | -)([0-9]{4})/ $1-$2/g;

if ($brackets) {
	s/(?<!\[)($pre_sig(סעיף|סעיפים|תקנה|תקנות|פרט|פרטים|אמו?ת[- ]מידה)[\s\n]$num_sig)(?!\])/[[$1]]/g;
	pos = 0;
	my $repeat = 0;
	while ($repeat || m/\[\[(.*?)\]\]/gsc) {
		$repeat = 0;
		next if /\G[,; ]*\[\[/;
		my $pos = $+[1];
		pos = $pos;
		
		0	|| s/\G\]\],[\s\n]($num_sig)/]], [[$1]]/
			|| s/\G\]\],[\s\n]($sub_sig)/, $1]]/
			|| s/\G\]\](,?[\s\n]*((ו-|או[\s\n]|עד[\s\n]|)\([א-ת\d]+\))+)/$1]]/
			|| s/\G\]\]([\s\n]עד[\s\n]$num_sig|[\s\n](?:ו-|או[\s\n]|עד[\s\n])\(\d\S*?\))/$1]]/
			|| s/\G\]\][\s\n]((?:ו-|או[\s\n]|עד[\s\n])$num_sig)(?!\])/]] [[$1]]/
			|| next;
		
		pos = $pos;
		# m/(.{0,20})\G(.{0,20})/; print STDERR "\t\t ... $1<-|->$2 ...\n" if ($debug);
		
		$repeat = 1;
		m/(.*?)\]\]/gc;
	}
	
	# s/(פסק([הא]|אות) ((ו-)?\(..?\),?)+) \[\[/[[$1/g;
	s/($pre_sig(?:הגדר[הת]|מונח) "[^"\]]+" )(\[\[(?:[^|\]]*\|)?)/$2$1/g;
	s/($pre_sig(?:הגדרו?ת) "[^"\]]+" (?:ו[-־]?|או )"[^"\]]+")(\[\[(?:[^|\]]*\|)?)/$2$1/g;
	# s/($pre_sig(?:פסקה|פסקאות) (?:\(.\))+ (?:(?:ו[־-]|או |עד )(?:\(.\))+ )*(?:של )?)(\[\[(?:[^|\]]*\|)?)/$2$1/g;
	s/($pre_sig(?:פסק(?:ה|אות)|סעי(?:ף|פים|פי))(?: (?:קטן|קטנים|משנה))? (?:\([0-9א-ת]{1,3}\))+ (?:(?:ו[־-]|או |עד )(?:\([0-9א-ת]{1,3}\))+ )*(?:של )?)(\[\[(?:[^|\]]*\|)?)/$2$1/g;
	s/\]\] ($pre_sig(?:לעיל|סיפ[אה]|ריש[אה]))/ $1]]/g;
	
	s/(?<!\[)($pre_sig(פרק|פרקים|סימן|סימנים|תוספת) ה?(ז[הו]|$num2_sig|$ext_sig)[^ ",.:;\n\[\]]{0,8}+)(?![\]:])/[[$1]]/g;
	s/(?<!\[)($pre_sig(אות[והם]) (סעיף(?! קטן)|סעיפים(?! קטנים)|תקנה|פרק|פרקים|סימן|סימנים|תוספת))(?![\]:])/[[$1]]/g;
	s/(?<!\[)($pre_sig(סעיף|תקנה|פרק|פרקים|סימן|סימנים|תוספת) ה(אמור|קוד)[א-ת]*)(?![\]:])/[[$1]]/g;
	# s/(?<!\[)(ו?ש?[בהלמ]?(תוספת))\b(?!\])/[[$1]]/g;
	s/(?<!\[)($law_sig [^;.\n]{1,100}?(, |-)\d{4})(?!\])/[[$1]]/g;
	s/\]\]( \[(נוסח\sחדש|נוסח\sמשולב)\])/$1]]/g;
	s/\[\[($law_sig [^\[\]].*?) ($law_sig[^\[\]].*)\]\]/$1 [[$2]]/g;
	s/\]\] \[\[(?=$law_sig)/ /g;
	
	s/\[\[([^\[\]]*+)\[\[(.*?)\]\](.*?)\]\]/[[$1$2$3]]/g;
	s/(\[\[[^\[\]\n]*+)\n([^\[\]\n]*+\]\])/$1 $2/g;
	s/^(=.*)$/remove_brakets($1)/gme;
}

s/(ק"ת|ס"ח|י"פ|ק"ת -? ?שיעורי מק"ח) (?:מס' |)([0-9]+), ה?(תש.?".)(?: \([0-9.]+\)|), עמ' ([0-9]+)( \[.*\]| \(.*\)|)[;.]/$1 (($3, $4||$2)); $5/g;
s/(ק"ת|ס"ח|י"פ|ק"ת -? ?שיעורי מק"ח) ה?(תש.?".) (?:מס' |)([0-9]+) (מיום [0-9.]+),? עמ' ([0-9]+) */$1 (($2, $5||$3)); /g;

if (/^\[*(חוק|פקודת|תקנות|צו|כללי)\b/s) {
	s/^(.*)\n(.*\d{4})( *\*+| \d|)\n/$1 $2$3\n/s;
	s/^(?:\<שם\>|) *(.*)\n/"<שם> ". remove_brakets($1) . "\n"/se;
	s/^(.*?\n)\n*/$1\n<מקור> ...\n\n/s if (!/<מקור>/);
}


s/\n*(.*?)\n*$/$1\n/s;
s/\n{3,}/\n\n/g;
s/ +$//mg;

print STDERR "Output size is " . length($_) . "\n" if $verbose;

print $_;

exit;
1;


sub fix_description {
	local $_ = shift;
	return $_ if /\d{4}$/;
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
	local $_ = shift;
	s/\[\[//;
	s/\]\]//;
	return $_;
}


sub cleanup {
	my $pwd = $0; $pwd =~ s/[^\/]*$//;
	my @cmd = ("$pwd/clean.pl");
	my $in = shift;
	my $out;
	run \@cmd, \$in, \$out, *STDERR;
	return decode_utf8($out);
}
