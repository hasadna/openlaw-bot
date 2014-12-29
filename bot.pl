#!/usr/bin/perl -w

use strict;
no strict 'refs';
no if ($]>=5.018), warnings => 'experimental';
use English;
use Encode;
use MediaWiki::Bot;
use IPC::Run 'run';
use Getopt::Long;
use utf8;

use SyntaxLaw;

binmode STDOUT, ":utf8";

my @pages = ();
my ($verbose, $dryrun, $force, $editnotice, $print, $onlycheck, $interactive);
my $locforce = 0;
my $outfile;

$editnotice = 1;

GetOptions(
	"force" => \$force, 
	"check" => \$onlycheck,
	"dryrun" => \$dryrun,
	"editnotice" => \$editnotice,
	"verbose" => \$verbose,
#	"OUTPUT=s" => sub { $print = 1; open(STDOUT, ">_[1]"); },
	"output" => \$print,
	"help|?" => \&HelpMessage,
	"" => \$interactive
) or die("Error in command line arguments\n");

@pages = map {decode_utf8($_)} @ARGV;

my %credentials = load_credentials('wiki_botconf.txt');
my $host = ( $credentials{host} || 'he.wikisource.org' );
print "HOST $host\n";
print "USER $credentials{username}\n";
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

unless (@pages) {
	my $cat = decode_utf8('קטגוריה:בוט חוקים');
	@pages = $bot->get_pages_in_category($cat);
	print "CATEGORY contains " . scalar(@pages) . " pages.\n";
}

$force = 0 if ($onlycheck);

foreach my $page_dst (@pages) {
	my $text;
	
	if ($page_dst eq '-') {
		# Interactive mode: Query new page
		print "> ";
		$_ = decode_utf8(<STDIN>);
		chomp;
		$locforce = 1 if (s/^-f //);
		s/[\x{200E}\x{200F}\x{202A}-\x{202E}]//g;
		s/^\s*(?:מקור:)?(.*?)\s*$/$1/s;
		next if (!$_);
		$page_dst = $_;
		push(@pages, '-');
	}
	
	$page_dst =~ s/^ *(.*?) *$/$1/;
	$page_dst =~ s/ /_/g;
	my $page_src = decode_utf8("מקור:") . $page_dst;
	
	my @hist_s = $bot->get_history($page_src);
	my @hist_t = $bot->get_history($page_dst);
	
	my $src_ok = (@hist_s>0);
	my $dst_ok = (@hist_t>0);
	
	if (!$src_ok) {
		# Check if source at "חוק/מקור"
		$page_src = $page_dst . decode_utf8("/מקור");
		@hist_s = $bot->get_history($page_src);
		$src_ok = (@hist_s>0);
		if (!$src_ok) {
			print "Source page \"מקור:$page_dst\" or \"$page_dst/מקור\" not found!\n";
			next;
		}
	}
	
	print "PAGE \x{202B}\"$page_dst\"\x{202C}:\t";
	
	my $revid_s = $hist_s[0]->{revid};
	my $revid_t = 0;
	my $comment = $hist_s[0]->{comment};
	my $rec     = undef;
	
	foreach my $rec (@hist_t) {
		last if ($revid_t);
		$revid_t = $rec->{comment};
		$revid_t =~ s/^ *(?:\[(\d+)\]|(\d+)).*/$1/ || ( $revid_t = 0 );
	}
	
	my $update = ($revid_t<$revid_s);
	
	print "ID $revid_s " . ($update?'>':'=') . " $revid_t";
	if ($onlycheck) {
		print ", Target not exist.\n" if (!$dst_ok);
		print ", Modified.\n" if ($revid_t<$revid_s && $dst_ok);
		print ", Target changed.\n" if ($revid_t>$revid_s);
		print ", Same.\n" if ($revid_t==$revid_s);
		next;
	}
	if (!$update && !$force && !$locforce) {
		print ", Skipping.\n";
		next;
	} elsif (!$update && ($force || $locforce)) {
		print ", Updating anyway (-force).\n";
	} elsif ($dryrun) {
		print ", Dryrun.\n";
	} else {
		print ", Updating.\n";
	}
	
	if ($comment =~ /העבירה? את הדף/) {
		$comment =~ s/^[^\]]*\]\][^\]]*\]\].*?\: *// || $comment =~ s/ \[.*/.../;
	}
	
	$locforce = 0;
	
	$text = $bot->get_text($page_src, $revid_s);
	$text = RunParsers($text);
	$comment = ( $comment ? "[$revid_s] $comment" : "[$revid_s]" );
	
	print STDOUT "$text\n" if ($print || $dryrun);
	$bot->edit( {
		page      => $page_dst,
		text      => $text,
		summary   => $comment,
		bot       => 1,
		minor     => 0,
		assertion => 'bot',
	}) unless ($dryrun);
	
	next unless $editnotice;
	
	# Check editnotice and update if neccessary
	my $noticepage = "Mediawiki:Editnotice-0-$page_dst";
	my $id = $bot->get_id($noticepage);
	if (!defined $id) {
		if ($dryrun) {
			print "Editnotice for '$page_dst' does not exist.\n";
		} else {
			print "Creating editnotice '$page_dst'.\n";
			$bot->edit({
				page    => $noticepage,
				text    => decode_utf8("{{הודעת עריכה חוקים}}"),
				summary => "editnotice",
			});
		}
	}

	$noticepage = "Mediawiki:Editnotice-116-$page_dst";
	$id = $bot->get_id($noticepage);
	if (!defined $id && !$dryrun) {
		$bot->edit({
			page    => $noticepage,
			text    => decode_utf8("{{הודעת עריכה חוקים}}"),
			summary => "editnotice",
		});
	}
}

$bot->logout();

exit 0;
1;

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

sub HelpMessage {
	print <<EOP;
USAGE: bot.pl [-h] [-d] [-f] [-l LOG] [-o] [-O OUTPUT] [-s] [-v]
              [TITLE [TITLE ...]] | [-]

Process law-source files to wiki-source.

Optional arguments:
  TITLE                 Wiki titles to fetch by the bot
  -                     Enter interacitve mode

Optional flags:
  -h, -?, --help         Show this help message and exit
  -c, --check            Lists wiki files with no commit
  -d, --dry-run          Run the process with no commit
  -f, --force            Force changing contents of destination
  -l LOG, --log LOG      Set a custom log file
  -o, --output           Output the final format to stdout
  -O FILE, --OUTPUT FILE Output the final format to file FILE
  -v, --verbose          Output full process log to stdout
  -s, --silent           Do not output the log info to stdout
EOP
	exit 0;
}
