use warnings;
use strict;

use Test::More tests => 9;
use XS::APItest ();
use Config;

alarm 10 unless $Config{'archname'} =~ /darwin-ios/;   # likely failure mode is an infinite loop

ok 1;
is eval q{ 3 + 1 }, 4;
is eval q{ BEGIN { $^H{"XS::APItest/addissub"} = 1; } 3 + 1 }, 4;
XS::APItest::setup_addissub(); ok 1;
is eval q{ 3 + 1 }, 4;
is eval q{ BEGIN { $^H{"XS::APItest/addissub"} = 1; } 3 + 1 }, 2;
XS::APItest::setup_addissub(); ok 1;
is eval q{ 3 + 1 }, 4;
is eval q{ BEGIN { $^H{"XS::APItest/addissub"} = 1; } 3 + 1 }, 2;

1;
