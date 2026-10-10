#!./perl

BEGIN {
    chdir 't' if -d 't';
    require './test.pl';
    skip_all('iOS only test') if $^O !~ /darwin-ios/;
}

sleep(180) if $^O =~ /darwin-ios/;

# try to avoid iOS killing harness for excessive CPU usage
# during t/op tests

ok( 1,         "sleep for 3m on iOS..." );

done_testing();
