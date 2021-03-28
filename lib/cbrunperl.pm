package cbrunperl;

# auto-flush on socket
$| = 1;
use strict;
#use warnings;
use open ":std", ":encoding(UTF-8)";
use CamelBones qw(:All);
use JSON::PP;
use Data::Dumper;
use Cwd qw/abs_path chdir getcwd/;

our @ISA = qw(Exporter);
our $VERSION = '0.0.1';
our @EXPORT = (
    'exec_test', 'exec_perl', 'exec_perl_capture', 'capture_test', 'yield'
);

our @EXPORT_OK = (
    'ios_runperl', 'exec_test', 'exec_file_tests', 'exec_perl',
    'exec_perl_capture', 'capture_test', 'yield'
);

our $DEBUG = 0;

my $json = JSON::PP->new->convert_blessed(1);

sub check_error {
  my ($error) = @_;
  warn "CBRunPerl error: $error" if $error;
}

sub yield {
  CamelBones::CBYield(shift);
}

# runperl, run_perl - Runs a separate perl interpreter and returns its output.
# Arguments :
#   switches => [ command-line switches ]
#   nolib    => 1 # don't use -I../lib (included by default)
#   non_portable => Don't warn if a one liner contains quotes
#   prog     => one-liner (avoid quotes)
#   progs    => [ multi-liner (avoid quotes) ]
#   progfile => perl script
#   stdin    => string to feed the stdin (or undef to redirect from /dev/null)
#   stderr   => If 'devnull' suppresses stderr, if other TRUE value redirect
#               stderr to stdout
#   args     => [ command-line arguments to the perl program ]
#   verbose  => print the command line

sub exec_perl {
  my ($req) = @_;
  my $runPerl = {
	switches => $req->{switches},
	nolib => $req->{nolib},
	non_portable => $req->{non_portable},
	prog => $req->{prog},
    progs => $req->{progs},
    progfile => $req->{progfile},
	stdin => $req->{stdin},
	stderr => $req->{stderr},
    args => $req->{args},
    verbose => $req->{verbose},
    pwd => $req->{pwd},
  };
  my $exec = $json->utf8->canonical->pretty->encode($runPerl);
  print "\$exec: $exec\n" if $DEBUG;
  my $t = CamelBones::CBRunPerl($exec);
  print "\$t: $t\n" if $DEBUG;
  return $t;
}

sub exec_perl_capture {
  my ($req) = @_;
  my $runPerl = {
	switches => $req->{switches},
	nolib => $req->{nolib},
	non_portable => $req->{non_portable},
	prog => $req->{prog},
    progs => $req->{progs},
    progfile => $req->{progfile},
	stdin => $req->{stdin},
	stderr => $req->{stderr},
    args => $req->{args},
    verbose => $req->{verbose},
    pwd => $req->{pwd},
  };
  my $exec = $json->utf8->canonical->pretty->encode($runPerl);
  print "exec_perl_capture \$exec: $exec\n" if $DEBUG;
  my $t = CamelBones::CBRunPerlCaptureStdout($exec);
  print "\$t: $t\n" if $DEBUG;
  return $t;
}

sub parse_test {
  my ($pwd, $t) = @_;
  print Dumper("parse_test pwd", $pwd) if $DEBUG;
  print Dumper("parse_test t", $t) if $DEBUG;

  my ($exec_path) = $t =~ s/(.*?)perl\s.*$/$1/r;
  print Dumper("Exec path", $exec_path) if $DEBUG;
  
  my ($cmd) = $t =~ s/.*?perl\s(.*$)/$1/r;
  print Dumper("cmd", $cmd) if $DEBUG;

  my ($file) = $cmd =~ s/(.*?)([^\s]*)\s*$/$2/r;
  print Dumper("File", $file) if $DEBUG;
  
  if (! -e "$pwd/$file") {
    warn "parse_test() file not found: $pwd/$file\n";
    return {
      file => undef
    }
  }

  my ($arg) = $t =~ s/(.*?$file)(.*)/$2/r;
  print Dumper("Args", $arg) if $DEBUG;
  my @args = split " ", $arg;

  my ($switch) = $cmd =~ s/(.*?)([^\s]*)\s*$/$1/r;
  my @switches = split " ", $switch;
  print Dumper("Switches:", @switches) if $DEBUG;
  
  my $result = {
    progfile => $file,
    pwd => $pwd,
    switches => \@switches,
    args => \@args,
  };

  print Dumper("parse_test", $result) if $DEBUG;
  return $result
}

sub exec_test {
  my ($pwd, $test) = @_;
  die ('Could not chdir to $pwd') if ($pwd && ! chdir $pwd);
  print "Executing: $test\nPWD: $pwd\n" if $DEBUG;
  my $json = parse_test($pwd, $test);
  print  Dumper("json", $json) if $DEBUG;
  my $exec = exec_perl($json);
  print  Dumper("exec_test", $exec) if $DEBUG;
  CamelBones::CBYield(.1);
  my $result = check_error($exec);
  print  Dumper("result", $result) if $DEBUG;
  return $exec;
}




