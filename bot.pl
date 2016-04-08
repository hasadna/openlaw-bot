#!/usr/bin/perl -w

use strict;
no strict 'refs';
no if ($]>=5.018), warnings => 'experimental';
use English;
use Encode;
use utf8;
# use Array::Utils;
use Data::Dumper;
use MediaWiki::Bot;
use IPC::Run 'run';
use Getopt::Long;

use SyntaxLaw;

binmode STDOUT, ":utf8";
binmode STDERR, ":utf8";

my @pages = ();
my ($verbose, $dryrun, $force, $print, $onlycheck, $interactive, $recent, $select);
my $botpage;
my $locforce = 0;
my $outfile;

my %processed;
my ($page, $id, $text);
my $bot_page = decode_utf8("משתמש:OpenLawBot/הוספה");

GetOptions(
	"force" => \$force, 
	"check" => \$onlycheck,
	"dryrun" => \$dryrun,
	"verbose" => \$verbose,
#	"OUTPUT=s" => sub { $print = 1; open(STDOUT, ">_[1]"); },
	"output" => \$print,
	"recent" => \$recent,
	"select=s" => \$select,
	"help|?" => \&HelpMessage,
	"" => \$interactive
) or die("Error in command line arguments\n");

@pages = map {decode_utf8($_)} @ARGV;

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
	my $cat = decode_utf8('קטגוריה:בוט חוקים');
	@pages = $bot->get_pages_in_category($cat);
	print "CATEGORY contains " . scalar(@pages) . " pages.\n";
	if (defined $select) {
		$select = convert_regexp(decode_utf8($select));
		@pages = grep { /^$select/ } @pages;
		print "Found " . scalar(@pages) . " pages with selector '$select'.\n";
	}
}

if ($recent) {
	# Get recently changed pages in namespace
	$recent = 1;
	my %cat = map { $_ => undef } @pages;
	@pages = $bot->recentchanges({ns => 116, limit => 100}); # Namespace 116 is 'מקור'
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
		# $res = $text[$line] . ($res ? " – $res" : "");
		$text[$line] =~ /^([:*]+)/;
		$res = "$1 {{$status}} $res";
		$text[$line] = $res;
	}
	
	$text = join("\n", @text);
	$text .= "\n";
	$text =~ s/\n{2,}/\n/g;
	
	$bot->edit( {
		page      => $bot_page,
		text      => $text,
		summary   => decode_utf8("תודה"),
		bot       => 1,
		minor     => 0,
		assertion => 'bot',
	}) unless ($onlycheck || $dryrun);
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
	my $page_src = decode_utf8("מקור:") . $page_dst;
	
	if ($recent) {
		return "" if defined $processed{$page_dst};
		$processed{$page_dst} = '';
	}
	
	my ($revid_s, $revid_t, $comment) = get_revid($bot, $page_dst);
	my $src_ok = ($revid_s>0);
	my $dst_ok = ($revid_t>0);
	
	print "PAGE \x{202B}\"$page_dst\"\x{202C}:\t";
	
	my $update = ($revid_t<$revid_s);
	my $done = 0;
	
	print "ID $revid_s " . ($update?'>':'=') . " $revid_t";
	if (!$src_ok) {
		print ", Source not exist.\n";
		$res = "x [[$page_src|דף מקור]] לא קיים";
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
	
	$text = $bot->get_text($page_src, $revid_s);
	eval {
		$text = RunParsers($text);
		1;
	} or do {
		print "FAILED!\n";
		return "x בעיה בהמרה";
	};
	
	$res = "v " . ($dst_ok ? "עודכן" : "נוצר") ." [[$page_dst]]";
	
	$comment = ( $comment ? "[$revid_s] $comment" : "[$revid_s]" );
	
	print STDOUT "$text\n" if ($print || $dryrun);
	unless ($dryrun) {
		$bot->edit( {
			page => $page_dst, text => $text, summary => $comment,
			bot => 1, minor => 0, assertion => 'bot'});
		# $bot->protect($page, $reason, $editlvl, $movelvl, $time, $cascade);
	}
	
	# Check editnotice and update if neccessary
	$page = "Mediawiki:Editnotice-0-$page_dst";
	$id = $bot->get_id($page);
	if (!defined $id) {
		if ($dryrun) {
			print "Editnotice for '$page_dst' does not exist.\n";
		} else {
			print "Creating editnotice '$page_dst'.\n";
			$bot->edit({
				page => $page, text => decode_utf8("{{הודעת עריכה חוקים}}"),
				summary => "editnotice", minor => 1,
			});
		}
	}
	
	$page = "Mediawiki:Editnotice-116-$page_dst";
	$id = $bot->get_id($page);
	if (!defined $id && !$dryrun) {
		$bot->edit({
			page    => $page, text => decode_utf8("{{הודעת עריכה חוקים}}"),
			summary => "editnotice", minor => 1,
		});
	}
	
	# Check talkpage and add redirection if neccessary
	$page = "שיחת מקור:$page_dst";
	$id = $bot->get_id($page);
	if (!defined $id && !$dryrun) {
		$bot->edit({
			page => $page, text => decode_utf8("#הפניה [[שיחה:$page_dst]]"),
			summary => "הפניה", minor => 1,
		});
	}
	$page = "שיחה:$page_dst";
	$id = $bot->get_id($page);
	if (!defined $id && !$dryrun) {
		$bot->edit({
			page => $page, text => "", summary => "דף ריק",
			minor => 1,
		});
	}
	
	$text = "#הפניה [[$page_dst]]";
	$page = $page_dst =~ s/־/-/gr;
	unless ($bot->get_id($page)) { $bot->edit({page => $page, text => $text, summary => "הפניה", minor => 1}); }
	$page = $page_dst =~ s/(?<=[א-ת])-(?=[א-ת])/ /gr;
	unless ($bot->get_id($page)) { $bot->edit({page => $page, text => $text, summary => "הפניה", minor => 1}); }
	$page = $page_dst =~ s/ – / - /gr;
	unless ($bot->get_id($page)) { $bot->edit({page => $page, text => $text, summary => "הפניה", minor => 1}); }
	
	return $res;
}

