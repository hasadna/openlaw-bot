#!/usr/bin/perl -w

use strict;
no strict 'refs';
no if ($]>=5.018), warnings => 'experimental';
use English;
use Encode;
use utf8;
use POSIX 'strftime';
use Data::Dumper;
use MediaWiki::Bot;
use Getopt::Long;

use SyntaxLaw();
use SyntaxWiki();

binmode STDOUT, ":utf8";
binmode STDERR, ":utf8";

my @pages = ();
my ($verbose, $dryrun, $force, $print, $onlycheck, $interactive, $recent, $select, $start);
my $botpage;
my $locforce = 0;
my $outfile;

my %processed;
my %new_pages;
my %updated_pages;
my ($page, $id, $text);
my $bot_page = "משתמש:OpenLawBot/הוספה";

GetOptions(
	"force" => \$force, 
	"check" => \$onlycheck,
	"dryrun" => \$dryrun,
	"verbose" => \$verbose,
#	"OUTPUT=s" => sub { $print = 1; open(STDOUT, ">_[1]"); },
	"output" => \$print,
	"recent" => \$recent,
	"select=s" => \$select,
	"start=s" => \$start,
	"help|?" => \&HelpMessage,
	"" => \$interactive
) or die("Error in command line arguments\n");

@pages = map {decode_utf8($_)} @ARGV;

print "=== [RUNNING bot.pl @ ", POSIX::strftime("%F %T", localtime), "] ===\n";

my %credentials = load_credentials('wiki_botconf.txt');
my $host = ( $credentials{host} || 'he.wikisource.org' );
print "HOST $host USER $credentials{username}\n";
my $bot = MediaWiki::Bot->new({
	host       => $host,
	agent      => sprintf('PerlWikiBot/%s',MediaWiki::Bot->VERSION),
	login_data => \%credentials,
	assert     => 'bot',
	protocol   => 'https',
	debug      => ($verbose?2:0),
}) or die "Error login...\n";


if ($interactive) {
	print "Entering interacitve mode (enter empty string to quit).\n";
	push @pages, '-';
}

if (@pages and $recent) {
	$recent = 0;
	print "Warning: '-recent' ignored.\n";
}

unless (@pages) {
	# Get category list
	my $cat = "קטגוריה:בוט חוקים";
	@pages = $bot->get_pages_in_category($cat);
	print "CATEGORY contains ", scalar(@pages), " pages.\n";
	if (defined $start) {
		$start = decode_utf8($start);
		while (my $str = shift @pages) {
			last if ($str eq $start);
		}
		unshift @pages, $start;
		print "Starting at '$start', up to ", scalar(@pages), " pages.\n";
	}
	if (defined $select) {
		$select = decode_utf8($select);
		$select = convert_regexp($select);
		@pages = grep { /^$select/ } @pages;
		print "Found ", scalar(@pages), " pages with selector '$select'.\n";
	}
}

