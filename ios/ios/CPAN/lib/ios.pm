package ios;

=head1 NAME

ios - supporting XS code for iOS and derivatives

=cut

BEGIN {
    if ($^O =~ /darwin-ios/) {
        *CORE::GLOBAL::readpipe = sub {
            my ($code, $result);
            eval {
                ($code, $result) = exec_cli(getcwd(), "@_")
            };
            if ($@ ne '') {
                warn $@;
                $result = $@;
            }
            $? = defined $code ? $code : -1;
            return $result;
        };
    }
}

use strict;
use warnings;
use Config;

require Exporter;
our @ISA = qw(Exporter);
our $VERSION = '0.0.1';

our @methods = (
    'capture_test',
    'exec_perl_capture',
    'exec_perl',
    'exec_test',
    'make',
    'yield',
    'cat',
);

our @EXPORT = @methods;
our @EXPORT_OK = @methods;

require XSLoader;
XSLoader::load('ios', $VERSION);

# auto-flush on socket
$| = 1;

use open ":std", ":encoding(UTF-8)";
use JSON::PP;
use Data::Dumper;
use Cwd qw(abs_path chdir getcwd);
use File::Basename qw(basename);
use Text::ParseWords;

our $DEBUG = 0;

our $capture = 1;

use constant DARWIN_O_WRONLY => 0x0001;
use constant DARWIN_O_CREAT => 0x0200;

my $json = JSON::PP->new->convert_blessed(1);

sub check_error {
  my ($error) = @_;
  warn "ios error: $error" if $error;
}

sub yield {
  CBYield(shift);
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
    my $old_pwd = getcwd();
    my $pwd = $req->{pwd};
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
    chdir $pwd or die "Could not chdir to $pwd: $!"
        if defined $pwd && $pwd ne '';
    my $t = eval { CBRunPerl($exec) };
    my $error = $@;
    chdir $old_pwd or die "Could not restore directory $old_pwd: $!";
    die $error if $error ne '';
    print "\$t: $t\n" if $DEBUG;
    return int($t);
}

sub exec_perl_capture {
    my ($req) = @_;

    # prevent NSNumber encoding
    foreach (@{$req->{args}}) {
        $_ .= "" if $_ =~ /\d*/;
    }

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
    my ($exit_code, $result);
    local $@;
    eval {
        ($exit_code, $result) = CBRunPerlCaptureStdout($exec);
    };
    print "exec_perl_capture \$result: $result:\n" if ($result && $DEBUG);
    return ($exit_code, $result ? $result : $@);
}

