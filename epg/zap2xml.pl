#!/usr/bin/perl
# zap2xml - zap2it tvschedule scraper - <zap2xml@gmail.com> 

use Compress::Zlib;
use Encode;
use File::Basename;
use File::Copy;
use Getopt::Std;
use HTML::Parser 3.00 ();
use HTTP::Cookies;
use LWP::UserAgent; 
use POSIX;
use Time::Local;
use URI::Escape;
#use JSON;
use JSON::PP;

%options=();
getopts("?A:c:C:d:DeE:Fgi:Il:Ln:N:o:Op:P:qr:s:S:t:Tu:Uwx",\%options);

$homeDir = $ENV{HOME};
$homeDir = $ENV{USERPROFILE} if !defined($homeDir);
$homeDir = '.' if !defined($homeDir);
$confFile = $homeDir . '/.zap2xmlrc';

# Defaults
$start = 0;
$days = 7;
$ncdays = 0;
$ncsdays = 0;
$retries = 3;
$outFile = 'xmltv.xml';
$outFile = 'xtvd.xml' if defined $options{x};
$cacheDir = 'cache';
$lang = 'en';
$userEmail = '';
$password = '';
$proxy;
$postalcode; 
$lineupId; 
$sleeptime = 0;

$outputXTVD = 0;
$lineuptype;
$lineupname;
$lineuplocation;

$sTBA = "To Be Announced";

&printHelp() if defined $options{'?'};

$confFile = $options{C} if defined $options{C};
# read config file
if (open (CONF, $confFile))
{
  &pout("Reading config file: $confFile\n");
  while (<CONF>)
  {
    s/#.*//; # comments
    if (/^\s*$/i)                            { }
    elsif (/^\s*start\s*=\s*(\d+)/i)         { $start = $1; }
    elsif (/^\s*days\s*=\s*(\d+)/i)          { $days = $1; }
    elsif (/^\s*ncdays\s*=\s*(\d+)/i)        { $ncdays = $1; }
    elsif (/^\s*ncsdays\s*=\s*(\d+)/i)       { $ncsdays = $1; }
    elsif (/^\s*retries\s*=\s*(\d+)/i)       { $retries = $1; }
    elsif (/^\s*user[\w\s]*=\s*(.+)/i)       { $userEmail = &rtrim($1); }
    elsif (/^\s*pass[\w\s]*=\s*(.+)/i)       { $password = &rtrim($1); }
    elsif (/^\s*cache\s*=\s*(.+)/i)          { $cacheDir = &rtrim($1); }
    elsif (/^\s*icon\s*=\s*(.+)/i)           { $iconDir = &rtrim($1); }
    elsif (/^\s*trailer\s*=\s*(.+)/i)        { $trailerDir = &rtrim($1); }
    elsif (/^\s*lang\s*=\s*(.+)/i)           { $lang = &rtrim($1); }
    elsif (/^\s*outfile\s*=\s*(.+)/i)        { $outFile = &rtrim($1); }
    elsif (/^\s*proxy\s*=\s*(.+)/i)          { $proxy = &rtrim($1); }
    elsif (/^\s*outformat\s*=\s*(.+)/i)      { $outputXTVD = 1 if $1 =~ /xtvd/i; }
    elsif (/^\s*lineupid\s*=\s*(.+)/i)       { $lineupId = &rtrim($1); }
    elsif (/^\s*lineupname\s*=\s*(.+)/i)     { $lineupname = &rtrim($1); }
    elsif (/^\s*lineuptype\s*=\s*(.+)/i)     { $lineuptype = &rtrim($1); }
    elsif (/^\s*lineuplocation\s*=\s*(.+)/i) { $lineuplocation = &rtrim($1); }
    elsif (/^\s*postalcode\s*=\s*(.+)/i)     { $postalcode = &rtrim($1); }
    else
    {
      die "Oddline in config file \"$confFile\".\n\t$_";
    }
  }
  close (CONF);
} 
&printHelp() if !(%options) && $userEmail eq '';

$cacheDir = $options{c} if defined $options{c};
$days = $options{d} if defined $options{d};
$ncdays = $options{n} if defined $options{n};
$ncsdays = $options{N} if defined $options{N};
$start = $options{s} if defined $options{s};
$retries = $options{r} if defined $options{r};
$iconDir = $options{i} if defined $options{i};
$trailerDir = $options{t} if defined $options{t};
$lang = $options{l} if defined $options{l};
$outFile = $options{o} if defined $options{o};
$password = $options{p} if defined $options{p};
$userEmail = $options{u} if defined $options{u};
$proxy = $options{P} if defined $options{P};
$outputXTVD = 1 if defined $options{x};
$sleeptime = $options{S} if defined $options{S};

$urlRoot = 'http://tvschedule.zap2it.com/tvlistings/';

$retries = 20 if $retries > 20; # Too many

my %programs = ();
my $cp;
my %stations = ();
my $cs;
my $rcs;
my %schedule = ();
my $sch;

my $tb = 0;
my $treq = 0;
my $expired = 0;
my $inStationTd = 0;
my $inIcons = 0;
my $ua;
my $tba = 0;
my $exp = 0;
my @fh = ();