if ($recent) {
	# Get recently changed pages in namespace
	$recent = 1;
	my %cat = map { $_ => undef } @pages;
	@pages = $bot->recentchanges({ns => 116, limit => $credentials{limit} // 100}); # Namespace 116 is 'מקור'
	@pages = map {$_->{title}} @pages;
	map {s/^\s*(?:מקור:|)\s*(.*?)\s*$/$1/} @pages;
	# Intersect list with category list
	@pages = grep {exists($cat{ $_ })} @pages;
}

if ($recent) {
	# Check additional actions at משתמש:OpenLawBot/הוספה	
	$text = $bot->get_text($bot_page) // "";
	my @actions = parse_actions($text);
	my @text = split(/\n/, $text);
	my $res;
	
	foreach my $cmd (@actions) {
		my $line = $cmd->{line};
		if ($cmd->{action} eq 'add') {
			$res = process_law("-f $cmd->{what}");
		} elsif ($cmd->{action} eq 'move') {
			$res = move_page($cmd->{what}->[0], $cmd->{what}->[1]);
		} else {
			next;
		}
		my $status = ($res =~ s/^([vx]) *//) ? $1 : " ";
		next if ($status eq ' ');
		$text[$line] =~ /^([:*]+)/;
		$res = "$1 {{$status}} $res";
		$text[$line] = $res;
	}
	
	unless ($onlycheck || $dryrun) {
		$text = join("\n", @text) . "\n";
		$text =~ s/\n{2,}/\n/g;
		$bot->edit({
			page => $bot_page, text => $text, summary => 'תודה',
			bot => 1, minor => 0, assertion => 'bot',
		})
	}
	
}

if ($onlycheck and $force) {
	$force = 0;
	print "Warning: '-force' ignored.\n";
}

foreach my $page_dst (@pages) {
	
	if ($page_dst eq '-') {
		# Interactive mode: Query for page name
		print "> ";
		$_ = decode_utf8(<STDIN>);
		chomp;
		s/[\x{200E}\x{200F}\x{202A}-\x{202E}]//g;
		s/^\s*(?:מקור:)?(.*?)\s*$/$1/s;
		next if (!$_);
		$page_dst = $_;
		push(@pages, '-');
	}
	
	process_law($page_dst);
	
	last if ($recent and $recent > 10);
}

# Update new texts page
if ((%new_pages) && !($onlycheck || $dryrun)) {
	$page = 'עמוד_ראשי/טקסטים_חדשים';
	$text = $bot->get_text($page);
	if ($text) {
		$text =~ /\}\}\n+/g || $text =~ /\n(?=\[\[)?/g || $text =~ s/ *\n*$/ {{*}}\n/gs;
		my $new = join("\n", (keys(%new_pages), ''));
		$new =~ s/(.+)/[[$1]] {{*}}/mg;
		$text =~ s/\G/$new/;
		$bot->edit({
			page => $page, text => $text, summary => 'טקסטים חדשים',
			bot => 1, minor => 0, assertion => 'bot',
		})
	}
}

# Update recently updated page
if ((%updated_pages) && !($onlycheck || $dryrun)) {
	$page = 'ויקיטקסט:ספר החוקים הפתוח/עדכונים אחרונים';
	$text = $bot->get_text($page);
	if ($text) {
		my $new = '';
		foreach my $p (keys(%updated_pages)) {
			my $re = ($p =~ s/(?<!\\)([.()\[\]\\])/\\$1/gr);
			$text =~ s/.*\[\[$re(\||\]\]).*\n//gm;
			my $alt = ($p =~ s/(\(.*\))/{{מוקטן|$1}}/r);
			if ($alt ne $p) {
				$new .= "* [[$p|$alt]]\n";
			} else {
				$new .= "* [[$p]]\n";
			}
		}
		$text =~ /^(?=\*)/gm;
		$text =~ s/\G/$new/;
		$text =~ /^(?=\*)/gm;
		$text =~ /\G(\*.*\n){0,15}+/gm;
		$text =~ s/\G(\*.*\n)*//m;
		
		$bot->edit({
			page => $page, text => $text, summary => 'עדכונים אחרונים',
			bot => 1, minor => 0, assertion => 'bot',
		})
	}
}

$page = 'ויקיטקסט:ספר החוקים הפתוח';
$bot->purge_page($page);

$bot->logout();

exit 0;
1;

#-------------------------------------------------------------------------------

sub process_law {
	my $page_dst = shift;
	my $res = '';
	
	$locforce = ($page_dst =~ s/^-f //);
	$page_dst =~ s/^ *(.*?) *$/$1/;
	# $page_dst =~ s/ /_/g;
	$page_dst =~ s/_/ /g;
	my $page_src = "מקור:$page_dst";
	
	if ($recent) {
		return "" if defined $processed{$page_dst};
		$processed{$page_dst} = '';
	}
	
	my ($revid_s, $revid_t, $comment, $minor) = get_revid($bot, $page_dst);
	my $src_ok = ($revid_s>0);
	my $dst_ok = ($revid_t>0);
	
	print "PAGE \"$page_dst\":\t";
	if (!$src_ok && $bot->get_id($page_dst)) {
		$text = $bot->get_text($page_dst);
		if ($text =~ /#(?:הפניה|Redirect) \[\[(?:מקור:|)(.*?)\]\]/) {
			print "redirection to \"$1\".\n";
			$page_dst = $1;
			$page_src = "מקור:$page_dst";
			($revid_s, $revid_t, $comment) = get_revid($bot, $page_dst);
			$src_ok = ($revid_s>0);
			$dst_ok = ($revid_t>0);
			print "PAGE \"$page_dst\":\t";
		} elsif ($text =~ /^ *<שם( קודם|)>/s) {
			print "Warning, source misplaced, moving to \"$page_src\".\n";
			$bot->move($page_dst, $page_src, '', { movetalk => 0, noredirect => 1, movesubpages => 0 }) unless ($dryrun);
			($revid_s, $revid_t, $comment) = get_revid($bot, $page_dst);
			$src_ok = ($revid_s>0);
			$dst_ok = ($revid_t>0);
		}
	}
	my $update = ($revid_t<$revid_s);
	my $done = 0;
	
	print "ID $revid_s ", ($update ? '>' : '='), " $revid_t";
	if (!$src_ok) {
		print ", Source not exist.\n";
		$res = "x דף מקור [[$page_src]] לא קיים";
		$done = 1;
	} elsif (!$dst_ok) {
		print ", Target not exist.\n";
		$done = 1 if ($onlycheck);
	} elsif ($onlycheck) {
		print ", Modified.\n" if ($revid_t<$revid_s);
		print ", Target changed.\n" if ($revid_t>$revid_s);
		print ", Same.\n" if ($revid_t==$revid_s);
		$done = 1;
	} elsif (!$update && !$force && !$locforce) {
		print ", Skipping.\n";
		$done = 1;
	} elsif (!$update && ($force || $locforce)) {
		print ", Updating anyway (-force).\n";
	} elsif ($dryrun) {
		print ", Dryrun.\n";
	} else {
		print ", Updating.\n";
	}
	
	if ($recent and $recent>0 and $src_ok and !$update) {
		if (++$recent > 10) { # No more recent updated, early exit
			print "Consecutive not-modified in recent changes; done for now.\n";
			return $res;
		}
	} elsif ($recent and $recent>0 and $update) {
		$recent = 1;
	}
	
	return $res if ($done);
	
	$comment =~ s/^[^\]]*\]\][^\]]*\]\].*?\: *// || $comment =~ s/ \[.*/.../ if ($comment =~ /העבירה? את הדף/);
	if ($comment =~ /^יצירת דף עם התוכן "/) {
		$comment = $page_dst;
		$comment =~ s/[_ ]+/ /g;
	}
	
	$locforce = 0;
	
	my $src_text = $bot->get_text($page_src, $revid_s);
	eval {
		$text = RunParsers($src_text);
		1;
	} or do {
		print "FAILED!\n";
		return "x בעיה בהמרה";
	};
	
	$comment = ( $comment ? "[$revid_s] $comment" : "[$revid_s]" );
	$minor //= 0;
	
	my $len1 = length($bot->get_text($page_dst) // '');
	my $len2 = length($text);
	
	# print "Length changed from $len1 to $len2.\n";
	$updated_pages{$page_dst} = '' if (abs($len1-$len2)>2000) && !$minor;
	
	# print STDOUT "$text\n" if ($print || $dryrun);
	unless ($dryrun) {
		$bot->edit( {
			page => $page_dst, text => $text, summary => $comment,
			bot => 1, minor => $minor, assertion => 'bot'});
		# unless ($bot->get_protection($page_dst)) {
		#	$bot->protect($page_dst, 'הגנה בפני עריכה בשגגה', 'sysop', 'sysop', 'infinite', 0);
		# }
	}
	
	$res = "v " . ($dst_ok ? "עודכן" : "נוצר") ." [[$page_dst]]";
	$new_pages{$page_dst} = '' if (!$dst_ok && $page_dst =~ /^(חוק|פקודת)/);
	
	# Check all possible redirections
	$text = "#הפניה [[$page_dst]]";
	my @redirects = possible_redirects($page_dst, $src_text =~ /^<שם[^>\n]*> *(.*?) *$/gm);
	foreach $page (@redirects) {
		next if ($page eq $page_dst);
		unless ($dryrun || $bot->get_id($page)) { $bot->edit({page => $page, text => $text, summary => "הפניה", minor => 1}); }
	}
	
	# Check talkpage and add redirection if neccessary
	$page = "שיחת מקור:$page_dst";
	$id = $bot->get_id($page);
	if ($dryrun) {
		# Do nothing
	} elsif (!defined $id) {
		$bot->edit({
			page => $page, text => "#הפניה [[שיחה:$page_dst]]",
			summary => "הפניה", minor => 1,
		});
	} elsif ($id>0 && !($bot->get_id("שיחה:$page_dst")) && ($bot->get_text($page) !~ /^\s*#(הפניה|redirect)/si)) {
		# Discussion at source talk page, move to main talk page
		$bot->move($page, "שיחה:$page_dst", "העברה", { movetalk => 1, noredirect => 0, movesubpages => 1 });
	}
	
	$page = "שיחה:$page_dst";
	$id = $bot->get_id($page);
	if (!$dryrun && !defined $id) {
		$bot->edit({
			page => $page, text => "",
			summary => "דף ריק", minor => 1,
		});
	}
	
	if (!$dryrun && !$dst_ok) {
		my $src_text2 = auto_correct($src_text);
		$bot->edit( {
			page => $page_src, text => $src_text2, summary => 'בוט: תיקונים אוטומטיים',
			bot => 1, minor => 1, assertion => 'bot'}
		) if ($src_text2 ne $src_text);
		# Update of $page_dst will take place on next run, providing user time to check automatic updates.
	}
	
	return $res;
}

sub auto_correct {
	my $HE = '(?:[א-ת][\x{05B0}-\x{05BD}]*+)';
	my $_ = shift;
	tr/\x{FEFF}//d;    # Unicode marker
	tr/\x{2000}-\x{200A}\x{205F}/ /; # typographic spaces
	tr/\x{200B}-\x{200D}//d;         # zero-width spaces
	s/  +/ /mg;
	s/ +$//mg;
	s/^ +//mg;
	s/ ([.,][ \n])/$1/sg;
	s/^(:+)(\()/$1 $2/mg;
	s/^(:+ "?\([^)]{1,2}\))($HE)/$1 $2/mg;
	s/(?:\]\]-|-\]\])(\d{4})/-$1]]/mg;
	# s/ *class="wikitable"//g;
	$_ = s_lut($_, { 
		'½' => '¹⁄₂', '⅓' => '¹⁄₃', '⅔' => '²⁄₃', '¼' => '¹⁄₄', '¾' => '³⁄₄', 
		'⅕' => '¹⁄₅', '⅙' => '¹⁄₆', '⅐' => '¹⁄₇', '⅛' => '¹⁄₈', '⅑' => '¹⁄₉', '⅒' => '¹⁄₁₀'
	});
	s/([⁰¹²³⁴-⁹]+\⁄[₀-₉]+)(\d+)/$2$1/g;
	# s/ %(\d*[⁰¹²³⁴-⁹]+\⁄[₀-₉]+|\d+\/\d+|\d+(\.\d+)?)/ $1%/g;
	# s/(\d+)%(\d*\.\d+)/$1$2%/g;
	s/^(@ \d[^ .]) /$1. /gm;
	s/^(@ \d.*?\.) \./$1 /gm;
	s/^@ :$/@/gm;
	s/\=\n+@\n/=\n/g;
	s/(חא"י),? (כרך [אב]'),? (פרק [א-ת"']+),? (עמ' )?/$1 $2 $3, עמ' /;
	s/(19\d\d) (תוס' [12])/$1, $2/g;
	s/ ([א-ת])(\[\[)/ $2$1/g;
	s/;(?=\n\n+@)/./g;
	s/^(:+-?)(?=[^ \n])/$1 /g;
	s/(@ [^:]* \(תיקון) (.*\))/$1: $2/g;
	s/^((?:@ \d+\. |):+ (?:\([^()]+\) *)*)(?|\(\((.*)\)\)([^ \n])|\(([^(])(.*)\)\)|\(\((.*)([^)])\))$/$1(($2$3))/gm;
	return $_;
}

sub s_lut {
	my $str = shift;
	my $table = shift;
	my $keys = join('', keys(%{$table}));
	$str =~ s/([$keys])/$table->{$1}/ge;
	return $str;
}


sub move_page {
	my $src = shift;
	my $dst = shift;
	return "x לא ניתן להעביר דף אל עצמו" if ($src eq $dst);
	return "x הדף [[$src]] לא קיים" unless $bot->get_id($src);
	return "x הדף [[מקור:$src]] לא קיים" unless $bot->get_id("מקור:$src");
	return "x דף היעד [[מקור:$dst]] קיים" if $bot->get_id("מקור:$dst");
	# return "x לא ניתן להעביר את [[$src]] אל [[$dst]]" unless $bot->get_id("Mediawiki:Editnotice-0-$src");
	print "MOVE '$src' to '$dst'.\n";
	unless ($dryrun) {
		$bot->move("מקור:$src", "מקור:$dst", "העברה", {movetalk => 1, noredirect => 1, movesubpages => 1});
		$bot->move($src, $dst, "העברה", {movetalk => 1, movesubpages => 1});
		$bot->edit({
			page => "שיחת מקור:$dst", text => "#הפניה [[שיחה:$dst]]",
			summary => "הפניה", minor => 1
		});
	}
	return "v דף [[$src]] הועבר לדף [[$dst]]";
}

sub possible_redirects {
	my %redirects;
	while (my $page = shift) {
		$page =~ s/ *\(תיקון:.*?\)$//;
		$page =~ s/ *\[נוסח חדש\]//;
		$page =~ s/, *(ה?תש.?["”״].[\-־–])?\d{4}$//;
		
		for (my $k = 0; $k < 32; $k++) {
			my $_ = $page;
			if ($k&1) { s/[–־]+/-/g; } else { s/(?<=[א-ת])[\-־](?=[א-ת])/־/g; }
			if ($k&2) { s/ – / - /g; s/--/-/g;} else { s/--/–/g; s/ - / – /g; }
			if ($k&4) { s/(?<=[א-ת])[\-־](?=[א-ת])/ /g; }
			if ($k&8) { tr/“”״„’‘׳/"""'''/; }
			if ($k&16) { s/, / /g; }
			$redirects{$_} = '';
		}
	}
	return keys %redirects;
}

sub RunParsers {
	my ( $str1, $str2, $str3 );
	$str1 = shift;
	$str2 = SyntaxLaw::convert( $str1 );
	$str3 = SyntaxWiki::convert( $str2 );
	return $str3 . "\n[[קטגוריה:בוט חוקים]]\n";
}


sub load_credentials {
	my %obj;
	my $_ = shift;
	open( my $FIN, $_ ) || die "Cannot open file \"$_\"!\n";
	while (<$FIN>) {
		if (m/^ *(.*?) *= *(.*?) *$/) {
			$obj{$1} = $2;
		}
	}
	close($FIN);
	return %obj;
}

sub get_revid {
	my $bot = shift;
	my $page = shift;
	$page = $page->{title} if (ref($page) eq 'HASH');
	
	$page =~ s/^\s*(?:מקור:)?(.*?)\s*$/$1/s;
	$page =~ s/ /_/g;
	
	my @hist_s = $bot->get_history("מקור:$page");
	my @hist_t = $bot->get_history($page);
	
	return (0,0,undef) unless (scalar(@hist_s));
	
	my $revid_s = $hist_s[0]->{revid};
	my $revid_t = 0;
	my $comment = $hist_s[0]->{comment} // $hist_t[0]->{comment};
	my $minor = $hist_s[0]->{minor};
	
	foreach my $rec (@hist_t) {
		if ($rec->{user} eq 'OpenLawBot' && $rec->{comment} =~ /^ *\[(\d+)\]/) {
			$revid_t = $1;
			last;
		}
	}
	
	return ($revid_s, $revid_t, $comment, $minor);
}


sub parse_actions {
	my @_ = split(/\n/, shift);
	my @actions;
	my $line = -1;
	foreach my $_ (@_) {
		$line++;
		next if !(/^ *\*/) || /{{v}}/ || /{{x}}/;
		if (/\[\[(.*?)\]\].*?\[\[(.*?)\]\]/) {
			# print STDERR "MOVE '$1' to '$2'\n";
			push @actions, { line => $line, action => 'move', what => [clean_name($1), clean_name($2)] };
		} elsif (/\[\[(.*?)\]\]/) {
			# print STDERR "ADD '$1'\n";
			push @actions, { line => $line, action => 'add', what => clean_name($1) };
		}
	}
	return @actions;
}

sub clean_name {
	my $_ = shift;
	s/\[\[(.*?)\|?.*?\]\]/$1/;
	s/^ *(.*?) *$/$1/;
	s/^מקור: *//;
	s/, (ה?תש.?".?-)?\d{4}$//;
	s/ {2,}/ /g;
	return $_;
}

sub convert_regexp {
	my $_ = shift;
	s/([.()\[\]])/\\$1/g;
	s/\*/.*/g;
	s/\?/./g;
	s/^\^?/^/;
	s/\.\*$//;
	return $_;
}

sub HelpMessage {
	print <<EOP;
USAGE: bot.pl [-h] [-d] [-f] [-l LOG] [-o] [-s SELECT] [-v]
              [TITLE [TITLE ...]] | [-]

Process law-source files to wiki-source.

Optional arguments:
  TITLE                 Wiki titles to fetch by the bot
  -                     Enter interacitve mode
  --select rule         Select titles using basic regexp rule
  --start title         Start processing at specifig title

Optional flags:
  -h, -?, --help        Show this help message and exit
  -c, --check           Lists wiki files with no commit
  -d, --dry-run         Run the process with no commit
  -f, --force           Force changing contents of destination
  -l LOG, --log LOG     Set a custom log file
  -o, --output          Output the final format to stdout
  -r, --recent          Check only recent changes
  -v, --verbose         Output full process log to stdout
EOP
#  -O FILE, --OUTPUT FILE Output the final format to file FILE
	exit 0;
}
