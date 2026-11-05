use strict;
use warnings;
use Config;
use Test::More;
use Time::HiRes ();

plan skip_all => 'iOS native clock IDs' unless $^O =~ /darwin-ios/;
plan tests => 12;

sub has_symbol {
    my ($symbol) = @_;
    return eval {
        Time::HiRes->import($symbol);
        no strict 'refs';
        &{$symbol}();
        1;
    } || 0;
}

SKIP: {
    my ($platform, $major) = $Config::Config{ccflags} =~
        /-m(iphoneos|ios|appletvos|tvos|watchos)(?:-simulator)?-version-min=(\d+)/;
    unless (defined $major) {
        fail("cannot determine iOS deployment target from compiler flags");
        skip "unknown deployment target", 11;
    }
    my $minimum = $platform eq 'watchos' ? 3 : 10;
    skip "deployment target predates native clocks", 12 if $major < $minimum;

    for my $symbol (qw(CLOCK_PROCESS_CPUTIME_ID CLOCK_THREAD_CPUTIME_ID
                       CLOCK_MONOTONIC_RAW CLOCK_UPTIME_RAW)) {
        my $available = has_symbol($symbol);
        ok($available, "$symbol is exported");
        SKIP: {
            skip "$symbol is unavailable", 2 unless $available;
            no strict 'refs';
            my $clock_id = &{$symbol}();
            my $time = Time::HiRes::clock_gettime($clock_id);
            my $resolution = Time::HiRes::clock_getres($clock_id);
            ok($time >= 0, "clock_gettime supports $symbol");
            ok($resolution >= 0, "clock_getres supports $symbol");
        }
    }
}
