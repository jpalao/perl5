#!perl -t

use strict;
use warnings;
use Test::More;
use Scalar::Util qw(tainted);

my ($perl) = $^X =~ /\A(.*)\z/s;
plan skip_all => 'interpreter path requires shell-specific quoting'
    if !length($perl) || $perl =~ m{[^A-Za-z0-9_./-]};
plan tests => 10;

my @warnings;
local $SIG{__WARN__} = sub { push @warnings, @_ };

{
    local $ENV{PATH} = '/bin:/usr/bin';
    local @ENV{qw(IFS CDPATH ENV BASH_ENV)};
    delete @ENV{qw(IFS CDPATH ENV BASH_ENV)};

    my $output = `$perl -le "print q(clean)"`;
    is($output, "clean\n", 'untainted interpreter command runs');
    is(join('', @warnings), '', 'untainted interpreter command is not reported');

    my @output = `$perl -le "print for 1..2"`;
    is_deeply(\@output, ["1\n", "2\n"], 'list backticks return output records');
    is(scalar(grep { !tainted($_) } @output), 0,
        'list backtick output is tainted');
}

{
    local $ENV{PATH} = '.';
    {
        no warnings 'taint';
        @warnings = ();
        my $output = `$perl -le "print q(Hello)"`;
        is($output, "Hello\n", 'backticks work with an insecure PATH under -t');
        is(join('', @warnings), '', 'no taint warning for an insecure PATH');
    }
    {
        use warnings 'taint';
        @warnings = ();
        my $output = `$perl -le "print q(Hello)"`;
        is($output, "Hello\n", 'backticks work with taint warnings enabled');
        like(join('', @warnings), qr/Insecure (?:directory in )?\$ENV\{PATH\}/,
            'insecure PATH is reported');
    }
    {
        use warnings FATAL => 'taint';
        my $ok = eval { `$perl -le 1`; 1 };
        ok(!$ok, 'fatal taint warnings reject an insecure PATH');
        like($@, qr/Insecure (?:directory in )?\$ENV\{PATH\}/,
            'fatal warning identifies the insecure PATH');
    }
}
