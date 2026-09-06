package ios;

=head1 NAME

ios - supporting XS code for iOS and derivatives

=cut

BEGIN {
    if ($^O =~ /darwin-ios/) {
        *CORE::GLOBAL::readpipe = sub {
            my $list_context = wantarray;
            my ($code, $result);
            eval {
                ($code, $result) = exec_cli(getcwd(), "@_")
            };
            if ($@ ne '') {
                warn $@;
                $result = $@;
            }
            $? = defined $code ? $code >> 8 : -1;
            if ($list_context && defined $result) {
                return _readpipe_records($result);
            }
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

sub _require {
    my ($module) = @_;
    no warnings 'redefine';
    local *CORE::GLOBAL::require;
    return require $module;
}

sub Dumper {
    _require('Data/Dumper.pm');
    return Data::Dumper::Dumper(@_);
}

sub abs_path {
    _require('Cwd.pm');
    return Cwd::abs_path(@_);
}

sub _chdir {
    _require('Cwd.pm');
    return Cwd::chdir(@_);
}

sub getcwd {
    _require('Cwd.pm');
    return Cwd::getcwd();
}

sub basename {
    _require('File/Basename.pm');
    return File::Basename::basename(@_);
}

sub copy {
    _require('File/Copy.pm');
    return File::Copy::copy(@_);
}

sub move {
    _require('File/Copy.pm');
    return File::Copy::move(@_);
}

sub remove_tree {
    _require('File/Path.pm');
    return File::Path::remove_tree(@_);
}

our $parsewords_loaded;
sub quotewords {
    if (!$parsewords_loaded) {
        my %main_symbols = map { $_ => 1 } keys %::;
        _require('Text/ParseWords.pm');
        delete @::{grep {
            /^(?:\d+|[`'&])$/ && !$main_symbols{$_}
        } keys %::};
        $parsewords_loaded = 1;
    }
    return Text::ParseWords::quotewords(@_);
}

our $DEBUG = 0;

our $capture = 1;

sub _readpipe_records {
    my ($output) = @_;
    return ($output) if !defined $/ || ref $/ || $/ eq '';

    my @records;
    my $offset = 0;
    while ((my $end = index($output, $/, $offset)) >= 0) {
        $end += length $/;
        push @records, substr($output, $offset, $end - $offset);
        $offset = $end;
    }
    push @records, substr($output, $offset) if $offset < length $output;
    return @records;
}

use constant DARWIN_O_WRONLY => 0x0001;
use constant DARWIN_O_CREAT => 0x0200;
use constant IOS_MAKE_DEFER => 125;

my $json;
sub _json {
    _require('Cpanel/JSON/XS.pm');
    $json ||= Cpanel::JSON::XS->new->convert_blessed(1);
    return $json;
}
our $make_recursion_state;

sub check_error {
  my ($error) = @_;
  warn "ios error: $error" if $error;
}

sub yield {
  CBYield(shift);
}

sub _perl_switches_with_environment {
        my ($switches) = @_;
        my @result = @{$switches || []};

        return \@result if grep { $_ eq '-T' || $_ eq '-t' } @result;
        return \@result if !defined $ENV{PERL5LIB};

        push @result, map { "-I$_" }
                grep { length } split /\Q$Config{path_sep}\E/, $ENV{PERL5LIB};
        return \@result;
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
    my $exec = _json()->utf8->canonical->pretty->encode($runPerl);
    print "\$exec: $exec\n" if $DEBUG;
    _chdir($pwd) or die "Could not chdir to $pwd: $!"
        if defined $pwd && $pwd ne '';
    my $t = eval { CBRunPerl($exec) };
    my $error = $@;
    _chdir($old_pwd) or die "Could not restore directory $old_pwd: $!";
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
    my $exec = _json()->utf8->canonical->pretty->encode($runPerl);
    print "exec_perl_capture \$exec: $exec\n" if $DEBUG;
    my ($capture_result, $error);
    local $@;
    eval {
        ($capture_result) = CBRunPerlCaptureStdout($exec);
        1;
    } or $error = $@;

    $capture_result = _normalize_capture_result($capture_result, $error);

    print "exec_perl_capture \$result: $capture_result->[1]:\n"
        if ($capture_result->[1] && $DEBUG);
    return ($capture_result);
}

sub _normalize_capture_result {
    my ($capture_result, $error) = @_;
    return $capture_result
        if ref $capture_result eq 'ARRAY' && defined $capture_result->[0];

    my $output = ref $capture_result eq 'ARRAY' ? $capture_result->[1] : undef;
    $error ||= 'CBRunPerlCaptureStdout returned no wait status';
    $error =~ s/\s+\z//;
    $output = defined $output && length $output ? "$output\n" : '';
    return [255 << 8, "${output}iOS embedded Perl failed: $error\n"];
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
        switches => _perl_switches_with_environment(\@switches),
        args => \@args,
    };

    print Dumper("parse_test", $result) if $DEBUG;
    return $result
}

sub parse_cli {
    my ($pwd, $cli) = @_;
    print Dumper("parse_test pwd", $pwd) if $DEBUG;
    print Dumper("parse_test t", $cli) if $DEBUG;
    my ($file, $prog, $stderr, @args, @switches);

    $stderr = 0;
    $cli =~ s/2>&1//;

    my @cmd_words = grep { defined && $_ !~ /^\s*$/ }
        &quotewords('\s+', 0, $cli);
    shift @cmd_words while @cmd_words
        && basename($cmd_words[0]) !~ /^(?:perl(?:5(?:\.\d+)*)?|harness)$/;
    shift @cmd_words if @cmd_words;
    print Dumper("\@cmd_words", "@cmd_words") if $DEBUG;

    my $eval_index;
    for my $index (0 .. $#cmd_words) {
        if ($cmd_words[$index] eq '-e') {
            $eval_index = $index;
            last;
        }
    }
    if (defined $eval_index) {
        @switches = splice @cmd_words, 0, $eval_index;
        shift @cmd_words;
        $prog = shift @cmd_words;
        @args = @cmd_words;
    }

    my $file_index = -1;
    if (!defined $prog) {
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

    if (!defined $prog) {
        if ($file) {
            push @args, splice @cmd_words, $file_index + 1;
            print Dumper("\@args", @args) if $DEBUG && @switches;
            @switches = splice @cmd_words, 0, $file_index;
            print Dumper("\@switches", @switches) if $DEBUG && @switches;
        } else {
            @switches = @cmd_words;
        }
    }

    @args = grep defined, @args;
    @switches = grep defined, @switches;

    my $result = {
        prog => $prog,
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
    die ('Could not chdir to $pwd') if ($pwd && ! _chdir($pwd));
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

sub _make_capture_once {
    my ($pwd, @args) = @_;
    my $old_pwd = getcwd();
    my $old_env_pwd = $ENV{PWD};
    my ($result, $error);

    $pwd = $old_pwd if !defined $pwd || $pwd eq '';
    eval {
        _chdir($pwd) or die "Could not chdir to $pwd: $!";
        ($result) = CBRunMakeCapture(@args);
        1;
    } or $error = $@;
    _chdir($old_pwd) or die "Could not restore directory $old_pwd: $!";
    if (defined $old_env_pwd) {
        $ENV{PWD} = $old_env_pwd;
    } else {
        delete $ENV{PWD};
    }
    die $error if defined $error;
    return @$result;
}

sub _parse_recursive_make_recipe {
    my ($pwd, $command) = @_;
    my @words = grep { defined && $_ ne '' }
        &quotewords('\s+', 0, $command);
    return if @words < 4 || shift(@words) ne 'cd';

    my $directory = shift @words;
    return if $directory !~ m{^[^/]+$} || $directory eq '.' || $directory eq '..';
    return if shift(@words) ne '&&';

    my $make_program = shift @words;
    return if basename($make_program) !~ /^(?:b?make|gmake)$/;

    my $child_pwd = abs_path("$pwd/$directory");
    return if !defined $child_pwd || !-d $child_pwd;
    return {
        pwd => $child_pwd,
        args => \@words,
        key => join("\0", $pwd, $command),
    };
}

sub make_capture {
    my ($pwd, @args) = @_;
    $pwd = getcwd() if !defined $pwd || $pwd eq '';
    $pwd = abs_path($pwd)
        or die "Could not resolve make directory $pwd: $!";
    my $state = $make_recursion_state || {
        active => {},
        completed => {},
    };

    local $make_recursion_state = $state;
    while (1) {
        delete $state->{pending};
        my @result = _make_capture_once($pwd, @args);
        my $recursive = delete $state->{pending};
        return @result if !defined $recursive;

        die "Recursive iOS make cycle at $recursive->{pwd}\n"
            if $state->{active}{$recursive->{key}};
        local $state->{active}{$recursive->{key}} = 1;
        my ($status, $output) = make_capture(
            $recursive->{pwd}, @{$recursive->{args}});
        return ($status, $output) if $status != 0;
        $state->{completed}{$recursive->{key}} = $output // '';
    }
}

sub make {
    my ($pwd, @args) = @_;
    my $old_pwd = getcwd();
    my $old_env_pwd = $ENV{PWD};
    my ($status, $error);

    $pwd = $old_pwd if !defined $pwd || $pwd eq '';
    eval {
        _chdir($pwd) or die "Could not chdir to $pwd: $!";
        $status = CBRunMake(@args);
        1;
    } or $error = $@;
    _chdir($old_pwd) or die "Could not restore directory $old_pwd: $!";
    if (defined $old_env_pwd) {
        $ENV{PWD} = $old_env_pwd;
    } else {
        delete $ENV{PWD};
    }
    die $error if defined $error;
    return $status;
}

sub _make_perl_request {
    my ($pwd, @words) = @_;
    my (@switches, @args, $progfile);
    my $after_separator = 0;

    while (@words) {
        my $word = shift @words;
        next if $word eq '\\' || $word =~ /^\s*$/;
        if ($after_separator) {
            push @args, $word;
        } elsif ($word eq '--') {
            $after_separator = 1;
            push @args, $word;
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
        nolib => 1,
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
    my $recursive = _parse_recursive_make_recipe(getcwd(), $command);
    if ($recursive && $make_recursion_state) {
        if (exists $make_recursion_state->{completed}{$recursive->{key}}) {
            print $make_recursion_state->{completed}{$recursive->{key}};
            return 0;
        }
        return IOS_MAKE_DEFER if exists $make_recursion_state->{pending};
        $make_recursion_state->{pending} = $recursive;
        return IOS_MAKE_DEFER;
    }

    my @words = grep { defined && $_ ne '' }
        &quotewords('\s+', 0, $command);
    return 0 if !@words;

    my %environment;
    while (@words && $words[0] =~ /^([A-Za-z_][A-Za-z0-9_]*)=(.*)$/s) {
        $environment{$1} = $2;
        shift @words;
    }
    return 0 if !@words;

    my $program = shift @words;
    my $name = basename($program);
    if ($name =~ /^(?:perl(?:5(?:\.\d+)*)?|harness)$/) {
        my ($redirect_mode, $redirect_file);
        if (@words >= 2 && $words[-2] =~ /^>{1,2}$/) {
            $redirect_file = pop @words;
            $redirect_mode = pop @words;
        }
        local @ENV{keys %environment} = values %environment
            if %environment;
        my ($result) = exec_perl_capture(
            _make_perl_request(getcwd(), @words));
        my ($status, $output) = @$result;
        if (defined $redirect_mode) {
            open my $handle, $redirect_mode, $redirect_file or return 1;
            return 1 if defined $output && length $output
                && !print {$handle} $output;
            close $handle or return 1;
        } else {
            print $output if defined $output && length $output;
        }
        $status = $status >> 8 if defined $status && $status > 255;
        return defined $status ? $status : 1;
    }

    return 0 if $name eq 'true' && !@words;

    if ($name eq 'echo') {
        my $newline = 1;
        if (@words && $words[0] eq '-n') {
            shift @words;
            $newline = 0;
        }
        if (@words >= 2 && $words[-2] =~ /^>{1,2}$/) {
            my $file = pop @words;
            my $mode = pop @words;
            open my $handle, $mode, $file or return 1;
            print {$handle} join(' ', @words), ($newline ? "\n" : '')
                or return 1;
            return close $handle ? 0 : 1;
        }
        print join(' ', @words), ($newline ? "\n" : '');
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

    if ($name eq 'rm') {
        my ($force, $recursive);
        while (@words && $words[0] =~ /^-/) {
            my $option = shift @words;
            last if $option eq '--';
            return 127 if $option !~ /^-[fRr]+$/;
            $force = 1 if $option =~ /f/;
            $recursive = 1 if $option =~ /[Rr]/;
        }
        return 1 if !@words;
        for my $file (@words) {
            if (-d $file && !-l $file) {
                return 1 if !$recursive;
                my $errors;
                remove_tree($file, { error => \$errors });
                return 1 if $errors && @$errors;
                next;
            }
            next if unlink $file;
            next if $force && !-e $file && !-l $file;
            return 1;
        }
        return 0;
    }

    if ($name eq 'cp' && @words == 2) {
        return copy($words[0], $words[1]) ? 0 : 1;
    }

    if ($name eq 'mv' && @words == 2) {
        return move($words[0], $words[1]) ? 0 : 1;
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