my $XTVD_startTime;
my $XTVD_endTime;

if (! -d $cacheDir) {
  mkdir($cacheDir) or die "Can't mkdir: $!\n";
} else {
  opendir (DIR, "$cacheDir/");
  @cacheFiles = grep(/\.html|\.js/,readdir(DIR));
  closedir (DIR);
  foreach $cacheFile (@cacheFiles) {
    $fn = "$cacheDir/$cacheFile";
    $atime = (stat($fn))[8];
    if ($atime + ( ($days + 2) * 86400) < time) {
      &pout("Deleting old cached file: $fn\n");
      unlink($fn);
    }
  }
}

my $s1 = time();
$maxCount = $days * 4;
$ncCount = $maxCount - ($ncdays * 4);
$offset = $start * 3600 * 24 * 1000;
$ncsCount = $ncsdays * 4;
$ms = &hourToMillis() + $offset;
for ($count=0; $count < $maxCount; $count++) {
  if ($count == 0) { 
    $XTVD_startTime = $ms;
  } elsif ($count == $maxCount - 1) { 
    $XTVD_endTime = $ms + (6 * 3600000) - 1;
  }

  $fn = "$cacheDir/$ms\.html\.gz";
  if (! -e $fn || $count >= $ncCount || $count < $ncsCount) {
    sleep $sleeptime; # do these rapid requests flood servers?
    $rc = Encode::encode('utf8', &getURL($urlRoot . "ZCGrid.do?isDescriptionOn=true&fromTimeInMillis=$ms") );
    &wbf($fn, Compress::Zlib::memGzip($rc));
  }
  &pout("[" . ($count+1) . "/" . "$maxCount] Parsing: $fn\n");
  &parseGrid($fn);
  if (defined($options{T}) && $tba) {
    &pout("Deleting: $fn (contains \"$sTBA\")\n");
    unlink($fn);
  }
  if ($exp) {
    &pout("Deleting: $fn (expired)\n");
    unlink($fn);
  }
  $exp = 0;
  $tba = 0;
  $ms += (6 * 3600 * 1000);
} 
my $s2 = time();

&pout("Downloaded $tb bytes in $treq http requests.\n") if $tb > 0;
&pout("Expired programs: $expired\n") if $expired > 0;
&pout("Writing XML file: $outFile\n");
open($FH, ">$outFile");
my $enc = 'ISO-8859-1';
if (defined($options{U})) {
  $enc = 'UTF-8';
} 
if ($outputXTVD) {
  &printHeaderXTVD($FH, $enc);
  &printStationsXTVD($FH);
  &printLineupsXTVD($FH);
  &printSchedulesXTVD($FH);
  &printProgramsXTVD($FH);
  &printGenresXTVD($FH);
  &printFooterXTVD($FH);
} else {
  &printHeader($FH, $enc);
  &printChannels($FH);
  &printProgrammes($FH);
  &printFooter($FH);
}
close($FH);

my $ts = 0;
for my $station (keys %stations ) {
  $ts += scalar (keys %{$schedule{$station}})
}
my $s3 = time();
&pout("Completed in " . ( $s3 - $s1 ) . "s (Parse: " . ( $s2 - $s1 ) . "s) " . keys(%stations) . " stations, " . keys(%programs) . " programs, $ts scheduled.\n");

if (defined($options{w})) {
  print "Press ENTER to exit:";
  <STDIN>;
}

exit 0;

sub pout {
  print @_ if !defined $options{q};
}

sub perr {
  warn @_;
}

sub rtrim {
  my $s = shift;
  $s =~ s/\s+$//;
  return $s;
}

sub trim {
  my $s = shift;
  $s =~ s/^\s+//;
  $s =~ s/\s+$//;
  return $s;
}

sub _rtrim3 {
  my $s = shift;
  return substr($s, 0, length($s)-3);
}

sub convTime {
  return strftime "%Y%m%d%H%M%S", localtime(&_rtrim3(shift));
}

sub convTimeXTVD {
  return strftime "%Y-%m-%dT%H:%M:%SZ", gmtime(&_rtrim3(shift));
}

sub convDateLocal {
  return strftime "%Y%m%d", localtime(&_rtrim3(shift));
}

sub convDateLocalXTVD {
  return strftime "%Y-%m-%d", localtime(&_rtrim3(shift));
}

sub convDurationXTVD {
  my $duration = shift; 
  $hour = int($duration / 3600000);
  $minutes = int(($duration - ($hour * 3600000)) / 60000);
  return sprintf("PT%02dH%02dM", $hour, $minutes);
}

sub appendAsterisk {
  my ($title, $station, $s) = @_;
  if (defined($options{A})) {
    if (($options{A} =~ "new" && defined($schedule{$station}{$s}{new}))
      || ($options{A} =~ "live" && defined($schedule{$station}{$s}{live}))) {
      $title .= " *";
    }
  }
  return $title;
}

sub stationToChannel {
  my $s = shift;
  if (defined($options{O})) {
    return sprintf("C%s%s.zap2it.com",$stations{$s}{number},lc($stations{$s}{name}));
  }
  return sprintf("I%s.labs.zap2it.com", $stations{$s}{stnNum});
}

