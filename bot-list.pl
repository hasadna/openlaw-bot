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
use IO::Handle;
use Time::Piece;

binmode STDOUT, ":utf8";
binmode STDERR, ":utf8";
STDOUT->autoflush(1);

print STDERR "=== [RUNNING ", $0 =~ /([^\/]+)$/, " @ ", POSIX::strftime("%F %T", localtime), "] ===\n";

my ($start, $end, $selector, $action, $verbose);
$action = '';

GetOptions(
	"start=s" => \$start,
	"end=s" => \$end,
	"pat=s" => \$selector,
	"act=s" => \$action,
	"verbose" => \$verbose,
) or die("Error in command line arguments\n");

$action = $ARGV[0] if (scalar(@ARGV)>0 && $action eq '');
$action = 'list' unless($action);

our $pre_sig = 'ו?כ?ש?מ?[בהל]?-?';
our $extref_sig = $pre_sig . '(?:חוק(?:[ -]ה?יסוד:?|)|פקוד[הת]|תקנות|צו|החלטה|הכרזה|תקנון|הוראו?ת|הודע[הת]|מנשר|כללים?|נוהל|קביעו?ת|חוק[הת]|אמנ[הת]|דברי?[ -]ה?מלך|החלטו?ת|הנחי[יו]ת|קווים מנחים|אמו?ת מידה|היתר)';
our $type_sig = $pre_sig . '(?:סעי(?:ף|פים)|תקנ(?:ה|ות)|אמו?ת[ -]מידה|חלק|פרק|סימן(?: משנה|)|לוח(?:ות|) השוואה|נספח|תוספת|טופס|לוח|טבל[הא])';
our $chp_sig = '\d+(?:[^ ,.:;"״\n\[\]()]{0,3}?\.|(?:\.\d+)+\.?)';
our $heb_num2 = '(?:[א-ט]|טו|טז|[יכלמנסעפצ][א-ט]?)';
our $heb_num3 = '(?:[א-ט]|טו|טז|[יכלמנסעפצ][א-ט]?|[קרש](?:טו|טז|[יכלמנסעפצ]?[א-ט]?))';

our $text;
our $page = '';
our $last = undef;

our $HE = '(?:[א-ת][\x{05B0}-\x{05BD}]*+)';

my %credentials = load_credentials('wiki_botconf.txt');
my $host = ( $credentials{host} || 'he.wikisource.org' );
print STDERR "HOST $host USER $credentials{username}\n";

my $bot = MediaWiki::Bot->new({
	host       => $host,
	agent      => sprintf('PerlWikiBot/%s',MediaWiki::Bot->VERSION),
	login_data => \%credentials,
	assert     => 'bot',
	protocol   => 'https',
	debug      => 0,
}) or die "Error login...\n";


my $cat = 'קטגוריה:בוט חוקים';
my @pages = $bot->get_pages_in_category($cat, { max => 0 });

print STDERR "CATEGORY contains ", scalar(@pages), " pages.\n";
if (defined $start || defined $end) {
	if (defined $start) {
		$start = decode_utf8($start); $start =~ tr/_/ /;
		@pages = grep($_ ge $start, @pages);
	}
	if (defined $end) {
		$end = decode_utf8($end); $end =~ tr/_/ /;
		@pages = grep($_ le $end, @pages);
	}
	print STDERR "Starting at '${pages[0]}', up to ", scalar(@pages), " pages.\n";
}
if (defined $selector) {
	$selector = decode_utf8($selector);
	$selector = convert_regexp($selector);
	@pages = grep { /^$selector/ } @pages;
	print STDERR "Found ", scalar(@pages), " pages matching to '$selector'.\n";
}


my $export_path = '/tmp/Export';