sub move_page {
	my $src = shift;
	my $dst = shift;
	return "x לא ניתן להעביר דף אל עצמו" if ($src eq $dst);
	return "x הדף [[$src]] לא קיים" unless $bot->get_id($src);
	return "x הדף [[מקור:$src]] לא קיים" unless $bot->get_id("מקור:$src");
	return "x דף היעד [[מקור:$dst]] קיים" if $bot->get_id("מקור:$dst");
	print "MOVE '$src' to '$dst'.\n";
	unless ($dryrun) {
		$bot->move("מקור:$src", "מקור:$dst", "העברה", {movetalk => 1, noredirect => 1, movesubpages => 1});
		$bot->move($src, $dst, "העברה", {movetalk => 1, movesubpages => 1});
		$bot->edit({
			page => "שיחת מקור:$dst", text => "#הפניה [[שיחה:$dst]]",
			summary => "הפניה", minor => 1
		});
		$bot->move("Mediawiki:Editnotice-0-$src", "Mediawiki:Editnotice-0-$dst", "העברה", {noredirect => 1});
		$bot->move("Mediawiki:Editnotice-116-$src", "Mediawiki:Editnotice-116-$dst", "העברה", {noredirect => 1});
	}
	return "v";
}


sub RunParsers {
	my ( $str1, $str2, $str3 );
	my @cmd1 = ('./SyntaxLaw.pm');
	my @cmd2 = ('./format-wiki.pl');
	$str1 = shift;
	
	# run \@cmd1, \$str1, \$str2, *STDERR;
	$str2 = SyntaxLaw::convert($str1);
	run \@cmd2, \$str2, \$str3, *STDERR;
	$str3 = decode_utf8($str3);
	$str3 .= decode_utf8("\n[[קטגוריה:בוט חוקים]]\n");
	return $str3;
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
	
	my @hist_s = $bot->get_history(decode_utf8("מקור:") . $page);
	my @hist_t = $bot->get_history($page);
	
	return (0,0,undef) unless (scalar(@hist_s));
	
	my $revid_s = $hist_s[0]->{revid};
	my $revid_t = 0;
	my $comment = $hist_s[0]->{comment};
	
	foreach my $rec (@hist_t) {
		last if ($revid_t);
		$revid_t = $rec->{comment};
		$revid_t =~ s/^ *(?:\[(\d+)\]|(\d+)).*/$1/ || ( $revid_t = 0 );
	}
	
	return ($revid_s,$revid_t,$comment);
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
	s/, ה?תש.?".?-\d{4}$//;
	s/ {2,}/ /g;
	return $_;
}


sub convert_regexp {
	my $_ = shift;
	s/\./\\./g;
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
  [-s|--select] rule    Select titles using basic regexp rule

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