sub sortChan {
  $stations{$a}{number} - $stations{$b}{number};
}

sub enc {
  my $t = shift;
  if (!defined($options{U})) {$t = Encode::decode('utf8', $t);}
  if (!defined($options{E}) || $options{E} =~ /amp/) {$t =~ s/&/&amp;/gs;}
  if (!defined($options{E}) || $options{E} =~ /quot/) {$t =~ s/"/&quot;/gs;}
  if (!defined($options{E}) || $options{E} =~ /apos/) {$t =~ s/'/&apos;/gs;}
  if (!defined($options{E}) || $options{E} =~ /lt/) {$t =~ s/</&lt;/gs;}
  if (!defined($options{E}) || $options{E} =~ /gt/) {$t =~ s/>/&gt;/gs;}
  if (defined($options{e})) {
    $t =~ s/([^\x20-\x7F])/'&#' . ord($1) . ';'/gse;
  }
  return $t;
}

sub printHeader {
  my ($FH, $enc) = @_;
  print $FH "<?xml version=\"1.0\" encoding=\"$enc\"?>\n";
  print $FH "<!DOCTYPE tv SYSTEM \"xmltv.dtd\">\n\n";
  print $FH "<tv source-info-url=\"http://tvschedule.zap2it.com/\" source-info-name=\"zap2it.com\" generator-info-name=\"zap2xml\" generator-info-url=\"zap2xml\@gmail.com\">\n";
}

sub printFooter {
  my $FH = shift;
  print $FH "</tv>\n";
} 

sub printChannels {
  my $FH = shift;
  for my $key ( sort sortChan keys %stations ) {
    $sname = &enc($stations{$key}{name});
    $snum = $stations{$key}{number};
    print $FH "\t<channel id=\"" . &stationToChannel($key) . "\">\n";
    print $FH "\t\t<display-name>" . $sname . "</display-name>\n" if defined($options{F}) && defined($sname);
    if (defined($snum)) {
      &copyLogo($key);
      print $FH "\t\t<display-name>" . $snum . " " . $sname . "</display-name>\n";
      print $FH "\t\t<display-name>" . $snum . "</display-name>\n";
    }
    print $FH "\t\t<display-name>" . $sname . "</display-name>\n" if !defined($options{F}) && defined($sname);
    print $FH "\t</channel>\n";
  }
}

sub printProgrammes {
  my $FH = shift;
  for my $station ( sort sortChan keys %stations ) {
    my $i = 0; 
    my @keyArray = sort { $schedule{$station}{$a}{time} cmp $schedule{$station}{$b}{time} } keys %{$schedule{$station}};
    foreach $s (@keyArray) {
      if ($#keyArray <= $i) {
        delete $schedule{$station}{$s};
        next; 
      } 
      my $p = $schedule{$station}{$s}{program};
      my $startTime = &convTime($schedule{$station}{$s}{time});
      my $startTZ = &timezone($schedule{$station}{$s}{time});
      my $stopTime = &convTime($schedule{$station}{$keyArray[$i+1]}{time});
      my $stopTZ = &timezone($schedule{$station}{$keyArray[$i+1]}{time});

      print $FH "\t<programme start=\"$startTime $startTZ\" stop=\"$stopTime $stopTZ\" channel=\"" . &stationToChannel($schedule{$station}{$s}{station}) . "\">\n";
      if (defined($programs{$p}{title})) {
        my $title = &enc($programs{$p}{title});
        $title = &appendAsterisk($title, $station, $s);
        print $FH "\t\t<title lang=\"$lang\">" . $title . "</title>\n";
      } 
      print $FH "\t\t<sub-title lang=\"$lang\">" . &enc($programs{$p}{episode}) . "</sub-title>\n" if defined($programs{$p}{episode});
      print $FH "\t\t<desc lang=\"$lang\">" . &enc($programs{$p}{description}) . "</desc>\n" if defined($programs{$p}{description});

      if (defined($programs{$p}{credits})) {
        print $FH "\t\t<credits>\n";
        foreach my $g (sort { $programs{$p}{credits}{$a} <=> $programs{$p}{credits}{$b} } keys %{$programs{$p}{credits}} ) {
          print $FH "\t\t\t<actor>" . &enc($g) . "</actor>\n";
        }
        print $FH "\t\t</credits>\n";
      }
  
      my $date;
      if (defined($programs{$p}{movie_year})) {
        $date = $programs{$p}{movie_year};
      } elsif ($p =~ /^EP/ && defined($programs{$p}{originalAirDate})) {
        $date = &convDateLocal($programs{$p}{originalAirDate});
      }

      print $FH "\t\t<date>$date</date>\n" if defined($date);
      if (defined($programs{$p}{genres})) {
        foreach my $g (sort { $programs{$p}{genres}{$a} <=> $programs{$p}{genres}{$b} } keys %{$programs{$p}{genres}} ) {
          print $FH "\t\t<category lang=\"$lang\">" . &enc(ucfirst($g)) . "</category>\n";
        }
      }

      if (defined($programs{$p}{imageUrl})) {
        print $FH "\t\t<icon src=\"" . $programs{$p}{imageUrl} . "\" />\n";
      }

      my $xs;
      my $xe;

      if (defined($programs{$p}{seasonNum}) && defined($programs{$p}{episodeNum})) {
        my $s = $programs{$p}{seasonNum};
        my $sf = sprintf("S%0*d", &max(2, length($s)), $s);
        my $e = $programs{$p}{episodeNum};
        my $ef = sprintf("E%0*d", &max(2, length($e)), $e);

        $xs = int($s) - 1;
        $xe = int($e) - 1;

        if ($s > 0 || $e > 0) {
          print $FH "\t\t<episode-num system=\"common\">" . $sf . $ef . "</episode-num>\n";
        }
      }

      $dd_prog_id = $p;
      if ( $dd_prog_id =~ /^(..\d{8})(\d{4})/ ) {
        $dd_prog_id = sprintf("%s.%s",$1,$2);
        print $FH "\t\t<episode-num system=\"dd_progid\">" . $dd_prog_id  . "</episode-num>\n";
      }

      if (defined($xs) && defined($xe) && $xs >= 0 && $xe >= 0) {
        print $FH "\t\t<episode-num system=\"xmltv_ns\">" . $xs . "." . $xe . ".</episode-num>\n";
      }

      if (defined($schedule{$station}{$s}{quality})) {
        print $FH "\t\t<video>\n";
        print $FH "\t\t\t<aspect>16:9</aspect>\n";
        print $FH "\t\t\t<quality>HDTV</quality>\n";
        print $FH "\t\t</video>\n";
      }
      my $new = defined($schedule{$station}{$s}{new});
      my $live = defined($schedule{$station}{$s}{live});
      my $cc = defined($schedule{$station}{$s}{cc});

      print $FH "\t\t<new />\n" if $new;
      # not part of XMLTV format yet?
      print $FH "\t\t<live />\n" if (defined($options{L}) && $live);
      print $FH "\t\t<subtitles type=\"teletext\" />\n" if $cc;

      if (! $new && ! $live && $p =~ /^EP|^SH/) {
        print $FH "\t\t<previously-shown ";
        if (defined($programs{$p}{originalAirDate})) {
          $date = &convDateLocal($programs{$p}{originalAirDate});
          print $FH "start=\"" . $date . "000000\" ";
        }
        print $FH "/>\n";
      }

      if (defined($programs{$p}{starRating})) {
        print $FH "\t\t<star-rating>\n\t\t\t<value>" . $programs{$p}{starRating} . "/4</value>\n\t\t</star-rating>\n";
      }
      print $FH "\t</programme>\n";
      $i++;
    }
  }
}

sub printHeaderXTVD {
  my ($FH, $enc) = @_;
  print $FH "<?xml version='1.0' encoding='$enc'?>\n";
  print $FH "<xtvd from='" . &convTimeXTVD($XTVD_startTime) . "' to='" . &convTimeXTVD($XTVD_endTime)  . "' schemaVersion='1.3' xmlns='urn:TMSWebServices' xmlns:xsi='http://www.w3.org/2001/XMLSchema-instance' xsi:schemaLocation='urn:TMSWebServices http://docs.tms.tribune.com/tech/xml/schemas/tmsxtvd.xsd'>\n";
}

sub printFooterXTVD {
  my $FH = shift;
  print $FH "</xtvd>\n";
} 

sub printStationsXTVD {
  my $FH = shift;
  print $FH "<stations>\n";
  for my $key ( sort sortChan keys %stations ) {
    print $FH "\t<station id='" . $stations{$key}{stnNum} . "'>\n";
    if (defined($stations{$key}{number})) {
      $sname = &enc($stations{$key}{name});
      print $FH "\t\t<callSign>" . $sname . "</callSign>\n";
      print $FH "\t\t<name>" . $sname . "</name>\n";
      print $FH "\t\t<fccChannelNumber>" . $stations{$key}{number} . "</fccChannelNumber>\n";
      if (defined($stations{$key}{logo}) && $stations{$key}{logo} =~ /_affiliate/i) {
        $affiliate = $stations{$key}{logo};
        $affiliate =~ s/(.*)\_.*/uc($1)/e;
        print $FH "\t\t<affiliate>" . $affiliate . " Affiliate</affiliate>\n";
      }
      &copyLogo($key);
    }
    print $FH "\t</station>\n";
  }
  print $FH "</stations>\n";
}

sub printLineupsXTVD {
  my $FH = shift;
  print $FH "<lineups>\n";
  print $FH "\t<lineup id='$lineupId' name='$lineupname' location='$lineuplocation' type='$lineuptype' postalCode='$postalcode'>\n";
  for my $key ( sort sortChan keys %stations ) {
    if (defined($stations{$key}{number})) {
      print $FH "\t<map station='" . $stations{$key}{stnNum} . "' channel='" . $stations{$key}{number} . "'></map>\n";
    }
  }
  print $FH "\t</lineup>\n";
  print $FH "</lineups>\n";
}

sub printSchedulesXTVD {
  my $FH = shift;
  print $FH "<schedules>\n";
  for my $station ( sort sortChan keys %stations ) {
    my $i = 0; 
    my @keyArray = sort { $schedule{$station}{$a}{time} cmp $schedule{$station}{$b}{time} } keys %{$schedule{$station}};
    foreach $s (@keyArray) {
      if ($#keyArray <= $i) {
        delete $schedule{$station}{$s};
        next; 
      } 
      my $p = $schedule{$station}{$s}{program};
      my $startTime = &convTimeXTVD($schedule{$station}{$s}{time});
      my $stopTime = &convTimeXTVD($schedule{$station}{$keyArray[$i+1]}{time});
      my $duration = &convDurationXTVD($schedule{$station}{$keyArray[$i+1]}{time} - $schedule{$station}{$s}{time});

      print $FH "\t<schedule program='$p' station='" . $stations{$station}{stnNum} . "' time='$startTime' duration='$duration'"; 
      print $FH " hdtv='true' " if (defined($schedule{$station}{$s}{quality}));
      print $FH " new='true' " if (defined($schedule{$station}{$s}{new}) || defined($schedule{$station}{$s}{live}));
      print $FH "/>\n";
      $i++;
    }
  }
  print $FH "</schedules>\n";
}

sub printProgramsXTVD {
  my $FH = shift;
  print $FH "<programs>\n";
  foreach $p (keys %programs) {
      print $FH "\t<program id='" . $p . "'>\n";
      print $FH "\t\t<title>" . &enc($programs{$p}{title}) . "</title>\n" if defined($programs{$p}{title});
      print $FH "\t\t<subtitle>" . &enc($programs{$p}{episode}) . "</subtitle>\n" if defined($programs{$p}{episode});
      print $FH "\t\t<description>" . &enc($programs{$p}{description}) . "</description>\n" if defined($programs{$p}{description});
      
      if (defined($programs{$p}{movie_year})) {
        print $FH "\t\t<year>" . $programs{$p}{movie_year} . "</year>\n";
      } else { #Guess
        my $showType = "Series"; 
        if ($programs{$p}{title} =~ /Paid Programming/i) {
          $showType = "Paid Programming";
        } 
        print $FH "\t\t<showType>$showType</showType>\n"; 
        print $FH "\t\t<series>EP" . substr($p,2,8) . "</series>\n"; 
        print $FH "\t\t<originalAirDate>" . &convDateLocalXTVD($programs{$p}{originalAirDate}) . "</originalAirDate>\n" if defined($programs{$p}{originalAirDate});
      }
      print $FH "\t</program>\n";
  }
  print $FH "</programs>\n";
}

sub printGenresXTVD {
  my $FH = shift;
  print $FH "<genres>\n";
  foreach $p (keys %programs) {
    if (defined($programs{$p}{genres}) && $programs{$p}{genres}{movie} != 1) {
      print $FH "\t<programGenre program='" . $p . "'>\n";
      foreach my $g (keys %{$programs{$p}{genres}}) {
        print $FH "\t\t<genre>\n";
        print $FH "\t\t\t<class>" . &enc(ucfirst($g)) . "</class>\n";
        print $FH "\t\t\t<relevance>0</relevance>\n";
        print $FH "\t\t</genre>\n";
      }
      print $FH "\t</programGenre>\n";
    }
  }
  print $FH "</genres>\n";
}

sub login {
  if (!defined($userEmail) || $userEmail eq '' || !defined($password) || $password eq '') {
    die "Unable to login: Unspecified username or password.\n" 
  }
  &pout("Logging in as \"$userEmail\"\n");
  if (!defined($ua)) {
    $ua = new LWP::UserAgent; 
    $ua->cookie_jar(HTTP::Cookies->new);
    $ua->proxy('http', $proxy) if defined($proxy);
    $ua->agent('Mozilla/4.0');
    $ua->default_headers->push_header('Accept-Encoding' => 'gzip, deflate');
  }

  my $rc = 0;
  while ($rc++ < $retries) {
    my $r = $ua->post($urlRoot . 'ZCLogin.do', 
      { 
        username => $userEmail, 
        password => $password,
        xhr => 'true', # xml
      }
    ); 
  
    $dc = Encode::encode('utf8', $r->decoded_content);
    if ($dc =~ /success,$userEmail/) {
      return $dc; 
    } else {
      &pout("[Attempt $rc] " . $dc);
    }
  }
  die "Failed to login within $retries retries.\n";
}

sub getURL {
  my $url = shift;
  if (!defined($ua)) {
    &login();
  }

  my $rc = 0;
  while ($rc++ < $retries) {
    &pout("Getting: $url\n");
    $treq++;
    my $r = $ua->get($url);
    if ($r->is_success) {
      $tb += length($r->content);
      return $r->decoded_content;
    } else {
      &perr("[Attempt $rc] " . $r->status_line);
    }
  }
  die "Failed to download within $retries retries.\n";
}

sub wbf {
  my($f, $s) = @_;
  open(FO, ">$f");
  binmode(FO);
  print FO $s;
  close(FO);
}

sub copyLogo {
  my $key = shift;
  if (defined($iconDir) && defined($stations{$key}{logo})) {
    my $num = $stations{$key}{number};
    my $src = "$iconDir/" . $stations{$key}{logo} . $stations{$key}{logoExt};
    my $dest1 = "$iconDir/$num" . $stations{$key}{logoExt};
    my $dest2 = "$iconDir/$num " . $stations{$key}{name} . $stations{$key}{logoExt};
    copy($src, $dest1);
    copy($src, $dest2);
  }
}

sub handleLogo {
  my $url = shift;
  if (! -d $iconDir) {
    mkdir($iconDir) or die "Can't mkdir: $!\n";
  }
  ($n,$_,$s) = fileparse($url, qr"\..*");
  $stations{$cs}{logo} = $n;
  $stations{$cs}{logoExt} = $s;
  $f = $iconDir . "/" . $n . $s;
  if (! -e $f) { &wbf($f, &getURL($url)); }
}

sub setOriginalAirDate {
  if (substr($cp,10,4) ne '0000') {
    if (!defined($programs{$cp}{originalAirDate})
        || ($schedule{$cs}{$sch}{time} < $programs{$cp}{originalAirDate})) {
      $programs{$cp}{originalAirDate} = $schedule{$cs}{$sch}{time};
    }
  }
}

sub on_th {
  my($self, $tag, $attr) = @_;
  if (defined($attr->{class})) {
    if ($attr->{class} =~ /zc-st/) {
      $inStationTd = 1;
    }
  } 
}

sub on_td {
  my($self, $tag, $attr) = @_;
  if (defined($attr->{class})) {
    if ($attr->{class} =~ /zc-pg/) {
      if (defined($attr->{onclick})) {
        $cs = $rcs;
        $oc = $attr->{onclick};
        $oc =~ s/.*\((.*)\).*/$1/s;
        @a = split(/,/, $oc);
        $cp = $a[1];
        $cp =~ s/'//g;
        $sch = $a[2];
        if (length($cp) == 0) {
          $cp = $cs = $sch = -1;
          $expired++;
          $exp = 1;
        }
        $schedule{$cs}{$sch}{time} = $sch;
        $schedule{$cs}{$sch}{program} = $cp;
        $schedule{$cs}{$sch}{station} = $cs;

        if ($attr->{class} =~ /zc-g-C/) { $programs{$cp}{genres}{children} = 1 }
        elsif ($attr->{class} =~ /zc-g-N/) { $programs{$cp}{genres}{news} = 1 }
        elsif ($attr->{class} =~ /zc-g-M/) { $programs{$cp}{genres}{movie} = 1 }
        elsif ($attr->{class} =~ /zc-g-S/) { $programs{$cp}{genres}{sports} = 1 }

        if (defined $options{D}) {
          my $fn = "$cacheDir/$cp\.js\.gz";
          if (! -e $fn) {
            sleep $sleeptime; # do these rapid requests flood servers?
            $rc = Encode::encode('utf8', &getURL($urlRoot . "gridDetailService?pgmId=$cp") );
            &wbf($fn, Compress::Zlib::memGzip($rc));
          }
          &pout("[D] Parsing: $cp\n");
          &parseJSOND($fn);
        }
        if (defined $options{I}) {
          my $fn = "$cacheDir/I$cp\.js\.gz";
          if (! -e $fn) {
            sleep $sleeptime; # do these rapid requests flood servers?
            $rc = Encode::encode('utf8', &getURL($urlRoot . "gridDetailService?rtype=pgmimg&pgmId=$cp") );
            &wbf($fn, Compress::Zlib::memGzip($rc));
          }
          &pout("[I] Parsing: $cp\n");
          &parseJSONI($fn);
        }
      }
    } elsif ($attr->{class} =~ /zc-st/) {
      $inStationTd = 1;
    }
  } 
}

sub handleTags {
  my $text = shift;
  if ($text =~ /LIVE/) {
    $schedule{$cs}{$sch}{live} = 'Live';
    &setOriginalAirDate();
  } elsif ($text =~ /HD/) {
    $schedule{$cs}{$sch}{quality} = 'HD';
  } elsif ($text =~ /NEW/) {
    $schedule{$cs}{$sch}{new} = 'New';
    &setOriginalAirDate();
  }
}

sub on_li {
  my($self, $tag, $attr) = @_;
  if ($attr->{class} =~ /zc-ic-ne/) {
      $schedule{$cs}{$sch}{new} = 'New';
      &setOriginalAirDate();
  } elsif ($attr->{class} =~ /zc-ic-cc/) {
      $schedule{$cs}{$sch}{cc} = 'CC';
  } elsif ($attr->{class} =~ /zc-ic/) { 
    $self->handler(text => sub { &handleTags(shift); }, "dtext");
  } elsif ($attr->{class} =~ /zc-icons-live/) {
      $schedule{$cs}{$sch}{live} = 'Live';
      &setOriginalAirDate();
  } elsif ($attr->{class} =~ /zc-icons-hd/) {
      $schedule{$cs}{$sch}{quality} = 'HD';
  }
}

sub on_img {
  my($self, $tag, $attr) = @_;
  if ($inIcons) {
    if ($attr->{alt} =~ /Live/) {
      $schedule{$cs}{$sch}{live} = 'Live';
      &setOriginalAirDate();
    } elsif ($attr->{alt} =~ /New/) {
      $schedule{$cs}{$sch}{new} = 'New';
      &setOriginalAirDate();
    } elsif ($attr->{alt} =~ /HD/ || $attr->{alt} =~ /High Definition/ 
      || $attr->{src} =~ /video-hd/ || $attr->{src} =~ /video-ahd/) {
      $schedule{$cs}{$sch}{quality} = 'HD';
    } 
  } elsif ($inStationTd && $attr->{alt} =~ /Logo/) {
    &handleLogo($attr->{src}) if defined($iconDir);
  }
}

sub on_a {
  my($self, $tag, $attr) = @_;
  if ($attr->{class} =~ /zc-pg-t/) {
    $self->handler(text => sub { $programs{$cp}{title} = (shift); $tba = 1 if $programs{$cp}{title} =~ /$sTBA/i;}, "dtext");
  } elsif ($inStationTd) {
    my $tcs = $attr->{href};
    $tcs =~ s/.*stnNum=(\w+).*/$1/;
    if (! ($tcs =~ /stnNum/)) {
      $cs = $rcs = $tcs;
    }
    if (!defined($stations{$cs}{stnNum})) {
      $stations{$cs}{stnNum} = $cs;
    }
    if (!defined($stations{$cs}{number})) {
      my $tnum = uri_unescape($attr->{href});
      $tnum =~ s/\s//gs;
      $tnum =~ s/.*channel=([.\w]+).*/$1/;
      $stations{$cs}{number} = $tnum if ! ($tnum =~ /channel=/);
    }
    if (!defined($postalcode) && $attr->{href} =~ /zipcode/) {
      $postalcode = $attr->{href};
      $postalcode =~ s/.*zipcode=(\w+).*/$1/;
    }
    if (!defined($lineupId) && $attr->{href} =~ /lineup/) {
      $lineupId = $attr->{href};
      $lineupId =~ s/.*lineupId=(.*?)&.*/uri_unescape($1)/e;
    }
  }
}

sub on_p {
  my($self, $tag, $attr) = @_;
  if (defined($attr->{class}) && ($attr->{class} =~ /zc-pg-d/)) {
    $self->handler(text => sub { $d = &trim(shift); $programs{$cp}{description} = $d if length($d) }, "dtext");
  }
}

sub on_div {
  my($self, $tag, $attr) = @_;
  if (defined($attr->{class}) && ($attr->{class} =~ /zc-icons/)) {
    $inIcons = 1;
  }
}

sub on_span {
  my($self, $tag, $attr) = @_;
  if (defined($attr->{class})) {
    if ($attr->{class} =~ /zc-pg-y/) {
      $self->handler(text => sub { $y = shift; $y =~ s/[^\d]//gs; $programs{$cp}{movie_year} = $y }, "dtext");
    } elsif ($attr->{class} =~ /zc-pg-e/) {
      $self->handler(text => sub { $programs{$cp}{episode} = shift; }, "dtext");
    } elsif ($attr->{class} =~ /zc-st-c/) {
      $self->handler(text => sub { $stations{$cs}{name} = &trim(shift) }, "dtext");
    } elsif ($attr->{class} =~ /zc-ic-s/) {
      $self->handler(text => sub { &handleTags(shift); }, "dtext");
    } elsif ($attr->{class} =~ /zc-pg-t/) {
      $self->handler(text => sub { $programs{$cp}{title} = (shift); $tba = 1 if $programs{$cp}{title} =~ /$sTBA/i;}, "dtext");
    }
  }
  if (defined($attr->{id})) {
    if ($attr->{id} =~ /zc-topbar-provider-name/) {
      $self->handler(text => sub { 
        $n = $l = $t = shift;
        $n =~ s/(.*)\-.*/&trim($1)/es;
        $l =~ s/.*\(\s*(.*)\s*\).*/&trim($1)/es;
        $t =~ s/.*\-(.*)\(.*/&trim($1)/es;

        if (!defined($lineuptype)) {
          if ($t =~ /satellite/i) { $lineuptype = "Satellite"; }
          elsif ($t =~ /digital/i) { $lineuptype = "CableDigital"; }
          elsif ($t =~ /cable/i) { $lineuptype = "Cable"; }
          else { $lineuptype = "LocalBroadcast"; }
        }
        $lineupname = $n if !defined($lineupname);
        $lineuplocation = $l if !defined($lineuplocation);

      }, "dtext");
    }
  }
}

sub handler_start {
  my($self, $tag, $attr) = @_;
  $f = "on_$tag";
  &$f(@_);
}

sub handler_end {
  my ($self, $tag) = @_;
  if ($tag eq 'td' || $tag eq 'th') { $inStationTd = 0; } 
  elsif ($tag eq 'div') { $inIcons = 0; }
  $self->handler(text => undef);
}

sub parseJSONI {
  my $gz = gzopen(shift, "rb");
  my $json = new JSON;
  my $buffer;
  $buffer .= $b while $gz->gzread($b, 65535) > 0;
  $gz->gzclose();
  $buffer =~ s/'/"/g;
  my $t = decode_json($buffer);
  if (defined($t->{imageUrl}) && $t->{imageUrl} =~ /^http/) {
    $programs{$cp}{imageUrl} = $t->{imageUrl}
  }
}

sub parseJSOND {
  my $gz = gzopen(shift, "rb");
  my $json = new JSON;
  my $buffer;
  $buffer .= $b while $gz->gzread($b, 65535) > 0;
  $gz->gzclose();
  $buffer =~ s/^.+?\=\ //gim;
  my $t = decode_json($buffer);
  my $p = $t->{'program'};

  if (defined($p->{'seasonNumber'})) {
    my $sn = $p->{'seasonNumber'};
    $sn =~ s/S//i;
    $programs{$cp}{seasonNum} = $sn if ($sn ne '');
  }
  if (defined($p->{'episodeNumber'})) {
    my $en = $p->{'episodeNumber'};
    $en =~ s/E//i;
    $programs{$cp}{episodeNum} = $en if ($en ne '');
  }
  if (defined($p->{'originalAirDate'})) {
    my $oad = $p->{'originalAirDate'};
    $programs{$cp}{originalAirDate} = $oad if ($oad ne '');
  }
  if (defined($p->{'description'})) {
    my $desc = $p->{'description'};
    $programs{$cp}{description} = $desc if ($desc ne '');
  }
  if (defined($p->{'genres'})) {
    my $genres = $p->{'genres'};
    my $i = 1;
    foreach $g (@{$genres}) {
      ${$programs{$cp}{genres}}{lc($g)} = $i++;
    }
  }
  if (defined($p->{'credits'})) {
    my $credits = $p->{'credits'};
    my $i = 1;
    foreach $g (@{$credits}) {
      ${$programs{$cp}{credits}}{$g} = $i++;
    }
  }
  if (defined($p->{'starRating'})) {
    my $sr = $p->{'starRating'};
    my $tsr = length($sr);
    if ($sr =~ /\+$/) {
      $tsr = $tsr - 1;
      $tsr .= ".5";
     } 
    $programs{$cp}{starRating} = $tsr;
  }
}

sub parseGrid {
  my @report_tags = qw(td th span a p div img li);
  my $p = HTML::Parser->new(
    api_version => 3,
    unbroken_text => 1,
    report_tags => \@report_tags,
    handlers  => [
      start => [\&handler_start, "self, tagname, attr"],
      end => [\&handler_end, "self, tagname"],
    ],
  );
  
  my $gz = gzopen(shift, "rb");
  $p->parse($b) while $gz->gzread($b, 65535) > 0;
  $gz->gzclose();
  $p->eof;
}

sub hourToMillis {
  ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
  $t = timegm(0,0,0,$mday,$mon,$year);
  $t = $t - (&tz_offset * 3600) if !defined($options{g});
  ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = gmtime($t);
  $t = timegm($sec, $min, $hour,$mday,$mon,$year);
  return $t . "000";
}

sub tz_offset {
  my $n = defined $_[0] ? $_[0] : time;
  my ($lm, $lh, $ly, $lyd) = (localtime $n)[1, 2, 5, 7];
  my ($gm, $gh, $gy, $gyd) = (gmtime $n)[1, 2, 5, 7];
  ($lm - $gm)/60 + $lh - $gh + 24 * ($ly - $gy || $lyd - $gyd)
}

sub timezone {
  my $tztime = defined $_[0] ? &_rtrim3(shift) : time; 
  my $os = sprintf "%.1f", (timegm(localtime($tztime)) - $tztime) / 3600;
  my $mins = sprintf "%02d", abs( $os - int($os) ) * 60;
  return sprintf("%+03d", int($os)) . $mins;
}

sub max ($$) { $_[$_[0] < $_[1]] }
sub min ($$) { $_[$_[0] > $_[1]] }

sub printHelp {
print <<END;
zap2xml <zap2xml\@gmail.com> (2015-07-22)
  -u <username>
  -p <password>
  -d <# of days> (default = $days)
  -n <# of no-cache days> (from end)   (default = $ncdays)
  -N <# of no-cache days> (from start) (default = $ncsdays)
  -s <start day offset> (default = $start)
  -o <output xml filename> (default = "$outFile")
  -c <cacheDirectory> (default = "$cacheDir")
  -l <lang> (default = "$lang")
  -x = output XTVD xml file format (default = XMLTV)
  -g = use GMT when retrieving data
  -q = quiet (no status output)
  -r <# of connection retries before failure> (default = $retries, max 20)
  -e = hex encode entities (html special characters like accents)
  -E "amp apos quot lt gt" = selectively encode standard XML entities
  -F = output channel names first (rather than "number name")
  -O = use old tv_grab_na style channel ids (C###nnnn.zap2it.com)
  -A "new live" = append " *" to program titles that are "new" and/or "live"
  -U = UTF-8 encoding (default = "ISO-8859-1")
  -L = output "<live />" tag (not part of xmltv.dtd)
  -T = don't cache files containing programs with "$sTBA" titles 
  -P <http://proxyhost:port> = to use an http proxy
  -C <configuration file> (default = "$confFile")
  -D = include details (season/episode) = 1 extra http request per program!
  -I = include icons (image URLs) - 1 extra http request per program!
END
exit 0;
}
