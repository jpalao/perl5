use strict;
use warnings;
use utf8;

use Test::More;

require JSON::PP;
require Cpanel::JSON::XS;

{
    package Local::BridgeObject;

    sub new {
        my ($class, $value) = @_;
        return bless { value => $value }, $class;
    }

    sub TO_JSON {
        my ($self) = @_;
        return { converted => $self->{value} };
    }
}

my @requests = (
    {
        switches => undef,
        nolib => undef,
        non_portable => undef,
        prog => undef,
        progs => undef,
        progfile => 't/basic.t',
        stdin => undef,
        stderr => undef,
        args => [],
        verbose => undef,
        pwd => '/tmp/test',
    },
    {
        switches => ['-I../lib', '-Mutf8'],
        nolib => 1,
        non_portable => 0,
        prog => qq{print "h\x{e9}llo\\n"},
        progs => ['line 1', 'line 2'],
        progfile => undef,
        stdin => "\x{3b1}\x{3b2}\n",
        stderr => 'merge',
        args => ['001', '42', '-7', 'x y', ''],
        verbose => 1,
        pwd => "/tmp/\x{e9}",
    },
    {
        z => [undef, 0, 1, '1', '01'],
        a => { nested => ["\x{2603}", "\x{10000}"] },
    },
    {
        object => Local::BridgeObject->new('ok'),
    },
);

my $json_pp = JSON::PP->new->convert_blessed(1)->utf8->canonical->pretty;
my $cpanel_json = Cpanel::JSON::XS->new
    ->convert_blessed(1)->utf8->canonical->pretty;

for my $index (0 .. $#requests) {
    my $expected = $json_pp->encode($requests[$index]);
    my $actual = $cpanel_json->encode($requests[$index]);

    is($actual, $expected, "request $index has identical JSON bytes");
    is_deeply(
        JSON::PP->new->utf8->decode($actual),
        JSON::PP->new->utf8->decode($expected),
        "request $index decodes identically",
    );
}

done_testing;