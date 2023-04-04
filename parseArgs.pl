#
# <- Last updated: Tue Apr  4 15:03:10 2023 -> SGK
#
# &ReadConfig($SCRIPT, \@ARGV, \%defOpts, \%ignOpts);
#
# @help = (); # set in ParseArgs from %defOpts
# %opts = &ParseArgs($SCRIPT, \@argv, \%defOpts, \@listOpts, \@mapOpts, \@help);
#
# &ValidateBackupOpts($SCRIPT, \%opts)
# &ValidateRestoreOpts($SCRIPT, \%opts)
#
# $ok = CheckIfFile($val)
# $ok = CheckIfDirectory($val)
# $ok = CheckIfNumber($val, $range) # $range = 'i,j' or 'i,*' or '*,j'
# $ok = CheckSize($val, $unit)      # $unit = 'kMGT' any list of single char
# $ok = CheckList($val, $list)      # $list = 'one,two,...' coma sep list
#
# (c) 2021-2023 - Sylvain G. Korzennik, Smithsonian Institution
# 
# ---------------------------------------------------------------------------
#
use strict;
# use Cwd;
use Net::Domain qw(hostname hostdomain);
#
# ---------------------------------------------------------------------------
#
sub ReadConfig {
  #
  # read config file
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
      $verbose++;
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
        if (defined($$p2opts{$key}) && $value ne '' && $key ne 'RCFILE') {
          #
          # no validation on $value, caveat empror
          $$p2opts{$key} = $value;
          #
        } elsif (defined($$p2ign{$key})) {
          #
          if ($verbose > 1) {
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
sub ParseArgs {
  #
  # parse arguments
  #
  # file          - file must exist
  # directory     - dir must exist
  # string        - no check
  # list(one,two) - must be one of the list
  # number        - number (signed integer)
  # number(1,2)   - number (signed integer) between 1 & 2
  # number(1,*)   - number (signed integer) GE 1
  # number(*,2)   - number (signed integer) LE 2
  # size(kMGT)    - number with optional unit either kMGT
  #
  my $SCRIPT  =   shift();
  my @args    = @{shift()};
  my %defOpts = %{shift()};
  my @options = @{shift()};
  my @mapOpts = @{shift()};
  my $p2help  =   shift();
  #
  my %values   = ();
  my %typeArg  = ();
  my %equivArg = ();
  my %canRepeat = ();
  #
  my $nErrors = 0;
  #
  my $option;
  #
  foreach $option (@options) {
    #
    my @w = split(';', $option, 2);
    #
    if ($#w == 1) {
      $option = shift(@w);
      $option =~ s/ *$//;
    } else {
      $option = '';
    }
    #
    my $help = shift(@w);
    #
    if ($option ne '') {
      my ($key, $type) = split('=', $option, 2);
      my @keys = split('\|', $key);
      $key  = '--'.pop(@keys);
      #
      if ($type eq '') { $type = '-'; }
      if ($type eq 'repeat') {
        $type = '-';
        $canRepeat{$key} = 1;
      }
      #
      $typeArg{$key} = $type;
      #
      my $kkk = $key;
      if ($#keys >= 0) {
        my $k;
        foreach $k (@keys) {
          $equivArg{'-'.$k} = $key;
          $kkk = '-'.$k.' | '.$kkk;
        }
      }
      #
      $help = sprintf("       %-25s ",$kkk).$help;
    } elsif($help =~ /^-/) {
      $help =~ s/./  /;
    } else {
      $help = sprintf("       %-25s ",' ').$help;
    }
    @{$p2help} = (@{$p2help}, $help);
  }
  #
  my $nErrors = 0;
  my %values = ();
  #
  while ($#args >= 0) {
    #
    my $argX = shift(@args);
    my $arg = $argX;
    if (defined $equivArg{$argX}) {
      $arg = $equivArg{$argX};
    }
    #
    if (defined $typeArg{$arg}) {
      #
      if (defined $values{$arg} && $canRepeat{$arg} != 1) {
        print STDERR "$SCRIPT: parseArgs() option '$argX' cannot be repeated\n";
        $nErrors++;
      } else {
        #
        my $type = $typeArg{$arg};
        #
        if ($type ne '-') {
          #
          if ($#args == -1) {
            print STDERR "$SCRIPT: parseArgs() missing $type for option '$argX'\n";
            $nErrors++;
            #
          } elsif ($args[0] eq '') {
            #
            print STDERR "$SCRIPT: parseArgs() empty $type for option '$argX'\n";
            $nErrors++;
            #
          } else {
            #
            my $val = $args[0];
            #
            # $type is defined
            #
            my $spec = '';
            #
            if ($type =~ /\(.*\)/) {
              $type =~ s/\((.*)\)//;
              $spec = $1;
            }
            #
            my $ok = 1;
            my $errMsg = '';
            #
            if      ($type eq 'number') {
              #
              $errMsg = "must be a $type";
              if ($spec ne '') { $errMsg .= " within ($spec)"; }
              $ok = CheckIfNumber($val, $spec);
              #
            } elsif ($type eq 'directory') {
              #
              $errMsg = "it is not a $type or it is not found";
              $ok = CheckIfDirectory($val);
              #
            } elsif ($type eq 'file') {
              #
              $errMsg = "it is not a $type or it is not found";
              $ok = CheckIfFile($val);
              #
            } elsif ($type eq 'string') {
              #
              $ok = 1;
              #
            } elsif ($type eq 'list') {
              #
              $errMsg = " must be ".join(' | ',split(',',$spec));
              $ok = CheckList($val, $spec);
              #
            } elsif ($type eq 'size') {
              #
              $errMsg = "must be a number with an optional unit [$spec]";
              $ok = CheckSize($val, $spec);
              #
            } else {
              die "Parsing \@OPTS specification error: '$type' is an invalid type\n";
            }
            #
            if ($ok) {
              $values{$arg} = $val;
            } else {
              # diff string
              #  !file
              #  number range
              #  string list
              print STDERR "$SCRIPT: parseArgs() '$val' is an invalid value for '$argX', $errMsg\n";
              $nErrors++;
              #
            }
          }
          #
          shift(@args);
          #
        } else {
          # no value to option
          $values{$arg}++;
        }
      }
    } else {
      #
      print STDERR "$SCRIPT: parseArgs() '$argX' invalid argument\n";
      $nErrors++;
      #
    }
  }
  #
  my %mapOpts = ();
  my $m;
  foreach $m (@mapOpts) {
    my ($k, $v) = split(':', $m);
    $mapOpts{$k} = $v;
  }
  #
  my %opts = ();
  my $k;
  #
  # set opts to defOpts;
  #
  foreach $k (keys(%defOpts)) {
    $opts{$k} = $defOpts{$k};
  }
  #
  #  overwrite def by passed vals
  #
  foreach $k (keys(%values)) {
    if ($mapOpts{$k} ne '') {
      $opts{$mapOpts{$k}} = $values{$k};
    } else {
      my $K = uc($k);
      $K =~ s/\-//g;
      $opts{$K} = $values{$k};
    }
  }
  #
##  foreach $k (keys(%opts)) {
##    print STDERR ">> $k $opts{$k}\n";
##  }
  #
  $opts{NERRORS} = $nErrors;
  if ($opts{NERRORS} > 0) { $opts{STATUS} = 1; } else { $opts{STATUS} = 0; }
  #
  return %opts;
}
#
# ---------------------------------------------------------------------------
#
sub CheckIfFile {
  #
  my $path = shift();
  if (! -e $path) {
    return 0;
  }
  return 1;
}
#
# ---------------------------------------------------------------------------
#
sub CheckIfDirectory {
  #
  my $path = shift();
  if (! -d $path) {
    return 0;
  }
  return 1;
}
#
# ---------------------------------------------------------------------------
#
sub CheckIfNumber {
  #
  # number(-2,5) or number(*,5) or number(-2,*)
  #
  my $val   = shift();
  my $range = shift();
  #
  if ($val !~ /^[+\-0-9]$/ &&
      $val !~ /^[+\-0-9][0-9]*$/) {
    return 0;
  }
  if ($range ne '') {
    my @range = split(',', $range);
    if ($range[0] ne '*') {
      if ($val < $range[0]) { return 0; }
    }
    if ($range[1] ne '*') {
      if ($val > $range[1]) { return 0; }
    }
  }
  return 1;
}
#
# ---------------------------------------------------------------------------
#
sub CheckSize {
  #
  my $val   = shift();
  my $units = shift();
  #
  if ($val =~ /[0-9]$/) {
    my $ok = CheckIfNumber($val, '');
    return $ok;
  }
  #
  $val =~ s/(.)$//;
  my $unit = $1;
  #
  my @units = split('', $units);
  my @u = grep(/$unit/, @units);
  if ($#u != 0) {
    return 0;
  }
  my $ok = CheckIfNumber($val, '');
  return $ok;
  #
}
#
# ---------------------------------------------------------------------------
#
sub CheckList {
  #
  my $val  = shift();
  my @list = split(',', shift());
  #
  my $v;
  foreach $v (@list) {
    # use =~ if starts w/ ^
    if ($v =~ /^\^/) {
      if ($val =~ /$v/) { return 1; }
    }
    if ($val eq $v) { return 1; }
  }
  #
  return 0;
}
#
# ---------------------------------------------------------------------------
#
sub ValidateBackupOpts {
  #
  # validate the options
  #
  my $SCRIPT = $_[0];
  my $p2opts = $_[1];
  #
  # no of errors upon entry
  my $nErrors = $$p2opts{NERRORS};
  #
  # 1- make sure SCRATCH holds an absolute path and resolve it if it is a symlink
  #
  if (-l $$p2opts{SCRATCH}) {
    # resolve symlink
    my $link = $$p2opts{SCRATCH};
    $$p2opts{SCRATCH} = realpath($link);
  }
  # 
  $$p2opts{SCRATCH} = AbsolutePath($$p2opts{SCRATCH});
  #
  # 2- remove leading / from base dir
  # 
  if ( $$p2opts{BASEDIR} =~ /^\//  ) { $$p2opts{BASEDIR} =~ s/.//; }
  #
  # must be root to use xcp
  #
  if (defined $$p2opts{SCANWITH} ) {
    if ( $$p2opts{SCANWITH} eq 'xcp' ) {
      my $id = $<;
      if ($id != 0) {
        print STDERR "$SCRIPT: ValidateOpts() must be root to use --scan-with '$$p2opts{SCANWITH}'\n";
        $$p2opts{NERRORS}++;
      }
    }
  }
  #
  # 3- define TAG_DATE
  #
  my $TAG_DATE;
  #
  if ($$p2opts{USEDRYRUN}) {
    #
    # --use-dry-run and --tag are incompatible
    #
    if (defined $$p2opts{USEDRYRUN} && defined $$p2opts{TAG_DATE}) {
      print STDERR "$SCRIPT: ValidateOpts() cannot specify --tag with --use-dry-run\n";
      $$p2opts{NERRORS}++;
    }
    #
    $TAG_DATE = $$p2opts{USEDRYRUN};
    #
  } elsif ($$p2opts{TAG_DATE}) {
    #
    # --tag
    #
    $TAG_DATE = $$p2opts{TAG_DATE};
    #
  } elsif ($$p2opts{USETHISVAULT}) {
    #
    # --use-this-vault
    #
    if (defined $$p2opts{USETHISVAULT} && defined $$p2opts{TAG_DATE}) {
      print STDERR "$SCRIPT: ValidateOpts() cannot specify --tag with --use-this-vault\n";
      $$p2opts{NERRORS}++;
    }
    #
    # TAG_DATE is the last 3 compoments of the vault name when split on '-'
    #
    my @w = split('-', $$p2opts{USETHISVAULT});
    my $n = $#w-2;
    $TAG_DATE = join('-', @w[$n..$#w]);
    #
  } else {
    #
    # --level
    #
    if (defined $$p2opts{LEVEL}) {
      #
      # use 'YYMMDD-hhmm'
      my ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst) = localtime(time);
      $TAG_DATE = sprintf("%2.2d%2.2d%2.2d-%2.2d%2.2d", $year-100, $mon+1, $mday, $hour, $min);
      #
      if ($$p2opts{LEVEL} =~ /^@/) {
        # -WF with respect to a file
        $TAG_DATE .= '-WF';
      } elsif ($$p2opts{LEVEL} =~ /^[0-9]$/ || $$p2opts{LEVEL} =~ /^[1-9][0-9]$/) {
        # -l for level [0-99]
        $TAG_DATE .= '-l'.$$p2opts{LEVEL};
      } elsif ($$p2opts{LEVEL} =~ /^-[1-9]$/ || $$p2opts{LEVEL} =~ /^-[1-9][0-9]$/) {
        # -WN for negative level [-99,-1]
        $TAG_DATE .= '-WN';
      } elsif ($$p2opts{LEVEL} =~ /^%[0-9][0-9][0-1][0-9][0-3][0-9]-[0-2][0-9][0-5][0-9]$/) {
        # -WD for with respect to a date
        $TAG_DATE .= '-WD';
      }  else {
        print STDERR "$SCRIPT: ValidateOpts() --level invalid specification '$$p2opts{LEVEL}'\n";
        $$p2opts{NERRORS}++;
      }
    }
  }
  #
  # 4 - now buld the vault name 63-24-4 = 35 chars long 
  # where 4+2+8+1+4+1+4=24 xxxx-*-YYYYMMDD-HHMM-lxxx 5 spare
  #
  my $VHDR;
  if ($$p2opts{CLOUD} eq 'aws:s3_freezer') { $VHDR = 'frzr'; } else { $VHDR = 'bkup'; }
  #
  # add the base dir, convert to lower case and replace complement of [a-z] [0-9] to '-'
  #
  my $VNAME = $$p2opts{LABEL}.'-'.$$p2opts{BASEDIR};
  $VNAME = lc($VNAME);
  $VNAME =~ s/[^a-z0-9]/-/g;
  #
  if (defined $TAG_DATE) {
    $$p2opts{VAULT} = sprintf("%s-%.35s-%s", $VHDR, $VNAME, $TAG_DATE);
    $$p2opts{TAG_DATE} = $TAG_DATE;
    #
    # update SCRATCH and use the full vault name (not just the TAG_DATE any longer)
    #
    $$p2opts{SCRATCH} .= '/'.$$p2opts{VAULT};
  } else {
    #
    print STDERR "$SCRIPT: ValidateOpts() missing --tag specification\n";
    $$p2opts{NERRORS}++;
    #
  }
  #
  # double check VAULT name
  if ($$p2opts{USETHISVAULT}) {
    if ($$p2opts{USETHISVAULT} ne $$p2opts{VAULT}) {
      print STDERR "$SCRIPT: ValidateOpts() incompatible vault name --use-vault $$p2opts{USETHISVAULT} vs $$p2opts{VAULT}\n";
      $$p2opts{NERRORS}++;
    }
  }
  #
  # 5- validate --limit-to
  #
  if ($$p2opts{LIMIT_TO}) {
    #
    my @list;
    #
    # is the list in a file, via @filename
    #
    if ($$p2opts{LIMIT_TO} =~ /^@/) {
      #
      my $file = $$p2opts{LIMIT_TO};
      $file =~ s/.//;
      #
      if (! -e $file || -z $file) {
        print STDERR "$SCRIPT: ValidateOpts() invalid --limit-to \@$file - '$file' file not found or empty\n";
        $$p2opts{NERRORS}++; 
      } else {
        @list = GetFileContent($file);
      }
      #
    } else {
      #
      @list = split(/ /, $$p2opts{LIMIT_TO});
      #
    }
    #
    # check that the list holds existing directories
    #
    my $dir;
    foreach $dir ( @list ) {
      #
      my $lDir = "/$$p2opts{BASEDIR}/$dir";
      if (! -d $lDir) {
        print STDERR "$SCRIPT: ValidateOpts() invalid value in --limit-to: '$lDir' not found or not a directory\n";
        $$p2opts{NERRORS}++; 
      }
    }
    $$p2opts{LIMIT_TO} = join(' ', @list);
  }
  #
  # 6- check incompatible options or invalid combo
  #
  if ($$p2opts{DRYRUN} && $$p2opts{USEDRYRUN})  {
    print STDERR "$SCRIPT: ValidateOpts() cannot specify --dry-run and --use-dry-run\n";
    $$p2opts{NERRORS}++;
  }
  #
  # 7- add'l check if --use-this-vault
  #
  if ($$p2opts{USETHISVAULT}) {
    #
    # need --limit-to
    #
    if ($$p2opts{LIMIT_TO} eq '') {
      print STDERR "$SCRIPT: ValidateOpts() error cannot specify --use-vault w/out --limit-to\n";
      $$p2opts{NERRORS}++;
    }
    #
    # the timestamp at the base must exist
    #
    my $timestamp = "$$p2opts{BASEDIR}/timestamp";
    if (! -e "$$p2opts{SCRATCH}/$timestamp") {
      #
      print STDERR "$SCRIPT: ValidateOpts() --use-vault $$p2opts{USETHISVAULT} error, ".
        "timestamp not found:\n  $$p2opts{SCRATCH}/$timestamp\n";
      $$p2opts{NERRORS}++;
    }
    #
    # check that the directories in --limit-to have not been already processed
    #
    my @list = split(' ', $$p2opts{LIMIT_TO});
    my $dir;
    foreach $dir ( @list ) {
      #
      $timestamp = "$$p2opts{SCRATCH}/$$p2opts{BASEDIR}/$dir/timestamp";
      if (-e  $timestamp && ($$p2opts{USEDRYRUN} == 0)) {
        #
        my @when = GetFileContent($timestamp);
        my $lDir = "/$$p2opts{BASEDIR}/$dir";
        print STDERR "$SCRIPT: ValidateOpts() invalid value in --limit-to: '$lDir' already processed (".join(' ', @when).")\n";
        $$p2opts{NERRORS}++;
      }
    }
  }
  #
  #
  # set host/author tags/metadata if not set in %defOptions() or config file
  #
  if(defined $$p2opts{TAG_HOST}) {
    if ($$p2opts{TAG_HOST}   eq '-') { $$p2opts{TAG_HOST} = hostname(); }
  }
  if (defined $$p2opts{TAG_AUTHOR}) {
    if ($$p2opts{TAG_AUTHOR} eq '-') {
      my $username = $ENV{LOGNAME} || $ENV{USER} || getpwuid($<);
      $$p2opts{TAG_AUTHOR} = $username.'@'.hostdomain();
    }
  }
  #
  if ($$p2opts{NERRORS} > $nErrors) {
    my $errors = 'error'; if ($$p2opts{NERRORS} > 1) { $errors = 'errors'; }
    print STDERR "$SCRIPT: ValidateOpts() $$p2opts{NERRORS} $errors\n";
  }
  #
  if ($$p2opts{NERRORS} > 0) { $$p2opts{STATUS} = 1; } else { $$p2opts{STATUS} = 0; }
  #
}
#
# ---------------------------------------------------------------------------
#
sub ValidateRestoreOpts {
  #
  my $SCRIPT = $_[0];
  my $p2opts = $_[1];
  #
  # no of errors upon entry
  my $nErrors = $$p2opts{NERRORS};
  #
  # always a dry run for archived backups
  # -------------------------------------
  if ($$p2opts{CLOUD} eq 'aws:glacier'    ||
      $$p2opts{CLOUD} eq 'aws:s3_glacier' ||
      $$p2opts{CLOUD} eq 'aws:s3_freezer' ||
      $$p2opts{CLOUD} eq 'az:archive') {
    if ( $$p2opts{DRYRUN} == 0) {
      print STDERR "$SCRIPT: --dry-run enforced for archived cloud, i.e.: '$$p2opts{CLOUD}'\n";
      $$p2opts{DRYRUN} = 1;
    }
  }
  #
  # must define --use-vault
  # -----------------------
  if (! defined $$p2opts{USETHISVAULT}) {
    print STDERR "$SCRIPT: --use-vault VAULT must be specified\n";
    $$p2opts{NERRORS}++;
  }
  #
  # check for exclusive options
  # ---------------------------
  my $n = 0;
  my $aList = '--show-dirs --show-files --restore-files --clean-scratch';
  my $key;
  my $KEY;
  my %map = ();
  #
  foreach my $key (split(' ', $aList)) {
    $KEY = uc($key);
    $KEY =~ s/\-//g;
    $map{$KEY} = $key;
  }
  #
  my @list = ();
  foreach $KEY (qw/SHOWDIRS SHOWFILES RESTOREFILES CLEANSCRATCH/) {
    if (defined $$p2opts{$KEY}) { $n++; @list = (@list, $map{$KEY}); }
  }
  #
  if ($n == 0) {
    #
    $$p2opts{NERRORS}++;
    print STDERR "$SCRIPT: missing one of the following $aList\n";
    #
  } elsif ($n > 1) {
    #
    $$p2opts{NERRORS} += $n;
    print STDERR "$SCRIPT: incompatibles options: ".join(' ', @list)."\n";
    print STDERR "$SCRIPT:   can only use one of the following $aList\n";
    #
  }
  #
  # verify use of --dry-run
  # -----------------------
  if ($$p2opts{DRYRUN}) {
    #
    foreach $KEY (qw/SHOWDIRS SHOWFILES/) {
      if (defined $$p2opts{$KEY}) {
        $$p2opts{NERRORS}++;
        print STDERR "$SCRIPT: cannot specify --dry-run with $map{$KEY}\n";
      }
    }
  }
  #
  # verify use of --use-dir
  # -----------------------
  if (defined $$p2opts{USEDIR}) {
    #
    foreach $KEY (qw/SHOWDIRS CLEANSCRATCH/) {
      if (defined $$p2opts{$KEY}) {
        $$p2opts{NERRORS}++;
        print STDERR "$SCRIPT: cannot specify --use-dir USEDIR with $map{$KEY}\n";
      }
    }
    #
  } else {
    #
    foreach $KEY (qw/SHOWFILES RESTOREFILES/) {
      if (defined $$p2opts{$KEY}) {
        $$p2opts{NERRORS}++;
        print STDERR "$SCRIPT: must specify --use-dir USEDIR with $map{$KEY}\n";
      }
    }
  }
  #
  # need to set VAULT to --use-vault VAULT 
  # -------------------------------------
  $$p2opts{VAULT} = $$p2opts{USETHISVAULT};
  #
  # prepend $cwd to scratch if relative path, remove any leading ./[///]
  $$p2opts{SCRATCH} = AbsolutePath($$p2opts{SCRATCH});
  # append / to scratch if not ending in /
  if ($$p2opts{SCRATCH} !~ /\/$/) { $$p2opts{SCRATCH} .= '/'; }
  #
  #  if ($$p2opts{NERRORS} > $nErrors) {
  #    my $s = IfPlural($$p2opts{NERRORS});
  #    print STDERR "$SCRIPT: ValidateOpts() $$p2opts{NERRORS} error$s\n";
  #  }
  #
  if ($$p2opts{NERRORS} > 0) { $$p2opts{STATUS} = 1; } else { $$p2opts{STATUS} = 0; }
  #
}
#
1;