foreach $page (@pages) {
	next if ($page =~ /^משתמש:/);
	next if ($page =~ /תזכיר|הצעת תנועת החירות לחוקת יסוד למדינת ישראל/);
	# next if ($page =~ /\//);
	
	# print STDERR "-- $page --\n";
	$text = $bot->get_text("מקור:$page");
	next if (!defined $text);
	my $org = $text;
	
	my ($name, $org_name, $src, $knesset_id);
	
	$_ = $text;
	
	($name) = /<שם> *(.*)/m;
	$name = $1 if (/<שם מלא> *(.*)/m);
	$org_name = clean_str($name);
	$name = canonic_name($name);
	($src) = /<מקור>[ \n]*(.*?)(?=\n[<:@_=])/s;
	$src = clean_str($src // '');
	
	if ($action eq 'list') {
		my $knesset_id = (/<מאגר (\d++)[^>]*>/) ? $1 : 0;
		my $page2 = s_lut($page, { ' ' => '_', '&' => '$amp;', '"' => '&quot;'});
		if ($knesset_id) {
			printf("%s\t%s\t%07d\n", $name, $page2, $knesset_id);
		} else {
			printf("%s\t%s\n", $name, $page2);
		}
	} elsif ($action eq 'rename') {
		next unless (/<שם (קודם|חדש)>/);
		
		my ($altname, $type, @fixes, $str);
		my @table = get_makor($src);
		if ($org_name =~ s/ \(תיקון: *([^)]*?) *\) *$//m) { push @fixes, reverse(split(/, */, $1)); }
		while (/<שם ([^>]+)> *(.*)/mg) {
			($type, $altname) = ($1, $2);
			$altname = clean_str($altname);
			next if ($type =~ /מלא|קצר/);
			next unless ($type =~ /קודם|חדש/);
			if ($altname =~ s/ \(תיקון: *([^)]*?) *\) *$//m) { push @fixes, reverse(split(/, */, $1)); }
			print STDERR "fixes = @fixes\n";
			my $fix = shift @fixes;
			if ($fix) {
				$str = find_makor(\@table, $fix, $altname);
				print "$altname\t$org_name\t(תיקון: $fix)\t$str\n";
			} else {
				print "$altname\t$org_name\t\t???\n";
			}
			if ($altname) { $org_name = $altname; }
		}
		
	} elsif ($action eq 'pdf') {
		my ($timestamp) = $bot->recent_edit_to_page($page);
		my $short1 = $page;
		$timestamp = Time::Piece->strptime($timestamp, "%Y-%m-%dT%H:%M:%SZ")->epoch;
		$short1 =~ s/\// – /g;
		my $page2 = $page;
		$short1 =~ s/(^.{,80}[^,_ "])[,_ ].*$/$1.../ if (length($short1)>80);
		$short1 =~ s/"/''/g;
		# next if (-e "$export_path/$short1.pdf");
		my $cnt = 0;
		my $short2 = "$short1 (0)";
		if (-e "$export_path/$short1.pdf" || -e "$export_path/$short2.pdf") { 
			rename("$export_path/$short1.pdf", "$export_path/$short2.pdf") unless (-e "$export_path/$short2.pdf");
			while (-e "$export_path/$short2.pdf") {
				$cnt++;
				$short2 =~ s/( \([0-9]+\)|)$/" ($cnt)"/e;
			}
		} else {
			$short2 = $short1;
		}
		print STDERR "Fetching \"$short2.pdf\"... ";
		$page2 =~ s/ /%20/g;
		$page2 =~ s/"/%22/g;
		$page2 =~ s/\//%2F/g;
		system("wget -q \"https://he.wikisource.org/api/rest_v1/page/pdf/$page2\" -O \"$export_path/$short2.pdf\"");
		if (-e "$export_path/$short2.pdf") {
			utime($timestamp, $timestamp, "$export_path/$short2.pdf");
			print STDERR "Ok.\n";
			sleep(3);
		} else {
			print STDERR "Failed to fetch file.\n";
		}
	}
	
}

exit 0;

1;

sub load_credentials {
	my %obj;
	local $_ = shift;
	open( my $FIN, $_ ) || die "Cannot open file \"$_\"!\n";
	while (<$FIN>) {
		if (m/^ *(.*?) *= *(.*?) *$/) {
			$obj{$1} = $2;
		}
	}
	close($FIN);
	return %obj;
}

sub print_pos {
#	if ($page ne $last) {
#		print "\n" if defined $last;
#		print "-- $page --\n";
#		$last = $page;
#	}
	$text =~ /^(.*\G.*)$/m;
	print "$1\n";
}

sub s_lut {
	my $str = shift;
	my $table = shift;
	my $keys = join('', keys(%{$table}));
	$str =~ s/([$keys])/$table->{$1}/ge;
	return $str;
}

sub replace_date {
	local $_ = shift;
	s/(\d{1,2})[\.\/](\d{1,2})[\.\/](\d{4})/sprintf("%d\.%d\.%02d", $1, $2, $3)/ge;
	return $_;
}

sub fix_intro {
	local $_ = shift;
	s/\[\[(=.*?)\|((?:$type_sig )?[^ \[\]]+) ($extref_sig[^\[\]]*(?:\[[^\[\]]*\][^\[\]]*)?)\]\]/[[+|$2]] [[$1|$3]]/g;
	return $_;
}

sub get_makor {
	my $src = shift;
	my @table;
	
	$src =~ tr/״–־/"\-\-/;
	$src =~ s/<!--((?:(?!<!--|-->).)*)-->//sg;
	$src =~ s/[\n ]+[@:_<].*$//s;
	print STDERR "get_makor: $src\n" if ($verbose);
	
	my ($s_,$y_); $s_ = $y_ = '';
	my $name = '';
	my $count = 0;
	
	while ($src =~ /(\(\(.*?\)\)(?!\)))/g) {
		my $atom = $1;
		my ($syp,$d,$r) = ($atom =~ m/\(\(([^|]+)\|([^|]+)(?|\|(.*)|())\)\)/);
		my ($s,$y,$s2,$p) = ($syp =~ m/(?|((?:ע"ר|חא"י,? כרך [0-9א-ת]'?|ס"ח|דמ"י|ק"ת|י"פ)),? |())(?|ה?(תש[א-ת]?"[א-ת]), |(\d{4}), |())(?|(תוס' [0-9א-ת]'?),? |())(?:עמ' )?((?:(?:[0-9]+[א-י]?|[XVI]+)(?:, |))+)/);
		$s //= $syp; $y //= ''; $p //= '';
		$s = "$s $s2" if ($s2);
		$s =~ tr/,'//;
		if ($y) { $count = 1; } else { $count++; }
		$d =~ s/^((?:תיקון|הוראת שעה)(?: מס' [0-9]+| \(מס' [0-9]+\)|)) ל(.*)$/$2 ($1)/;
		$d =~ s/ ?\[[^\]]*\]// unless ($d =~ /\[(נוסח חדש|נוסח משולב)\]/);
		if ($d =~ /^(תיקון|הוראת שעה|ביטול)/) {
			$d = "($d)";
			$d =~ s/^\((.*?)\((.*?)\)\)$/($1) ($2)/;
			$d = "__ $d";
		}
		$d =~ s/^הודעה(?= *$|\()/הודעת __/;
		$d = '__' if ($d eq '');
		$d =~ s/  / /g;
		$name ||= $d;
		$s_ = $s if ($s && $y);
		$y_ = $y if ($y);
		foreach my $pp (split(/, */, $p)) {
			print STDERR "[$s_, $y_, $pp, $d, $r]\n" if ($verbose);
			push @table, [$s_, $y_, $pp, $d, $r];
		}
	}
	return @table;
}

sub find_makor {
	my @table = @{$_[0]};
	my $itm = $_[1];
	my $name = $_[2] || $table[0][3];
	return '???' unless ($itm);
	$name =~ s/, (ה?ת[א-ת][א-ת]?"[א-ת]-\d{4}|\d{4}|\d{4} עד \d{4})$//;
	$itm =~ s/\(תיקון: (.*?) *\)/$1/;
	$itm =~ tr/״”“„/"/; $itm =~ tr/–־/-/;
	my ($s, $y, $c) = $itm =~ /(?|([א-ת]+"[א-ת]) |())(?|ה?(תש[א-ת]?"[א-ת])|(\d{4}))(?|-(\d+)|())/;
	$c ||= 1;
	if ($y eq $table[0][1] && ($s eq '' || $s eq $table[0][0])) { $c++; }
	@table = grep($_->[1] eq $y, @table);
	return '???' unless (@table);
	$s ||= $table[0][0];
	print STDERR "find_makor: \$itm=$itm; \$s=$s, \$y=$y, \$c=$c.\n" if ($verbose);
	@table = grep($_->[0] eq $s, @table);
	# print STDERR Dumper($table->[$c-1]);
	my $rec = $table[$c-1];
	return '???' unless (defined $rec);
	print STDERR "            record = [$rec->[0], $rec->[1], $rec->[2], $rec->[3], $rec->[4]]\n" if ($verbose);
	my $str = "$rec->[3], מתוך $rec->[0] $rec->[1], $rec->[2]";
	$str .= " [$rec->[4]]" if ($rec->[4]);
	if ($str =~ /^הודעת/) {
		$str =~ s/__/ $name =~ s|^[א-ת]+||r /e;
	} else {
		$str =~ s/__/$name/e;
	}
	return $str;
}


sub clean_str {
	local $_ = shift;
	tr/־/-/;
	tr/״”“„/"/;
	tr/׳‘’/'/;
	tr/\x{05B0}-\x{05BD}//d;
	s/(?<=[א-ת])–(?=[0-9])/-/g;
	s/ - / – /g;
	s/^ *(.*?) *$/$1/;
	s/ {2,}/ /g;
	return $_;
}

sub canonic_name {
	local $_ = clean_str(shift);
	s/( *\(תיקון:[^)]+\))+$//;
	return $_;
}
