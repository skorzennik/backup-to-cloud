#
# <- Last updated: Fri Mar 24 18:13:15 2023 -> SGK
#
# &ReadConfig($SCRIPT, \@ARGV, \%defOpts, \%ignOpts);
# %opts = &ParseArgs($SCRIPT, \@ARGV, \%defOpts, \%defOptions);
# &ValidateOpts($SCRIPT, \%opts)
# $ok = CheckIfNumber($val)
#
# (c) 2021-2023 - Sylvain G. Korzennik, Smithsonian Institution
# 
# ---------------------------------------------------------------------------
#
use strict;
use Cwd;
use Net::Domain qw(hostname hostdomain);
#
# ---------------------------------------------------------------------------
#
# read config file
sub ReadConfig {
  #
  my $SCRIPT =   $_[0];
  my @argv   = @{$_[1]};
  my $p2opts =   $_[2];
  my $p2ign  =   $_[3];
  #
  my $verbose    = 0;
  my $mustExist  = 0;
  my $configFile = $$p2opts{RCFILE};
  #
  # parse -v|--verbose -rc|--config-file FILENAME
  while ($#argv > -1) {
    my $arg = shift(@argv);
    if ($arg eq '-v' ||
        $arg eq '--verbose') {
      $verbose = 1;
    } elsif ($arg eq '-rc' ||
             $arg eq '--config-file') {
      if ($#argv > -1) {
        $configFile = shift(@argv);
        $mustExist = 1;
      }
    }
  }
  #
  # is there  a config file
  if (-e $configFile) {
    if ($verbose) {
      print STDERR "$SCRIPT: using configuration file '$configFile'\n";
    }
    #
    # read it
    my @lines = GetFileContent($configFile);
    my $nErrors = 0;
    #
    # parse it
    my $i = 0;
    foreach my $lineX (@lines) {
      my $line = $lineX;
      $i++;
      #
      # remove leading blanks and anything after #
      $line =~ s/^ *//;
      $line =~ s/#.*//;
      #
      if ($line) {
        my ($key, $value) = split(' ', $line, 2);
        #
        # valid
        if ($$p2opts{$key} && $value ne '' && $key ne 'RCFILE') {
          #
          # no validation on $value, caveat empror
          $$p2opts{$key} = $value;
          #
        } elsif ($$p2ign{$key}) {
          #
          if ($verbose) {
            print STDERR "$SCRIPT: ignoring '$key = $value' entry in configuration file '$configFile'\n";
          }
          #
        } else {
          print STDERR "$SCRIPT: invalid line in configuration file '$configFile'\n";
          print STDERR " at line $i: $lineX\n";
          $nErrors++;
        }
      }
    }
    #
    # any errors?
    if ($nErrors) {
      my $s = '';
      if ($nErrors > 1 ) { $s = 's'; }
      die "$SCRIPT: $nErrors error$s in configuration file.\n";
    }
  } elsif ($mustExist) {
    die "$SCRIPT: configuration file $configFile not found.\n";
  }
}
#
# ---------------------------------------------------------------------------
#
# parse arguments
sub ParseArgs {
  #
  my $SCRIPT =   $_[0];
  my @argv   = @{$_[1]};
  my %opts   = %{$_[2]};
  my @HELP   = @{$_[3]};
  my @clouds = qw(aws:glacier aws:s3_glacier aws:s3_freezer aws:s3_standard
                  az:archive az:cool az:hot
                  rclone:.* ldisk:.*);
  my @compressions = qw(none gzip bzip2 lz4);
  my @sortings     = qw(size name time none);
  my @finds        = qw(xcp find);
  #
  my %validClouds;
  my %validCompress;
  my %validSortBy; 
  my %validFind; 
  #
  my $key;
  foreach $key (@clouds)       { $validClouds{$key}   = 1;   }
  foreach $key (@compressions) { $validCompress{$key} = 1; }
  foreach $key (@sortings)     { $validSortBy{$key}   = 1;  }
  foreach $key (@finds)        { $validFind{$key}     = 1;  }
  #
  # set host/author tags/metadata if not set in %defOptions() or config file
  if(defined $opts{TAG_HOST}) {
    if ($opts{TAG_HOST}   eq '-') { $opts{TAG_HOST} = hostname(); }
  }
  if (defined $opts{TAG_AUTHOR}) {
    if ($opts{TAG_AUTHOR} eq '-') { 
      my $username = $ENV{LOGNAME} || $ENV{USER} || getpwuid($<);
      $opts{TAG_AUTHOR} = $username.'@'.hostdomain(); 
    }
  }
  #
  my $arg;
  my %argvUsed = ();
  #
  $opts{STATUS} = 1;
  #
  # loop on the arguments
  while ($#argv > -1) {
    $arg = shift(@argv);
    #
    if (defined $argvUsed{$arg}) { 
      print STDERR "$SCRIPT: error - cannot repeat argument '$arg'\n";
      print STDERR "  use -h|--help for help\n\n";
      return %opts;
    }
    #
    $argvUsed{$arg}++;
    if ($arg eq '--n-threads') {
      if ($#argv == -1) { goto MISSINGARG; } $arg = shift(@argv);
      if (CheckIfNumber($arg) == 1) {
        $opts{NTHREADS} = $arg;
      } else {
        print STDERR "$SCRIPT: invalid --n-threads specification: '$arg' is not a number\n";
        return %opts;
      }
    } elsif ($arg eq '--level') {
      if ($#argv == -1) { goto MISSINGARG; } $arg = shift(@argv);
      if (CheckIfNumber($arg) == 1) {
        $opts{LEVEL} = $arg;
      } else {
        print STDERR "$SCRIPT: invalid --level specification: '$arg' is not a number\n";
        return %opts;
      }
      #
    } elsif ($arg eq '--label') {
      if ($#argv == -1) { goto MISSINGARG; } $arg = shift(@argv);
      # convert to lower case
      $opts{LABEL} = lc($arg);
      #
    } elsif ($arg eq '--max-size') {
      if ($#argv == -1) { goto MISSINGARG; } $arg = shift(@argv);
      # no validation of string
      $opts{MAXSIZE}= $arg;
      #      
    } elsif ($arg eq '--max-count') {
      if ($#argv == -1) { goto MISSINGARG; } $arg = shift(@argv);
      if (CheckIfNumber($arg) == 1) {
        $opts{MAXCOUNT}= $arg;
      } else {
        print STDERR "$SCRIPT: invalid --max-count specification: '$arg' is not a numeb\n";
        return %opts;
      }
      #      
    } elsif ($arg eq '--scratch') {
      if ($#argv == -1) { goto MISSINGARG; } $arg = shift(@argv);
      if ( -d $arg) {
        $opts{SCRATCH} = $arg;
      } else {
        print STDERR "$SCRIPT: invalid --scratch argument, '$arg' is not a directory\n";
        return %opts;
      }
      #
    } elsif ($arg eq '--base-dir') {
      if ($#argv == -1) { goto MISSINGARG; } $arg = shift(@argv);
      # strip leading /
      if ($arg !~ /^\//) { $arg = '/'.$arg; }
      if ( -d $arg) {
        $opts{BASEDIR} = $arg;
      } else {
        print STDERR "$SCRIPT: invalid ---base-dir, '$arg' is not a directory\n";
        return %opts;
      }
       #
    } elsif ($arg eq '--extra-sleep') {
      if ($#argv == -1) { goto MISSINGARG; } $arg = shift(@argv);
      if (CheckIfNumber($arg) == 1) {
        $opts{EXTRASLEEP} = $arg;
      } else {
        print STDERR "$SCRIPT: invalid --extra-sleep specification: '$arg' is not a number\n";
        return %opts;
      }
      #
    } elsif ($arg eq '--use-cloud') {
      if ($#argv == -1) { goto MISSINGARG; } $arg = shift(@argv);
      # validate against @clouds
      my $isValid = 0;
      foreach my $key (keys(%validClouds)) {
        if ($arg =~ /^${key}$/) {
          $opts{CLOUD} = $arg;
          $isValid = 1;
        }
      }
      #
      if ($isValid == 0)  {
        print STDERR "$SCRIPT: invalid --use-cloud option '$arg'\n";
        print STDERR "  use: ".join('|',sort(keys(%validClouds)))."\n";
        return %opts;
      }
      #
    } elsif ($arg eq '--compress') {
      if ($#argv == -1) { goto MISSINGARG; } $arg = shift(@argv);
      # validate against @compress
      if ($validCompress{$arg}) {
        $opts{COMPRESS} = $arg;
      } else {
        print STDERR "$SCRIPT: invalid --compress option '$arg'\n";
        print STDERR "  use:  ".join('|',sort(keys(%validCompress)))."\n";
        return %opts;
      }
      #
    } elsif ($arg eq '--scan-with') {
      if ($#argv == -1) { goto MISSINGARG; } $arg = shift(@argv);
      # validate against @finds
      if ($validFind{$arg}) {
        $opts{SCANWITH} = $arg;
      } else {
        print STDERR "$SCRIPT: invalid --scan-with option '$arg'\n";
        print STDERR "  use: ".join('|',sort(keys(%validFind)))."\n";
        return %opts;
      }
      #
    } elsif ($arg eq '--sort-by') {
      if ($#argv == -1) { goto MISSINGARG; } $arg = shift(@argv);
      # validate against @sortings
      if ($validSortBy{$arg}) {
        $opts{SORTBY} = $arg;
      } else {
        print STDERR "$SCRIPT: invalid --sort-by option '$arg'\n";
        print STDERR "  use:  ".join('|',sort(keys(%validSortBy)))."\n";
        return %opts;
      }
      #
    } elsif ($arg eq '--limit-to') {
      if ($#argv == -1) { goto MISSINGARG; } $arg = shift(@argv);
      $opts{LIMIT_TO} = $arg;
      #
    } elsif ($arg eq '-rc' ||
             $arg eq '--config-file') {
      if ($#argv == -1) { goto MISSINGARG; } $arg = shift(@argv);
      $opts{RCFILE} = $arg;
      #
    } elsif ($arg eq '--no-remove') {
      $opts{NOREMOVE} = 1;
      #
    } elsif ($arg eq '--include-empty-dirs') {
      $opts{INCEDIRS} = 1;
      #
    } elsif ($arg eq '--no-upload') {
      $opts{NOUPLOAD} = 1;
      #
    } elsif ($arg eq '--keep-tar-lists') {
      $opts{KEEPTARLISTS} = 1;
      #
    } elsif ($arg eq '--rclone-metadata-set') {
      $opts{RCMDATASET} = 1;
      #
    } elsif ($arg eq '--tar-cf-opts') {
      if ($#argv == -1) { goto MISSINGARG; } $arg = shift(@argv);
      $opts{TAR_CF_OPTS} = $arg;
      #
    } elsif ($arg eq '--tag-host') {
      if ($#argv == -1) { goto MISSINGARG; } $arg = shift(@argv);
      $opts{TAG_HOST} = $arg;
      #
    } elsif ($arg eq '--tag-author') {
      if ($#argv == -1) { goto MISSINGARG; } $arg = shift(@argv);
      $opts{TAG_AUTHOR} = $arg;
      #
    } elsif ($arg eq '--use-dry-run') {
      if ($#argv == -1) { goto MISSINGARG; } $arg = shift(@argv);
      $opts{USEDRYRUN} = $arg;
      #
    } elsif ($arg eq '--use-vault') {
      if ($#argv == -1) { goto MISSINGARG; } $arg = shift(@argv);
      $opts{USETHISVAULT} = $arg;
      #
    } elsif ($arg eq '--tag') {
      if ($#argv == -1) { goto MISSINGARG; } $arg = shift(@argv);
      $opts{TAG_DATE} = $arg;
      #
    } elsif ($arg eq '--out-dir') {
      if ($#argv == -1) { goto MISSINGARG; } $arg = shift(@argv);
      if ( -d $arg) {
        $opts{OUTDIR} = $arg;
      } else {
        print STDERR "$SCRIPT: invalid --out-dir argument, '$arg' is not a directory\n";
        return %opts;
      }
      #
    } elsif ($arg eq '-v' || 
             $arg eq '--verbose') {
      $opts{VERBOSE} += 1;
      #
    } elsif ($arg eq '-n' || 
             $arg eq '--dry-run' ) {
      $opts{DRYRUN} = 1;
      #
    } elsif ($arg eq '-p' || 
             $arg eq '--parse-only') {
      $opts{PARSEONLY} = 1;
      #
    } elsif ($arg eq '-h' || 
             $arg eq '--help') { 
      print STDERR join("\n", @HELP)."\n";
      # return %opts;
      die "\n";
      #   
    } else { 
      print STDERR "$SCRIPT: error - invalid argument '$arg'\n";
      print STDERR "  use -h|--help for help\n\n";
      return %opts; 
    }
  }
  #
  $opts{STATUS} = 0;
  return %opts;
  #
MISSINGARG:
  print STDERR "$SCRIPT: error: missing argument to '$arg'\n";
  print STDERR "  use -h|--help for help\n\n";
  return %opts; 
}
#
# ---------------------------------------------------------------------------
#
sub ValidateOpts {
  #
  # validate the options
  my $SCRIPT = $_[0];
  my $p2opts = $_[1];
  #
  # make sure SCRATCH holds an absolute path and resolve it if symlink
  if (-l $$p2opts{SCRATCH}) {
    my $link = $$p2opts{SCRATCH};
    $$p2opts{SCRATCH} = realpath($link);
  }
  #
  if ( $$p2opts{SCRATCH} !~ /^^\// ) { $$p2opts{SCRATCH} = getcwd().'/'.$$p2opts{SCRATCH}; }
  if ( $$p2opts{BASEDIR} =~ /^\//  ) { $$p2opts{BASEDIR} =~ s/.//; }
  #
  # must be root to use xcp
  if (defined $$p2opts{SCANWITH} ) {
    if ( $$p2opts{SCANWITH} eq 'xcp' ) {
      my $id = $<;
      if ($id != 0) {
        print STDERR "$SCRIPT: must be root to use --scan-with '$$p2opts{SCANWITH}'\n";
        $$p2opts{STATUS} = 1;  
      }
    }
  }
  #
  my $TAG_DATE;
  if ($$p2opts{USEDRYRUN}) {
    #
    $TAG_DATE = $$p2opts{USEDRYRUN};
    #
  } elsif ($$p2opts{TAG_DATE}) {
    #
    $TAG_DATE = $$p2opts{TAG_DATE};
    #
  } elsif ($$p2opts{USETHISVAULT}) {
    # 
    # TAG_DATE is the last 3 compoments of vault name split on '-'
    my @w = split('-', $$p2opts{USETHISVAULT});
    my $n = $#w-2;
    $TAG_DATE = join('-', @w[$n..$#w]);
    #
  } else {
    # 
    if (defined $$p2opts{LEVEL}) {
      my ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst) = localtime(time);
      $TAG_DATE = sprintf("%2.2d%2.2d%2.2d-%2.2d%2.2d", $year-100, $mon+1, $mday, $hour, $min);
      if ($$p2opts{LEVEL} =~ /^@/) {
        $TAG_DATE .= '-WF';
      } elsif ($$p2opts{LEVEL} =~ /^[0-9]$/ || $$p2opts{LEVEL} =~ /^[0-9][0-9]$/) {
        $TAG_DATE .= '-l'.$$p2opts{LEVEL};
      } elsif ($$p2opts{LEVEL} =~ /^-[0-9]$/ || $$p2opts{LEVEL} =~ /^-[0-9][0-9]$/) {
        $TAG_DATE .= '-WN';
      } elsif ($$p2opts{LEVEL} =~ /^%[0-9][0-9][0-9][0-9][0-9][0-9]-[0-9][0-9][0-9][0-9]$/) {
        $TAG_DATE .= '-WD';
      }  else {
        print STDERR "$SCRIPT: --level invalid specification '$$p2opts{LEVEL}'\n";
        $$p2opts{STATUS} = 1; 
      }
    }
  }
  #
  # vault name 63-24-4 = 35 chars long 
  # where 4+2+8+1+4+1+4=24 xxxx-*-YYYYMMDD-HHMM-lxxx 5 spare
  my $VHDR;
  if ($$p2opts{CLOUD} eq 'aws:s3_freezer') { $VHDR = 'frzr'; } else { $VHDR = 'bkup'; }
  # convert to lower case and replace complement of [a-z] [0-9] to '-'
  my $VNAME = lc($$p2opts{LABEL}.'-'.$$p2opts{BASEDIR});
  $VNAME =~ s/[^a-z0-9]/-/g;
  #
  if (defined $TAG_DATE) {
    $$p2opts{VAULT} = sprintf("%s-%.35s-%s", $VHDR, $VNAME, $TAG_DATE);
    $$p2opts{TAG_DATE} = $TAG_DATE;
    # use the full vault name, not just the TAG_DATE
    $$p2opts{SCRATCH} .= '/'.$$p2opts{VAULT};
  } else {
    print STDERR "$SCRIPT: missing --tag specification\n";
    $$p2opts{STATUS} = 1;
  }
  #
  # double check VAULT name
  if ($$p2opts{USETHISVAULT}) {
    if ($$p2opts{USETHISVAULT} ne $$p2opts{VAULT}) {
      print STDERR "$SCRIPT: incompatible --use-vault $$p2opts{USETHISVAULT} vs $$p2opts{VAULT}\n";
      $$p2opts{STATUS} = 1;
    }
  }
  #
  # valid --limit-to?
  if ($$p2opts{LIMIT_TO}) {
    my @list;
    if ($$p2opts{LIMIT_TO} =~ /^@/) {
      my $file = $$p2opts{LIMIT_TO};
      $file =~ s/.//;
      if (! -e $file) {
        print STDERR "$SCRIPT: invalid --limit-to \@$file - '$file' file not found\n";
        $$p2opts{STATUS} = 1; 
      } else {
        open(FILE, "<$file");
        @list = <FILE>;
        close(FILE);
        chomp(@list);
      }
    } else {
      @list = split(/ /, $$p2opts{LIMIT_TO});
    }
    foreach my $dir ( @list ) {
      my $lDir = "/$$p2opts{BASEDIR}/$dir";
      if (! -d $lDir) {
        print STDERR "$SCRIPT: invalid --limit-to $$p2opts{LIMIT_TO} - '$lDir' is not a directory\n";
        $$p2opts{STATUS} = 1; 
      }
    }
    $$p2opts{LIMIT_TO} = join(' ', @list);
  }
  #
  # check incompatible options or invalid combo
  if ($$p2opts{DRYRUN} && $$p2opts{USEDRYRUN})  {
    print STDERR "$SCRIPT: error can't use --dry-run and --use-dry-run\n";
    $$p2opts{STATUS} = 1;
  }
  #
  if ($$p2opts{USETHISVAULT}) {
    if ($$p2opts{LIMIT_TO} eq '') {
      print STDERR "$SCRIPT: error can't use --use-vault w/out --limit-to\n";
      $$p2opts{STATUS} = 1;
    }
    # this timestamp must exist
    my $timestamp = "$$p2opts{BASEDIR}/timestamp";
    if (! -e "$$p2opts{SCRATCH}/$timestamp") {
      print STDERR "$SCRIPT --use-vault: invalid --base-dir \n";
      print STDERR "  $timestamp not found in $$p2opts{SCRATCH}\n";
      $$p2opts{STATUS} = 1;
    }
    #
    foreach my $dir ( split(' ', $$p2opts{LIMIT_TO}) ) {
      $timestamp = "$$p2opts{SCRATCH}/$$p2opts{BASEDIR}/$dir/timestamp";
      if (-e  $timestamp && ($$p2opts{USEDRYRUN} == 0)) {
        # first error?
        if ($$p2opts{STATUS} == 0) {
          print STDERR "$SCRIPT --use-vault: invalid --limit-to value(s)\n";
        }
        #
        my @when = GetFileContent($timestamp);
        print STDERR "  '$dir' already processed (".join(' ', @when).")\n";
        $$p2opts{STATUS} = 1;
      }
    }
  }
  #
}
#
# ---------------------------------------------------------------------------
#
sub CheckIfNumber {
  #
  my $val = shift(@_);
  if ($val =~ /^[0-9]$/ || 
      $val =~ /^[0-9][0-9]$/ || 
      $val =~ /^[0-9][0-9][0-9]$/) { 
    return 1;
  } else {
    return 0;
  }
}
#
1;