sub parse_test {
    my ($pwd, $t) = @_;
    print Dumper("parse_test pwd", $pwd) if $DEBUG;
    print Dumper("parse_test t", $t) if $DEBUG;

    my @command = grep defined,
        ref $t eq 'ARRAY' ? @$t : &quotewords('\s+', 0, $t);
    shift @command while @command && $command[0] !~ /(?:perl|harness)["']?$/;
    shift @command;

    my $file_index;
    for my $index (0 .. $#command) {
        my $candidate = $command[$index];
        my $candidate_path = $candidate =~ m{^/} ? $candidate : "$pwd/$candidate";
        if (-f $candidate_path) {
            $file_index = $index;
            last;
        }
    }

    if (! defined $file_index) {
        warn "parse_test() test file not found in command: $t\n";
        return {
            file => undef
        }
    }

    my @switches = splice @command, 0, $file_index;
    my $file = shift @command;
    my @args = @command;
    print Dumper("File", $file) if $DEBUG;
    print Dumper("Switches:", @switches) if $DEBUG;
    print Dumper("Args", @args) if $DEBUG;

    my $result = {
        progfile => $file,
        pwd => $pwd,
        switches => \@switches,
        args => \@args,
    };

    print Dumper("parse_test", $result) if $DEBUG;
    return $result
}

sub parse_cli {
    my ($pwd, $cli) = @_;
    print Dumper("parse_test pwd", $pwd) if $DEBUG;
    print Dumper("parse_test t", $cli) if $DEBUG;
    my ($file, $arg, $switch, $stderr, @args, @switches);

    my ($cmd) = $cli =~ s/[^\s]*(perl|harness)["']?\s*([^\s]+.*$)/$2/r;

    print Dumper("cmd", $cmd) if $DEBUG;

    $stderr = 0;
    $cmd =~ s/2>&1//;

    my $file_index = -1;
    my @cmd_words = &quotewords('\s+', 0, $cmd);
    @cmd_words = grep defined, @cmd_words;
    print Dumper("\@cmd_words", "@cmd_words") if $DEBUG;
    if ($cmd !~ /\-[l]?e['" ]+/) {
        for (my $i = 0; $i < scalar @cmd_words; $i++) {
            print Dumper("trying word", $cmd_words[$i]) if $DEBUG;
            if (-f $cmd_words[$i]) {
                $file = $cmd_words[$i];
                print Dumper("File", $file) if $DEBUG;
                $file_index = $i;
                last;
            }
        }
    }

    if ($file) {
        @args = splice @cmd_words, $file_index +1, @cmd_words -1;
        print Dumper("\@args", @args) if $DEBUG && @switches;
        @switches = splice @cmd_words, 0, $file_index;
        print Dumper("\@switches", @switches) if $DEBUG && @switches;
    } else {
        @switches = @cmd_words;
    }

    @args = grep defined, @args;
    @switches = grep defined, @switches;

    my $result = {
        progfile => $file,
        pwd => $pwd,
        switches => \@switches,
        args => \@args,
    };

    print Dumper("parse_cli", $result) if $DEBUG;
    return $result
}

sub exec_test {
    my ($pwd, $test) = @_;
    die ('Could not chdir to $pwd') if ($pwd && ! chdir $pwd);
    print "Executing: $test\nPWD: $pwd\n" if $DEBUG;
    my $json = parse_test($pwd, $test);
    print  Dumper("json", $json) if $DEBUG;
    my $result;
    local $@;

    if ($capture){
        eval {
            ($result) = exec_perl_capture($json);
        };
        print  Dumper("code", $result->[0]) if $DEBUG;
        print  Dumper("output", $result->[1]) if $DEBUG;
        return ($result->[0], $result->[1] ? $result->[1] : $@);
    } else {
        eval {
            ($result) = exec_perl($json);
        };
        return ($result, "");
    }
}

sub exec_cli {
    my ($pwd, $test) = @_;
    print "Executing: $test\nPWD: $pwd\n" if $DEBUG;
    my @words = grep { defined && $_ ne '' }
        &quotewords('\s+', 0, $test);
    if (@words && basename($words[0]) =~ /^(?:b?make|gmake)$/) {
        shift @words;
        @words = grep { $_ ne '2>&1' } @words;
        return make_capture($pwd, @words);
    }
    my $json = parse_cli($pwd, $test);
    print  Dumper("json", $json) if $DEBUG;
    my $result;
    local $@;

    eval {
        ($result) = exec_perl_capture($json);
    };
    print  Dumper("code", $result->[0]) if $DEBUG;
    print  Dumper("output", $result->[1]) if $DEBUG;
    return ($result->[0], $result->[1] ? $result->[1] : $@);
}

sub make_capture {
    my ($pwd, @args) = @_;
    my $old_pwd = getcwd();
    my ($result, $error);

    $pwd = $old_pwd if !defined $pwd || $pwd eq '';
    @args = ('pure_all') if !@args;
    eval {
        chdir $pwd or die "Could not chdir to $pwd: $!";
        ($result) = CBRunMakeCapture(@args);
        1;
    } or $error = $@;
    chdir $old_pwd or die "Could not restore directory $old_pwd: $!";
    die $error if defined $error;
    return @$result;
}

sub make {
    my ($pwd, @args) = @_;
    my $old_pwd = getcwd();
    my ($status, $error);

    $pwd = $old_pwd if !defined $pwd || $pwd eq '';
    @args = ('pure_all') if !@args;
    eval {
        chdir $pwd or die "Could not chdir to $pwd: $!";
        $status = CBRunMake(@args);
        1;
    } or $error = $@;
    chdir $old_pwd or die "Could not restore directory $old_pwd: $!";
    die $error if defined $error;
    return $status;
}

sub _make_perl_request {
    my ($pwd, @words) = @_;
    my (@switches, @args, $progfile);
    my $after_separator = 0;

    while (@words) {
        my $word = shift @words;
        next if $word eq '\\';
        if ($after_separator) {
            push @args, $word;
        } elsif ($word eq '--') {
            $after_separator = 1;
        } elsif ($word !~ /^-/ && -f ($word =~ m{^/} ? $word : "$pwd/$word")) {
            $progfile = $word;
            @args = grep { $_ ne '\\' } @words;
            last;
        } else {
            push @switches, $word;
        }
    }

    return {
        pwd => $pwd,
        progfile => $progfile,
        switches => \@switches,
        args => \@args,
    };
}

{
    no open;

    sub _make_touch_file {
        my ($file) = @_;
        sysopen my $handle, $file,
            DARWIN_O_CREAT | DARWIN_O_WRONLY, 0666
            or return 0;
        return close $handle;
    }
}

sub _run_make_recipe {
    my ($command) = @_;
    my @words = grep { defined && $_ ne '' }
        &quotewords('\s+', 0, $command);
    return 0 if !@words;

    my $program = shift @words;
    my $name = basename($program);
    if ($name =~ /^(?:perl(?:5(?:\.\d+)*)?|harness)$/) {
        my ($result) = exec_perl_capture(
            _make_perl_request(getcwd(), @words));
        my ($status, $output) = @$result;
        print $output if defined $output && length $output;
        $status = $status >> 8 if defined $status && $status > 255;
        return defined $status ? $status : 1;
    }

    return 0 if $name eq 'true' && !@words;

    if ($name eq 'echo') {
        print join(' ', @words), "\n";
        return 0;
    }

    if ($name eq 'chmod' && @words >= 2 && $words[0] =~ /^[0-7]{3,4}$/) {
        my $mode = oct shift @words;
        return chmod($mode, @words) == @words ? 0 : 1;
    }

    if ($name eq 'touch' && @words) {
        for my $file (@words) {
            if (-e $file) {
                return 1 if !utime undef, undef, $file;
            } else {
                return 1 if !_make_touch_file($file);
            }
        }
        return 0;
    }

    warn "Unsupported iOS make recipe: $command\n";
    return 127;
}

sub cat {
    my ($file) = @_;
    open(my $fh, '<:encoding(UTF-8)', $file)
        or die "Could not open file $file  $!";
    my $result;
    while (my $row = <$fh>) {
        $result .= $row;
    }
    close $fh;
    print $result;
}

1;
